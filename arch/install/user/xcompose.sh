# Set default XCompose that is triggered with CapsLock
tee ~/.XCompose >/dev/null <<EOF
# Run strapd-restart-xcompose to apply changes

# Include fast emoji access
include "/usr/share/strapd/default/xcompose"

# Identification
<Multi_key> <space> <n> : "$STRAPD_USER_NAME"
<Multi_key> <space> <e> : "$STRAPD_USER_EMAIL"
EOF
