# Setup user theme folder and seed the default only when no theme exists yet.
mkdir -p ~/.config/strapd/themes

if [[ ! -s $HOME/.local/state/strapd/current/theme.name ]]; then
  # iso-chroot and provision-owner both run without a live session to notify.
  if [[ ${STRAPD_SETUP_CONTEXT:-runtime} != "runtime" ]]; then
    STRAPD_THEME_HEADLESS=1 strapd-theme-set "Everforest"
    rm -f ~/.config/chromium/SingletonLock # otherwise archiso owns the Chromium singleton
  else
    strapd-theme-set "Everforest"
  fi
fi
strapd-theme-set-pi --activate

mkdir -p ~/.config/btop/themes
ln -snf "$HOME/.local/state/strapd/current/theme/btop.theme" ~/.config/btop/themes/current.theme
