#!/usr/bin/env bash
set -e

# --- Helper Functions (Muscles) ---

print_info() {
  printf ">> \033[1;32m${1}\033[0m\n"
}

assert_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "This script needs to be run as root."
    exit 1
  fi
}

create_loop() {
  local loop_device
  loop_device=$(losetup -f)
  losetup -P "$loop_device" "${1}"
  echo "$loop_device"
}

make_bootable() {
  cgpt add -i 2 -S 1 -T 5 -P 10 -l kernel "$1"
}

partition_disk() {
  local image_path="$1"
  local bootloader_size="$2"
  local rootfs_name="$3"
  # Create partition table with fdisk
  (
    echo g # new gpt disk label
    echo n # new partition 1 (stateful)
    echo
    echo
    echo +1M
    echo n # new partition 2 (kernel)
    echo
    echo
    echo +32M
    echo t # change partition type
    echo 2
    echo FE3A2A5D-4F32-41A7-B725-ACCC3285A309 # chromeos kernel
    echo n # new partition 3 (bootloader)
    echo
    echo
    echo "+${bootloader_size}M"
    echo t # change partition type
    echo 3
    echo 3CB8E202-3B7E-47DD-8A3C-7FF2A13CFCEC # chromeos rootfs
    echo n # new partition 4 (rootfs)
    echo
    echo
    echo
    echo w # write changes
  ) | fdisk "$image_path" > /dev/null
}

create_partitions() {
  local image_loop="$1"
  local kernel_path="$2"

  mkfs.ext4 -L STATE "${image_loop}p1"
  dd if="$kernel_path" of="${image_loop}p2" bs=1M oflag=sync
  make_bootable "$image_loop"
  mkfs.ext2 -L BOOT "${image_loop}p3"
  mkfs.ext4 -L ROOTFS "${image_loop}p4"
}

populate_partitions() {
  local image_loop="$1"
  local bootloader_dir="$2"
  local rootfs_dir="$3"

  # Mount and write to bootloader rootfs
  local bootloader_mount="/tmp/shim_bootloader"
  mkdir -p "$bootloader_mount"
  mount "${image_loop}p3" "$bootloader_mount"
  cp -ar "$bootloader_dir"/* "$bootloader_mount"
  umount "$bootloader_mount"

  # Write rootfs to image
  local rootfs_mount=/tmp/new_rootfs
  mkdir -p "$rootfs_mount"
  mount "${image_loop}p4" "$rootfs_mount"
  print_info "Copying rootfs... (this may take a moment)"
  cp -ar "$rootfs_dir"/* "$rootfs_mount"
  umount "$rootfs_mount"
}

create_image() {
  local image_path="$1"
  local bootloader_size="$2"
  local rootfs_size="$3"
  local rootfs_name="$4"

  # stateful + kernel + bootloader + rootfs
  local total_size=$((1 + 32 + bootloader_size + rootfs_size))
  rm -f "${image_path}"
  fallocate -l "${total_size}M" "${image_path}"
  partition_disk "$image_path" "$bootloader_size" "$rootfs_name"
}

# --- Main Logic (Bones) ---

if [ "$#" -ne 4 ]; then
  echo "Usage: $0 <output_path> <kernel_path> <initramfs_dir> <rootfs_dir>"
  exit 1
fi

assert_root

OUTPUT_PATH="$(realpath -m "${1}")"
KERNEL_PATH="$(realpath -m "${2}")"
INITRAMFS_DIR="$(realpath -m "${3}")"
ROOTFS_DIR="$(realpath -m "${4}")"

print_info "Creating disk image"
ROOTFS_SIZE_MB="$(du -sm "$ROOTFS_DIR" | cut -f 1)"
# Make rootfs partition 20% larger than its contents, plus a little extra.
ROOTFS_PART_SIZE_MB=$((ROOTFS_SIZE_MB * 12 / 10 + 100))
# Create a 32MB bootloader partition.
BOOTLOADER_PART_SIZE_MB=32
create_image "$OUTPUT_PATH" "$BOOTLOADER_PART_SIZE_MB" "$ROOTFS_PART_SIZE_MB"

print_info "Creating loop device for the image"
IMAGE_LOOP="$(create_loop "$OUTPUT_PATH")"

# Ensure loop device is cleaned up on exit
trap 'losetup -d "$IMAGE_LOOP"' EXIT

print_info "Creating partitions on the disk image"
create_partitions "$IMAGE_LOOP" "$KERNEL_PATH"

print_info "Copying data into the image"
populate_partitions "$IMAGE_LOOP" "$INITRAMFS_DIR" "$ROOTFS_DIR"

print_info "Cleaning up loop devices"
# The trap will handle this, but we can be explicit.
losetup -d "$IMAGE_LOOP"
trap - EXIT

print_info "Done. Final image is at: $OUTPUT_PATH"
