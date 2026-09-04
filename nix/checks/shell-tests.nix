# test/shell under `nix flake check`.
#
# The suite runs against a tree shaped like the NixOS package: same command
# exclusions, shebangs patched the way the package's are. Tests are pruned on
# principle rather than by hand-kept list -- a test referencing a command the
# exclusions deleted is a test of the Arch layer -- plus a handful of extra
# prunes for Arch machinery that never names an excluded command directly.
#
# The sandbox is not the dev VM the suite grew up on: no /bin/bash for
# runtime-written stubs, no compositor binaries, no /usr/bin for an env -i PATH,
# C locale, no timezone database. All handled explicitly below.
{ stdenvNoCC
, src
, excludedCommands
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
, makeFontsConf
, dejavu_fonts
, desktop-file-utils
, xdg-user-dirs
}:

stdenvNoCC.mkDerivation {
  name = "strapd-shell-tests";
  inherit src;

  nativeBuildInputs = [
    bashInteractive
    coreutils
    findutils
    gnugrep
    gnused
    ripgrep
    jq
    yq-go
    nodejs
    lua5_4
    python3
    zbar
    qrencode
    tesseract
    tmux
    sudo # for visudo, which dev-link's sudoers drop-in test validates with
    procps
    util-linux
    imagemagick
    openssh # ssh -G resolves configs in the reconnect-helper tests
    iproute2 # `ip route get` in the Wi-Fi interface detection
    desktop-file-utils
    xdg-user-dirs
  ];

  dontConfigure = true;
  dontInstall = true;

  buildPhase = ''
    runHook preBuild

    # The neutral tree this layer ships lives in shared/, which is shaped
    # exactly like the runtime tree, so test/shell resolves its own ROOT here.
    # The exclusion and prune passes below are a safety net; they no-op now
    # that arch/ pre-filters the tree.
    cd shared

    # patchShebangs handles the files; tests additionally embed #!/bin/bash
    # inside heredocs for the stubs they write at runtime, which it cannot see,
    # so those are rewritten textually.
    patchShebangs --build . >/dev/null
    grep -rl '#!/bin/bash' test/ | xargs -r sed -i "s|#!/bin/bash|#!$BASH|g"

    # uwsm-env-test wipes the environment and rebuilds PATH from FHS
    # directories that hold nothing here. Its assertions are about GDK/QT/
    # Mozilla variables, so keep the sandbox PATH behind the tree's own bin.
    sed -i 's|PATH="$ROOT/bin:/usr/local/bin:/usr/bin:/bin"|PATH="$ROOT/bin:$PATH"|' \
      test/shell.d/uwsm-env-test.sh

    # The hybrid-GPU tests' blocking stub sleeps via /usr/bin/sleep, which does
    # not exist here; falling through instantly turns "daemon that cannot
    # answer" into "daemon that answered Hybrid".
    sed -i 's|/usr/bin/sleep|sleep|g' \
      test/shell.d/hw-hybrid-gpu-test.sh test/shell.d/hybrid-gpu-test.sh

    # capture-text-test renders sample text with magick and no -font, which
    # freetype cannot resolve without a system font map; name one.
    sed -i 's|-pointsize 48|-font ${dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf -pointsize 48|' \
      test/shell.d/capture-text-test.sh

    # Shape the tree like the package, recording what went so the tests that
    # exercise it can follow.
    ls bin > "$TMPDIR/commands-before"
    while IFS= read -r pattern; do
      case $pattern in ""|\#*) continue ;; esac
      rm -f bin/$pattern
    done < ${excludedCommands}
    ls bin > "$TMPDIR/commands-after"
    comm -23 "$TMPDIR/commands-before" "$TMPDIR/commands-after" > "$TMPDIR/commands-removed"

    # Mirror the package's menu prune: the Update row runs the excluded
    # strapd-update, so dropping it keeps menu-test's "every row runs a command
    # that exists" check honest on this layer.
    sed -i '/strapd-update$/d' default/menu/tree.tsv

    for test in test/shell.d/*-test.sh; do
      if grep -oE 'strapd-[a-z0-9-]+' "$test" | sort -u \
          | grep -qxFf - "$TMPDIR/commands-removed" 2>/dev/null; then
        echo "pruned (tests an excluded command): $test"
        rm -f "$test"
      fi
    done

    # Arch-layer tests that never name an excluded command directly.
    # firewall-config-test exercises install/config/firewall.sh, part of the
    # Arch install layer the NixOS one deletes wholesale.
    rm -f \
      test/shell.d/install-script-test.sh \
      test/shell.d/install-path-resolvable-test.sh \
      test/shell.d/place-tree-test.sh \
      test/shell.d/firewall-config-test.sh

    # session-test starts every compositor the keybinding generator knows. Only
    # presence is checked; uwsm is stubbed before anything would run.
    mkdir -p "$TMPDIR/compositor-stubs"
    for compositor in niri sway mango; do
      printf '#!%s\nexit 0\n' "$BASH" > "$TMPDIR/compositor-stubs/$compositor"
      chmod +x "$TMPDIR/compositor-stubs/$compositor"
    done

    export HOME=$TMPDIR/home
    mkdir -p "$HOME"
    export STRAPD_PATH=$PWD
    # The tree's own commands call each other by bare name.
    export PATH=$PWD/bin:$TMPDIR/compositor-stubs:$PATH
    # Glyph-width assertions (ascii art) need a UTF-8 locale, and the
    # Fireworks usage scanner needs a real timezone database.
    export LC_ALL=C.UTF-8
    export TZDIR=${tzdata}/share/zoneinfo
    # magick renders text in the OCR capture test.
    export FONTCONFIG_FILE=${makeFontsConf { fontDirectories = [ dejavu_fonts ]; }}

    bash test/shell

    runHook postBuild
    touch $out
  '';
}
