# The login screen: greetd, running tuigreet, listing the sessions strapd
# installs. See etc/greetd/config.toml for why tuigreet and not the
# noctalia-greeter the plan names.
#
# This is the Debian twin of arch/install/login/all.sh, and it carries two
# fixes for where Debian's greetd packaging differs from Arch's, both found by
# booting strapd on real trixie:
#
#   1. The greeter runs as a user greetd's own package creates, and Debian names
#      that user "_greetd" where Arch names it "greeter". The shipped
#      config.toml is written for Arch, so on Debian its `user = "greeter"` line
#      points at a user that does not exist and greetd cannot start the greeter.
#      Rewrite it to whichever greetd user this system actually has.
#
#   2. Debian's greetd.service does not Conflicts= the tty1 getty, and the base
#      system leaves getty@tty1 enabled. With both live, greetd and the getty
#      fight over VT 1 and greetd restart-loops ("greeter exited without
#      creating a session"). Mask the getty on greetd's VT so greetd owns it.

install -Dm644 "$STRAPD_PATH/etc/greetd/config.toml" /etc/greetd/config.toml

# tuigreet starts on the first session in the list, so a compositor that is not
# installed must not be in it. That matters more here than on Arch: trixie
# carries sway and neither niri nor mango, so two of the three sessions are
# absent on a stock install and the first one alphabetically is one of them.
strapd-refresh-sessions | while IFS= read -r line; do strapd_log_line "Login: $line"; done

# Point the greeter at the greetd user this distribution's package created.
# Prefer _greetd (Debian); fall back to greeter (in case a future image matches
# Arch). Only rewrite when the shipped user is absent and the alternative is
# present, so a hand-edited config is left alone.
if ! getent passwd greeter >/dev/null && getent passwd _greetd >/dev/null; then
  sed -i 's/^user = "greeter"$/user = "_greetd"/' /etc/greetd/config.toml
  strapd_log_line "Login: greeter user set to _greetd (Debian greetd package)"
fi

# The greeter's VT, from the config (default 1). Mask the getty there so it does
# not compete with greetd for the console.
greeter_vt=$(sed -nE 's/^vt = ([0-9]+).*/\1/p' /etc/greetd/config.toml | head -1)
greeter_vt="${greeter_vt:-1}"
if systemctl is-enabled "getty@tty${greeter_vt}.service" >/dev/null 2>&1 ||
   systemctl is-active "getty@tty${greeter_vt}.service" >/dev/null 2>&1; then
  systemctl mask "getty@tty${greeter_vt}.service"
  strapd_log_line "Login: masked getty@tty${greeter_vt} so greetd owns VT ${greeter_vt}"
fi

# Only enable greetd if nothing else already owns the login screen. A machine
# that came with GDM or SDDM has a display-manager.service alias pointing at it,
# and enabling a second one either fails or silently takes over the thing the
# user boots into; neither is a decision an installer should make for them.
if [[ -e /etc/systemd/system/display-manager.service ]] &&
   [[ $(readlink -f /etc/systemd/system/display-manager.service) != *greetd* ]]; then
  strapd_log_line "Login: leaving the existing display manager alone ($(basename "$(readlink -f /etc/systemd/system/display-manager.service)"))"
  strapd_log_line "Login: enable greetd yourself with: systemctl enable --force greetd.service"
else
  systemctl enable greetd.service
  strapd_log_line "Login: greetd enabled, greeting with tuigreet"
fi
