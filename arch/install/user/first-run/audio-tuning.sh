#!/bin/bash

# Apply the speaker tuning for this laptop. At first-run rather than at
# finalize-user time because finalize-user also runs in the ISO chroot, where
# there is no audio server: the sink the tuning targets does not exist, nothing
# could be written, and nothing would retry, since the finalizer marks all
# shipped migrations complete on a fresh install.
#
# A no-op on machines no tuning matches.

set -euo pipefail

strapd-audio-tuning on
