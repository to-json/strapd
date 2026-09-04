# strapd installation media

A bootable image that installs strapd onto a machine. `../install.sh` is the
other route and needs a working Arch already; this one starts from a blank
disk.

## Building it

Needs an Arch machine with `archiso`, root, and about 15 GB of scratch space.

```sh
sudo pacman -S --needed archiso
sudo iso/build.sh
```

The image lands in `iso/out/`. The build takes a while, mostly compressing a
two-gigabyte filesystem.

The profile is archiso's own `releng` with `iso/overlay/` laid over it, copied
fresh at build time rather than vendored here. That's four files, and it means
the medium tracks whatever archiso upstream tests instead of a fork of it.

## Writing it to a USB stick

On macOS, run `diskutil list` first and be certain which disk is the stick:

```sh
diskutil unmountDisk /dev/diskN
sudo dd if=iso/out/strapd-*.iso of=/dev/rdiskN bs=4m status=progress
diskutil eject /dev/diskN
```

On linux:

```sh
sudo dd if=iso/out/strapd-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Ventoy, Rufus and balenaEtcher all work too; the image is a plain hybrid ISO.
With Rufus, choose "DD image" mode if it asks.

## Booting it

Two firmware settings stop a custom image from booting on hardware that boots
everything else:

- Turn Secure Boot off. Nothing on this medium is signed by a key your firmware
  trusts, so with Secure Boot on it refuses to start, usually with no
  explanation or a "security violation".
- Pick the USB stick from the firmware's boot menu, not from a saved boot order.
  The key is usually F12, F9, F8 or Esc, shown briefly at power-on.

If the screen stays black or the display is garbled, choose safe graphics in the
boot menu. That means the kernel can't drive this machine's graphics yet. It's
the one failure the medium can't report to you, since reporting it would need a
working display.

The medium boots on both UEFI and BIOS machines. The *installer* needs UEFI, and
says so up front instead of finding out after the disk is erased. If your
firmware offers both entries for the stick, take the UEFI one.

## Installing

You're logged in automatically. Then:

```sh
strapd-install
```

It needs a network, because it downloads its packages. Wired should already
work. For wi-fi:

```sh
iwctl
  station wlan0 scan
  station wlan0 get-networks
  station wlan0 connect YOUR-SSID
  exit
```

The installer asks for the disk, hostname, username, password, timezone and
keymap up front, and writes nothing until you confirm the disk by typing its
path a second time. Then it partitions, installs, and hands over to the same
system setup `install.sh` uses.

## If the installed system does not come up

The boot menu has three entries. Two of them are for this:

- strapd (LTS kernel), for when the current kernel has a problem with this
  hardware. It's a different, older one, already installed.
- strapd (safe graphics), for when it's the GPU. Gets you to a console where you
  can look at it.

A session that starts and drops straight back to the login screen leaves a log
at `~/.local/state/strapd/session.log`. The one from the login that just failed
is kept beside it as `session.log.1`.
