# ./nix/rootfs.nix
{ pkgs, drivers }:

pkgs.buildFHSUserEnv {
  name = "shimboot-nixos-fhs-rootfs";

  # List all the packages you want in your final system.
  targetPkgs = ps: with ps; [
    # The patched systemd from our overlay
    systemd
    # A basic desktop and login manager
    (xfce.override {
      withGtk3 = true;
    })
    lightdm-gtk-greeter
    # Basic command line tools
    bashInteractive
    coreutils
    # Add whatever else you want here...
    neofetch
    firefox
  ];

  # This runs after the environment is built to add extra files.
  extraCommands = ''
    # Copy the drivers from our custom package into the FHS root.
    cp -r --no-preserve=ownership ${drivers}/lib/* $out/lib/

    # Add other custom configs here, replacing the old `rootfs` dir.
    # For example:
    mkdir -p $out/etc/modules-load.d
    echo "tun" > $out/etc/modules-load.d/tun.conf
  '';
}
