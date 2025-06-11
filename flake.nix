# ./flake.nix
{
  description = "A declarative build for a NixOS-based shimboot image";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ (import ./nix/overlay.nix) ];
      };

      # We define our drivers as a fixed-output derivation.
      # This is the pure and correct way to handle the pre-extracted drivers.
      drivers = pkgs.stdenv.mkDerivation {
        name = "chromebook-drivers";
        
        # We lie to fetchurl. The URL is irrelevant. The HASH is everything.
        # Nix will check its store for something with this hash. If it doesn't
        # find it, it will fail. It will NOT try to download from the fake URL.
        src = pkgs.fetchurl {
          url = "file:///tmp/extracted-drivers.tar.gz"; # A lie. This path is never used.
          # This is your sacred hash. The cryptographic promise.
          sha256 = "sha256-yK1bsMLx82RTroRyPsol0d6YRZDmsmWRF4dcG3NlqHU=";
        };

        # The install phase simply copies the contents of the source
        # (which Nix provides from the store path matching the hash)
        # into the output directory.
        installPhase = ''
          mkdir -p $out
          cp -r ./* $out/
        '';
      };

    in {
      packages.${system} = {
        default = self.packages.${system}.rootfs;
        rootfs = import ./nix/rootfs.nix {
          inherit pkgs;
          inherit drivers;
        };
      };
    };
}
