# Real newlines, not a literal \n: the card renders the body as it arrives, and
# elides past three lines.
#
# The keys named are the ones keybindings/actions.toml actually binds. Super + K
# is "focus the window above" in all three compositors, so the cheatsheet is on
# the shifted one.
strapd-notification-send -u critical -g  "Learn Keybindings" \
  $'Super + Shift + K for the cheatsheet.\nSuper + Space for the strapd menu.' \
  --exec strapd-menu-keybindings
