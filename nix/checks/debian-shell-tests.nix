# The full shell suite against the Debian-assembled tree.
#
# The Debian sibling of checks/arch-shell-tests.nix. Today the tree carries
# only the neutral suite (the Debian layer ships no tests of its own yet), so
# its job is to prove that layer's own commands satisfy the tree-wide checks
# that scan bin/ when layered onto the neutral core.
#
# nixpkgs is used here only as a hermetic source of GNU userland; this is CI
# plumbing, not the NixOS layer.
{ stdenvNoCC
, src
, tzdata
, bashInteractive
, coreutils
, findutils
, gnugrep
, gnused
, ripgrep
, jq
, yq-go
, nodejs
, lua5_4
, python3
, zbar
, qrencode
, tesseract
, tmux
, sudo
, procps
, util-linux
, imagemagick
, openssh
, iproute2
, fakeroot
, makeFontsConf
, dejavu_fonts
, desktop-file-utils
, xdg-user-dirs
}:

stdenvNoCC.mkDerivation {
  name = "strapd-debian-shell-tests";
  inherit src;

  nativeBuildInputs = [
    bashInteractive coreutils findutils gnugrep gnused ripgrep jq yq-go nodejs
    lua5_4 python3 zbar qrencode tesseract tmux sudo procps util-linux
    imagemagick openssh iproute2 fakeroot desktop-file-utils xdg-user-dirs
  ];

  dontConfigure = true;
  dontInstall = true;

  buildPhase = ''
    runHook preBuild

    # Assemble the flat runtime tree the way place-tree.sh does.
    tree=$TMPDIR/tree
    mkdir -p "$tree"
    cp -a shared/. "$tree/"
    cp -a debian/. "$tree/"
    cd "$tree"

    # Same sandbox accommodations as the shared check (no /bin/bash for the
    # heredoc stubs, no /usr/bin/sleep, freetype needs a named font).
    patchShebangs --build . >/dev/null
    grep -rl '#!/bin/bash' test/ | xargs -r sed -i "s|#!/bin/bash|#!$BASH|g"
    sed -i 's|PATH="$ROOT/bin:/usr/local/bin:/usr/bin:/bin"|PATH="$ROOT/bin:$PATH"|' \
      test/shell.d/uwsm-env-test.sh
    sed -i 's|/usr/bin/sleep|sleep|g' \
      test/shell.d/hw-hybrid-gpu-test.sh test/shell.d/hybrid-gpu-test.sh
    sed -i 's|-pointsize 48|-font ${dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf -pointsize 48|' \
      test/shell.d/capture-text-test.sh

    mkdir -p "$TMPDIR/compositor-stubs"
    for compositor in niri sway mango; do
      printf '#!%s\nexit 0\n' "$BASH" > "$TMPDIR/compositor-stubs/$compositor"
      chmod +x "$TMPDIR/compositor-stubs/$compositor"
    done

    export HOME=$TMPDIR/home
    mkdir -p "$HOME"
    export STRAPD_PATH=$PWD
    export PATH=$PWD/bin:$TMPDIR/compositor-stubs:$PATH
    export LC_ALL=C.UTF-8
    export TZDIR=${tzdata}/share/zoneinfo
    export FONTCONFIG_FILE=${makeFontsConf { fontDirectories = [ dejavu_fonts ]; }}

    bash test/shell

    runHook postBuild
    touch $out
  '';
}
