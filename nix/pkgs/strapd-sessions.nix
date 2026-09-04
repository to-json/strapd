# strapd's three wayland-session files, alone in their own package.
#
# Alone on purpose: etc/greetd/config.toml documents why the greeter must see
# exactly these three and not the compositors' own session files, a bare
# niri/sway/mango session starts without uwsm, generated keybindings, or the
# session environment, and comes up looking like a broken strapd. The NixOS
# module points tuigreet's --sessions at this package's share/wayland-sessions
# and also lists it in services.displayManager.sessionPackages for machines
# that keep another greeter.
#
# Exec is rewritten to the store path: a greeter's PATH is its own business,
# and TryExec=<compositor> is left alone (greeters ignore it anyway, as the
# Arch config's comments attest).
{ lib, stdenvNoCC, strapd }:

stdenvNoCC.mkDerivation {
  pname = "strapd-sessions";
  version = strapd.version;

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/wayland-sessions
    for session in ${strapd}/share/strapd/default/wayland-sessions/*.desktop; do
      sed 's|^Exec=strapd-session|Exec=${strapd}/bin/strapd-session|' \
        "$session" > "$out/share/wayland-sessions/$(basename "$session")"
    done
    runHook postInstall
  '';

  passthru.providedSessions = [ "strapd-niri" "strapd-sway" "strapd-mango" ];

  meta = {
    description = "strapd's wayland-session entries, isolated for the greeter";
    inherit (strapd.meta) license platforms;
  };
}
