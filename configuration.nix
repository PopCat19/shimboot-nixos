{ config, pkgs, lib, ... }:
{
  imports = [ ];

  # No bootloader - you're handling that yourself
  boot.loader.grub.enable = false;
  boot.loader.systemd-boot.enable = false;
  
  boot.loader.initScript.enable = true;

  # Create traditional Unix filesystem layout
  system.activationScripts.traditionalLayout = ''
    mkdir -p /sbin /usr/sbin
    ln -sf /init /sbin/init
    ln -sf /init /usr/sbin/init
  '';
  
  # Your patched systemd
  systemd.package = pkgs.systemd.overrideAttrs (old: {
    patches = (old.patches or []) ++ [
      ./nix/patches/systemd_unstable.patch
    ];
  });

  # Minimal system
  system.stateVersion = "24.11";
  
  # Disable all the networking nonsense
  networking.dhcpcd.enable = false;
  networking.useDHCP = false;
  systemd.network.enable = false;
  services.resolved.enable = false;
  
  # Keep it simple - no automatic networking
  networking.firewall.enable = false;

  # Tell NixOS this isn't really a container
  boot.isContainer = lib.mkForce false;
  
  # Essential services only
  systemd.services."serial-getty@ttyS0".enable = true;
  
  # No GUI
  services.xserver.enable = false;
  
  # Essential packages
  environment.systemPackages = with pkgs; [
    busybox
    util-linux
  ];

  fileSystems."/" = {
    device = "/dev/disk/by-partlabel/shimboot_rootfs:nixos";
    fsType = "ext4";
  };
}
