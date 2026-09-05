# Install Tuxedo drivers for keyboard backlighting on Tuxedo laptops and
# compatible devices like the Slimbook Executive (Clevo/Tuxedo chassis).
if cat /sys/class/dmi/id/sys_vendor 2>/dev/null | grep -qi "TUXEDO\|Slimbook"; then
  # Two sources, so two commands: the headers are in the repos, the DKMS tree
  # is in the AUR and `pacman -S` cannot resolve it.
  strapd-pkg-add linux-headers
  strapd-pkg-aur-add tuxedo-drivers-nocompatcheck-dkms

  # Blacklist the legacy clevo_xsm_wmi module which conflicts with the tuxedo-drivers
  # clevo_wmi module. When clevo_xsm_wmi loads first, it grabs the Clevo WMI GUIDs,
  # preventing tuxedo-drivers from initializing the keyboard backlight properly.
  mkdir -p /etc/modprobe.d
  echo "blacklist clevo_xsm_wmi" > /etc/modprobe.d/blacklist-clevo-xsm-wmi.conf

  # Remove any orphaned clevo_xsm_wmi module files not managed by a package
  for f in /lib/modules/*/extra/clevo-xsm-wmi.ko; do
    if [[ -f $f ]]; then
      rm "$f"
    fi
  done
fi
