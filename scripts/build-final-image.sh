#!/usr/bin/env bash
set -e
set -o pipefail

# --- Helper Functions ---
print_info() {
  printf ">> \033[1;32m${1}\033[0m\n"
}

print_debug() {
  printf "   \033[0;36m${1}\033[0m\n"
}

print_error() {
  printf "!! \033[1;31m${1}\033[0m\n" >&2
}

check_sudo() {
  print_debug "Checking sudo access..."
  if ! sudo -n true 2>/dev/null; then
    echo "This script will need sudo access for some operations."
    echo "Please enter your password when prompted."
    sudo -v
  fi
  print_debug "Sudo access confirmed"
}

keep_sudo_alive() {
  print_debug "Starting sudo keepalive process..."
  while true; do
    sleep 60
    sudo -n true
  done 2>/dev/null &
  echo $! >/tmp/sudo_keepalive_$$
  print_debug "Sudo keepalive PID: $(cat /tmp/sudo_keepalive_$$)"
}

cleanup_sudo() {
  if [ -f "/tmp/sudo_keepalive_$$" ]; then
    local pid=$(cat /tmp/sudo_keepalive_$$)
    print_debug "Killing sudo keepalive process (PID: $pid)..."
    kill $pid 2>/dev/null || true
    rm -f /tmp/sudo_keepalive_$$
  fi
}

# --- Main Logic ---

if [ "$EUID" -eq 0 ]; then
  print_error "Don't run this script as root! It will escalate privileges when needed."
  exit 1
fi

print_info "Starting shimboot NixOS image build process..."
print_debug "Script PID: $$"
print_debug "User: $USER (UID: $(id -u), GID: $(id -g))"
print_debug "Groups: $(id -Gn)"

PROJECT_ROOT=$(pwd)
SHIM_FILE="$PROJECT_ROOT/data/shim.bin"
KERNEL_FILE="$PROJECT_ROOT/data/kernel.bin"
BOOTLOADER_DIR="$PROJECT_ROOT/bootloader"

print_debug "Project root: $PROJECT_ROOT"
print_debug "Shim file: $SHIM_FILE"
print_debug "Kernel file: $KERNEL_FILE"
print_debug "Bootloader dir: $BOOTLOADER_DIR"

print_info "Checking prerequisites..."
for cmd in nix cgpt binwalk nixos-generate jq hexdump strings fdisk tar; do
  if command -v $cmd >/dev/null; then
    print_debug "✓ $cmd found at $(command -v $cmd)"
  else
    print_error "✗ $cmd not found"
    exit 1
  fi
done

for file in "$SHIM_FILE" "$BOOTLOADER_DIR"; do
  if [ -e "$file" ]; then
    print_debug "✓ $file exists"
  else
    print_error "✗ $file not found"
    exit 1
  fi
done

check_sudo
keep_sudo_alive

TMP_DIR=$(mktemp -d)
print_info "Working directory: $TMP_DIR"
print_debug "Temp directory permissions: $(ls -ld "$TMP_DIR")"

IMAGE_LOOP=""

cleanup_all() {
  print_info "Cleaning up..."
  cleanup_sudo

  for mount_point in "/tmp/new_rootfs" "/tmp/shim_bootloader"; do
    if mountpoint -q "$mount_point" 2>/dev/null; then
      print_debug "Unmounting $mount_point..."
      sudo umount "$mount_point" 2>/dev/null || true
    fi
  done

  if [ -n "$IMAGE_LOOP" ]; then
    print_debug "Detaching loop device $IMAGE_LOOP..."
    sudo losetup -d "$IMAGE_LOOP" 2>/dev/null || true
  fi

  if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
    print_debug "Removing temp directory $TMP_DIR..."
    rm -rf "$TMP_DIR" 2>/dev/null || true
  fi

  print_debug "Cleanup complete"
}

trap 'cleanup_all' EXIT

# --- Step 1: The Pure Build (Tarball Method) ---
print_info "Building NixOS rootfs tarball..."
print_debug "Running: nixos-generate -f docker -c ./configuration.nix --system x86_64-linux"

NIXOS_TARBALL=$(nixos-generate -f docker -c ./configuration.nix --system x86_64-linux)
print_debug "nixos-generate returned: $NIXOS_TARBALL"

if [ ! -f "$NIXOS_TARBALL" ]; then
  print_error "Failed to find generated NixOS tarball at $NIXOS_TARBALL"
  exit 1
fi
print_info "NixOS tarball generated at $NIXOS_TARBALL"
print_debug "Tarball size: $(ls -lh "$NIXOS_TARBALL")"

# --- Step 2: The Impure Harvest ---
print_info "Harvesting kernel and initramfs from shim..."
print_info "Extracting kernel partition (KERN-A)..."

print_debug "Running: sudo cgpt show -i 2 \"$SHIM_FILE\""
cgpt_output=$(sudo cgpt show -i 2 "$SHIM_FILE")
print_debug "cgpt output:"
print_debug "$cgpt_output"

read -r part_start part_size _ < <(
  echo "$cgpt_output" | awk '$4 == "Label:" && $5 == "\"KERN-A\""'
)
print_debug "Partition start: $part_start, size: $part_size"

print_debug "Extracting kernel with dd..."
sudo dd if="$SHIM_FILE" of="$KERNEL_FILE" bs=512 skip="$part_start" count="$part_size" status=progress

print_debug "Fixing ownership of $KERNEL_FILE..."
print_debug "Current file ownership: $(ls -l "$KERNEL_FILE")"
print_debug "Target ownership: $(id -u):$(id -g)"
sudo chown "$(id -u):$(id -g)" "$KERNEL_FILE"
print_debug "New file ownership: $(ls -l "$KERNEL_FILE")"

print_info "Extracting initramfs from kernel..."
print_debug "Stage 1: Finding gzip offset..."
tmp_log_1=$(mktemp)
binwalk -y gzip -l "$tmp_log_1" "$KERNEL_FILE"
print_debug "binwalk gzip log:"
cat "$tmp_log_1"
offset=$(grep '"offset"' "$tmp_log_1" | awk -F': ' '{print $2}' | sed 's/,//')
rm "$tmp_log_1"
print_debug "Gzip offset: $offset"

print_debug "Stage 1: Decompressing kernel..."
dd if="$KERNEL_FILE" bs=1 skip="$offset" | zcat >"$TMP_DIR/decompressed_kernel.bin" || true
print_debug "Decompressed kernel size: $(ls -lh "$TMP_DIR/decompressed_kernel.bin")"

print_debug "Stage 2: Finding XZ offset..."
tmp_log_2=$(mktemp)
binwalk -l "$tmp_log_2" "$TMP_DIR/decompressed_kernel.bin"
print_debug "binwalk XZ log:"
cat "$tmp_log_2"
xz_offset=$(cat "$tmp_log_2" | jq '.[0].Analysis.file_map[] | select(.description | contains("XZ compressed data")) | .offset')
rm "$tmp_log_2"
print_debug "XZ offset: $xz_offset"

mkdir -p "$TMP_DIR/initramfs_extracted"
print_debug "Stage 2: Extracting XZ cpio archive..."
dd if="$TMP_DIR/decompressed_kernel.bin" bs=1 skip="$xz_offset" | xz -d | cpio -id -D "$TMP_DIR/initramfs_extracted" || true
print_debug "Initramfs extraction complete. Contents:"
ls -la "$TMP_DIR/initramfs_extracted" | head -10

print_info "Patching initramfs with shimboot bootloader..."
original_init="$TMP_DIR/initramfs_extracted/init"
print_debug "Original init script: $original_init"
print_debug "Copying bootloader from: $BOOTLOADER_DIR"
cp -rT "$BOOTLOADER_DIR" "$TMP_DIR/initramfs_extracted/"
print_debug "Adding exec hook to init script..."
echo 'exec /bin/bootstrap.sh' >>"$original_init"
print_debug "Making bootloader scripts executable..."
find "$TMP_DIR/initramfs_extracted/bin" -type f -exec chmod +x {} \;
print_debug "Initramfs patching complete"

# --- Step 3: The Final Assembly ---
print_info "Assembling the final disk image..."
OUTPUT_PATH="$PROJECT_ROOT/shimboot_nixos.bin"
print_debug "Output path: $OUTPUT_PATH"

print_debug "Estimating required rootfs size..."
COMPRESSED_SIZE_MB=$(du -m "$NIXOS_TARBALL" | cut -f 1)
# Estimate uncompressed size as 8x compressed size, plus some buffer.
ROOTFS_SIZE_MB=$((COMPRESSED_SIZE_MB * 8))
ROOTFS_PART_SIZE_MB=$((ROOTFS_SIZE_MB * 12 / 10 + 200))
BOOTLOADER_PART_SIZE_MB=32
TOTAL_SIZE=$((1 + 32 + BOOTLOADER_PART_SIZE_MB + ROOTFS_PART_SIZE_MB))

print_debug "Compressed tarball size: ${COMPRESSED_SIZE_MB}MB"
print_debug "Estimated uncompressed rootfs size: ${ROOTFS_SIZE_MB}MB"
print_debug "Final rootfs partition size: ${ROOTFS_PART_SIZE_MB}MB"
print_debug "Bootloader partition size: ${BOOTLOADER_PART_SIZE_MB}MB"
print_debug "Total image size: ${TOTAL_SIZE}MB"

print_info "Creating ${TOTAL_SIZE}MB disk image"
rm -f "$OUTPUT_PATH"
fallocate -l "${TOTAL_SIZE}M" "$OUTPUT_PATH"
print_debug "Disk image created: $(ls -lh "$OUTPUT_PATH")"

print_info "Partitioning disk image"
print_debug "Running fdisk to create partition table..."
(
  echo g
  echo n
  echo
  echo
  echo +1M
  echo n
  echo
  echo
  echo +32M
  echo n
  echo
  echo
  echo "+${BOOTLOADER_PART_SIZE_MB}M"
  echo n
  echo
  echo
  echo
  echo w
) | sudo fdisk "$OUTPUT_PATH" >/dev/null

print_debug "Setting partition attributes with cgpt..."
sudo cgpt add -i 1 -t data -l "STATE" "$OUTPUT_PATH"
sudo cgpt add -i 2 -t kernel -l "kernel" -S 1 -T 5 -P 10 "$OUTPUT_PATH"
sudo cgpt add -i 3 -t rootfs -l "BOOT" "$OUTPUT_PATH"
sudo cgpt add -i 4 -t data -l "shimboot_rootfs:nixos" "$OUTPUT_PATH"

print_debug "Verifying partition table:"
sudo fdisk -l "$OUTPUT_PATH"

print_info "Creating loop device for final image"
IMAGE_LOOP=$(sudo losetup -f)
print_debug "Assigned final image loop device: $IMAGE_LOOP"
sudo losetup -P "$IMAGE_LOOP" "$OUTPUT_PATH"
print_debug "Final image partitions:"
ls -la "${IMAGE_LOOP}"* || true

print_info "Formatting partitions"
print_debug "Formatting STATE partition..."
sudo mkfs.ext4 -L STATE "${IMAGE_LOOP}p1" >/dev/null
print_debug "Copying kernel to KERN-A partition..."
sudo dd if="$KERNEL_FILE" of="${IMAGE_LOOP}p2" bs=1M oflag=sync status=progress
print_debug "Formatting BOOT partition..."
sudo mkfs.ext2 -L BOOT "${IMAGE_LOOP}p3" >/dev/null
print_debug "Formatting ROOTFS partition..."
sudo mkfs.ext4 -L ROOTFS -O ^has_journal,^extent,^huge_file,^flex_bg,^metadata_csum,^64bit,^dir_nlink "${IMAGE_LOOP}p4" >/dev/null

print_info "Copying bootloader..."
BOOTLOADER_MOUNT="/tmp/shim_bootloader"
sudo mkdir -p "$BOOTLOADER_MOUNT"
print_debug "Mounting bootloader partition: ${IMAGE_LOOP}p3 -> $BOOTLOADER_MOUNT"
sudo mount "${IMAGE_LOOP}p3" "$BOOTLOADER_MOUNT"
print_debug "Copying initramfs contents to bootloader partition..."
sudo cp -ar "$TMP_DIR/initramfs_extracted"/* "$BOOTLOADER_MOUNT/"
print_debug "Bootloader partition contents:"
sudo ls -la "$BOOTLOADER_MOUNT" | head -10
sudo umount "$BOOTLOADER_MOUNT"

print_info "Copying NixOS rootfs... (this may take a while)"
ROOTFS_MOUNT="/tmp/new_rootfs"
sudo mkdir -p "$ROOTFS_MOUNT"
print_debug "Mounting rootfs partition: ${IMAGE_LOOP}p4 -> $ROOTFS_MOUNT"
sudo mount "${IMAGE_LOOP}p4" "$ROOTFS_MOUNT"
print_debug "Extracting rootfs tarball to partition..."
sudo tar -xJf "$NIXOS_TARBALL" -C "$ROOTFS_MOUNT"
print_debug "Rootfs extraction complete"
print_debug "Manually creating traditional symlinks..."
sudo mkdir -p "${ROOTFS_MOUNT}/sbin" "${ROOTFS_MOUNT}/usr/sbin"
sudo ln -sf /init "${ROOTFS_MOUNT}/sbin/init"
sudo ln -sf /init "${ROOTFS_MOUNT}/usr/sbin/init"
sudo umount "$ROOTFS_MOUNT"

print_debug "Fixing ownership of output file..."
sudo chown "$(id -u):$(id -g)" "$OUTPUT_PATH"
print_debug "Final image ownership: $(ls -l "$OUTPUT_PATH")"

print_info "All done! Your shimboot NixOS image is ready at: $OUTPUT_PATH"
print_debug "Final image size: $(ls -lh "$OUTPUT_PATH")"
