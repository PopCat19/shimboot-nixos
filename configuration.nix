{ config, pkgs, lib, ... }:
{
  imports = [];

  # No bootloader - you're handling that yourself
  boot.loader.grub.enable = false;
  boot.loader.systemd-boot.enable = false;
  boot.kernelPackages = pkgs.linuxPackages_5_4;

  # Ensure your custom initrd—patched from shim—still loads these modules:
  boot.initrd.availableKernelModules = [
    "atkbd" # PS/2 keyboard
    "i8042" # PS/2 controller
    "serio_raw" # raw serio interface
    "usbcore"
    "usbhid"
    "hid_generic"
  ];
  boot.initrd.kernelModules = [];

  boot.loader.initScript.enable = true;

  # Force the kernel console to tty1, where getty is running
  boot.kernelParams = [ "console=tty1" ];

  # Create traditional Unix filesystem layout
  system.activationScripts.traditionalLayout = ''
    mkdir -p /sbin /usr/sbin
    ln -sf /init /sbin/init
    ln -sf /init /usr/sbin/init
  '';

  # Your patched systemd
  systemd.package = pkgs.systemd.overrideAttrs (old: {
    patches = (old.patches or []) ++
      [ ./nix/patches/systemd_unstable.patch ];
  });

  # Minimal system
  system.stateVersion = "24.11";

  system.copySystemConfiguration = true;

  # Disable all the networking
  networking.dhcpcd.enable = false;
  networking.useDHCP = false;
  systemd.network.enable = false;
  services.resolved.enable = false;

  # Keep it simple - no automatic networking
  networking.firewall.enable = false;

  # Tell NixOS this isn't really a container
  boot.isContainer = lib.mkForce false;

  # Essential packages
  environment.systemPackages = with pkgs; [
    busybox
    util-linux
    coreutils
    bash
    nano
    micro
    btop
    file
    which
    ranger
    # Add chvt for the bootstrap script
    kbd
  ];

  programs.fish.enable = true;

  time.timeZone = "America/New_York";
  services.xserver.xkb.layout = "us";
  i18n.defaultLocale = "en_US.UTF-8";

  services.getty.autologinUser = "root";

  # Make sure you have a root user with a shell
  users.users.root = {
    password = ""; # No password needed for autologin
    shell = pkgs.bash;
  };

  # Create a regular user too
  users.users.nixos-user = {
    isNormalUser = true;
    password = "";
    shell = pkgs.fish;
    extraGroups = [ "wheel" "video" "audio" "networkmanager" ];
  };

  # Allow empty passwords (temporary, for testing)
  users.allowNoPasswordLogin = true;
  security.pam.services.login.allowNullPassword = true;
  security.pam.services.passwd.allowNullPassword = true;

  # Disable the tmpfs on /tmp and let it be a normal directory on the root filesystem.
  systemd.mounts = [
    {
      what = "tmpfs";
      where = "/tmp";
      type = "tmpfs";
      options = "defaults,size=0"; # Effectively disables it by setting size to 0
    }
  ];

  # Dummy /boot filesystem to satisfy the nixos-generate build checks.
  fileSystems."/boot" = {
    device = "tmpfs";
    fsType = "tmpfs";
  };

  # Force override the filesystem device for shimboot
  fileSystems."/" = lib.mkForce {
    device = "/dev/disk/by-partlabel/shimboot_rootfs:nixos";
    fsType = "ext4";
  };
}
