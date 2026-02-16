# 🚀 Arch Linux Automated Deployment (Installer Scripts)

Custom, fully automated Arch Linux installation.
This repository contains the scripts to bootstrap a highly optimized, bloat-free Wayland environment (Hyprland) tailored for software development (Neovim/LSP) and gaming.

⚠️ **Architecture Note:** This repository uses a "Separation of Concerns" approach. It ONLY handles the OS installation and package provisioning. The actual configurations (dotfiles) are stored in a separate repository (`CSrubenz/dotfiles`) which will be automatically fetched during the setup phase.

## ✨ Features

* **🧠 Smart Hardware Detection:** Automatically configures drivers based on your profile (Desktop, ThinkPad T480, or Custom). Handles iGPU/dGPU stacking (Intel/AMD/Nvidia) flawlessly.
* **🔋 Form-Factor Aware:** Automatically installs `tlp`, `brightnessctl`, and `upower` (for merged battery stats) if a laptop is detected.
* **⌨️ Keyboard Patching:** Uses `keyd` at the kernel level to map missing ISO keys (`<` and `>`) on ANSI keyboards (like the imported T480).
* **🎮 Gaming Ready:** Pre-configured with Steam, Gamemode, Gamescope, MangoHud, Heroic Games Launcher, and ProtonUp-Qt.
* **💻 Dev Ready:** Fully loaded runtime environment for Neovim LSPs (Rust, Go, C/C++, Java, Python, PHP, Haskell, OCaml, LaTeX) and Fzf-Lua (`rg`, `fd`, `fzf`).
* **🪄 Seamless Handoff:** The installer automatically prepares the Phase 2 script in your new home directory with the correct permissions.

---

## 💿 Installation Guide

### Phase 1: Base System Installation (From Live USB)
1. Boot into the official Arch Linux Live USB.
2. Ensure you have an active internet connection (e.g., via ethernet or `iwctl`).
3. Clone this repository and execute the OS installer:

```bash
git clone [https://github.com/CSrubenz/arch-installer.git](https://github.com/CSrubenz/arch-installer.git)
cd arch-installer
chmod +x install_arch.sh
./install_arch.sh
```

Note: The script will guide you through partitioning (cfdisk) and ask for your hardware profile. Once finished, type reboot and remove the USB drive.

### Phase 2: User Provisioning & Dotfiles (After Reboot)

Log in with your newly created user account.

```bash
./setup.sh
```

Note: This script will install the AUR helper (yay), user-specific packages, clone CSrubenz/dotfiles repository, and deploy them using GNU Stow.

### Phase 3: Blast Off

Once setup_user.sh finishes, your system is fully configured. You can safely delete the Arch_linux_installation repository :

```bash
rm -rf Arch_linux_installation
```

Start your Wayland session :

```bash
Hyprland
```

Enjoy!

## 🛠️ Post-Installation Notes

* Audio: Managed by PipeWire. Use the Waybar module or pavucontrol to manage outputs.

* Bluetooth: Managed by bluez and the blueman-applet running in the system tray.

* Typographic Quotes (T480): If using the T480 ANSI profile, AltGr + < outputs <.
