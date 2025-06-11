#!/usr/bin/env bash
set -e

# --- Helper Functions ---
print_info() {
  printf ">> \033[1;32m${1}\033[0m\n"
}

assert_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "This script needs to be run as root for the final assembly."
    exit 1
  fi
}

# --- Main Logic ---
assert_root

# Define our project paths
# This assumes the script is run from the project root
PROJECT_ROOT=$(pwd)
SHIM_FILE="$PROJECT_ROOT/data/shim.bin"
KERNEL_FILE="$PROJECT_ROOT/data/kernel.bin"
ROOTFS_DIR="$PROJECT_ROOT/result"
BOOTLOADER_DIR="$PROJECT_ROOT/bootloader"

# Check for prerequisites
command -v nix >/dev/null || { echo "Nix not found."; exit 1; }
command -v cgpt >/dev/null || { echo "cgpt not found. Is vboot_utils installed system-wide?"; exit 1; }
command -v binwalk >/dev/null || { echo "binwalk not found."; exit 1; }
# ...add any other checks as needed...

# --- Step 1: The Pure Build ---
print_info "Building the pure NixOS rootfs..."
nix build "$PROJECT_ROOT#rootfs" --extra-experimental-features "nix-command flakes"
print_info "Rootfs build complete. Output is at $ROOTFS_DIR"

# --- Step 2: The Impure Harvest ---
print_info "Harvesting kernel and initramfs from shim..."

# Create a temporary workspace
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Harvest the Body (kernel.bin)
print_info "Extracting kernel partition (KERN-A)..."
read -r part_start part_size _ < <(cgpt show -i 2 "$SHIM_FILE" | awk '$4 == "Label:" && $5 == "\"KERN-A\""')
dd if="$SHIM_FILE" of="$KERNEL_FILE" bs=512 skip="$part_start" count="$part_size" status=progress

# Harvest the Spark (initramfs)
print_info "Extracting initramfs from kernel..."
# Stage 1: Decompress the kernel's gzip stream
tmp_log_1=$(mktemp)
binwalk -y gzip -l "$tmp_log_1" "$KERNEL_FILE"
offset=$(grep '"offset"' "$tmp_log_1" | awk -F': ' '{print $2}' | sed 's/,//')
rm "$tmp_log_1"
# Apply the balm to zcat
dd if="$KERNEL_FILE" bs=1 skip="$offset" | zcat > "$TMP_DIR/decompressed_kernel.bin" || true

# Stage 2: Find and extract the XZ-compressed cpio archive
tmp_log_2=$(mktemp)
binwalk -l "$tmp_log_2" "$TMP_DIR/decompressed_kernel.bin"
xz_offset=$(cat "$tmp_log_2" | jq '.[0].Analysis.file_map[] | select(.description | contains("XZ compressed data")) | .offset')
rm "$tmp_log_2"
mkdir -p "$TMP_DIR/initramfs_extracted"
# Apply the balm to cpio
dd if="$TMP_DIR/decompressed_kernel.bin" bs=1 skip="$xz_offset" | xz -d | cpio -id -D "$TMP_DIR/initramfs_extracted" || true

# Patch the Spark
print_info "Patching initramfs with shimboot bootloader..."
cp -rT "$BOOTLOADER_DIR" "$TMP_DIR/initramfs_extracted/"

# --- Step 3: The Final Assembly ---
print_info "Assembling the final disk image..."
"$PROJECT_ROOT/scripts/create-image.sh" \
  "$PROJECT_ROOT/shimboot_nixos.bin" \
  "$KERNEL_FILE" \
  "$TMP_DIR/initramfs_extracted" \
  "$ROOTFS_DIR"

print_info "All done. Your world is ready at shimboot_nixos.bin"
