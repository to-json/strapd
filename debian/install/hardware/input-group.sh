# Give this user privileged input access for dictation tools + xbox controllers to work.
# Recorded for provisioning first-boot user creation and factory reset, granted directly
# when the install user already exists (deferred-provisioning installs create the user at
# first boot instead).
provisioning_dir="${STRAPD_PROVISIONING_DIR:-/var/lib/strapd/provisioning}"
mkdir -p "$provisioning_dir"
grep -qxF input "$provisioning_dir/groups" 2>/dev/null || echo input >>"$provisioning_dir/groups"

if [[ -n ${STRAPD_INSTALL_USER:-} ]] && getent passwd "$STRAPD_INSTALL_USER" >/dev/null; then
  usermod -aG input "$STRAPD_INSTALL_USER"
fi
