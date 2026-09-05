#!/usr/bin/env bash
#
# Convert Audible .aax audiobooks to .m4b using ffmpeg, preserving chapters
# and cover artwork, then move the result to an output directory and remove
# the source .aax file.
#
# Usage:
#   aax-to-m4b.sh -a ACTIVATION_BYTES [-a ACTIVATION_BYTES ...] [-i INPUT_DIR] [-o OUTPUT_DIR] [-k] [-v]
#
# Multiple activation bytes may be given (repeat -a, or pass a
# comma-separated list) and are tried in order against each file until one
# succeeds. Activation bytes can also be supplied via the
# AAX_ACTIVATION_BYTES environment variable (comma-separated) instead of -a.

set -euo pipefail

INPUT_DIR="."
OUTPUT_DIR="."
ACTIVATION_BYTES_LIST=()
KEEP_SOURCE=0
VERBOSE=0

usage() {
    cat <<EOF
Usage: $(basename "$0") -a ACTIVATION_BYTES [-a ACTIVATION_BYTES ...] [-i INPUT_DIR] [-o OUTPUT_DIR] [-k] [-v]

  -a ACTIVATION_BYTES  8-character hex activation bytes for decrypting .aax
                        files. May be repeated, or a single -a may contain a
                        comma-separated list; each is tried in order until
                        one works. (Or set AAX_ACTIVATION_BYTES, also
                        comma-separated.)
  -i INPUT_DIR          Directory to scan for .aax files (default: .)
  -o OUTPUT_DIR         Directory to move converted .m4b files to (default: .)
  -k                    Keep the source .aax file instead of deleting it
  -v                    Verbose ffmpeg output
  -h                    Show this help
EOF
}

while getopts ":a:i:o:kvh" opt; do
    case "$opt" in
        a) IFS=',' read -ra _bytes <<< "$OPTARG"; ACTIVATION_BYTES_LIST+=("${_bytes[@]}") ;;
        i) INPUT_DIR="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        k) KEEP_SOURCE=1 ;;
        v) VERBOSE=1 ;;
        h) usage; exit 0 ;;
        \?) echo "Unknown option: -$OPTARG" >&2; usage; exit 1 ;;
        :) echo "Option -$OPTARG requires an argument" >&2; usage; exit 1 ;;
    esac
done

if [ ${#ACTIVATION_BYTES_LIST[@]} -eq 0 ] && [ -n "${AAX_ACTIVATION_BYTES:-}" ]; then
    IFS=',' read -ra ACTIVATION_BYTES_LIST <<< "$AAX_ACTIVATION_BYTES"
fi

if [ ${#ACTIVATION_BYTES_LIST[@]} -eq 0 ]; then
    echo "Error: at least one activation bytes value is required (-a or AAX_ACTIVATION_BYTES)" >&2
    usage
    exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "Error: ffmpeg is not installed or not on PATH" >&2
    exit 1
fi

if [ ! -d "$INPUT_DIR" ]; then
    echo "Error: input directory '$INPUT_DIR' does not exist" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

FFMPEG_LOGLEVEL="error"
[ "$VERBOSE" -eq 1 ] && FFMPEG_LOGLEVEL="info"

shopt -s nullglob
aax_files=("$INPUT_DIR"/*.aax)
shopt -u nullglob

if [ ${#aax_files[@]} -eq 0 ]; then
    echo "No .aax files found in '$INPUT_DIR'"
    exit 0
fi

status=0

for aax_file in "${aax_files[@]}"; do
    base_name="$(basename "$aax_file" .aax)"
    tmp_out="$OUTPUT_DIR/${base_name}.m4b.tmp"
    final_out="$OUTPUT_DIR/${base_name}.m4b"

    echo "Converting '$aax_file' -> '$final_out'"

    converted=0
    for bytes in "${ACTIVATION_BYTES_LIST[@]}"; do
        if [ ${#ACTIVATION_BYTES_LIST[@]} -gt 1 ]; then
            echo "  Trying activation bytes '$bytes'..."
        fi

        if ffmpeg -y -loglevel "$FFMPEG_LOGLEVEL" \
            -activation_bytes "$bytes" \
            -i "$aax_file" \
            -map 0 -c copy -map_metadata 0 -movflags +faststart \
            "$tmp_out"; then
            converted=1
            break
        fi

        rm -f "$tmp_out"
    done

    if [ "$converted" -eq 1 ]; then
        mv "$tmp_out" "$final_out"

        if [ "$KEEP_SOURCE" -eq 0 ]; then
            rm -f "$aax_file"
        fi

        echo "Done: '$final_out'"
    else
        echo "Error: ffmpeg failed converting '$aax_file' with all activation bytes" >&2
        status=1
    fi
done

exit "$status"
