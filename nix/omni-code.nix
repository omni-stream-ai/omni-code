{
  lib,
  flutter,
  alsa-lib,
  cmake,
  gtk3,
  gst_all_1,
  makeWrapper,
  writeShellScriptBin,
  zlib,
}:

let
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
