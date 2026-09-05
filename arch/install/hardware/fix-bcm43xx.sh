# Install Wi-Fi drivers for Broadcom chips found in some MacBooks, as well as other systems:
# - BCM4360 (2013–2015 MacBooks)
# - BCM4331 (2012, early 2013 MacBooks)

pci_info=$(lspci -nn)

if (echo "$pci_info" | grep -q "14e4:43a0" || echo "$pci_info" | grep -q "14e4:4331"); then
  echo "BCM4360 / BCM4331 detected"
  # Two sources, so two commands: dkms and the headers are in the repos,
  # broadcom-wl is in the AUR and `pacman -S` cannot resolve it.
  strapd-pkg-add dkms linux-headers
  strapd-pkg-aur-add broadcom-wl
fi
