{
  lib,
  stdenv,
  autoPatchelfHook,
  fetchurl,
  flutter,
  alsa-lib,
  cmake,
  gtk3,
  libepoxy,
  webkitgtk_4_1,
  gst_all_1,
  makeWrapper,
  writeShellScriptBin,
  zlib,
  libpulseaudio,
  lz4,
  libGL,
  libx11,
  libxcb,
  wayland,
  libgbm,
  libdrm,
  xz,
  freetype,
  harfbuzz,
  fontconfig,
  fribidi,
}:

let
  videoRuntimeLibraries = [
    alsa-lib libpulseaudio lz4 libGL libx11 libxcb wayland
    libgbm libdrm xz zlib freetype harfbuzz fontconfig fribidi
    stdenv.cc.cc.lib
  ];
  mdkSdk = fetchurl {
    url = "https://github.com/wang-bin/mdk-sdk/releases/download/v0.40.1/mdk-sdk-linux-x64.tar.xz";
    sha256 = "e53a38b6bcdce99cea852ecff25b0e4acc67539418a04b7c27868c24c130021d";
  };
  versionLine = lib.findFirst
    (line: lib.hasPrefix "version: " line)
    (throw "version is missing from pubspec.yaml")
    (lib.splitString "\n" (builtins.readFile ../pubspec.yaml));
  version = builtins.head (
    lib.splitString "+" (lib.removePrefix "version: " versionLine)
  );
  cmakeWithoutJni = writeShellScriptBin "cmake" ''
    sourceDir="''${!#}"
    pluginsFile="$sourceDir/flutter/generated_plugins.cmake"
    if [[ -f "$pluginsFile" ]]; then
      sed -i '/^  jni$/d' "$pluginsFile"
    fi
    exec ${cmake}/bin/cmake "$@"
  '';
in
flutter.buildFlutterApplication {
  pname = "omni-code";
  inherit version;

  src = lib.cleanSourceWith {
    src = ../.;
    filter = path: type:
      let
        name = baseNameOf path;
      in
      !builtins.elem name [
        ".dart_tool"
        ".git"
        ".idea"
        ".vscode"
        "build"
        "result"
      ];
  };

  pubspecLock = lib.importJSON ./pubspec.lock.json;
  # CMake normally downloads MDK into the fvp package. Nix dependencies are
  # read-only and builds have no network, so prepare a fixed, patched SDK first.
  customSourceBuilders.fvp = { src, version, ... }: stdenv.mkDerivation {
    pname = "pub-fvp";
    inherit src version;
    inherit (src) passthru;
    nativeBuildInputs = [ autoPatchelfHook ];
    buildInputs = videoRuntimeLibraries;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      cp -r . "$out"
      chmod -R u+w "$out"
      tar xf ${mdkSdk} -C "$out/linux"
      rm -rf "$out/linux/mdk-sdk/bin"
      find "$out/linux/mdk-sdk" -name '*.dsym' -delete
      substituteInPlace "$out/linux/CMakeLists.txt" \
        --replace-fail 'include(../cmake/deps.cmake)' \
          'include(mdk-sdk/lib/cmake/FindMDK.cmake)' \
        --replace-fail 'fvp_setup_deps()' ""
      printf '#pragma once\n#define FVP_VERSION "%s"\n' "${version}" > "$out/lib/src/version.h"
      runHook postInstall
    '';
  };
  dontUseCmakeConfigure = true;

  preBuild = ''
    export PATH="${cmakeWithoutJni}/bin:$PATH"
  '';

  nativeBuildInputs = [
    cmake
    makeWrapper
  ];
  buildInputs = [
    alsa-lib
    gtk3
    libepoxy
    webkitgtk_4_1
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    zlib.out
    zlib.dev
  ];

  CMAKE_LIBRARY_PATH = "${zlib.out}/lib";
  CMAKE_INCLUDE_PATH = "${zlib.dev}/include";

  postInstall = ''
    makeWrapper $out/app/$pname/omni_code $out/bin/omni-code \
      --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : ${
        lib.makeSearchPath "lib/gstreamer-1.0" [ gst_all_1.gst-plugins-base ]
      }

    install -Dm644 ${./omni-code.desktop} \
      $out/share/applications/omni-code.desktop
    install -Dm644 ${./omni-code.metainfo.xml} \
      $out/share/metainfo/com.omnistreamai.code.metainfo.xml
    install -Dm644 ${../web/icons/Icon-512.png} \
      $out/share/icons/hicolor/512x512/apps/com.omnistreamai.code.png
    install -Dm644 ${../LICENSE} \
      $out/share/licenses/omni-code/LICENSE
  '';

  meta = {
    description = "Flutter desktop client for managing coding agent sessions";
    homepage = "https://github.com/omni-stream-ai/omni-code";
    changelog = "https://github.com/omni-stream-ai/omni-code/releases/tag/v${version}";
    downloadPage = "https://github.com/omni-stream-ai/omni-code/releases";
    license = lib.licenses.mit;
    mainProgram = "omni-code";
    platforms = [ "x86_64-linux" ];
  };
}
