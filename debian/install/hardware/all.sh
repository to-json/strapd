# The Debian hardware layer.
#
# The Arch layer runs a long tail of machine-specific quirk fixes (Intel PTL
# kernels, Apple T2, ASUS ROG, Framework QMK, ...), almost all of which install
# firmware or DKMS modules through pacman and target hardware a generic install
# never sees. Those are deferred on Debian: they need per-fix
# translation to apt/Debian kernels and are not on the path to a working desktop
# on ordinary hardware or a VM.
#
# What runs here is the distro-neutral core every machine needs: retire any
# competing systemd-networkd DHCP state so NetworkManager owns the link, grant
# the install user input-group access for dictation and controllers, and enable
# the Bluetooth daemon. Each is guarded and idempotent.
run_logged "$STRAPD_INSTALL/hardware/network.sh"
run_logged "$STRAPD_INSTALL/hardware/input-group.sh"
run_logged "$STRAPD_INSTALL/hardware/bluetooth.sh"
