{ lib, stdenv, fetchurl, autoPatchelfHook, makeWrapper, alsa-lib, gtk3, glib, gst_all_1 }:

stdenv.mkDerivation rec {
  pname = "omni-code";
  version = "0.7.0";

  src = fetchurl {
    url = "https://github.com/omni-stream-ai/omni-code/releases/download/v${version}/omni-code-linux-x86_64.tar.gz";
    hash = "sha256-4V/89zdWo8H198dxOj2XVbZUMfWJO6Ysz+roDDIDbzI=";
  };

  nativeBuildInputs = [ autoPatchelfHook makeWrapper ];
  buildInputs = [ alsa-lib gtk3 glib gst_all_1.gstreamer gst_all_1.gst-plugins-base ];
  autoPatchelfIgnoreMissingDeps = [ "libjvm.so" ];

  unpackPhase = ''
    tar -xzf $src
    cd omni-code-linux-x86_64
  '';

  installPhase = ''
    mkdir -p $out/opt/omni-code $out/bin $out/share/applications $out/share/metainfo $out/share/licenses/omni-code
    cp -r . $out/opt/omni-code/
    makeWrapper $out/opt/omni-code/omni_code $out/bin/omni-code \
      --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : ${lib.makeSearchPath "lib/gstreamer-1.0" [ gst_all_1.gst-plugins-base ]}
    install -Dm644 ${./omni-code.desktop} $out/share/applications/omni-code.desktop
    install -Dm644 ${./omni-code.metainfo.xml} $out/share/metainfo/com.omnistreamai.code.metainfo.xml
    install -Dm644 ${../web/icons/Icon-512.png} $out/share/icons/hicolor/512x512/apps/com.omnistreamai.code.png
    install -Dm644 ${../LICENSE} $out/share/licenses/omni-code/LICENSE
  '';

  meta = {
    description = "Flutter desktop client for managing coding agent sessions";
    homepage = "https://github.com/omni-stream-ai/omni-code";
    license = lib.licenses.mit;
    mainProgram = "omni-code";
    platforms = [ "x86_64-linux" ];
  };
}
