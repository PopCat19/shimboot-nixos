# ./flake.nix
{
  description = "A declarative build for a NixOS-based shimboot image";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      # We'll build for x86_64 Linux.
      system = "x86_64-linux";

      # Apply our systemd patch overlay.
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ (import ./nix/overlay.nix) ];
      };

      # The path to the official shim image you downloaded.
      # You'll need to create this data directory and put the file there.
      shimFile = ./data/shim_board_name.bin;

    in {
      # The packages this flake provides.
      packages.${system} = {
        # The main build artifact: our FHS-compliant rootfs.
        default = self.packages.${system}.rootfs;

        # The rootfs itself.
        rootfs = import ./nix/rootfs.nix {
          inherit pkgs;
          # Pass our custom drivers package to the rootfs builder.
          drivers = self.packages.${system}.drivers;
        };

        # The custom drivers package, exposed for debugging.
        drivers = import ./nix/drivers.nix {
          inherit pkgs;
          inherit shimFile;
        };
      };
    };
}
