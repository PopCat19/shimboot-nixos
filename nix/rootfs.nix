# ./nix/rootfs.nix
{ pkgs, drivers }:

pkgs.buildFHSEnv {
  name = "shimboot-nixos-fhs-rootfs";

  targetPkgs = ps: with ps; [
    systemd
    xfce.xfwm4
    lightdm-gtk-greeter
    bashInteractive
    coreutils
    neofetch
    firefox
  ];

  extraCommands = ''
    cp -r --no-preserve=ownership ${drivers}/lib/* $out/lib/
    mkdir -p $out/etc/modules-load.d
    echo "tun" > $out/etc/modules-load.d/tun.conf
  '';
}
