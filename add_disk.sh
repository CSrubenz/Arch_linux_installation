#!/bin/bash
# ==============================================================================
# AUTOMATED SECONDARY ENCRYPTED DISK ADDITION SCRIPT (LUKS + AUTO-UNLOCK)
# ==============================================================================
set -e

# Security check: Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "[!] ERROR: This script must be run as root (sudo)."
  exit 1
fi

echo "==> LIST OF AVAILABLE DISKS:"
lsblk -d -p -o NAME,SIZE,MODEL,TYPE | grep disk
echo ""

read -p "-> Enter the path of the NEW disk to format (e.g., /dev/nvme1n1 or /dev/sdb): " DISK

if [ ! -b "$DISK" ]; then
    echo "[!] ERROR: $DISK is not a valid block device."
    exit 1
fi

echo "WARNING: ALL DATA ON $DISK WILL BE ERASED!"
read -p "Are you sure you want to continue? (Type 'YES' to confirm): " CONFIRM
if [ "$CONFIRM" != "YES" ]; then
    echo "Operation cancelled."
    exit 0
fi

read -p "-> Enter the desired mount point (e.g., /mnt/Data or /home/username/data): " MOUNT_POINT
read -p "-> Enter your username (to grant ownership of this folder): " USER_NAME

DISK_NAME=$(basename "$DISK")
MAPPER_NAME="crypt_${DISK_NAME}"
KEY_DIR="/etc/luks-keys"
KEY_FILE="${KEY_DIR}/${DISK_NAME}.key"

# Initial Encryption (Recovery Password)
echo "==> Encrypting disk (Creating recovery password)..."
cryptsetup -y -v luksFormat "$DISK"

# Creation and addition of the keyfile for Auto-Unlock
echo "==> Configuring automatic unlock at boot..."
mkdir -p "$KEY_DIR"
chmod 700 "$KEY_DIR"

# Generating an ultra-secure 4096-bit random key
dd if=/dev/urandom of="$KEY_FILE" bs=1024 count=4
chmod 400 "$KEY_FILE"

echo "-> Please re-enter the recovery password to authorize the automatic keyfile:"
cryptsetup luksAddKey "$DISK" "$KEY_FILE"

# Opening the volume
echo "==> Opening the encrypted container..."
cryptsetup open "$DISK" "$MAPPER_NAME" --key-file "$KEY_FILE"

# Formatting to Ext4
echo "==> Formatting the volume to Ext4..."
mkfs.ext4 -m 1 /dev/mapper/"$MAPPER_NAME"

# Extracting UUIDs for system configuration
PHYS_UUID=$(blkid -s UUID -o value "$DISK")
MAPPER_UUID=$(blkid -s UUID -o value /dev/mapper/"$MAPPER_NAME")

# Updating /etc/crypttab (For automatic unlock)
echo "==> Updating /etc/crypttab..."
if ! grep -q "$MAPPER_NAME" /etc/crypttab; then
    echo "$MAPPER_NAME UUID=$PHYS_UUID $KEY_FILE luks" >> /etc/crypttab
fi

# Updating /etc/fstab (For automatic mounting)
echo "==> Updating /etc/fstab..."
if ! grep -q "$MOUNT_POINT" /etc/fstab; then
    echo "UUID=$MAPPER_UUID $MOUNT_POINT ext4 defaults,noatime 0 2" >> /etc/fstab
fi

# Mounting and Permissions
echo "==> Mounting the disk and setting permissions..."
mkdir -p "$MOUNT_POINT"
mount -a

# Grant ownership of the folder to the correct user
chown -R "$USER_NAME":"$USER_NAME" "$MOUNT_POINT"

echo ""
echo "[OK] SUCCESS! The disk $DISK is now configured."
echo "-> It is mounted at: $MOUNT_POINT"
echo "-> It will automatically unlock and mount at every boot."
