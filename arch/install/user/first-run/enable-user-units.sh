#!/bin/bash

# Enable AND start the user systemd units we ship. At first-run rather than at
# finalize-user time because the user manager isn't live during the ISO chroot;
# by first-run the session is up, and `enable --now` both writes the .wants
# symlinks and starts the services, so the first session has them live.
# ConditionPath* keeps them inert on hardware they don't apply to.
#
# Only units default/systemd/user actually ships are listed: `enable --now`
# fails the whole first run on a unit that is not there.

set -euo pipefail

systemctl --user daemon-reload
systemctl --user enable --now \
  bt-agent.service \
  strapd-fcitx5.service \
  strapd-crash-watch.service \
  strapd-recover-internal-monitor.service \
  mako.service
