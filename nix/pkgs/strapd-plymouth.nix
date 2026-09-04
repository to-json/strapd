# strapd's Plymouth boot splash, packaged as a theme derivation.
#
# The Arch layer installs default/plymouth to /usr/share/plymouth/themes/
# through its boot stack; NixOS wants a package carrying the theme under
# share/plymouth/themes/<name>, handed to boot.plymouth.themePackages.
#
# The one rewrite: the shipped .plymouth points ImageDir/ScriptFile at
# /usr/share/plymouth/... . NixOS's plymouth module relocates a theme into the
# initrd by sed-matching store paths that end in /share/plymouth/themes, so the
# descriptor has to name this package's own store path, not the Arch one,
# for that relocation to catch it.
{ lib, stdenvNoCC, src }:

stdenvNoCC.mkDerivation {
  pname = "strapd-plymouth";
  version = "0-unstable-${src.shortRev or src.dirtyShortRev or "dirty"}";
  inherit src;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/plymouth/themes/strapd
    cp -a shared/default/plymouth/. $out/share/plymouth/themes/strapd/

    substituteInPlace $out/share/plymouth/themes/strapd/strapd.plymouth \
      --replace-fail /usr/share/plymouth $out/share/plymouth

    runHook postInstall
  '';

  meta = {
    description = "strapd Plymouth boot splash theme";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
