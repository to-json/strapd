# /etc/pam.d/system-auth is upstream-owned and the changes are insertions, not
# a full-file override, so they stay scripted.
sed -i 's|^\(auth\s\+required\s\+pam_faillock.so\)\s\+preauth.*$|\1 preauth silent deny=10 unlock_time=120|' \
           /etc/pam.d/system-auth
sed -i 's|^\(auth\s\+\[default=die\]\s\+pam_faillock.so\)\s\+authfail.*$|\1 authfail deny=10 unlock_time=120|' \
           /etc/pam.d/system-auth

# The autologin PAM stack gets the same faillock treatment in phase 5, against
# whatever greetd installs. /etc/pam.d/sddm-autologin is gone with the package,
# and sed -i on a file that is not there fails the whole config layer.
