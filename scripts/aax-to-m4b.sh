#!/usr/bin/env bash
#
# Convert Audible .aax audiobooks to .m4b using ffmpeg, preserving chapters
# and cover artwork, then move the result to an output directory and remove
# the source .aax file.
#
# Usage:
#   aax-to-m4b.sh -a ACTIVATION_BYTES [-i INPUT_DIR] [-o OUTPUT_DIR] [-k] [-v]
#
# The activation bytes can also be supplied via the AAX_ACTIVATION_BYTES
# environment variable instead of -a.

set -euo pipefail

INPUT_DIR="."
OUTPUT_DIR="."
ACTIVATION_BYTES="${AAX_ACTIVATION_BYTES:-}"
KEEP_SOURCE=0
VERBOSE=0

usage() {
    cat <<EOF
Usage: $(basename "$0") -a ACTIVATION_BYTES [-i INPUT_DIR] [-o OUTPUT_DIR] [-k] [-v]

  -a ACTIVATION_BYTES  8-character hex activation bytes for decrypting .aax
                        files (or set AAX_ACTIVATION_BYTES env var)
  -i INPUT_DIR          Directory to scan for .aax files (default: .)
  -o OUTPUT_DIR         Directory to move converted .m4b files to (default: .)
  -k                    Keep the source .aax file instead of deleting it
  -v                    Verbose ffmpeg output
  -h                    Show this help
EOF
}

while getopts ":a:i:o:kvh" opt; do
    case "$opt" in
        a) ACTIVATION_BYTES="$OPTARG" ;;
        i) INPUT_DIR="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        k) KEEP_SOURCE=1 ;;
        v) VERBOSE=1 ;;
        h) usage; exit 0 ;;
        \?) echo "Unknown option: -$OPTARG" >&2; usage; exit 1 ;;
        :) echo "Option -$OPTARG requires an argument" >&2; usage; exit 1 ;;
    esac
done

if [ -z "$ACTIVATION_BYTES" ]; then
    echo "Error: activation bytes are required (-a or AAX_ACTIVATION_BYTES)" >&2
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

    if ffmpeg -y -loglevel "$FFMPEG_LOGLEVEL" \
        -activation_bytes "$ACTIVATION_BYTES" \
        -i "$aax_file" \
        -map 0 -c copy -map_metadata 0 -movflags +faststart \
        "$tmp_out"; then
        mv "$tmp_out" "$final_out"

        if [ "$KEEP_SOURCE" -eq 0 ]; then
            rm -f "$aax_file"
        fi

        echo "Done: '$final_out'"
    else
        echo "Error: ffmpeg failed converting '$aax_file'" >&2
        rm -f "$tmp_out"
        status=1
    fi
done

exit "$status"
