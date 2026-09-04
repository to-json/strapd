notify_update() {
  strapd-notification-send -u critical -g  "Update System" "Click to update the system." \
    --exec strapd-launch-floating-terminal-with-presentation strapd-update
}

notify_wifi() {
  strapd-notification-send -u critical -g 󰖩 "Setup Wi-Fi" "Click to configure the wireless network." \
    --exec strapd-shell shell toggle strapd.network
}

announce_network() {
  # Ethernet is still negotiating DHCP when the session starts, so probing
  # right away calls a working machine offline. NetworkManager reports startup
  # complete once it has tried every connection it could auto-activate, which
  # is the first moment the answer means anything.
  nm-online -q -s -t 30

  # -x takes that answer as it stands rather than waiting out the timeout, so
  # a laptop with nothing to connect to gets prompted immediately.
  if ! nm-online -q -x -t 30; then
    notify_wifi
    # Nothing to update against until a link lands, so hold that prompt.
    nm-online -q -t 3600 || return
  fi

  notify_update
}

# Detached, so a slow or absent connection never holds up the rest of first run.
announce_network &
