#!/usr/bin/env bash
# Proposal step 5, part 1: H.264 ladder, 2-second GOP aligned across renditions, AAC 128k stereo per audio language (2026-10-16).
# Usage: encode.sh <source (path or presigned URL)> <outdir> [maxHeight]
# One ffmpeg run: the master is decoded once. Rungs above the source height are skipped (no upscaling).
set -euo pipefail
SRC="$1"; OUT="$2"; MAXH="${3:-2160}"
mkdir -p "$OUT"
FPS=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 "$SRC" | head -1)
GOP=$(python3 -c "from fractions import Fraction; print(round(float(Fraction('$FPS'))*2))" 2>/dev/null || echo 48)
# Audio languages (2026-10-16; Ztor codes since 2026-10-28): every audio stream of the master becomes its own stereo AAC
# file, audio_<code>.mp4, named by the Ztor code of the stream's language tag (audio_codes.sh: cn hk en kr th de fr it jp).
# The tag may be the Ztor code itself (MKV) or its three-letter form (cmn yue eng kor tha deu fra ita jpn, the only kind an
# MP4 or MOV master can store); either way only the Ztor code goes further. With several streams every one must carry a
# different language from the table, or the job stops here with a clear message. A single stream never stops the job: a
# language from the table is kept, anything else (no tag, or another tag) becomes "und", shown as "Original".
. "$(dirname "$0")/audio_codes.sh"
AUDIO_LANGS=()
while IFS=, read -r IDX LANG; do
  [ -z "$IDX" ] && continue
  LANG=$(echo "${LANG:-und}" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9-'); [ -z "$LANG" ] && LANG=und
  AUDIO_LANGS+=("$(ztor_from_tag "$LANG")")
done < <(ffprobe -v error -select_streams a -show_entries stream=index:stream_tags=language -of csv=p=0 "$SRC")
if [ "${#AUDIO_LANGS[@]}" -gt 1 ]; then
  for L in "${AUDIO_LANGS[@]}"; do
    is_ztor_lang "$L" && continue
    if [ "$L" = "und" ]; then WHAT="has no language tag"; else WHAT="is tagged '$L'"; fi
    echo "audio: ${#AUDIO_LANGS[@]} audio tracks and one $WHAT; tag every track with a Ztor code ($ZTOR_LANGS) or, in an MP4 or MOV master, its three-letter form ($ZTOR_TAGS_3) and deliver again" >&2; exit 1
  done
  DUP=$(printf '%s\n' "${AUDIO_LANGS[@]}" | sort | uniq -d | head -1); [ -n "$DUP" ] && { echo "audio: two tracks are tagged '$DUP'; every track needs a different language" >&2; exit 1; }
elif [ "${#AUDIO_LANGS[@]}" -eq 1 ] && ! is_ztor_lang "${AUDIO_LANGS[0]}"; then
  [ "${AUDIO_LANGS[0]}" != "und" ] && echo "audio: the only track is tagged '${AUDIO_LANGS[0]}', not a language in the Ztor table; it is shown as \"Original\""
  AUDIO_LANGS=(und)
fi

# height bitrate_k maxrate_k bufsize_k
LADDER="2160 16000 17600 32000
1080 6000 6600 12000
720 3000 3300 6000
480 1500 1650 3000
360 800 880 1600"

X264="-c:v libx264 -preset medium -profile:v high -g $GOP -keyint_min $GOP -sc_threshold 0 -pix_fmt yuv420p -force_key_frames expr:gte(t,n_forced*2)"
FILTERS=""; MAPS=(); N=0; LABELS=()
while read -r H BR MAXR BUF; do
  [ "$H" -gt "$MAXH" ] && continue
  LABELS+=("$H"); N=$((N+1))
done <<< "$LADDER"
[ "$N" -eq 0 ] && { echo "no rung fits height $MAXH" >&2; exit 1; }

SPLIT="[0:v]split=$N"; i=0
for H in "${LABELS[@]}"; do SPLIT="$SPLIT[s$i]"; i=$((i+1)); done
FILTERS="$SPLIT"; i=0
for H in "${LABELS[@]}"; do FILTERS="$FILTERS;[s$i]scale=-2:${H}:flags=lanczos[v$H]"; i=$((i+1)); done

# HTTP(S) sources: reconnect on dropped connections instead of silently treating a reset as end-of-file.
NETOPTS=(); case "$SRC" in http://*|https://*) NETOPTS=(-reconnect 1 -reconnect_streamed 1 -reconnect_on_network_error 1 -reconnect_on_http_error 5xx -reconnect_delay_max 30 -rw_timeout 30000000);; esac
ARGS=(-nostdin -v error -y "${NETOPTS[@]}" -i "$SRC" -filter_complex "$FILTERS")
while read -r H BR MAXR BUF; do
  [ "$H" -gt "$MAXH" ] && continue
  ARGS+=(-map "[v$H]" $X264 -b:v ${BR}k -maxrate ${MAXR}k -bufsize ${BUF}k -an -f mp4 -movflags +faststart "$OUT/video_${H}p.mp4")
done <<< "$LADDER"
# The file is named by the Ztor code; inside it the track carries the standard code, the only kind MP4 can store.
AI=0; for L in "${AUDIO_LANGS[@]}"; do ARGS+=(-map 0:a:$AI -vn -c:a aac -b:a 128k -ac 2 -metadata:s:a:0 language=$(iso_lang "$L") -f mp4 "$OUT/audio_${L}.mp4"); AI=$((AI+1)); done
echo "audio tracks: ${AUDIO_LANGS[*]:-none}"
[ "${#AUDIO_LANGS[@]}" -gt 0 ] && echo "${AUDIO_LANGS[0]}" > "$OUT/audio_default"   # the master's first track is the default language

ffmpeg "${ARGS[@]}"
echo "rungs=${LABELS[*]} gop=$GOP audio=${HAS_AUDIO:-none}"
ls -l "$OUT"
