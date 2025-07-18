#!/usr/bin/env bash
set -euo pipefail

# This script automates the one-time installation of NixOS on the NUCs.
# It should be run from the NixOS live installer environment.
#
# Example usage: ./scripts/install-nuc.sh -h nuc1

# --- Argument Parsing ---
HOSTNAME=""

while getopts "h:" opt; do
  case ${opt} in
    h ) HOSTNAME=$OPTARG;;
    \? ) echo "Usage: cmd -h <hostname>"
         exit 1;;
  esac
done

if [ -z "$HOSTNAME" ]; then
    echo "Hostname argument (-h) is required."
    echo "Usage: cmd -h <hostname>"
    exit 1
fi

# --- Interactive Device Selection ---
echo ">>> Available block devices:"
lsblk -dno NAME,SIZE,MODEL
echo ""

read -r -p "Enter the device for the OS drive (e.g., nvme0n1): " OS_DEVICE_NAME
OS_DEVICE="/dev/${OS_DEVICE_NAME}"

read -r -p "Enter the device for the fast data drive (e.g., nvme1n1): " FAST_DEVICE_NAME
FAST_DEVICE="/dev/${FAST_DEVICE_NAME}"

echo "------------------------------------------------------------------"
echo "WARNING: This script is about to wipe and partition the following devices:"
echo "OS Drive:   ${OS_DEVICE}"
echo "Data Drive: ${FAST_DEVICE}"
echo "Hostname:   ${HOSTNAME}"
echo "------------------------------------------------------------------"
read -r -p "Are you sure you want to continue? (yes/no): " CONFIRMATION
if [[ "$CONFIRMATION" != "yes" ]]; then
    echo "Installation cancelled."
    exit 1
fi

# --- Script ---

echo ">>> Starting NUC installation for hostname: ${HOSTNAME}"

# 1. Partition the OS drive
echo ">>> Partitioning OS drive: ${OS_DEVICE}"
# Wipe the partition table
sgdisk -Z "${OS_DEVICE}"
# Create a 1GB boot partition and a root partition with the remaining space
sgdisk -n 1:0:+1G -t 1:ef00 -c 1:"boot" \
       -n 2:0:0   -t 2:8300 -c 2:"root" \
       "${OS_DEVICE}"

# 2. Partition the fast storage drive
echo ">>> Partitioning fast storage drive: ${FAST_DEVICE}"
# Wipe the partition table
sgdisk -Z "${FAST_DEVICE}"
# Create a single partition for data
sgdisk -n 1:0:0 -t 1:8300 -c 1:"data" \
       "${FAST_DEVICE}"

# 3. Format the partitions
echo ">>> Formatting partitions"

# Force kernel to re-read partition tables to prevent errors
partprobe "${OS_DEVICE}"
partprobe "${FAST_DEVICE}"
sleep 2 

# Determine partition naming convention (e.g., sda1 vs nvme0n1p1)
OS_P1="${OS_DEVICE}1"
OS_P2="${OS_DEVICE}2"
if [[ "${OS_DEVICE}" == *"nvme"* ]] || [[ "${OS_DEVICE}" == *"mmcblk"* ]]; then
    OS_P1="${OS_DEVICE}p1"
    OS_P2="${OS_DEVICE}p2"
fi

FAST_P1="${FAST_DEVICE}1"
if [[ "${FAST_DEVICE}" == *"nvme"* ]] || [[ "${FAST_DEVICE}" == *"mmcblk"* ]]; then
    FAST_P1="${FAST_DEVICE}p1"
fi

mkfs.fat -F 32 -n boot "${OS_P1}"
mkfs.ext4 -L root "${OS_P2}"
mkfs.ext4 -L data "${FAST_P1}"

# 4. Mount the filesystems
echo ">>> Mounting filesystems"
mount /dev/disk/by-label/root /mnt
mkdir -p /mnt/boot
mount /dev/disk/by-label/boot /mnt/boot
mkdir -p /mnt/data
mount /dev/disk/by-label/data /mnt/data

# 5. Generate NixOS configuration
echo ">>> Generating NixOS configuration"
nixos-generate-config --root /mnt

# Replace the generated configuration with one that points to our flake
rm /mnt/etc/nixos/configuration.nix
cat > /mnt/etc/nixos/configuration.nix <<EOF
{ ... }:

{
  imports =
    [
      # This pulls in the hardware-specific configuration
      ./hardware-configuration.nix

      # This points to the host-specific configuration in our flake
      # Assumes the flake repository is available at /tmp/homelab
      /tmp/homelab/hosts/${HOSTNAME}/configuration.nix
    ];
}
EOF

# 6. Install NixOS
echo ">>> Installing NixOS"
nixos-install --no-root-passwd

# 7. Finalize
echo ">>> Unmounting filesystems"
umount -R /mnt

echo ">>> Installation complete for ${HOSTNAME}. Please remove the installation media and reboot." 
