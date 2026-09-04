# The full shell suite against the Arch-assembled tree.
#
# Where checks/shell-tests.nix runs shared/ alone, this assembles what
# place-tree.sh assembles -- shared/ + arch/ merged into the flat runtime
# layout -- and runs every test, shared and arch. The assembled tree is
# byte-identical to the old repo root, so the suite that passed there passes
# here.
#
# No command-exclusion or prune pass: the Arch layer keeps its whole command
# set, its imperative-update menu row and its provisioning autostart.
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
  name = "strapd-arch-shell-tests";
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
    cp -a arch/. "$tree/"
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

    # firewall-config-test assumes an Arch FHS environment its stubs cannot get
    # in the Nix sandbox. It is verified on a real Arch machine, not here, and
    # the NixOS check prunes it for the same reason.
    rm -f test/shell.d/firewall-config-test.sh

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
