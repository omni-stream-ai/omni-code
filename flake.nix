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
        omni-code = pkgs.callPackage ./nix/omni-code.nix { };
        omni-code-bin = pkgs.callPackage ./nix/omni-code-bin.nix { };
        default = self.packages.${system}.omni-code;
      });

      apps = forAllSystems (pkgs: let system = pkgs.stdenv.hostPlatform.system; in {
        omni-code = {
          type = "app";
          program = "${self.packages.${system}.omni-code}/bin/omni-code";
          meta.description = "Run Omni Code built from source";
        };
        omni-code-bin = {
          type = "app";
          program = "${self.packages.${system}.omni-code-bin}/bin/omni-code";
          meta.description = "Run the prebuilt Omni Code release";
        };
        default = {
          type = "app";
          program = "${self.packages.${system}.omni-code}/bin/omni-code";
          meta.description = "Run Omni Code built from source";
        };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            flutter
            gtk3
            pkg-config
            jdk
            alsa-lib
            gst_all_1.gstreamer
            gst_all_1.gst-plugins-base
            zlib.out
            zlib.dev
          ];

          # JNI needs the JDK home, rather than the root of its Nix output.
          JAVA_HOME = pkgs.jdk.home;

          # Native plugins use CMake library discovery in addition to pkg-config.
          CMAKE_LIBRARY_PATH = pkgs.lib.makeLibraryPath [ pkgs.alsa-lib pkgs.zlib ];
          CMAKE_INCLUDE_PATH = "${pkgs.zlib.dev}/include";
        };
      });
    };
}
