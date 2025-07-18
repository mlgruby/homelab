#!/usr/bin/env bash
set -euo pipefail

# This script automates the one-time installation of NixOS on the NUCs.
# It should be run from the NixOS live installer environment.
#
# Example usage: ./scripts/install-nuc.sh -h nuc1

# --- Cleanup Trap ---
# This ensures that we always attempt to unmount everything on script exit,
# regardless of success or failure. This makes the script re-runnable.
trap 'echo ">>> Script finished or failed. Unmounting filesystems..."; umount -R /mnt || true' EXIT

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

# --- Get Repo Root ---
# We assume this script is being run from the root of the homelab git repo
# E.g., /path/to/homelab/scripts/install-nuc.sh
# So the repo root is the current working directory.
REPO_ROOT=$(pwd)
echo ">>> Using repository root: ${REPO_ROOT}"

echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "!!! IMPORTANT: Have you added your SSH public key to"
echo "!!! ${REPO_ROOT}/common/common.nix ?"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
read -r -p "Press Enter to continue, or Ctrl-C to cancel and edit the file."

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

# 0. Forcefully deactivate any LVM, RAID, or ZFS to release device locks
echo ">>> Forcefully removing device-mapper mappings and deactivating LVM..."
(dmsetup remove_all --force) 2>/dev/null || true
(vgchange -an) 2>/dev/null || true

echo ">>> Stopping RAID and clearing ZFS labels..."
(mdadm --stop --scan) 2>/dev/null || true
# The following command is critical for disks previously used with ZFS (e.g., Proxmox)
(zpool labelclear -f "${OS_DEVICE}") 2>/dev/null || true
(zpool labelclear -f "${FAST_DEVICE}") 2>/dev/null || true
sleep 2 # Give the system a moment to release locks

# 1. Ensure devices are unmounted and clean
echo ">>> Wiping existing signatures from disks..."
umount -R "${OS_DEVICE}" 2>/dev/null || true
umount -R "${FAST_DEVICE}" 2>/dev/null || true
wipefs --all "${OS_DEVICE}"
wipefs --all "${FAST_DEVICE}"

# 2. Partition the OS drive
echo ">>> Partitioning OS drive: ${OS_DEVICE}"
# Wipe the partition table
sgdisk -Z "${OS_DEVICE}"
# Create a 1GB boot partition and a root partition with the remaining space
sgdisk -n 1:0:+1G -t 1:ef00 -c 1:"boot" \
       -n 2:0:0   -t 2:8300 -c 2:"root" \
       "${OS_DEVICE}"

# 3. Partition the fast storage drive
echo ">>> Partitioning fast storage drive: ${FAST_DEVICE}"
# Wipe the partition table
sgdisk -Z "${FAST_DEVICE}"
# Create a single partition for data
sgdisk -n 1:0:0 -t 1:8300 -c 1:"data" \
       "${FAST_DEVICE}"

# 4. Format the partitions
echo ">>> Formatting partitions"

# Force kernel to re-read partition tables to prevent errors
echo ">>> Informing kernel of new partitions..."
partprobe "${OS_DEVICE}"
partprobe "${FAST_DEVICE}"
sleep 3 

# Determine partition naming convention (e.g., sda1 vs nvme0n1p1)
OS_P1=""
OS_P2=""
if [[ "${OS_DEVICE}" =~ "nvme" || "${OS_DEVICE}" =~ "mmcblk" ]]; then
    OS_P1="${OS_DEVICE}p1"
    OS_P2="${OS_DEVICE}p2"
else
    OS_P1="${OS_DEVICE}1"
    OS_P2="${OS_DEVICE}2"
fi

FAST_P1=""
if [[ "${FAST_DEVICE}" =~ "nvme" || "${FAST_DEVICE}" =~ "mmcblk" ]]; then
    FAST_P1="${FAST_DEVICE}p1"
else
    FAST_P1="${FAST_DEVICE}1"
fi

echo ">>> Formatting boot partition: ${OS_P1}"
mkfs.fat -F 32 -n boot "${OS_P1}"

echo ">>> Formatting root partition: ${OS_P2}"
mkfs.ext4 -F -L root "${OS_P2}"

echo ">>> Formatting data partition: ${FAST_P1}"
mkfs.ext4 -F -L data "${FAST_P1}"

# 5. Mount the filesystems
echo ">>> Mounting filesystems"
mount /dev/disk/by-label/root /mnt
mkdir -p /mnt/boot
mount /dev/disk/by-label/boot /mnt/boot
mkdir -p /mnt/data
mount /dev/disk/by-label/data /mnt/data

# 6. Generate NixOS configuration
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
      ${REPO_ROOT}/hosts/${HOSTNAME}/configuration.nix
    ];
}
EOF

# 7. Install NixOS
echo ">>> Installing NixOS"
nixos-install --no-root-passwd

# 8. Finalize
# The umount is now handled by the trap at the beginning of the script.

# Get the current IP address
CURRENT_IP=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+' 2>/dev/null || echo "unknown")

echo "------------------------------------------------------------------"
echo ">>> SUCCESS: Installation complete for ${HOSTNAME}."
echo ">>> "
echo ">>> Current system information:"
echo ">>> Hostname: ${HOSTNAME}"
echo ">>> IP Address: ${CURRENT_IP}"
echo ">>> "
echo ">>> Next steps:"
echo ">>> 1. Remove the USB installation media"
echo ">>> 2. Reboot the system"
echo ">>> 3. The system will boot into NixOS and be accessible via SSH"
echo ">>> "
echo ">>> SSH connection command:"
echo ">>> ssh -i ~/.ssh/nuc_homelab_id_ed25519 satya@${CURRENT_IP}"
echo ">>> "
echo ">>> Note: If the IP address changes after reboot (DHCP), you can find it by:"
echo ">>> - Checking your router's admin panel for connected devices"
echo ">>> - Using: nmap -sn 192.168.1.0/24 (adjust subnet as needed)"
echo ">>> - Looking for hostname '${HOSTNAME}' in your network"
echo "------------------------------------------------------------------"

read -r -p "Would you like to reboot now? (y/n): " REBOOT_CHOICE
if [[ "$REBOOT_CHOICE" =~ ^[Yy]$ ]]; then
    echo ">>> Rebooting in 5 seconds... Remove the USB now!"
    sleep 5
    reboot
else
    echo ">>> Remember to remove the USB installation media before rebooting manually."
fi 
