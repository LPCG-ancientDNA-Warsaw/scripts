#!/bin/bash

usage() {
    echo "Usage: $0 -o OLD_PATH -n NEW_PATH [-p FILE_PATTERN]"
    echo
    echo "Options:"
    echo "  -o    Old path to replace"
    echo "  -n    New path"
    echo "  -p    File pattern (default: *.tsv)"
    exit 1
}

FILE_PATTERN="*.tsv"

while getopts ":o:n:p:h" opt; do
    case $opt in
        o) OLD_PATH="$OPTARG" ;;
        n) NEW_PATH="$OPTARG" ;;
        p) FILE_PATTERN="$OPTARG" ;;
        h) usage ;;
        \?) echo "Invalid option: -$OPTARG"; usage ;;
        :) echo "Option -$OPTARG requires an argument."; usage ;;
    esac
done

if [[ -z "$OLD_PATH" || -z "$NEW_PATH" ]]; then
    usage
fi

echo "=== Correcting paths in TSV files ==="
echo "Looking in: $(pwd)"
echo "Pattern: $FILE_PATTERN"
echo "Substituting: $OLD_PATH  -->  $NEW_PATH"
echo "--------------------------------------------------"

TOTAL_FILES=$(find . -type f -name "$FILE_PATTERN" | wc -l)
echo "Found $TOTAL_FILES matching files."

MODIFIED_COUNT=0

while IFS= read -r tsv_file; do
    if grep -q "$OLD_PATH" "$tsv_file"; then
        sed -i "s|${OLD_PATH}|${NEW_PATH}|g" "$tsv_file"
        echo "[FIXED] Updated: $tsv_file"
        ((MODIFIED_COUNT++))
    fi
done < <(find . -type f -name "$FILE_PATTERN")

echo "--------------------------------------------------"
echo "Files checked: $TOTAL_FILES"
echo "Files corrected: $MODIFIED_COUNT"