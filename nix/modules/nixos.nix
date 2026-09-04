# nixosModules.strapd, the system half of the NixOS layer.
#
# The Arch equivalents this module replaces, kept as a map for anyone diffing
# the two halves:
#
#   install/place-tree.sh            -> the strapd package + environment.etc."strapd"
#   etc/greetd/config.toml           -> services.greetd (ported verbatim, comments too)
#   install/config/enable-services.sh-> the service enablement block
#   etc/systemd/*.conf.d, sysctl.d,
#   tmpfiles.d, sudoers.d, modprobe.d-> the settings block
#   etc/nsswitch.conf                -> avahi.nssmdns4 (NixOS composes nsswitch itself)
#
# Deliberately absent, because NixOS owns them: pacman/libalpm, limine,
# mkinitcpio, snapper (generations are the rollback story). The plymouth theme
# is adopted below via boot.plymouth.
self: { config, lib, pkgs, ... }:

let
  cfg = config.strapd;
  system = pkgs.stdenv.hostPlatform.system;

  # Sessions follow cfg.package so an overridden strapd package carries its own.
  sessions = self.packages.${system}.strapd-sessions.override { strapd = cfg.package; };

  compositorEnabled = c: builtins.elem c cfg.compositors;
in
{
  options.strapd = {
    enable = lib.mkEnableOption "the strapd desktop";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${system}.strapd;
      defaultText = lib.literalExpression "strapd.packages.\${system}.strapd";
      description = "The strapd tree package.";
    };

    compositors = lib.mkOption {
      type = lib.types.listOf (lib.types.enum [ "niri" "sway" "mango" ]);
      default = [ "niri" "sway" "mango" ];
      description = ''
        Which of the three supported compositors to install. The greeter
        offers a session for each.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # The keystone: the stable path every packaged script and seeded user config
    # resolves the tree through. Survives rebuilds and GC, rooted by the system
    # profile.
    environment.etc."strapd".source = "${cfg.package}/share/strapd";

    # uwsm sessions and login shells resolve STRAPD_PATH through env-bootstrap;
    # interactive shells get it here.
    environment.extraInit = ''
      [ -r /etc/strapd/default/bash/env-bootstrap ] && . /etc/strapd/default/bash/env-bootstrap
    '';

    environment.systemPackages =
      [ cfg.package ]
      ++ cfg.package.passthru.runtimeDeps
      ++ (with pkgs; [
        # The session userland every compositor config spawns or binds.
        mako
        fuzzel
        swaylock
        playerctl
        gammastep
        hyprpicker
        xwayland-satellite # niri >= 25.05 spawns it from PATH when present
        brightnessctl
        xdg-terminal-exec
        xdg-user-dirs
        wf-recorder
        # The strapd-fcitx5 user unit launches this; it just has to exist.
        # i18n.inputMethod's own autostart would race the unit.
        fcitx5
      ]);

    # Compositors through their nixpkgs modules: each brings its portal, polkit
    # and session plumbing.
    programs.niri.enable = compositorEnabled "niri";
    programs.sway.enable = compositorEnabled "sway";
    programs.mango.enable = compositorEnabled "mango";

    # strapd-session execs `uwsm start` itself; waylandCompositors stays empty
    # because generated <compositor>-uwsm.desktop entries would recreate the
    # six-sessions trap etc/greetd/config.toml documents.
    programs.uwsm.enable = true;

    # Spawned by each compositor's autostart, so the module just installs it.
    programs.noctalia.enable = true;

    # greetd + tuigreet, ported from etc/greetd/config.toml. vt 1 is fixed so
    # the login screen is always in the same place after a session ends.
    # --sessions names strapd's own sessions package, three entries, never the
    # compositors' bare session files.
    services.greetd = {
      enable = true;
      settings = {
        terminal.vt = 1;
        default_session = {
          command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --remember-user-session --sessions ${sessions}/share/wayland-sessions";
          user = "greeter";
        };
      };
    };

    # For machines that keep a different display manager.
    services.displayManager.sessionPackages = [ sessions ];

    # default/plymouth, packaged as a theme (its .plymouth points at its own
    # store path so NixOS can relocate it into the initrd). mkDefault so a
    # machine that would rather see its boot messages can turn it off. The theme
    # degrades to a bare progress bar without a logo.png.
    boot.plymouth = {
      enable = lib.mkDefault true;
      theme = "strapd";
      themePackages = [ self.packages.${system}.strapd-plymouth ];
    };

    # The systemd user units the package ships, plus the user-environment
    # generator that lets a machine with no render node reach its desktop at all.
    # systemd only runs generators from its own directories, so that one is
    # placed by path rather than by package.
    systemd.packages = [ cfg.package ];
    environment.etc."systemd/user-environment-generators/50-strapd-renderer" = {
      source = "${cfg.package}/share/strapd/default/systemd/user-environment-generators/50-strapd-renderer";
      mode = "0555";
    };

    # Replaces install/user/first-run/enable-user-units.sh; the NixOS layer
    # drops that imperative first-run. asDropin keeps each unit's own text from
    # the package, adding only the wantedBy symlink, and each unit's Condition*
    # lines keep it inert where it does not apply.
    #
    # mako is absent because it is D-Bus activated by the first notification;
    # speaker-tuning and tailscale-receive because the Arch enable list omitted
    # them too.
    systemd.user.services = lib.genAttrs [
      "bt-agent"
      "strapd-fcitx5"
      "strapd-crash-watch"
    ] (_: {
      overrideStrategy = "asDropin";
      wantedBy = [ "graphical-session.target" ];
    }) // {
      strapd-recover-internal-monitor = {
        overrideStrategy = "asDropin";
        wantedBy = [ "graphical-session-pre.target" ];
      };
    };

    networking.networkmanager.enable = lib.mkDefault true;
    systemd.services.NetworkManager-wait-online.enable = lib.mkDefault false;

    services.resolved = {
      enable = lib.mkDefault true;
      # etc/systemd/resolved.conf.d: multicast name resolution is Avahi's job,
      # and Docker containers get the stub listener on the bridge address.
      settings.Resolve = {
        LLMNR = "no";
        MulticastDNS = "no";
        DNSStubListenerExtra = "172.17.0.1";
      };
    };

    services.avahi = {
      enable = lib.mkDefault true;
      # Replaces etc/nsswitch.conf's mdns_minimal entry.
      nssmdns4 = true;
    };

    services.printing.enable = lib.mkDefault true;

    virtualisation.docker = {
      enable = lib.mkDefault true;
      # enable-services.sh enables docker.socket, not docker.service:
      # socket-activated, started on first use.
      enableOnBoot = false;
    };

    services.power-profiles-daemon.enable = lib.mkDefault true;

    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
    };

    # etc/systemd/oomd.conf.d/10-strapd.conf. The companion app.slice drop-in
    # ships in the package's user units: only app.slice is a kill candidate.
    systemd.oomd = {
      enable = lib.mkDefault true;
      settings.OOM = {
        DefaultMemoryPressureDurationSec = "20s";
        DefaultMemoryPressureLimit = "50%";
      };
    };

    # etc/systemd/system.conf.d and user.conf.d.
    systemd.settings.Manager = {
      DefaultTimeoutStopSec = "5s";
      DefaultLimitNOFILE = "65536:524288";
    };
    systemd.user.settings.Manager = {
      DefaultLimitNOFILE = "65536:524288";
    };

    # etc/systemd/logind.conf.d.
    services.logind.settings.Login = {
      HandlePowerKey = "ignore";
      InhibitDelayMaxSec = 15;
    };

    # default/systemd/zram-generator.conf.d/90-strapd.conf.
    zramSwap = {
      enable = lib.mkDefault true;
      memoryPercent = 100;
      algorithm = "zstd";
      priority = 100;
    };
    # etc/tmpfiles.d/strapd-zswap.conf: zswap off, zram is the swap story.
    systemd.tmpfiles.rules = [ "w! /sys/module/zswap/parameters/enabled - - - - N" ];

    # etc/sysctl.d.
    boot.kernel.sysctl = {
      "fs.inotify.max_user_watches" = 524288;
      "net.ipv4.tcp_mtu_probing" = 1;
      "vm.swappiness" = 150;
      "vm.vfs_cache_pressure" = 50;
      "vm.page-cluster" = 0;
      "vm.watermark_boost_factor" = 0;
      "vm.watermark_scale_factor" = 125;
      "vm.dirty_background_bytes" = 67108864;
      "vm.dirty_bytes" = 268435456;
      "vm.dirty_writeback_centisecs" = 1500;
    };

    # etc/modprobe.d/strapd-usb-autosuspend.conf.
    boot.extraModprobeConfig = ''
      options usbcore autosuspend=-1
    '';

    # etc/sudoers.d. asdcontrol's rule is omitted until the package is; the dns
    # and timezone rules are what the menus call through.
    security.sudo.extraConfig = ''
      Defaults passwd_tries=10
    '';
    security.sudo.extraRules = [
      {
        groups = [ "wheel" ];
        commands = [
          { command = "/run/current-system/sw/bin/strapd-dns Cloudflare"; options = [ "NOPASSWD" ]; }
          { command = "/run/current-system/sw/bin/strapd-dns Google"; options = [ "NOPASSWD" ]; }
          { command = "/run/current-system/sw/bin/strapd-dns DHCP"; options = [ "NOPASSWD" ]; }
          { command = "/run/current-system/sw/bin/timedatectl set-timezone *"; options = [ "NOPASSWD" ]; }
        ];
      }
    ];

    fonts.packages = with pkgs; [
      nerd-fonts.caskaydia-mono
      noto-fonts
      noto-fonts-color-emoji
    ];
  };
}
