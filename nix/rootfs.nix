# ./nix/rootfs.nix
{ pkgs, drivers }:

pkgs.buildFHSEnv {
  name = "shimboot-nixos-fhs-rootfs";

  targetPkgs = ps: with ps; [
    systemd
    xfce.xfce4-session
    xfce.xfce4-panel
    xfce.xfwm4
    xfce.xfce4-settings
    xfce.xfce4-terminal
    lightdm-gtk-greeter
    bashInteractive
    coreutils
    neofetch
    # firefox # love exit code 137
  ];

  extraCommands = ''
    cp -r --no-preserve=ownership ${drivers}/lib/* $out/lib/
    mkdir -p $out/etc/modules-load.d
    echo "tun" > $out/etc/modules-load.d/tun.conf
  '';
}
