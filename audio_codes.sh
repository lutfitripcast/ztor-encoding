# Ztor audio language codes (2026-10-28, Ztor standard from Colin). Sourced by encode.sh, package.sh and package_clear.sh.
#
#   code  language    zh-tw / zh-hk  en-us
#   cn    Mandarin    國語            Mandarin
#   hk    Cantonese   粵語            Cantonese
#   en    English     英語            English
#   kr    Korean      韓語            Korean
#   th    Thai        泰語            Thai
#   de    German      德語            German
#   fr    French      法語            French
#   it    Italian     義大利語         Italian
#   jp    Japanese    日語            Japanese
#
# The audio tracks of a master carry these codes as language tags (or, in MP4 / MOV, the three-letter form, see
# ztor_from_tag), and the manifests carry them as LANGUAGE="cn" and so on.
# They are not ISO language codes: Shaka Packager refuses cn, hk and jp ("Unknown/invalid language specified") and would
# read kr as Kanuri. So the packager is given the standard code behind each one (iso_lang), and after packaging the master
# playlist is rewritten so LANGUAGE= carries the Ztor code again (ztor_master). The display names live in the Worker
# (src/lib/util.ts AUDIO_LABELS).
ZTOR_LANGS="cn hk en kr th de fr it jp"

# The standard three-letter code for a Ztor code; "und" for anything else.
iso_lang() {
  case "$1" in
    cn) echo cmn;; hk) echo yue;; en) echo eng;; kr) echo kor;; th) echo tha;;
    de) echo deu;; fr) echo fra;; it) echo ita;; jp) echo jpn;; *) echo und;;
  esac
}

is_ztor_lang() { case " $ZTOR_LANGS " in *" $1 "*) return 0;; esac; return 1; }

# A master's tag as the Ztor code (2026-10-28). An MP4 or MOV master can only store a three-letter tag, so the three-letter
# form of each language is accepted too and converted here; a Ztor code (possible in MKV) passes unchanged. Only the Ztor code
# goes further: file names, NAME= and LANGUAGE= in the manifests. Any other tag passes unchanged and is refused (several
# tracks) or shown as "Original" (one track) by encode.sh.
ZTOR_TAGS_3="cmn yue eng kor tha deu ger fra fre ita jpn"
ztor_from_tag() {
  case "$1" in
    cmn) echo cn;; yue) echo hk;; eng) echo en;; kor) echo kr;; tha) echo th;;
    deu|ger) echo de;; fra|fre) echo fr;; ita) echo it;; jpn) echo jp;; *) echo "$1";;
  esac
}

# Every audio line of a master playlist: LANGUAGE= becomes the Ztor code, which the packager kept in NAME= (hls_name).
# Lines whose NAME is not a Ztor code (an untagged "und" track, older films) are left as they are.
ztor_master() {
  local m="$1"
  [ -f "$m" ] || return 0
  awk -v codes=" $ZTOR_LANGS " '
    /^#EXT-X-MEDIA:/ && /TYPE=AUDIO/ && match($0, /NAME="[^"]*"/) {
      n = substr($0, RSTART + 6, RLENGTH - 7)
      if (index(codes, " " n " ")) {
        if ($0 ~ /LANGUAGE="[^"]*"/) sub(/LANGUAGE="[^"]*"/, "LANGUAGE=\"" n "\"")
        else sub(/NAME="/, "LANGUAGE=\"" n "\",NAME=\"")
      }
    }
    { print }' "$m" > "$m.tmp" && mv "$m.tmp" "$m"
}
