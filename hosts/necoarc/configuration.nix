{ config, pkgs, sources, finix, patchedNvidia, ... }:
let
  xdg-utils-perlless = pkgs.callPackage ../../xdg-utils-perlless.nix { };
  wrappers = import ../../wrappers { inherit pkgs; hostName = config.networking.hostName; };

  rfkill-unblock = pkgs.writeShellScriptBin "rfkill-unblock" ''
    exec ${pkgs.util-linux}/bin/rfkill unblock all
  '';

  start-pipewire = pkgs.writeShellScriptBin "start-pipewire" ''
    set -eu

    pkill -u "$USER" -x pipewire-pulse 2>/dev/null || true
    pkill -u "$USER" -x wireplumber 2>/dev/null || true
    pkill -u "$USER" -x pipewire 2>/dev/null || true

    rm -f "$XDG_RUNTIME_DIR/pipewire-0"

    pipewire &

    until [ -S "$XDG_RUNTIME_DIR/pipewire-0" ]; do
      sleep 0.1
    done

    wireplumber &
    pipewire-pulse &
  '';

  # Despite the module override to use libudev-zero, pipewire's build picked
  # systemd udev; this broke hotplugging event on mdevd, even with nlgroups=4.
  pipewireFixed =
    (pkgs.pipewire.override {
      enableSystemd = false;
      udev = pkgs.libudev-zero;
    }).overrideAttrs (old: {
      preConfigure = (old.preConfigure or "") + ''
        export PKG_CONFIG_PATH="${pkgs.libudev-zero}/lib/pkgconfig:$PKG_CONFIG_PATH"
        export NIX_LDFLAGS="-L${pkgs.libudev-zero}/lib $NIX_LDFLAGS"
      '';

      patches = (old.patches or [ ]) ++ [
        "${finix}/modules/programs/pipewire/pipewire.patch"
      ];
  });

  start-waybar-sound = pkgs.writeShellScriptBin "start-waybar-sound" ''
    until
      wpctl get-volume @DEFAULT_AUDIO_SINK@ >/dev/null 2>&1 &&
      wpctl get-volume @DEFAULT_AUDIO_SOURCE@ >/dev/null 2>&1
    do
      sleep 0.2
    done

    sleep 0.5

    exec waybar
  '';

  flakeRegistry = builtins.toFile "flake-registry.json" (
    builtins.toJSON {
      version = 2;

      flakes = [
        {
          from = {
            type = "indirect";
            id = "nixpkgs";
          };

          to = {
            type = "github";
            owner = "NixOS";
            repo =  "nixpkgs";
            rev = sources.nixpkgs.rev;
          };
        }
      ];
    }
  );

  start-ashell = pkgs.writeShellScriptBin "start-ashell" ''
    until
      wpctl get-volume @DEFAULT_AUDIO_SINK@ \
        >/dev/null 2>&1 &&
      wpctl get-volume @DEFAULT_AUDIO_SOURCE@ \
        >/dev/null 2>&1
    do
      sleep 0.2
    done

    sleep 1

    exec ashell
  '';
in
{

  imports = [
    ./hardware-configuration.nix
  ];

  finit.runlevel = 3;
  finit.tasks.rfkill-unblock = {
    command = "${rfkill-unblock}/bin/rfkill-unblock";
  };

  hardware = {
    cpu.amd.updateMicrocode = true;

    firmware = with pkgs; [
      linux-firmware
      sof-firmware
      wireless-regdb
    ];

    graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = [ pkgs.nvidia-vaapi-driver ];
    };
    nvidia = {
      enable = true;
      #package = config.boot.kernelPackages.nvidiaPackages.latest;
      modesetting.enable = true;
      kernelModule = "open";
      power.suspend.enable = true;
      power.suspend.notifier = "kernel";
    };
  };

  programs = {
    bash.enable = true;
    brightnessctl.enable = true;
    gnome-keyring.enable = true;

    limine = {
      enable = true;
      settings.editor_enabled = true;
      maxGenerations = 10;
    };

    nano.enable = true;
    nano.defaultEditor = true;

    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
    };

    sudo.enable = true;
    wireplumber.enable = true;
    xwayland-satellite.enable = true;

  };

  services = {
    chrony.enable = true;
    bluetooth.enable = true;
    dbus.enable = true;
    dbus.packages = with pkgs; [
      dconf
      thunar
    ];
    dhcpcd.enable = true;
    iwd.enable = true;
    ly.enable = true;
    udev.enable = true;

    nix-daemon = {
       enable = true;
       package = pkgs.nixVersions.latest;
       settings = {
         allow-import-from-derivation = false;
         auto-optimise-store = true;
         connect-timeout = 5;
         fallback = true;
         flake-registry = flakeRegistry;
         experimental-features = [ "nix-command" "flakes" ];
         max-jobs = 2;
         cores = 4;
         nix-path = "";
         trusted-users = [
           "root"
           "@wheel"
         ];
         warn-dirty = "false";

       };
     };

    openssh.enable = true;
    polkit.enable = true;
    rtkit.enable = true;
    rtkit.extraGroups = [
      config.services.seatd.group
    ];
    seatd.enable = true;
    sysklogd.enable = true;
  };

  networking.hostName = "necoarc";
  time.timeZone = "Asia/Yerevan";

  users.users.kibter = {
    isNormalUser = true;
    description = "Mowzas!";
    extraGroups = [ "wheel" "video" "input" "render" "audio" "pipewire" config.services.seatd.group ];
  };

  i18n = {
    defaultLocale = "en_GB.UTF-8";
    extraLocaleSettings = {
      LC_ADDRESS = "en_GB.UTF-8";
      LC_IDENTIFICATION = "en_GB.UTF-8";
      LC_MEASUREMENT = "en_GB.UTF-8";
      LC_MONETARY = "en_GB.UTF-8";
      LC_NAME = "en_GB.UTF-8";
      LC_NUMERIC = "en_GB.UTF-8";
      LC_PAPER = "en_GB.UTF-8";
      LC_TELEPHONE = "en_GB.UTF-8";
      LC_TIME = "en_GB.UTF-8";
    };
  };
  programs.modprobe.blacklist = [ "nouevau" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.lenovo-legion-module ];
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.initrd.supportedFilesystems.btrfs.enable = true;
  boot.initrd.supportedFilesystems.vfat.enable = true;
  boot.supportedFilesystems.vfat.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelParams = [
    "zswap.enabled=1"
    "zswap.max_pool_percent=25"
  ];
  boot.initrd.kernelModules = [
    "efivarfs"
    "nvidia"
    "nvidia_modeset"
    "nvidia_uvm"
    "nvidia_drm"
  ];
  boot.kernelModules = [ "legion_laptop" ];

  xdg.portal = {
    enable = true;
    portals = with pkgs; [
      xdg-desktop-portal-gtk
      xdg-desktop-portal-gnome
    ];
  };

  xdg.autostart.enable = true;
  xdg.icons.enable = true;
  xdg.mime.enable = true;

  fonts = {
    fontconfig = {
      enable = true;
      defaultFonts = {
      serif = [ "Iosevka" ];
      sansSerif = [ "Iosevka" ];
      monospace = [ "Cozette" ];
      };
    };

    packages = [
      pkgs.iosevka
      pkgs.cozette
      pkgs.nerd-fonts._0xproto
      pkgs.noto-fonts-cjk-sans
      pkgs.noto-fonts-color-emoji
    ];
  };

  environment.pathsToLink = [
    "/share/wireplumber"
    "/share/icons"
  ];

  environment.etc."xdg/xdg-desktop-portal/niri-portals.conf".text = ''
     [preferred]
     default=gnome;gtk;
     org.freedesktop.impl.portal.FileChooser=gtk;
  ''; # TODO: decide on gtk/termfilechooser for the FileChooser portal.

  environment.etc."xdg/xdg-desktop-portal-wlr/config".text = ''
    [screencast]
    chooser_type=dmenu
    chooser_cmd=fuzzel --dmenu --prompt="Share: "
  '';

  providers.privileges.rules = [
    {
      users = [ "kibter" ];
      groups = [ ];
      runAs = "root";
      requirePassword = false;
      command = "/run/current-system/sw/bin/initctl";
      args = [
        "cond"
        "set"
        "usr/audio"
      ];
    }
    {
      users = [ "kibter" ];
      groups = [ ];
      runAs = "root";
      requirePassword = false;
      command = "/run/current-system/sw/bin/initctl";
      args = [
        "cond"
        "clear"
        "usr/audio"
      ];
    }
    {
       users = [ "kibter" ];
       groups = [ ];
       runAs = "root";
       requirePassword = false;
       command = "/run/current-system/sw/bin/poweroff";
     }
     {
       users = [ "kibter" ];
       groups = [ ];
       runAs = "root";
       requirePassword = false;
       command = "/run/current-system/sw/bin/reboot";
     }
     {
       users = [ "kibter" ];
       groups = [ ];
       runAs = "root";
       requirePassword = false;
       command = "/run/current-system/sw/bin/initctl";
       args = [ "suspend" ];
     }
  ];

  security.pam.environment = {
    NH_FILE.default = "/home/kibter/finix-dotfiles/fi.nix";
    NH_ATTRP.default = "finixConfigurations.necoarc";
    NIX_PATH.default = "nixpkgs=flake:nixpkgs";
  };

  environment.systemPackages = with pkgs; [
    appimage-run
    audacious
    jq
    yt-dlp
    wget
    (git.override {
      perlSupport = false;
    })
    iputils
    iwmenu
    iproute2
    flameshot
    libnotify
    wl-clipboard-rs
    xsel
    foot
    adwaita-icon-theme
    catppuccin-cursors.frappeLavender
    wrappers.fuzzel
    wrappers.firefox
    xdg-utils-perlless
    vesktop
    swaybg
    yazi
    dconf
    thunar
    fastfetch
    nh
    playerctl
    tree
    btop
    libarchive
    grim
    slurp
    swaynotificationcenter
    wrappers.waybar-master
    wrappers.niri
    wrappers.ashell
    wrappers.kanshi
    tack
    start-pipewire
    start-ashell
    rfkill-unblock
    lutris-free
  ];
}
