if strapd-hw-framework16; then
  # AUR, so not strapd-pkg-add: that runs `pacman -S`, which cannot resolve it.
  strapd-pkg-aur-add qmk-hid
fi
