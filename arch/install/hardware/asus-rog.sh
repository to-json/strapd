if strapd-hw-asus-rog; then
  # AUR, so not strapd-pkg-add: that runs `pacman -S`, which cannot resolve it.
  strapd-pkg-aur-add asusctl
fi
