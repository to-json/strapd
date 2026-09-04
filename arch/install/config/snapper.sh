SNAPPER_CONFIG_PATH="${STRAPD_SNAPPER_CONFIG_PATH:-/etc/snapper/configs/root}"
SNAPPER_CONF_PATH="${STRAPD_SNAPPER_CONF_PATH:-/etc/conf.d/snapper}"
template="${STRAPD_SNAPPER_TEMPLATE:-${STRAPD_PATH:-/usr/share/strapd}/default/snapper/root}"

echo "Configuring strapd Snapper snapshot retention"

if [[ ! -f $SNAPPER_CONFIG_PATH ]]; then
  mkdir -p "$(dirname "$SNAPPER_CONFIG_PATH")"

  if [[ ${STRAPD_SNAPPER_CONFIGURE_TEST:-0} == "1" ]]; then
    : >"$SNAPPER_CONFIG_PATH"
  else
    # The dbus retry is for a live system, where --no-dbus can be refused.
    # Inside the install chroot there is no bus at all, so it can only ever add
    # a ServiceUnknown on top of the real failure, and with --no-dbus's own
    # stderr discarded, that misleading second error was the only one anyone
    # saw. Keep the retry, but report what the first attempt actually said.
    create_error=$(mktemp)
    if ! snapper --no-dbus -c root create-config / >/dev/null 2>"$create_error"; then
      if ! snapper -c root create-config / >/dev/null 2>&1; then
        cat "$create_error" >&2
        rm -f "$create_error"
        exit 1
      fi
    fi
    rm -f "$create_error"
  fi
fi

install -m 0644 "$template" "$SNAPPER_CONFIG_PATH"

mkdir -p "$(dirname "$SNAPPER_CONF_PATH")"
printf '%s\n' 'SNAPPER_CONFIGS="root"' >"$SNAPPER_CONF_PATH"
chmod 0644 "$SNAPPER_CONF_PATH"

systemctl disable --now snapper-timeline.timer >/dev/null 2>&1 || true
systemctl enable --now snapper-cleanup.timer limine-snapper-sync.service >/dev/null 2>&1 || true
