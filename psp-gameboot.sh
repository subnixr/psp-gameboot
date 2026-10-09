#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Build a PSP gameboot.pmf from a video (+ optional WAV), replicating
# https://wololo.net/talk/viewtopic.php?t=38029 without the GUI tools:
#   VirtualDub + WinMEnc + WAV converter -> ffmpeg
#   UmdStreamComposer                    -> psmfenc + psmfmux   (wine)
#   Gameboot Converter.bat               -> PsmfComposerCMD     (wine)
#
# Standalone: needs ffmpeg, ffprobe and wine. The Sony PSMF suite is fetched
# once (curl + 7z or bsdtar), after asking, into the user cache dir; scratch
# files go to a temp dir on wine's C: drive that is removed on exit.
set -euo pipefail

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/psp-gameboot"
TOOLS="$CACHE/psmf"
SUITE_URL="https://github.com/Little-Data/Gametoolkit/releases/download/V4.3.1/PSMF.Stream.Composer.Suite.v2.5.7z"
SUITE_SHA256="7fee209f4b5ac57b67504fccfc7ac22b1b59e3843e00e215f96bf2d44eb84137"

VBITRATE=2000   # kbps average, 1000-2000 (peak is 2x)
ABITRATE=128    # kbps ATRAC3plus stereo: 48 64 96 128 160 192 256 320
TRIM=""
OUT="gameboot.pmf"
KEEP=""
YES=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [-t seconds] [-b video_kbps] [-a audio_kbps] [-o out.pmf] [-k] [-y] [video] [audio]
  -t  trim to this many seconds (tutorial uses 2.5; default: keep full length)
  -b  average video bitrate, 1000-2000 (default $VBITRATE)
  -a  audio bitrate (default $ABITRATE)
  -o  output file (default ./$OUT)
  -k  keep the temp build dir and print its path
  -y  download the PSMF suite without asking
  video  default: the only .mov in the current directory
  audio  default: ./gameboot.wav if present, else the video's own audio track

Requires ffmpeg, ffprobe and wine. On first run the Sony PSMF Stream Composer
Suite is downloaded, after confirmation, to $TOOLS
(needs curl and one of 7z, 7zz, 7za, bsdtar).
EOF
}

while getopts "t:b:a:o:kyh" opt; do
    case "$opt" in
        t) TRIM="$OPTARG" ;;
        b) VBITRATE="$OPTARG" ;;
        a) ABITRATE="$OPTARG" ;;
        o) OUT="$OPTARG" ;;
        k) KEEP=1 ;;
        y) YES=1 ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done
shift $((OPTIND - 1))

die() { echo "error: $*" >&2; exit 1; }

# The suite tools run from the build dir, so every path must be absolute.
abspath() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s\n' "$PWD/$1" ;;
    esac
}

VIDEO="${1:-}"
if [[ -z "$VIDEO" ]]; then
    shopt -s nullglob
    movs=(./*.mov)
    shopt -u nullglob
    [[ ${#movs[@]} -eq 1 ]] || die "no video given and not exactly one .mov in $PWD"
    VIDEO="${movs[0]}"
fi
AUDIO="${2:-}"
if [[ -z "$AUDIO" ]]; then
    if [[ -f gameboot.wav ]]; then AUDIO="gameboot.wav"; else AUDIO="$VIDEO"; fi
fi
[[ -f "$VIDEO" ]] || die "video not found: $VIDEO"
[[ -f "$AUDIO" ]] || die "audio not found: $AUDIO"
VIDEO="$(abspath "$VIDEO")"
AUDIO="$(abspath "$AUDIO")"
OUT="$(abspath "$OUT")"

missing=()
for cmd in ffmpeg ffprobe wine; do
    command -v "$cmd" >/dev/null || missing+=("$cmd")
done
[[ ${#missing[@]} -eq 0 ]] || die "missing dependencies: ${missing[*]}"

BUILD=""
FETCH=""
cleanup() {
    [[ -n "$FETCH" ]] && rm -rf "$FETCH"
    if [[ -n "$BUILD" ]]; then
        rm -f "$BUILD.xml"
        if [[ -n "$KEEP" ]]; then echo ">> build dir kept: $BUILD"; else rm -rf "$BUILD"; fi
    fi
    return 0
}
trap cleanup EXIT

sha256() {
    if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1
}

unpacker() {
    local x
    for x in 7z 7zz 7za bsdtar; do
        if command -v "$x" >/dev/null; then echo "$x"; return 0; fi
    done
    return 1
}

unpack() {
    local archive="$1" dest="$2" x
    x="$(unpacker)"
    if [[ "$x" == bsdtar ]]; then
        bsdtar -xf "$archive" -C "$dest"
    else
        "$x" x -y -o"$dest" "$archive" >/dev/null
    fi
}

# Sony PSMF Stream Composer Suite (psmfenc, psmfmux, PsmfComposerCMD)
find_suite() {
    local exe
    exe="$(find "$TOOLS" -iname psmfenc.exe -print -quit 2>/dev/null)" || true
    [[ -n "$exe" ]] && dirname "$exe"
    return 0
}
SUITE="$(find_suite)"
if [[ -z "$SUITE" ]]; then
    command -v curl >/dev/null || die "curl not found (needed to fetch the PSMF suite)"
    command -v sha256sum >/dev/null || command -v shasum >/dev/null \
        || die "sha256sum or shasum not found (needed to verify the PSMF suite)"
    unpacker >/dev/null || die "no 7z, 7zz, 7za or bsdtar found (needed to unpack the PSMF suite)"
    if [[ -z "$YES" ]]; then
        echo "The Sony PSMF Stream Composer Suite (third-party Windows binaries, ~10 MB) is required."
        echo "  from: $SUITE_URL"
        echo "  to:   $TOOLS"
        [[ -t 0 ]] || die "PSMF suite not installed; rerun with -y to download it"
        read -r -p "Download it now? [y/N] " answer
        [[ "$answer" == [yY]* ]] || die "PSMF suite download declined"
    fi
    echo ">> fetching PSMF Stream Composer Suite"
    mkdir -p "$CACHE"
    # Unpacked aside and moved into place, so a failed fetch leaves no cache.
    FETCH="$(mktemp -d "$CACHE/fetch.XXXXXX")"
    curl -fL --progress-bar -o "$FETCH/suite.7z" "$SUITE_URL"
    [[ "$(sha256 "$FETCH/suite.7z")" == "$SUITE_SHA256" ]] || die "PSMF suite checksum mismatch"
    mkdir "$FETCH/psmf"
    unpack "$FETCH/suite.7z" "$FETCH/psmf"
    rm -rf "$TOOLS"
    mv "$FETCH/psmf" "$TOOLS"
    SUITE="$(find_suite)"
    [[ -n "$SUITE" ]] || die "psmfenc.exe not found after unpacking"
fi

export WINEDEBUG="${WINEDEBUG:--all}"

# Runs a suite tool from the build dir; the tools exit 0 on some failures, so
# the caller names the file that must exist afterwards.
run_tool() {
    local expect="$1" exe="$2"
    shift 2
    rm -f "$BUILD/$expect"
    (cd "$BUILD" && wine "$SUITE/$exe" "$@") || die "$exe failed"
    [[ -s "$BUILD/$expect" ]] || die "$exe produced no $expect"
}

# PsmfComposerCMD drops <output name>.xml in the root of the drive it runs on,
# so the build dir has to sit on a drive with a writable root (not Z: = /).
# Building at the top of C: with the output named after the build dir puts
# that file at $BUILD.xml, where cleanup removes it.
DRIVE_C="$(winepath -u 'C:\' 2>/dev/null)" || die "cannot locate wine's C: drive"
BUILD="$(mktemp -d "${DRIVE_C%/}/psp-gameboot-XXXXXX")"
PMF="$(basename "$BUILD").pmf"

trim=()
[[ -n "$TRIM" ]] && trim=(-t "$TRIM")

echo ">> ffmpeg: 480x272 @ 29.97 raw AVI"
# Overlay on black so a source with alpha is flattened properly. Full-range
# BT.601 out: psmfenc expects 0-255 input and scales it to 16-235 itself.
ffmpeg -hide_banner -loglevel error -y -i "$VIDEO" "${trim[@]}" \
    -filter_complex "color=black:s=480x272:r=30000/1001[bg];[0:v]scale=480:272:flags=lanczos,fps=30000/1001,format=gbrap[fg];[bg][fg]overlay=shortest=1:format=gbrp,scale=out_color_matrix=bt601:out_range=pc,format=yuyv422" \
    -c:v rawvideo -an "$BUILD/video.avi"

echo ">> ffmpeg: 44.1 kHz 16-bit stereo WAV"
ffmpeg -hide_banner -loglevel error -y -i "$AUDIO" "${trim[@]}" \
    -vn -ar 44100 -ac 2 -c:a pcm_s16le "$BUILD/audio.wav"

echo ">> psmfenc: H.264 video"
run_tool video.bsf psmfenc.exe -video -avgb "$VBITRATE" -peakb "$((VBITRATE * 2))" \
    -2pass video.avi video.bsf

echo ">> psmfenc: ATRAC3plus audio"
run_tool audio.atx psmfenc.exe -audio -avgb "$ABITRATE" -adjust_v video.avi audio.wav audio.atx

echo ">> psmfmux: MPEG2 program stream"
run_tool gameboot.mps psmfmux.exe video.bsf audio.atx gameboot.mps

echo ">> PsmfComposerCMD: PSMF header"
run_tool "$PMF" PsmfComposerCMD.exe gameboot.mps "$PMF"

[[ "$(head -c 8 "$BUILD/$PMF")" == "PSMF0015" ]] || die "unexpected PSMF header"
# The XMB only plays gameboots with the old PSMF0012 header and no EP map
# (what the tutorial's Gameboot Converter writes); the layout is otherwise equal.
printf '0012' | dd of="$BUILD/$PMF" bs=1 seek=4 conv=notrunc status=none
mkdir -p "$(dirname "$OUT")"
mv -f "$BUILD/$PMF" "$OUT"

echo ">> done: $OUT ($(($(wc -c <"$OUT"))) bytes)"
ffprobe -hide_banner "$OUT" 2>&1 | grep -E 'Duration|Stream' || true
