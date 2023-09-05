#!/bin/bash

if [ $# -ne 1 ]; then
  echo "Usage: $0 <input_file>"
  exit 1
fi

input_file="$1"

# Check if the input file exists
if [ ! -f "$input_file" ]; then
  echo "Error: File not found: $input_file"
  exit 1
fi

# Use sed to remove extra empty lines and save the result to a temporary file
temp_file="$(mktemp)"
sed '/^[[:space:]]*$/d' "$input_file" > "$temp_file"

# Overwrite the original file with the cleaned content
mv "$temp_file" "$input_file"

echo "Extra empty lines removed from $input_file"
