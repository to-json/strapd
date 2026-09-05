# The login screen: greetd, running tuigreet, listing the sessions strapd
# installs. See etc/greetd/config.toml for why tuigreet and not the
# noctalia-greeter the plan names.

install -Dm644 "$STRAPD_PATH/etc/greetd/config.toml" /etc/greetd/config.toml

# tuigreet starts on the first session in the list, so a compositor that is not
# installed must not be in it: that is what made first boot land on MangoWC and
# fail. Re-run on every apply, so a compositor built later comes back on its own.
strapd-refresh-sessions | while IFS= read -r line; do strapd_log_line "Login: $line"; done

# Only if nothing else already owns the login screen. A machine that came with
# GDM or SDDM has a display-manager.service alias pointing at it, and enabling
# a second one either fails or silently takes over the thing the user boots
# into; neither is a decision an installer should make for them.
if [[ -e /etc/systemd/system/display-manager.service ]] &&
   [[ $(readlink -f /etc/systemd/system/display-manager.service) != *greetd* ]]; then
  strapd_log_line "Login: leaving the existing display manager alone ($(basename "$(readlink -f /etc/systemd/system/display-manager.service)"))"
  strapd_log_line "Login: enable greetd yourself with: systemctl enable --force greetd.service"
else
  systemctl enable greetd.service
  strapd_log_line "Login: greetd enabled, greeting with tuigreet"
fi
