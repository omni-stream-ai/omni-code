#!/usr/bin/env bash
set -euo pipefail

pkgver="${1:?version required}"
repo="${2:-omni-stream-ai/omni-code}"
license_sha="${3:?license sha required}"
linux_x86_sha="${4:?linux x86 sha required}"
output_dir="${5:-aur-bin}"

mkdir -p "$output_dir"

cat > "$output_dir/PKGBUILD" <<EOF
# Maintainer: Junjie <junjie@omni-stream.ai>
pkgname=omni-code-bin
pkgver=${pkgver}
pkgrel=1
pkgdesc="Flutter desktop client for managing Omni Code bridge sessions"
arch=('x86_64')
url="https://github.com/${repo}"
license=('MIT')
depends=('gcc-libs' 'glib2' 'gstreamer' 'gst-plugins-base-libs' 'gtk3')
provides=('omni-code')
conflicts=('omni-code')
source=("omni-code.desktop"
        "omni-code.png"
        "LICENSE-\$pkgver::https://raw.githubusercontent.com/${repo}/v\${pkgver}/LICENSE")
source_x86_64=("omni-code-\$pkgver-linux-x86_64.tar.gz::https://github.com/${repo}/releases/download/v\${pkgver}/omni-code-linux-x86_64.tar.gz")
sha256sums=('SKIP'
            'SKIP'
            '${license_sha}')
sha256sums_x86_64=('${linux_x86_sha}')

package() {
    install -d "\$pkgdir/opt/omni-code"
    cp -a "\$srcdir/omni-code-linux-x86_64/." "\$pkgdir/opt/omni-code/"

    install -Dm644 "\$srcdir/LICENSE-\$pkgver" "\$pkgdir/usr/share/licenses/\$pkgname/LICENSE"
    install -Dm644 "\$srcdir/omni-code.desktop" "\$pkgdir/usr/share/applications/omni-code.desktop"
    install -Dm644 "\$srcdir/omni-code.png" "\$pkgdir/usr/share/icons/hicolor/512x512/apps/omni-code.png"

    install -d "\$pkgdir/usr/bin"
    ln -sf "/opt/omni-code/omni_code" "\$pkgdir/usr/bin/omni-code"
}
EOF

cat > "$output_dir/omni-code.desktop" <<'EOF'
[Desktop Entry]
Name=Omni Code
Comment=Flutter client for managing Omni Code bridge sessions
Exec=omni-code
Icon=omni-code
Terminal=false
Type=Application
Categories=Development;Utility;
StartupNotify=true
StartupWMClass=omni_code
EOF

cat > "$output_dir/.SRCINFO" <<EOF
pkgbase = omni-code-bin
	pkgdesc = Flutter desktop client for managing Omni Code bridge sessions
	pkgver = ${pkgver}
	pkgrel = 1
	url = https://github.com/${repo}
	arch = x86_64
	license = MIT
	depends = gcc-libs
	depends = glib2
	depends = gstreamer
	depends = gst-plugins-base-libs
	depends = gtk3
	provides = omni-code
	conflicts = omni-code
	source = omni-code.desktop
	source = omni-code.png
	source = LICENSE-${pkgver}::https://raw.githubusercontent.com/${repo}/v${pkgver}/LICENSE
	sha256sums = SKIP
	sha256sums = SKIP
	sha256sums = ${license_sha}
	source_x86_64 = omni-code-${pkgver}-linux-x86_64.tar.gz::https://github.com/${repo}/releases/download/v${pkgver}/omni-code-linux-x86_64.tar.gz
	sha256sums_x86_64 = ${linux_x86_sha}

pkgname = omni-code-bin
EOF
