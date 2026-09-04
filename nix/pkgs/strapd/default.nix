# The strapd tree as a Nix package: what install/place-tree.sh does
# imperatively on Arch, done once at build time.
#
# Layout mirrors place-tree.sh's targets, relocated into $out:
#   $out/share/strapd                    the tree (was /usr/share/strapd)
#   $out/bin/strapd*                     command symlinks (was /usr/bin)
#   $out/share/uwsm/env.d/10-strapd      uwsm env hook
#   $out/lib/systemd/user/               user units + app.slice.d drop-in
#
# Two build-time rewrites:
#
#   /usr/share/strapd -> /etc/strapd, not the store path: user-mutable copies of
#   config files embed this string, and a store path baked into a home file goes
#   stale on every rebuild and dangles after GC. /etc/strapd.conf still wins
#   (dev-link mode), since env-bootstrap's default is rewritten along with it.
#
#   /usr/bin -> /run/current-system/sw/bin, in the systemd user units only:
#   their ExecStart/Condition lines name absolute paths.
{ lib
, stdenvNoCC
, src
  # Tools the scripts call at runtime. Deliberately not wrapped per-script:
  # compositor keybindings invoke strapd-launch-* directly, so the dependencies
  # have to be on the session PATH anyway. Exposed as passthru.runtimeDeps so
  # the module and the checks share one definition.
, gum
, jq
, fzf
, ripgrep
, yq-go
, nodejs
, lua5_4
, imagemagick
, libnotify
, wl-clipboard
, slurp
, grim
, zbar
}:

stdenvNoCC.mkDerivation {
  pname = "strapd";
  version = "0-unstable-${src.shortRev or src.dirtyShortRev or "dirty"}";
  inherit src;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/strapd
    # The distro-neutral core is shared/. The tree is pre-filtered by the source
    # layout, so there is no command-exclusion pass any more.
    cp -a shared/. $out/share/strapd

    # A few shared files still name Arch-only functionality that lives in arch/
    # and so is absent here. First, the dispatcher's help entries for groups
    # whose members are all in arch/bin.
    sed -i -E '/^GROUP_DESCRIPTIONS\[(pkg|update|channel|snapshot|install|plymouth|reinstall|setup)\]=/d' \
      $out/share/strapd/bin/strapd

    # The seeded compositor autostart spawns strapd-provision-first-run (an
    # arch/ command); drop the line and its comment. Three compositors, three
    # spellings.
    sed -i '/provision-first-run/d; /First-run provisioning/d' \
      $out/share/strapd/default/sway/autostart.conf \
      $out/share/strapd/default/niri/autostart.kdl \
      $out/share/strapd/default/mango/strapd.conf

    # strapd-update is excluded, so the menu's Update row would run a command
    # that is gone -- and a distro you rebuild from a flake carries no
    # imperative-update entry anyway.
    sed -i '/	strapd-update$/d' $out/share/strapd/default/menu/tree.tsv

    # The stable-path rewrite. -I skips binaries (theme assets).
    grep -rlI /usr/share/strapd $out/share/strapd | xargs -r sed -i 's|/usr/share/strapd|/etc/strapd|g'

    # place-tree.sh sets modes explicitly rather than trusting the source tree.
    chmod 0755 $out/share/strapd/bin/*
    for runner in $out/share/strapd/test/shell $out/share/strapd/test/acceptance; do
      [ -f "$runner" ] && chmod 0755 "$runner"
    done

    mkdir -p $out/bin
    for command in $out/share/strapd/bin/strapd*; do
      ln -s "$command" "$out/bin/$(basename "$command")"
    done

    install -Dm644 $out/share/strapd/default/uwsm/env.d/10-strapd \
      $out/share/uwsm/env.d/10-strapd

    # The tree-local sessions copy place-tree.sh makes, so /etc/strapd/
    # wayland-sessions exists for anything reading it. The greeter itself is
    # pointed at the strapd-sessions package, whose Exec lines are store paths.
    mkdir -p $out/share/strapd/wayland-sessions
    cp $out/share/strapd/default/wayland-sessions/*.desktop $out/share/strapd/wayland-sessions/

    for unit in $out/share/strapd/default/systemd/user/*.service; do
      install -Dm644 "$unit" "$out/lib/systemd/user/$(basename "$unit")"
    done
    install -Dm644 $out/share/strapd/default/systemd/user/app.slice.d/10-oomd.conf \
      $out/lib/systemd/user/app.slice.d/10-oomd.conf
    sed -i 's|/usr/bin/|/run/current-system/sw/bin/|g' $out/lib/systemd/user/*.service

    runHook postInstall
  '';

  passthru.runtimeDeps = [
    gum
    jq
    fzf
    ripgrep
    yq-go
    nodejs
    lua5_4
    imagemagick
    libnotify
    wl-clipboard
    slurp
    grim
    zbar
  ];

  meta = {
    description = "An Arch + Wayland desktop where the compositor is a choice, packaged for NixOS";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "strapd";
  };
}
