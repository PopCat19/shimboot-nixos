#!/usr/bin/env bash
set -e

# This script takes two arguments: the path to shim.bin and the output directory.
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <path/to/shim.bin> <output_directory>"
  exit 1
fi

SHIM_FILE="$1"
OUTPUT_DIR="$2"

# Ensure we have the tools we need.
command -v cgpt >/dev/null || { echo "cgpt not found. Is vboot_utils installed?"; exit 1; }
command -v losetup >/dev/null || { echo "losetup not found."; exit 1; }
command -v mount >/dev/null || { echo "mount not found."; exit 1; }

echo "--- Performing impure driver extraction ---"

# Create a temporary directory for mounting
MOUNT_POINT=$(mktemp -d)
# Ensure cleanup happens even if we fail
trap 'sudo umount "$MOUNT_POINT" || true; sudo rmdir "$MOUNT_POINT" || true; [ -n "$LOOP_DEVICE" ] && sudo losetup -d "$LOOP_DEVICE"' EXIT

# Find the partition info
read -r part_start part_size _ < <(cgpt show -i 3 "$SHIM_FILE" | awk '$4 == "Label:" && $5 == "\"ROOT-A\""')

echo "Found ROOT-A at sector $part_start, size $part_size sectors."

# Setup loop device and mount
LOOP_DEVICE=$(sudo losetup -f)
sudo losetup -o $(($part_start * 512)) --sizelimit $(($part_size * 512)) "$LOOP_DEVICE" "$SHIM_FILE"
sudo mount -o ro "$LOOP_DEVICE" "$MOUNT_POINT"

echo "Mounted partition on $MOUNT_POINT."

# Create the final output directory
mkdir -p "$OUTPUT_DIR"/lib

# Copy the sacred artifacts
echo "Copying /lib/firmware and /lib/modules..."
sudo cp -r "$MOUNT_POINT"/lib/firmware "$OUTPUT_DIR"/lib/
sudo cp -r "$MOUNT_POINT"/lib/modules "$OUTPUT_DIR"/lib/

echo "--- Extraction complete. Output at: $OUTPUT_DIR ---"
