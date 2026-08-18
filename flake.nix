{
  description = "Omni Code Flutter desktop client";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system:
        f (import nixpkgs { inherit system; }));
    in {
      packages = forAllSystems (pkgs: let system = pkgs.stdenv.hostPlatform.system; in {
        omni-code = pkgs.callPackage ./nix/omni-code-bin.nix { };
        default = self.packages.${system}.omni-code;
      });

      apps = forAllSystems (pkgs: let system = pkgs.stdenv.hostPlatform.system; in {
        default = {
          type = "app";
          program = "${self.packages.${system}.omni-code}/bin/omni-code";
          meta.description = "Run Omni Code";
        };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell { packages = with pkgs; [ flutter gtk3 pkg-config ]; };
      });
    };
}
