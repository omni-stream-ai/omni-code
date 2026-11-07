{ lib, writeShellApplication, auto-patchelf, patchelf, stdenv, alsa-lib
, libpulseaudio, lz4, libGL, libx11, libxcb, wayland, libgbm, libdrm
, xz, zlib, freetype, harfbuzz, fontconfig, fribidi }:

let
  libraries = [
    alsa-lib libpulseaudio lz4 libGL libx11 libxcb wayland
    libgbm libdrm xz zlib freetype harfbuzz fontconfig fribidi
    stdenv.cc.cc.lib
  ];
in
writeShellApplication {
  name = "omni-code-prepare-linux-bundle";
  runtimeInputs = [ auto-patchelf patchelf ];
  text = ''
    bundle="''${1:?Usage: omni-code-prepare-linux-bundle BUNDLE}"
    auto-patchelf \
      --paths "$bundle" \
      --libs "$bundle/lib" ${lib.escapeShellArgs (map (package: "${lib.getLib package}/lib") libraries)} \
      --preserve-origin --relativize-rpath
  '';
}
