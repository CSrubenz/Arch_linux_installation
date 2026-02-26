#!/bin/bash
# ==============================================================================
# AUTOMATED DISK CONFIGURATION SCRIPT (SMART DETECTION & AUTO-UNLOCK)
# ==============================================================================
set -e

if [ "$EUID" -ne 0 ]; then
  echo "[!] ERROR: This script must be run as root (sudo)."
  exit 1
fi

echo "==> LIST OF AVAILABLE DISKS:"
lsblk -d -p -o NAME,SIZE,MODEL,TYPE | grep disk
echo ""

read -p "-> Enter the path of the disk (e.g., /dev/nvme1n1 or /dev/sdb): " DISK

if [ ! -b "$DISK" ]; then
    echo "[!] ERROR: $DISK is not a valid block device."
    exit 1
fi

read -p "-> Enter the desired mount point (e.g., /mnt/Data or /home/user/data): " MOUNT_POINT
read -p "-> Enter your username (to grant ownership of this folder): " USER_NAME

echo ""
echo "================================================================="
echo "==> WHAT DO YOU WANT TO DO WITH $DISK?"
echo "1) NEW DISK: Format and encrypt (ERASES ALL DATA)"
echo "2) EXISTING DISK: Mount the disk (Auto-detects encryption)"
echo "================================================================="
read -p "-> Enter your choice (1 or 2): " ACTION

DISK_NAME=$(basename "$DISK")
MAPPER_NAME="crypt_${DISK_NAME}"
KEY_DIR="/etc/luks-keys"
KEY_FILE="${KEY_DIR}/${DISK_NAME}.key"

IS_LUKS=false
FORMAT_NEEDED=false

# ==========================================
# DETERMINE ACTION AND STATE
# ==========================================
if [ "$ACTION" == "1" ]; then
    echo ""
    echo "WARNING: ALL DATA ON $DISK WILL BE ERASED!"
    read -p "Do you want to continue? (Type 'YES' to confirm): " CONFIRM
    if [ "$CONFIRM" != "YES" ]; then
        echo "Operation cancelled."
        exit 0
    fi

    echo "==> LUKS Formatting (Creating recovery password)..."

    while ! cryptsetup -y -v luksFormat "$DISK"; do
        echo "[!] Formatting error. Please try again."
    done

    IS_LUKS=true
    FORMAT_NEEDED=true

elif [ "$ACTION" == "2" ]; then
    echo ""
    echo "==> Analyzing the existing disk..."

    # check if the disk has a LUKS header
    if cryptsetup isLuks "$DISK" >/dev/null 2>&1; then
        echo "-> DETECTION: This disk is ENCRYPTED (LUKS)."
        IS_LUKS=true
    else
        echo "-> DETECTION: This disk is STANDARD (Unencrypted)."
    fi
else
    echo "[!] Invalid choice. Cancelling."
    exit 1
fi

# ==========================================
# ENCRYPTION HANDLING (If applicable)
# ==========================================
if [ "$IS_LUKS" = true ]; then
    echo "==> Configuring automatic unlock at boot..."
    mkdir -p "$KEY_DIR"
    chmod 700 "$KEY_DIR"

    # Create the keyfile if it doesn't exist and save to your root to auto-unlock
    if [ ! -f "$KEY_FILE" ]; then
        dd if=/dev/urandom of="$KEY_FILE" bs=1024 count=4 status=none
        chmod 400 "$KEY_FILE"
    fi

    echo "-> Please enter the LUKS password for the disk to authorize auto-unlock:"

    while ! cryptsetup luksAddKey "$DISK" "$KEY_FILE"; do
        echo "[!] Incorrect password or error. Please try again."
    done

    echo "==> Opening the encrypted volume..."
    cryptsetup open "$DISK" "$MAPPER_NAME" --key-file "$KEY_FILE"

    if [ "$FORMAT_NEEDED" = true ]; then
        echo "==> Formatting the volume to Ext4..."
        mkfs.ext4 -m 1 /dev/mapper/"$MAPPER_NAME"
    fi

    TARGET_DEVICE="/dev/mapper/$MAPPER_NAME"
    PHYS_UUID=$(blkid -s UUID -o value "$DISK")

    echo "==> Updating /etc/crypttab..."
    if ! grep -q "$MAPPER_NAME" /etc/crypttab; then
        echo "$MAPPER_NAME UUID=$PHYS_UUID $KEY_FILE luks" >> /etc/crypttab
    fi
else
    TARGET_DEVICE="$DISK"
fi

# ==========================================
# MOUNTING AND PERMISSIONS
# ==========================================
TARGET_UUID=$(blkid -s UUID -o value "$TARGET_DEVICE")
FS_TYPE=$(blkid -s TYPE -o value "$TARGET_DEVICE")

if [ -z "$FS_TYPE" ]; then
    echo "[!] Cannot detect the file system on $TARGET_DEVICE. Is the disk formatted?"
    exit 1
fi

echo "==> Updating /etc/fstab..."
if ! grep -q "$MOUNT_POINT" /etc/fstab; then
    echo "UUID=$TARGET_UUID $MOUNT_POINT $FS_TYPE defaults,noatime 0 2" >> /etc/fstab
fi

echo "==> Mounting the disk and setting permissions..."
mkdir -p "$MOUNT_POINT"
mount -a
chown -R "$USER_NAME":"$USER_NAME" "$MOUNT_POINT"

echo ""
echo "================================================================="
echo "[OK] SUCCESS! The disk $DISK is configured."
echo "-> Mounted at: $MOUNT_POINT (Format: $FS_TYPE)"
echo "-> Available space:"
df -h "$MOUNT_POINT" | tail -n 1
echo "================================================================="
