# The Arch post-install layer restores pacman.conf and the offline mirror after
# an ISO install; the Debian layer installs onto a running apt system that
# already has its sources configured, so only the distro-neutral steps run
# here, reloading udev for the rules the tree just placed, and refreshing the
# locate database so the installed files are findable immediately.
run_logged "$STRAPD_INSTALL/post-install/udev.sh"
run_logged "$STRAPD_INSTALL/post-install/localdb.sh"
