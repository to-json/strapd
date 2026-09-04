# The Debian config layer. The neutral steps (theme, ssh, docker-group policy,
# service enablement, firewall) carry over from the Arch layer; what is dropped
# is Arch-specific and has no Debian meaning here:
#
#   increase-lockout-limit.sh:       Arch faillock tuning; Debian's PAM lockout
#                                    stack differs and this is not boot-critical
#   fix-powerprofilesctl-shebang.sh: rewrites an Arch package's /usr/bin/python
#                                    shebang; Debian ships its own
#   snapper.sh, locate.sh:           Btrfs/snapper snapshot plumbing; the Debian
#                                    distro does not assume Btrfs
run_logged "$STRAPD_INSTALL/config/build-uwsm.sh"
run_logged "$STRAPD_INSTALL/config/theme-system.sh"
run_logged "$STRAPD_INSTALL/config/ssh-command-path.sh"
run_logged "$STRAPD_INSTALL/config/ssh-keepalive.sh"
run_logged "$STRAPD_INSTALL/config/docker.sh"
run_logged "$STRAPD_INSTALL/config/enable-services.sh"
run_logged "$STRAPD_INSTALL/config/firewall.sh"
