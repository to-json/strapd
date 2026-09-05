# Install drivers for Motorcomm YT6801 ethernet adapter used by the Slimbook Executive
if lspci | grep -i "YT6801\|Motorcomm.*Ethernet"; then
  # Two sources, so two commands: the headers are in the repos, the DKMS tree
  # is in the AUR and `pacman -S` cannot resolve it.
  strapd-pkg-add linux-headers
  strapd-pkg-aur-add yt6801-dkms
fi
