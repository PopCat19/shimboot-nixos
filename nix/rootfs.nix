# ./nix/rootfs.nix
{ pkgs, drivers }:

pkgs.buildEnv {
  name = "shimboot-nixos-fhs-rootfs";

  # A list of packages whose contents will be merged together
  # into a single FHS-style directory structure.
  paths = with pkgs; [
    # The core system, with our patch
    systemd

    # The essential XFCE desktop components
    xfce.xfce4-session
    xfce.xfce4-panel
    xfce.xfwm4
    xfce.xfce4-settings
    xfce.xfce4-terminal

    # The login manager to start the graphical session
    lightdm-gtk-greeter

    # Basic command-line tools
    bashInteractive
    coreutils
    neofetch

    # Our custom package containing the Chromebook-specific drivers
    drivers
  ];

  # We can add extra files here if needed, but for now, let's keep it simple.
  # The 'paths' option handles merging everything automatically.
}
