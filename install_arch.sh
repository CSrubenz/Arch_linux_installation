#!/bin/bash
# ==============================================================================
# ARCH LINUX INSTALLATION AND HARDWARE DRIVERS (LUKS + LVM)
# ==============================================================================
set -e

if [ "$1" != "--chroot" ]; then
    echo "==> STARTING ARCH LINUX INSTALLATION..."

    # ==========================================================================
    # HARDWARE CONFIGURATION MENU
    # ==========================================================================
    echo "==> SELECT THE HARDWARE PROFILE FOR THIS MACHINE:"
    echo "  1) Desktop (Ryzen 7700 [AMD iGPU], RX 6900 XT [AMD dGPU], AZERTY)"
    echo "  2) Lenovo T480 (Intel [iGPU], MX150 [Nvidia dGPU], QWERTY->AZERTY)"
    echo "  3) Custom (Manual configuration)"
    read -p "-> " PROFIL_CHOIX

    if [ "$PROFIL_CHOIX" = "1" ]; then
        HW_HOSTNAME="desktop"
        HW_TYPE="desktop"
        HW_CPU="amd"
        HW_IGPU="amd"
        HW_DGPU="amd"
        HW_KEY_SOFT="fr"
        HW_KEY_PHYS="iso"
    elif [ "$PROFIL_CHOIX" = "2" ]; then
        HW_HOSTNAME="t480"
        HW_TYPE="laptop"
        HW_CPU="intel"
        HW_IGPU="intel"
        HW_DGPU="nvidia"
        HW_KEY_SOFT="fr"
        HW_KEY_PHYS="ansi"
    else
        echo "--- MANUAL CONFIGURATION ---"
        read -p "-> Hostname: " HW_HOSTNAME

        echo "-> Type of machine? [1] Desktop  [2] Laptop"
        read -p "   Choice: " type_c
        [ "$type_c" = "1" ] && HW_TYPE="desktop" || HW_TYPE="laptop"

        echo "-> Processor (CPU)? [1] AMD  [2] Intel"
        read -p "   Choice: " cpu_c
        [ "$cpu_c" = "1" ] && HW_CPU="amd" || HW_CPU="intel"

        echo "-> Integrated Graphics (iGPU)? [0] None  [1] Intel  [2] AMD"
        read -p "   Choice: " igpu_c
        case $igpu_c in
            1) HW_IGPU="intel" ;;
            2) HW_IGPU="amd" ;;
            *) HW_IGPU="none" ;;
        esac

        echo "-> Dedicated Graphics (dGPU)? [0] None  [1] AMD  [2] Nvidia  [3] Intel"
        read -p "   Choice: " dgpu_c
        case $dgpu_c in
            1) HW_DGPU="amd" ;;
            2) HW_DGPU="nvidia" ;;
            3) HW_DGPU="intel" ;;
            *) HW_DGPU="none" ;;
        esac

        read -p "-> Software keyboard layout (e.g., fr, us): " HW_KEY_SOFT

        echo "-> Physical keyboard format? [1] Eu (ISO)  [2] US (ANSI)"
        read -p "   Choice: " key_c
        [ "$key_c" = "1" ] && HW_KEY_PHYS="iso" || HW_KEY_PHYS="ansi"
    fi

    # ==========================================================================
    # BASIC SETUP (Network, Mirrors, Disks)
    # ==========================================================================
    echo "==> Checking network connection..."
    ping -c 3 archlinux.org > /dev/null || (echo "[!] ERROR: No internet connection." && exit 1)
    timedatectl set-ntp true

    echo "==> Optimizing pacman mirrors..."
    pacman -Sy --noconfirm reflector
    reflector --country France --age 24 --sort rate --save /etc/pacman.d/mirrorlist

    # ==========================================================================
    # DISK MANAGEMENT (LUKS + LVM)
    # ==========================================================================
    echo "==> DISK MANAGEMENT"
    lsblk
    read -p "-> Which disk to install on? (e.g., /dev/nvme0n1): " DISK
    echo "-> Press Enter to launch cfdisk."
    echo "   [!] Create ONLY TWO partitions: 1=EFI (e.g., 500M), 2=Linux Filesystem (The Rest)"
    read
    cfdisk $DISK

    lsblk $DISK
    read -p "-> EFI Partition (e.g., ${DISK}p1): " PART_EFI
    read -p "-> Partition to Encrypt (e.g., ${DISK}p2): " PART_CRYPT

    # LVM Sizes
    read -p "-> Enter SWAP size in GB (e.g., 16): " SWAP_SIZE
    read -p "-> Enter ROOT size in GB (e.g., 50, or leave empty to use 100% of remaining disk): " ROOT_SIZE

    # Encryption
    echo "==> Encrypting $PART_CRYPT (WARNING: This will erase the partition!)..."
    echo "-> REMINDER: Type your LUKS password in QWERTY layout just in case!"
    cryptsetup -y -v luksFormat $PART_CRYPT
    echo "-> Opening the encrypted container..."
    cryptsetup open $PART_CRYPT cryptlvm

    # LVM Creation
    echo "==> Creating LVM Volumes inside the encrypted container..."
    pvcreate /dev/mapper/cryptlvm
    vgcreate vg0 /dev/mapper/cryptlvm

    if [ -n "$SWAP_SIZE" ]; then
        lvcreate -L ${SWAP_SIZE}G vg0 -n swap
    fi

    if [ -n "$ROOT_SIZE" ]; then
        lvcreate -L ${ROOT_SIZE}G vg0 -n root
        lvcreate -l 100%FREE vg0 -n home
    else
        lvcreate -l 100%FREE vg0 -n root
    fi

    echo "==> Formatting and Mounting LVM Volumes..."
    mkfs.fat -F32 $PART_EFI
    mkfs.ext4 -F /dev/vg0/root
    [ -b "/dev/vg0/home" ] && mkfs.ext4 -F /dev/vg0/home
    [ -b "/dev/vg0/swap" ] && mkswap /dev/vg0/swap && swapon /dev/vg0/swap

    mount /dev/vg0/root /mnt
    mkdir -p /mnt/boot
    mount $PART_EFI /mnt/boot
    if [ -b "/dev/vg0/home" ]; then
        mkdir -p /mnt/home
        mount /dev/vg0/home /mnt/home
    fi

    # Added lvm2 to the base pacstrap
    echo "==> Installing base system..."
    pacstrap /mnt base linux linux-firmware nvim git stow sudo lvm2
    genfstab -U /mnt >> /mnt/etc/fstab

    # SAVE HARDWARE PROFILE AND LUKS UUID FOR THE CHROOT
    CRYPT_UUID=$(blkid -s UUID -o value $PART_CRYPT)

    echo "HW_HOSTNAME=$HW_HOSTNAME" > /mnt/etc/arch_hw_profile.conf
    echo "HW_TYPE=$HW_TYPE" >> /mnt/etc/arch_hw_profile.conf
    echo "HW_CPU=$HW_CPU" >> /mnt/etc/arch_hw_profile.conf
    echo "HW_IGPU=$HW_IGPU" >> /mnt/etc/arch_hw_profile.conf
    echo "HW_DGPU=$HW_DGPU" >> /mnt/etc/arch_hw_profile.conf
    echo "HW_KEY_SOFT=$HW_KEY_SOFT" >> /mnt/etc/arch_hw_profile.conf
    echo "HW_KEY_PHYS=$HW_KEY_PHYS" >> /mnt/etc/arch_hw_profile.conf
    echo "CRYPT_UUID=$CRYPT_UUID" >> /mnt/etc/arch_hw_profile.conf

    echo "==> Entering chroot environment..."
    cp "$0" /mnt/install_arch.sh
    cp "$(dirname "$0")/setup.sh" /mnt/setup.sh
    arch-chroot /mnt /install_arch.sh --chroot

    echo "[OK] OS INSTALLED SUCCESSFULLY (ENCRYPTED LVM)!"
    echo "-> Type 'reboot', log in, and run ./setup.sh."
    umount -R /mnt
    swapoff -a
    vgchange -an vg0
    cryptsetup close cryptlvm
    exit 0
fi

# ==============================================================================
# CHROOT PHASE (Executed inside the new system)
# ==============================================================================
source /etc/arch_hw_profile.conf

# 1. Base (Timezone, Locale, Hostname)
echo "==> Configuring Timezone and Locale..."
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
hwclock --systohc
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
sed -i "s/^#$HW_KEY_SOFT\_/""$HW_KEY_SOFT""\_/" /etc/locale.gen || sed -i 's/^#fr_FR.UTF-8/fr_FR.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=$HW_KEY_SOFT" > /etc/vconsole.conf
echo "$HW_HOSTNAME" > /etc/hostname

echo "==> Installing Network dependencies..."
pacman -S --noconfirm networkmanager wpa_supplicant wireless_tools network-manager-applet dialog

echo "==> Set ROOT password:"
passwd

read -p "-> Enter new username: " USER_NAME
useradd -m -G wheel,video,audio -s /bin/bash $USER_NAME
passwd $USER_NAME
# Allow wheel group members to use sudo
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo "==> Preparing setup script for $USER_NAME..."
mv /setup.sh /home/$USER_NAME/
chown $USER_NAME:$USER_NAME /home/$USER_NAME/setup.sh
chmod +x /home/$USER_NAME/setup.sh

# ==========================================================================
# LUKS + LVM SYSTEM CONFIGURATION (MKINITCPIO & GRUB)
# ==========================================================================
echo "==> Configuring mkinitcpio for Encryption and LVM..."
sed -i 's/^HOOKS=(.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt lvm2 filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

echo "==> Installing GRUB Bootloader..."
pacman -S --noconfirm grub efibootmgr os-prober mtools dosfstools

# Modify GRUB to unlock LUKS
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=${CRYPT_UUID}:cryptlvm root=/dev/vg0/root\"|" /etc/default/grub
sed -i 's/^#GRUB_ENABLE_CRYPTODISK=y/GRUB_ENABLE_CRYPTODISK=y/' /etc/default/grub

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

echo "==> Installing CPU Microcode..."
[ "$HW_CPU" = "intel" ] && pacman -S --noconfirm intel-ucode
[ "$HW_CPU" = "amd" ] && pacman -S --noconfirm amd-ucode

# ==========================================================================
# SMART GPU DRIVER STACKING
# ==========================================================================
GPU_PKGS=""

# iGPU logic
[ "$HW_IGPU" = "intel" ] && GPU_PKGS="$GPU_PKGS mesa vulkan-intel"
[ "$HW_IGPU" = "amd" ] && GPU_PKGS="$GPU_PKGS mesa vulkan-radeon xf86-video-amdgpu"

# dGPU logic
[ "$HW_DGPU" = "amd" ] && GPU_PKGS="$GPU_PKGS mesa vulkan-radeon xf86-video-amdgpu"
[ "$HW_DGPU" = "nvidia" ] && GPU_PKGS="$GPU_PKGS nvidia nvidia-utils"
[ "$HW_DGPU" = "intel" ] && GPU_PKGS="$GPU_PKGS mesa vulkan-intel"

# Remove duplicates and install
GPU_PKGS=$(echo "$GPU_PKGS" | tr ' ' '\n' | sort -u | tr '\n' ' ')
echo "==> Installing graphics drivers: $GPU_PKGS"
pacman -S --noconfirm $GPU_PKGS

# ==========================================================================
# OFFICIAL PACKAGES INSTALLATION
# ==========================================================================
echo "==> Enabling [multilib] repository for Steam..."
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
pacman -Sy

echo "==> Installing Core Desktop (Hyprland & Wayland tools)..."
pacman -S --noconfirm \
    hyprland waybar foot fuzzel hyprpaper mako polkit-kde-agent \
    wlr-randr wl-clipboard slurp grim wlsunset wtype \
    pipewire pipewire-audio pipewire-pulse pipewire-alsa wireplumber \
    pavucontrol playerctl \
    bluez bluez-utils blueman

echo "==> Installing specific hardware tools..."
if [ "$HW_TYPE" = "laptop" ]; then
    echo "==> Laptop detected: Installing TLP and brightnessctl..."
    pacman -S --noconfirm tlp brightnessctl upower
    systemctl enable tlp
fi

echo "==> Installing Apps & Fonts (Multimedia, PDF, Chinese input)..."
pacman -S --noconfirm \
    firefox pcmanfm gvfs mpv imv yt-dlp imagemagick ffmpeg \
    zathura zathura-cb zathura-djvu zathura-pdf-mupdf zathura-ps \
    noto-fonts noto-fonts-emoji noto-fonts-cjk noto-fonts-extra ttf-nerd-fonts-symbols \
    wqy-zenhei wqy-microhei wqy-bitmapfont \
    fcitx5 fcitx5-im fcitx5-chinese-addons

# Wayland environment variables (required for fcitx5 Chinese input)
echo "GTK_IM_MODULE=fcitx" >> /etc/environment
echo "QT_IM_MODULE=fcitx" >> /etc/environment
echo "XMODIFIERS=@im=fcitx" >> /etc/environment

# Enable Core Services
echo "==> Enabling system services..."
systemctl enable NetworkManager
systemctl enable bluetooth

# Clean up
rm /install_arch.sh
