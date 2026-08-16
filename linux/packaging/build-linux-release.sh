#!/usr/bin/env bash
# Build, package and checksum a distributable Linux release of Field Kit.
#
# Produces, under dist/:
#   fieldkit_<version>_amd64.deb           desktop-integrated install (Debian/Ubuntu/Mint/Pop!_OS)
#   FieldKit-<version>-linux-x64.tar.gz    portable bundle for everything else
#   SHA256SUMS.linux                       checksums for both
#
# Run it on a Linux host that already builds Flutter desktop. Nothing here needs
# root: the .deb is assembled from a staging tree with fakeroot-free dpkg-deb.
set -euo pipefail

cd "$(dirname "$0")/../.."          # -> repo root
REPO_ROOT="$PWD"
PKG_DIR="$REPO_ROOT/linux/packaging"
APP_ID="com.labaccessnow.fieldkit"
BIN_NAME="fieldkit"

VERSION="$(awk '/^version:/ {split($2, a, "+"); print a[1]; exit}' pubspec.yaml)"
[ -n "$VERSION" ] || { echo "could not read version from pubspec.yaml" >&2; exit 1; }
echo "==> fieldkit $VERSION"

echo "==> flutter build linux --release"
flutter build linux --release

BUNDLE="build/linux/x64/release/bundle"
[ -x "$BUNDLE/$BIN_NAME" ] || { echo "expected $BUNDLE/$BIN_NAME — did BINARY_NAME change?" >&2; exit 1; }

DIST="$REPO_ROOT/dist"
STAGE="$DIST/stage"
rm -rf "$STAGE" "$DIST/${BIN_NAME}_"*.deb "$DIST/FieldKit-"*"-linux-x64.tar.gz" "$DIST/SHA256SUMS.linux"
mkdir -p "$DIST"

# ---------------------------------------------------------------- staging tree
# The bundle lives under /opt because Flutter's loader resolves data/ and lib/
# relative to the executable; splitting it across /usr/bin and /usr/lib would
# break that. /usr/bin gets a symlink so `fieldkit` is on PATH.
install -d "$STAGE/opt/$BIN_NAME" "$STAGE/usr/bin" "$STAGE/usr/share/applications"
cp -r "$BUNDLE/." "$STAGE/opt/$BIN_NAME/"
ln -sf "/opt/$BIN_NAME/$BIN_NAME" "$STAGE/usr/bin/$BIN_NAME"

for size in 16 24 32 48 64 128 256 512; do
  install -Dm644 "$PKG_DIR/icons/$size.png" \
    "$STAGE/usr/share/icons/hicolor/${size}x${size}/apps/$APP_ID.png"
done
install -Dm644 "$PKG_DIR/$APP_ID.desktop" \
  "$STAGE/usr/share/applications/$APP_ID.desktop"
install -Dm644 "$REPO_ROOT/LICENSE" "$STAGE/usr/share/doc/$BIN_NAME/copyright"

# ------------------------------------------- prune provably-unused native bits
# Some plugins drag in libdartjni.so (Android bindings) which links libjvm.so
# and would make a JRE a dependency of a desktop app. Field Kit shouldn't have
# it at all — but check-and-prune rather than assume, so this stays correct if
# a future plugin changes the picture.
JNI="$STAGE/opt/$BIN_NAME/lib/libdartjni.so"
if [ -f "$JNI" ]; then
  REFS=$( { ldd "$STAGE/opt/$BIN_NAME/$BIN_NAME"
            for f in "$STAGE/opt/$BIN_NAME"/lib/*.so; do
              [ "$f" = "$JNI" ] || ldd "$f"
            done
          } 2>/dev/null | grep -c dartjni || true )
  STRS=$(strings "$STAGE/opt/$BIN_NAME/lib/libapp.so" 2>/dev/null | grep -c dartjni || true)
  if [ "$REFS" -eq 0 ] && [ "$STRS" -eq 0 ]; then
    echo "==> dropping unreferenced libdartjni.so (it would pull in a JRE)"
    rm -f "$JNI"
  else
    echo "==> keeping libdartjni.so — now referenced (ldd=$REFS strings=$STRS)"
  fi
fi

# ------------------------------------------------------- runtime dependencies
# dpkg-shlibdeps reads what the artefacts actually link against and emits proper
# versioned constraints. Hand-maintaining a Depends list silently rots the day a
# plugin is added; resolving paths with dpkg -S does not survive usrmerge, since
# ldd reports /lib/... while dpkg's database records /usr/lib/....
echo "==> resolving runtime dependencies"
install -d "$STAGE/DEBIAN" "$STAGE/debian"
cat > "$STAGE/debian/control" <<EOF
Source: $BIN_NAME

Package: $BIN_NAME
Architecture: amd64
EOF
DEPS="$(cd "$STAGE" && dpkg-shlibdeps -O --ignore-missing-info \
          -l"$PWD/opt/$BIN_NAME/lib" \
          "opt/$BIN_NAME/$BIN_NAME" "opt/$BIN_NAME"/lib/*.so 2>/dev/null |
        sed -n 's/^shlibs:Depends=//p')"
rm -rf "$STAGE/debian"
echo "    ${DEPS:-<none resolved>}"
[ -n "$DEPS" ] || { echo "no dependencies resolved — refusing to ship an unrunnable .deb" >&2; exit 1; }
case "$DEPS" in
  *jre*|*jdk*|*java*)
    echo "refusing to ship: a JVM leaked into Depends ($DEPS)" >&2; exit 1 ;;
esac

INSTALLED_KB="$(du -sk "$STAGE" | cut -f1)"
cat > "$STAGE/DEBIAN/control" <<EOF
Package: $BIN_NAME
Version: $VERSION
Section: utils
Priority: optional
Architecture: amd64
Depends: $DEPS
Installed-Size: $INSTALLED_KB
Maintainer: labaccessnow <dev@labaccessnow.com>
Homepage: https://netopsfieldnotes.com/tools/
Description: Network and security tools that run on your machine
 Eighteen small tools in one window: subnet and VLSM planning, CIDR
 summarization, wildcard/ACL conversion, MTU/MSS math, config diff, ping,
 port and DNS checks, TLS certificate inspection — plus IOC defanging,
 CVSS v3.1 scoring, JWT decoding, hashing, timestamp conversion and a
 decoder workbench.
 .
 Everything you paste stays local. The only network traffic is from the
 tools whose job is the network.
EOF

cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = "configure" ]; then
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -f -t /usr/share/icons/hicolor || true
  fi
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q /usr/share/applications || true
  fi
fi
EOF
cat > "$STAGE/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -f -t /usr/share/icons/hicolor || true
  fi
fi
EOF
chmod 755 "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/postrm"

DEB="$DIST/${BIN_NAME}_${VERSION}_amd64.deb"
echo "==> building $(basename "$DEB")"
dpkg-deb --root-owner-group --build "$STAGE" "$DEB" >/dev/null

# ------------------------------------------------------------------- tarball
# Same payload as the .deb — copied from the staged tree, not the raw build
# output, so both artefacts carry identical (pruned) contents — plus an
# installer for distros that are not Debian-derived.
TARROOT="$DIST/FieldKit-${VERSION}-linux-x64"
install -d "$TARROOT"
cp -r "$STAGE/opt/$BIN_NAME/." "$TARROOT/"
install -d "$TARROOT/share"
cp -r "$PKG_DIR/icons" "$TARROOT/share/icons"
cp "$PKG_DIR/$APP_ID.desktop" "$TARROOT/share/"
cp "$REPO_ROOT/LICENSE" "$TARROOT/"

cat > "$TARROOT/install.sh" <<EOF
#!/usr/bin/env bash
# Install Field Kit into your home directory. No root, nothing outside ~/.local.
set -euo pipefail
cd "\$(dirname "\$0")"
PREFIX="\${PREFIX:-\$HOME/.local}"
APP_ID="$APP_ID"

install -d "\$PREFIX/lib/$BIN_NAME" "\$PREFIX/bin" "\$PREFIX/share/applications"
cp -r ./data ./lib "./$BIN_NAME" "\$PREFIX/lib/$BIN_NAME/"
ln -sf "\$PREFIX/lib/$BIN_NAME/$BIN_NAME" "\$PREFIX/bin/$BIN_NAME"

for size in 16 24 32 48 64 128 256 512; do
  install -Dm644 "share/icons/\$size.png" \\
    "\$PREFIX/share/icons/hicolor/\${size}x\${size}/apps/\$APP_ID.png"
done

sed "s|^Exec=$BIN_NAME\$|Exec=\$PREFIX/bin/$BIN_NAME|" "share/\$APP_ID.desktop" \\
  > "\$PREFIX/share/applications/\$APP_ID.desktop"

command -v gtk-update-icon-cache >/dev/null 2>&1 && \\
  gtk-update-icon-cache -q -f -t "\$PREFIX/share/icons/hicolor" || true
command -v update-desktop-database >/dev/null 2>&1 && \\
  update-desktop-database -q "\$PREFIX/share/applications" || true

echo "Field Kit installed to \$PREFIX"
case ":\$PATH:" in
  *":\$PREFIX/bin:"*) ;;
  *) echo "note: \$PREFIX/bin is not on your PATH" ;;
esac
EOF

cat > "$TARROOT/uninstall.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
PREFIX="\${PREFIX:-\$HOME/.local}"
APP_ID="$APP_ID"
rm -rf "\$PREFIX/lib/$BIN_NAME" "\$PREFIX/bin/$BIN_NAME" \\
       "\$PREFIX/share/applications/\$APP_ID.desktop"
find "\$PREFIX/share/icons/hicolor" -name "\$APP_ID.*" -delete 2>/dev/null || true
echo "Field Kit removed from \$PREFIX"
EOF
chmod +x "$TARROOT/install.sh" "$TARROOT/uninstall.sh"

TARBALL="$DIST/FieldKit-${VERSION}-linux-x64.tar.gz"
tar -C "$DIST" -czf "$TARBALL" "$(basename "$TARROOT")"

# ----------------------------------------------------------------- checksums
rm -rf "$STAGE" "$TARROOT"
( cd "$DIST" && sha256sum "$(basename "$DEB")" "$(basename "$TARBALL")" > SHA256SUMS.linux )

echo
echo "==> dist/"
ls -lh "$DIST"
echo
cat "$DIST/SHA256SUMS.linux"
