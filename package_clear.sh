#!/usr/bin/env bash
# Protected-URL version: the same renditions packaged as CMAF HLS (HLS only since 2026-10-13), 6 s segments, NO encryption.
# The only protection is the signed, expiring URL the Worker requires on every manifest and segment.
# Usage: package_clear.sh <renditions_dir> <outdir>
set -euo pipefail
REN="$1"; OUT="$2"
rm -rf "$OUT"; mkdir -p "$OUT"
ARGS=()
for f in "$REN"/video_*p.mp4; do
  n=$(basename "$f" .mp4)
  ARGS+=("in=$f,stream=video,init_segment=$OUT/$n/init.mp4,segment_template=$OUT/$n/\$Number\$.m4s")
done
# Audio (2026-10-16; Ztor codes 2026-10-28): one playlist per language in a single HLS audio group. audio_128k.mp4 is the
# pre-2026-10-16 single unnamed track and keeps its old audio/ folder; tagged tracks go to audio_<code>/. The packager gets the
# standard code (it refuses Ztor codes, and "und" too, so an untagged track gets no language= at all); NAME= keeps the Ztor
# code and ztor_master below copies it into LANGUAGE=. audio_default (written by encode.sh) names the default track.
. "$(dirname "$0")/audio_codes.sh"
for f in "$REN"/audio_*.mp4; do
  [ -f "$f" ] || continue
  n=$(basename "$f" .mp4); lang=${n#audio_}; [ "$lang" = "128k" ] && lang=und
  dir=audio_$lang; [ "$lang" = "und" ] && dir=audio
  LANGOPT=""; [ "$lang" != "und" ] && LANGOPT="language=$(iso_lang "$lang"),"
  ARGS+=("in=$f,stream=audio,${LANGOPT}hls_name=$lang,hls_group_id=audio,init_segment=$OUT/$dir/init.mp4,segment_template=$OUT/$dir/\$Number\$.m4s")
done
DEFLANG=(); DEF=$(cat "$REN/audio_default" 2>/dev/null || true); [ -n "$DEF" ] && [ "$DEF" != "und" ] && DEFLANG=(--default_language "$(iso_lang "$DEF")")
packager "${ARGS[@]}" ${DEFLANG[@]+"${DEFLANG[@]}"} \
  --segment_duration 6 --fragment_duration 6 --generate_static_live_mpd \
  --hls_master_playlist_output "$OUT/master.m3u8" \
  --quiet
ztor_master "$OUT/master.m3u8"   # LANGUAGE= carries the Ztor code (cn, hk, ...)
echo "audio: $(grep 'TYPE=AUDIO' "$OUT/master.m3u8" | grep -oE 'LANGUAGE="[^"]*"|DEFAULT=[A-Z]+' | tr '\n' ' ' || true)"
find "$OUT" -type f | wc -l | sed 's/^/files=/'
