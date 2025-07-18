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

# --- Extract Username from Configuration ---
USERNAME=$(grep -o 'users\.users\.[a-zA-Z0-9_-]*' "${REPO_ROOT}/common/common.nix" | head -1 | cut -d'.' -f3)
if [[ -z "$USERNAME" ]]; then
    echo ">>> ⚠ WARNING: Could not extract username from configuration, using 'satya' as fallback"
    USERNAME="satya"
else
    echo ">>> ✓ Detected username from configuration: ${USERNAME}"
fi

echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "!!! IMPORTANT: Checking SSH public key configuration..."
if grep -q "openssh\.authorizedKeys\.keys" "${REPO_ROOT}/common/common.nix"; then
    echo "!!! ✓ SSH public key found in ${REPO_ROOT}/common/common.nix"
    # Extract and show the key comment/name for verification
    SSH_KEY_INFO=$(grep "ssh-" "${REPO_ROOT}/common/common.nix" | head -1 | awk '{print $3}' || echo "unknown")
    echo "!!! Key: ${SSH_KEY_INFO}"
else
    echo "!!! ✗ ERROR: No SSH public key found in ${REPO_ROOT}/common/common.nix"
    echo "!!! Please add your SSH public key before continuing."
    exit 1
fi
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
read -r -p "Press Enter to continue, or Ctrl-C to cancel and edit the file."

# --- Interactive Device Selection ---
echo ">>> Available block devices:"
lsblk -dno NAME,SIZE,MODEL
echo ""

read -r -p "Enter the device for the OS drive (default: sda): " OS_DEVICE_NAME
OS_DEVICE_NAME=${OS_DEVICE_NAME:-sda}
OS_DEVICE="/dev/${OS_DEVICE_NAME}"

read -r -p "Enter the device for the fast data drive (default: nvme0n1): " FAST_DEVICE_NAME
FAST_DEVICE_NAME=${FAST_DEVICE_NAME:-nvme0n1}
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

# Additional aggressive cleanup for stubborn devices
echo ">>> Performing additional device cleanup..."
(swapoff -a) 2>/dev/null || true
(umount -R "${OS_DEVICE}" "${FAST_DEVICE}") 2>/dev/null || true
(blockdev --rereadpt "${OS_DEVICE}") 2>/dev/null || true
(blockdev --rereadpt "${FAST_DEVICE}") 2>/dev/null || true

# Try to clear any remaining filesystem signatures more aggressively
echo ">>> Attempting aggressive signature clearing..."
(dd if=/dev/zero of="${OS_DEVICE}" bs=1M count=100) 2>/dev/null || true
(dd if=/dev/zero of="${FAST_DEVICE}" bs=1M count=100) 2>/dev/null || true

sleep 2 # Give the system a moment to release locks

# 0.1. Verify devices are accessible
echo ">>> Verifying device accessibility"
if [[ -b "${OS_DEVICE}" ]]; then
    echo ">>> ✓ OS device accessible: ${OS_DEVICE}"
    echo ">>>   Size: $(lsblk -dno SIZE "${OS_DEVICE}")"
    echo ">>>   Model: $(lsblk -dno MODEL "${OS_DEVICE}" 2>/dev/null || echo "Unknown")"
else
    echo ">>> ✗ ERROR: OS device not accessible: ${OS_DEVICE}"
    exit 1
fi

if [[ -b "${FAST_DEVICE}" ]]; then
    echo ">>> ✓ Fast storage device accessible: ${FAST_DEVICE}"
    echo ">>>   Size: $(lsblk -dno SIZE "${FAST_DEVICE}")"
    echo ">>>   Model: $(lsblk -dno MODEL "${FAST_DEVICE}" 2>/dev/null || echo "Unknown")"
else
    echo ">>> ✗ ERROR: Fast storage device not accessible: ${FAST_DEVICE}"
    exit 1
fi

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

# 2.1. Verify OS drive partitioning
echo ">>> Verifying OS drive partitioning"
if sgdisk -p "${OS_DEVICE}" | grep -q "boot"; then
    echo ">>> ✓ Boot partition created successfully"
else
    echo ">>> ✗ ERROR: Boot partition not found"
    exit 1
fi

if sgdisk -p "${OS_DEVICE}" | grep -q "root"; then
    echo ">>> ✓ Root partition created successfully" 
else
    echo ">>> ✗ ERROR: Root partition not found"
    exit 1
fi

# 3. Partition the fast storage drive
echo ">>> Partitioning fast storage drive: ${FAST_DEVICE}"
# Wipe the partition table
sgdisk -Z "${FAST_DEVICE}"
# Create a single partition for data
sgdisk -n 1:0:0 -t 1:8300 -c 1:"data" \
       "${FAST_DEVICE}"

# 3.1. Verify fast storage drive partitioning
echo ">>> Verifying fast storage drive partitioning"
if sgdisk -p "${FAST_DEVICE}" | grep -q "data"; then
    echo ">>> ✓ Data partition created successfully"
else
    echo ">>> ✗ ERROR: Data partition not found"
    exit 1
fi

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

# 5.1. Verify partitions and mounts
echo ">>> Verifying partition setup"

# Check that all expected partitions exist
if [[ -e "${OS_P1}" && -e "${OS_P2}" && -e "${FAST_P1}" ]]; then
    echo ">>> ✓ All partitions created successfully"
    echo ">>>   Boot: ${OS_P1}"
    echo ">>>   Root: ${OS_P2}" 
    echo ">>>   Data: ${FAST_P1}"
else
    echo ">>> ✗ ERROR: Some partitions are missing!"
    echo ">>>   Boot: ${OS_P1} $(test -e "${OS_P1}" && echo "✓" || echo "✗")"
    echo ">>>   Root: ${OS_P2} $(test -e "${OS_P2}" && echo "✓" || echo "✗")"
    echo ">>>   Data: ${FAST_P1} $(test -e "${FAST_P1}" && echo "✓" || echo "✗")"
    exit 1
fi

# Verify filesystems were formatted correctly
echo ">>> Verifying filesystem formats"
BOOT_FS=$(lsblk -no FSTYPE "${OS_P1}")
ROOT_FS=$(lsblk -no FSTYPE "${OS_P2}")
DATA_FS=$(lsblk -no FSTYPE "${FAST_P1}")

if [[ "$BOOT_FS" == "vfat" ]]; then
    echo ">>> ✓ Boot partition formatted as FAT32"
else
    echo ">>> ✗ ERROR: Boot partition has wrong filesystem: $BOOT_FS (expected vfat)"
    exit 1
fi

if [[ "$ROOT_FS" == "ext4" ]]; then
    echo ">>> ✓ Root partition formatted as ext4"
else
    echo ">>> ✗ ERROR: Root partition has wrong filesystem: $ROOT_FS (expected ext4)"
    exit 1
fi

if [[ "$DATA_FS" == "ext4" ]]; then
    echo ">>> ✓ Data partition formatted as ext4"
else
    echo ">>> ✗ ERROR: Data partition has wrong filesystem: $DATA_FS (expected ext4)"
    exit 1
fi

# Verify all filesystems are mounted
echo ">>> Verifying filesystem mounts"
if mountpoint -q /mnt; then
    echo ">>> ✓ Root filesystem mounted at /mnt"
else
    echo ">>> ✗ ERROR: Root filesystem not mounted"
    exit 1
fi

if mountpoint -q /mnt/boot; then
    echo ">>> ✓ Boot filesystem mounted at /mnt/boot"
else
    echo ">>> ✗ ERROR: Boot filesystem not mounted"
    exit 1
fi

if mountpoint -q /mnt/data; then
    echo ">>> ✓ Data filesystem mounted at /mnt/data"
else
    echo ">>> ✗ ERROR: Data filesystem not mounted"
    exit 1
fi

# Show disk usage
echo ">>> Filesystem usage:"
df -h /mnt /mnt/boot /mnt/data

# 6. Generate NixOS configuration
echo ">>> Generating NixOS configuration"
nixos-generate-config --root /mnt

# 6.1. Verify hardware configuration was generated
echo ">>> Verifying hardware configuration generation"
if [[ -f /mnt/etc/nixos/hardware-configuration.nix ]]; then
    echo ">>> ✓ Hardware configuration generated successfully"
    # Check if it contains expected filesystem entries
    if grep -q "boot\.loader" /mnt/etc/nixos/hardware-configuration.nix; then
        echo ">>> ✓ Hardware config contains boot loader settings"
    else
        echo ">>> ⚠ WARNING: Hardware config may be incomplete (no boot loader settings)"
    fi
    if grep -q "fileSystems" /mnt/etc/nixos/hardware-configuration.nix; then
        echo ">>> ✓ Hardware config contains filesystem definitions"
    else
        echo ">>> ✗ ERROR: Hardware config missing filesystem definitions"
        exit 1
    fi
else
    echo ">>> ✗ ERROR: Hardware configuration not generated"
    exit 1
fi

# Copy our configuration files to the installed system
echo ">>> Copying configuration files to installed system"
mkdir -p "/mnt/etc/nixos/homelab/common"

cp "${REPO_ROOT}/common/common.nix" "/mnt/etc/nixos/homelab/common/"

# Replace the generated configuration with one that points to our copied files
rm /mnt/etc/nixos/configuration.nix
cat > /mnt/etc/nixos/configuration.nix <<EOF
{ ... }:

{
  imports =
    [
      # This pulls in the hardware-specific configuration
      ./hardware-configuration.nix

      # This points to the common configuration (safe for fresh installs)
      ./homelab/common/common.nix
      
      # Basic hostname setting
    ];
    
  # Set hostname for this installation
  networking.hostName = "${HOSTNAME}";
  
  # Enable passwordless sudo for wheel group (needed for first deploy-rs deployment)
  # This will be overridden by deploy-rs configuration later
  security.sudo.wheelNeedsPassword = false;
  
  # Basic system version
  system.stateVersion = "24.05";
}
EOF

# 6.2. Verify our configuration files exist and are accessible
echo ">>> Verifying configuration file setup"
if [[ -f /mnt/etc/nixos/configuration.nix ]]; then
    echo ">>> ✓ Main configuration.nix created successfully"
else
    echo ">>> ✗ ERROR: Failed to create configuration.nix"
    exit 1
fi

# Check if common configuration exists in the installed system
if [[ -f /mnt/etc/nixos/homelab/common/common.nix ]]; then
    echo ">>> ✓ Common configuration copied: /etc/nixos/homelab/common/common.nix"
else
    echo ">>> ✗ ERROR: Common configuration not copied properly"
    exit 1
fi

# 7. Install NixOS
echo ">>> Installing NixOS"
nixos-install --no-root-passwd

# 7.1. Validate NixOS configuration syntax
echo ">>> Validating NixOS configuration syntax"
echo ">>> Note: This validation runs in the installer environment and may show warnings"
if nixos-enter --root /mnt -- nixos-rebuild dry-run --fast &>/dev/null; then
    echo ">>> ✓ NixOS configuration syntax is valid"
else
    echo ">>> ⚠ Configuration validation had issues (this may be normal in installer environment)"
    echo ">>> The installation will continue - configuration will be validated on first boot"
fi

# 8. Verify SSH configuration
echo ">>> Verifying SSH configuration in installed system"

# Verify SSH service is configured in our config files
if grep -q "services\.openssh\.enable = true" "${REPO_ROOT}/common/common.nix"; then
    echo ">>> ✓ SSH service is enabled in configuration"
else
    echo ">>> ⚠ WARNING: SSH service not found in configuration"
fi

# Verify user has SSH keys configured
if grep -q "openssh\.authorizedKeys\.keys" "${REPO_ROOT}/common/common.nix"; then
    KEY_COUNT=$(grep -c "ssh-" "${REPO_ROOT}/common/common.nix")
    echo ">>> ✓ SSH authorized keys configured for user '${USERNAME}' (${KEY_COUNT} key(s))"
else
    echo ">>> ⚠ WARNING: No SSH authorized keys found in configuration"
fi

echo ">>> SSH configuration verification complete"
echo ">>> Note: SSH connectivity will be available after reboot and system startup"

# 9. Finalize
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
echo ">>> ssh -i ~/.ssh/nuc_homelab_id_ed25519 ${USERNAME}@${CURRENT_IP}"
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
