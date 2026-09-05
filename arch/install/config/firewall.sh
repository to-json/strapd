# Allow nothing in, everything out.
ufw default deny incoming
ufw default allow outgoing

# Allow ports for LocalSend.
ufw allow 53317/udp
ufw allow 53317/tcp

# Allow Docker containers to use DNS on host.
ufw allow in proto udp from 172.16.0.0/12 to 172.17.0.1 port 53 comment 'allow-docker-dns'
ufw allow in proto udp from 192.168.0.0/16 to 172.17.0.1 port 53 comment 'allow-docker-dns'

# Turn on Docker protections. ufw-docker refuses to install its after.rules
# block unless UFW is already active, but during ISO finalization the target
# chroot shares the live installer's kernel firewall. Keep the live firewall
# untouched: for this config-file-only install action, satisfy ufw-docker's
# status preflight without activating UFW.
install_ufw_docker_rules() {
  local shim_dir status ufw_docker_bin

  ufw_docker_bin=$(command -v ufw-docker)
  shim_dir=$(mktemp -d)
  cat >"$shim_dir/ufw" <<'EOF'
#!/bin/bash
if [[ ${1:-} == "status" ]]; then
  echo "Status: active"
  exit 0
fi

exec /usr/bin/ufw "$@"
EOF

  # The packaged ufw-docker pins PATH internally, so run a temporary copy whose
  # PATH can see the status shim above.
  sed "0,/^PATH=/s#^PATH=.*#PATH=\"$shim_dir:/bin:/usr/bin:/sbin:/usr/sbin:/snap/bin/\"#" \
    "$ufw_docker_bin" >"$shim_dir/ufw-docker"
  chmod 755 "$shim_dir/ufw" "$shim_dir/ufw-docker"

  if "$shim_dir/ufw-docker" install; then
    status=0
  else
    status=$?
  fi

  rm -rf "$shim_dir"
  return "$status"
}

# ufw-docker is vendored, so install.sh builds it before this runs and the
# branch below is normally taken. The check stays because the vendor build is
# deliberately not fatal: one PKGBUILD that will not build should cost its own
# package, not the Docker protections and not the whole config layer.
if strapd-cmd-present ufw-docker; then
  install_ufw_docker_rules
else
  echo "ufw-docker is not installed; skipping Docker firewall protections until phase 8 builds the AUR package set"
fi

# Installs are followed by reboot, so configure UFW to start on the installed
# system instead of mutating the live install session's firewall.
sed -i 's/^ENABLED=.*/ENABLED=yes/' /etc/ufw/ufw.conf
systemctl enable ufw
