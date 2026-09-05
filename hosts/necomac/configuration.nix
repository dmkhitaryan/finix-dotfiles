{
  config,
  pkgs,
  lib,
  wrappers,
  finix,
  sources,
  ...
}:
let

  wrappers = import ../../wrappers {
    inherit pkgs;
    hostName = config.networking.hostName;
    wireplumber = config.programs.wireplumber.package;
  };
  xdg-utils-perlless = pkgs.callPackage ../../xdg-utils-perlless.nix { };

  xdg-desktop-portal-rdmaless =
    (pkgs.xdg-desktop-portal.override {
      umockdev = pkgs.umockdev.override {
        libpcap = pkgs.libpcap.override {
          withRdma = false;
        };
      };
    }).overrideAttrs
      (old: {
        buildInputs = builtins.filter (dep: dep != pkgs.flatpak) old.buildInputs;

        mesonFlags = old.mesonFlags ++ [
          "-Dflatpak-interfaces=disabled"
        ];
      });

  pam = pkgs.symlinkJoin {
    name = "linux-pam-with-lastlog2";

    paths = [
      pkgs.pam
    ];

    postBuild = ''
      ln -s \
        ${pkgs.util-linux.lastlog}/lib/security/pam_lastlog2.so \
        $out/lib/security/pam_lastlog.so
    '';
  };

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
            repo = "nixpkgs";
            rev = sources.nixpkgs.rev;
          };
        }
      ];
    }
  );

  # https://github.com/emersion/xdg-desktop-portal-wlr/issues/395 still helps it seems.
  xdg-desktop-portal-wlr = pkgs.xdg-desktop-portal-wlr.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace include/pipewire_screencast.h \
        --replace-fail '#define XDPW_PWR_BUFFERS 2' \
                       '#define XDPW_PWR_BUFFERS 4' \
        --replace-fail '#define XDPW_PWR_BUFFERS_MIN 2' \
                       '#define XDPW_PWR_BUFFERS_MIN 4'
    '';
  });

  # Despite the module override to use libudev-zero, pipewire's build picked
  # systemd udev; this broke hotplugging event on mdevd, even with nlgroups=4.
  pipewireFixed =
    (pkgs.pipewire.override {
      enableSystemd = false;
      udev = pkgs.libudev-zero;
    }).overrideAttrs
      (old: {
        preConfigure = (old.preConfigure or "") + ''
          export PKG_CONFIG_PATH="${pkgs.libudev-zero}/lib/pkgconfig:$PKG_CONFIG_PATH"
          export NIX_LDFLAGS="-L${pkgs.libudev-zero}/lib $NIX_LDFLAGS"
        '';

        patches = (old.patches or [ ]) ++ [
          "${finix}/modules/programs/pipewire/pipewire.patch"
        ];
      });

  start-pipewire = pkgs.writeShellScriptBin "start-pipewire" ''
    export ALSA_CONFIG_UCM2="${pkgs.alsa-ucm-conf-asahi}/share/alsa/ucm2"

    /run/wrappers/bin/doas -n \
      /run/current-system/sw/bin/initctl cond clear usr/audio

    pkill -u "$USER" -x pipewire-pulse 2>/dev/null || true
    pkill -u "$USER" -x wireplumber 2>/dev/null || true
    pkill -u "$USER" -x pipewire 2>/dev/null || true

    while pgrep -u "$USER" -x pipewire >/dev/null ||
      pgrep -u "$USER" -x wireplumber >/dev/null ||
      pgrep -u "$USER" -x pipewire-pulse >/dev/null
    do
      sleep 0.1
    done

    /run/current-system/sw/bin/pipewire &

    until [ -S "$XDG_RUNTIME_DIR/pipewire-0" ]; do
      sleep 1
    done

    /run/current-system/sw/bin/wireplumber &
    /run/current-system/sw/bin/pipewire-pulse &

    until wpctl status -n 2>/dev/null \
      | grep -qE 'alsa_output\..*\[vol:'
    do
      sleep 1
    done

    /run/wrappers/bin/doas -n \
      /run/current-system/sw/bin/initctl cond set usr/audio
  '';

  ashell-battery-capacity = pkgs.writeShellScriptBin "ashell-battery-capacity" ''
    battery=/sys/class/power_supply/macsmc-battery

    last=""

    while true; do
      if [ -r "$battery/capacity" ]; then
        capacity=$(cat "$battery/capacity")

        if [ "$capacity" != "$last" ]; then
          printf '{"text":"%s%%","alt":"battery"}\n' "$capacity"
          last="$capacity"
        fi
      else
        printf '{"text":"?","alt":"unavailable"}\n'
      fi

      sleep 5
    done
  '';

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

    exec ashell -c /home/jagerroni/.config/ashell/config.toml
  '';

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

  termfilechooser = pkgs.xdg-desktop-portal-termfilechooser.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];

    postInstall = (old.postInstall or "") + ''
      wrapProgram \
        "$out/share/xdg-desktop-portal-termfilechooser/yazi-wrapper.sh" \
        --prefix PATH : ${
          lib.makeBinPath [
            pkgs.yazi
            pkgs.gnused
            pkgs.coreutils
            pkgs.findutils
          ]
        }

      mkdir -p "$out/etc/xdg/xdg-desktop-portal-termfilechooser"

      cat > "$out/etc/xdg/xdg-desktop-portal-termfilechooser/config" <<EOF
      [filechooser]
      cmd=$out/share/xdg-desktop-portal-termfilechooser/yazi-wrapper.sh
      default_dir=\$HOME
      env=TERMCMD=foot -T yazi-filechooser
      open_mode=suggested
      save_mode=last
      EOF
    '';
  });

  pass-secret-service-fix = pkgs.pass-secret-service.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
            cat > "$out/share/dbus-1/services/org.freedesktop.secrets.service" <<EOF
      [D-BUS Service]
      Name=org.freedesktop.secrets
      Exec=$out/bin/pass_secret_service
      EOF
    '';
  });

  oo7-server-fix = pkgs.oo7-server.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
            cat > "$out/share/dbus-1/services/org.freedesktop.secrets.service" <<EOF
      [D-BUS Service]
      Name=org.freedesktop.secrets
      Exec=$out/libexec/oo7-daemon
      EOF
    '';
  });

  mesaAsahi =
    (pkgs.mesa.override {
      vulkanDrivers = [ "asahi" ];

      galliumDrivers = [
        "asahi"
        "llvmpipe"
      ];

      vulkanLayers = [
        "device-select"
        "overlay"
        "screenshot"
      ];

      enablePatentEncumberedCodecs = false;
      withValgrind = false;
    }).overrideAttrs
      (old: {
        mesonFlags =
          map (
            flag:
            if lib.hasPrefix "-Dtools=" flag then
              "-Dtools=asahi"
            else if lib.hasPrefix "-Dintel-rt=" flag then
              "-Dintel-rt=disabled"
            else if lib.hasPrefix "-Dteflon=" flag then
              "-Dteflon=false"
            else if lib.hasPrefix "-Dgallium-rusticl=" flag then
              "-Dgallium-rusticl=false"
            else if lib.hasPrefix "-Dgallium-extra-hud=" flag then
              "-Dgallium-extra-hud=false"
            else
              flag
          ) (lib.filter (flag: !lib.hasPrefix "-Dgallium-rusticl-enable-drivers=" flag) old.mesonFlags)
          ++ [ "-Dgallium-va=disabled" ];

        postInstall = (old.postInstall or "") + ''
          rm -rf "$opencl/etc/OpenCL"
          mkdir -p "$spirv2dxil" "$opencl"
        '';

        postFixup =
          lib.replaceStrings
            [
              "$out/lib/libgallium*.so $opencl/lib/libRusticlOpenCL.so"
            ]
            [
              "$out/lib/libgallium*.so"
            ]
            (old.postFixup or "");
      });
in
{
  imports = [
    ./hardware-configuration.nix
    ./apple-silicon-support
    ../../modules/security/wrappers
    #./sddm.nix
  ];

  disabledModules = [
    "${sources.finix}/modules/security/wrappers"
  ];

  # In flake setups, vendor directory must be set explicitly.
  hardware.asahi.enable = true;
  hardware.asahi.peripheralFirmwareDirectory = /boot/vendorfw;

  finit.runlevel = 3;

  finit.services.nix-daemon = {
    environment.CURL_CA_BUNDLE = config.security.pki.caBundle;
  };

  finit.tasks.battery-charge-limit = {
    description = "Set battery limit (to 80%)";
    runlevels = "2345";
    command = pkgs.writeShellScript "battery-charge-limit" ''
      path=/sys/class/power_supply/macsmc-battery/charge_control_end_threshold

      while [ ! -e "$path" ]; do
        sleep 0.1
      done

      echo 80 > "$path"
    '';
  };

  i18n = {
    defaultLocale = "C.UTF-8";
    glibcLocales = null;
  };

  services.nix-daemon = {
    enable = true;
    package = pkgs.nixVersions.latest;
    settings = {
      allow-import-from-derivation = false;
      auto-optimise-store = true;
      connect-timeout = 5;
      fallback = true;
      flake-registry = flakeRegistry;
      experimental-features = [
        "nix-command"
        "flakes"
      ];
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

  boot.loader.efi.canTouchEfiVariables = false;
  boot.kernelParams = [
    "appledrm.show_notch=1"
    "zswap.enabled=1"
    "zswap.max_pool_percent=20"
  ];
  boot.kernelPatches = [
    # ~20% battery boost on M1 Pro!
    {
      name = "apple-use-pmp";
      patch = ../../patches/apple-use-pmp.patch;
    }
  ];

  xdg.portal = {
    enable = true;
    #package = xdg-desktop-portal-rdmaless;
    portals = [
      pkgs.xdg-desktop-portal-gtk
      xdg-desktop-portal-wlr
    ];
  };

  programs = {
    limine = {
      enable = true;
      settings.editor_enabled = true; # Disable on systems that need security
      maxGenerations = 10;
    };

    pipewire = {
      enable = true;
      alsa.enable = true;
      package = pipewireFixed;
      packages = [ pkgs.asahi-audio ];
    };
    brightnessctl.enable = true;
    fastfetch.enable = false;
    wireplumber.enable = true;
    sudo.enable = false;
    doas.enable = true;
    nano.enable = true;
    nano.defaultEditor = true;
    bash.enable = true;
    gnome-keyring.enable = false;
  };

  services.dbus.packages = [
    pkgs.dconf
    pkgs.pcmanfm
    oo7-server-fix
  ];

  fonts.fontconfig = {
    enable = true;
    defaultFonts = {
      serif = [ "Iosevka" ];
      sansSerif = [ "Iosevka" ];
      monospace = [ "Cozette" ];
    };
  };

  fonts.packages = [
    pkgs.iosevka-bin
    pkgs.cozette
    pkgs.nerd-fonts._0xproto
    pkgs.noto-fonts-cjk-sans
    pkgs.noto-fonts-color-emoji
  ];

  services = {
    #bootchart.enable = true;
    #bootchart.stop.conditions = [ "service/ly/ready" ];
    ly.enable = true;
    openssh.enable = true;
    polkit.enable = true;
    anacron.enable = true;
    sysklogd.enable = true;
    dbus.enable = true;
    mdevd.enable = true;
    mdevd.nlgroups = 4;
    keventd.enable = false;
    dhcpcd.enable = true;
    iwd.enable = true;
    seatd.enable = true;
    rtkit.enable = true;
    bluetooth.enable = true;
    mdevd.hotplugRules = lib.mkMerge [
      (lib.mkAfter ''
        SUBSYSTEM=input;.* root:input 660
        SUBSYSTEM=sound;.* root:audio 660
      '')
    ];
  };

  networking.hostName = "necomac";
  time.timeZone = "Asia/Yerevan";

  users.users.jagerroni = {
    isNormalUser = true;
    description = "nya~";
    extraGroups = [
      "wheel"
      "video"
      "rtkit"
      "input"
      "render"
      "audio"
      "pipewire"
      config.services.seatd.group
    ];
    packages = with pkgs; [ ];
  };
  users.defaultUserShell = pkgs.bashInteractive;

  hardware.graphics.enable = true;
  hardware.graphics.package = mesaAsahi;

  finit.services = {
    speakersafetyd = {
      enable = true;
      description = "Apple Silicon Speaker Safety Interlock Daemon";
      command = "${pkgs.speakersafetyd}/bin/speakersafetyd -c ${pkgs.speakersafetyd}/share/speakersafetyd";
      runlevels = "2345";
      conditions = "usr/audio";
    };
  };
  environment.pathsToLink = [
    "/share/wireplumber"
    "/share/icons"
  ];

  environment.etc."xdg/xdg-desktop-portal/mango-portals.conf".text = ''
    [preferred]
    default=wlr;gtk;
    org.freedesktop.impl.portal.Screenshot=wlr;
    org.freedesktop.impl.portal.ScreenCast=wlr;
    org.freedesktop.impl.portal.Secret=oo7-portal;
  ''; # TODO: decide on gtk/termfilechooser for the FileChooser portal.

  environment.etc."xdg/xdg-desktop-portal-wlr/config".text = ''
    [screencast]
    chooser_type=dmenu
    chooser_cmd=fuzzel --dmenu --prompt="Share: "
  '';

  environment.etc."finit.d/getty-tty3.conf".text = ''
    service [34] name:getty-tty3 restart:10 \
      ${pkgs.util-linux}/bin/agetty 38400 tty3 linux
  '';

  environment.etc."finit.d/getty-tty4.conf".text = ''
    service [34] name:getty-tty4 restart:10 \
      ${pkgs.util-linux}/bin/agetty 38400 tty4 linux
  '';

  environment.etc."finit.d/getty-tty5.conf".text = ''
    service [34] name:getty-tty5 restart:10 \
      ${pkgs.util-linux}/bin/agetty 38400 tty5 linux
  '';

  environment.etc."finit.d/getty-tty6.conf".text = ''
    service [34] name:getty-tty6 restart:10 \
      ${pkgs.util-linux}/bin/agetty 38400 tty6 linux
  '';

  providers.scheduler.backend = "anacron";
  providers.privileges.rules = [
    {
      users = [ "jagerroni" ];
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
      users = [ "jagerroni" ];
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
      users = [ "jagerroni" ];
      groups = [ ];
      runAs = "root";
      requirePassword = false;
      command = "poweroff";
    }
    {
      users = [ "jagerroni" ];
      groups = [ ];
      runAs = "root";
      requirePassword = false;
      command = "reboot";
    }
    {
      users = [ "jagerroni" ];
      groups = [ ];
      runAs = "root";
      requirePassword = false;
      command = "initctl";
      args = [ "suspend" ];
    }
  ];
  environment.variables.LANGUAGE = "en_GB:en";
  environment.variables.LV2_PATH = lib.makeSearchPath "lib/lv2" [
    # All needed for sound on Asahi Linux.
    pkgs.triforce-lv2
    pkgs.bankstown-lv2
    pkgs.lsp-plugins
  ];

  security.pam.environment.NH_FILE.default = "/home/jagerroni/dotfiles/fi.nix";
  security.pam.environment.NH_ATTRP.default = "finixConfigurations.necomac";
  security.pam.environment.NIX_PATH.default = "nixpkgs=flake:nixpkgs";

  security.pam.services.ly.text = lib.mkForce ''
    account required pam_unix.so

    auth optional pam_unix.so likeauth nullok
    auth sufficient pam_unix.so likeauth nullok try_first_pass
    auth required pam_deny.so

    password sufficient pam_unix.so nullok yescrypt

    session required pam_env.so debug conffile=/etc/security/pam_env.conf readenv=1
    session required pam_unix.so
    session optional pam_loginuid.so

    ${lib.optionalString config.services.elogind.enable "session optional ${pkgs.elogind}/lib/security/pam_elogind.so"}

    ${lib.optionalString config.services.seatd.enable "session optional ${pkgs.pam_rundir}/lib/security/pam_rundir.so"}

    session optional ${pkgs.util-linux.lastlog}/lib/security/pam_lastlog2.so silent
    session required pam_limits.so
  '';

  security.pam.services.login.text = lib.mkForce ''
    # Account management.
    account required pam_unix.so # unix (order 10900)

    # Authentication management.
    auth optional pam_unix.so likeauth nullok # unix-early (order 11500)
    auth sufficient pam_unix.so likeauth nullok try_first_pass # unix (order 12800)
    auth required pam_deny.so # deny (order 13600)

    # Password management.
    password sufficient pam_unix.so nullok yescrypt # unix (order 10200)

    # Session management.
    session required pam_env.so conffile=/etc/security/pam_env.conf readenv=0 # env (order 10100)
    session required pam_unix.so # unix (order 10200)
    session required pam_loginuid.so # loginuid (order 10300)
    session required pam_limits.so conf=/etc/security/limits.conf

    session optional ${pkgs.util-linux.lastlog}/lib/security/pam_lastlog2.so silent

    ${lib.optionalString config.services.elogind.enable "session optional ${pkgs.elogind}/lib/security/pam_elogind.so"}
    ${lib.optionalString config.services.seatd.enable "session optional ${pkgs.pam_rundir}/lib/security/pam_rundir.so"}
  '';

  environment.systemPackages = with pkgs; [
    wget
    (git.override {
      perlSupport = false;
    })
    iputils
    iwmenu
    iproute2
    # flameshot
    libnotify
    wl-clipboard-rs
    foot
    adwaita-icon-theme
    bibata-cursors
    wrappers.fuzzel
    wrappers.firefox.firefox-bin-void
    xdg-utils-perlless
    oo7-server-fix
    oo7-portal
    asahi-audio
    alsa-ucm-conf-asahi
    speakersafetyd
    triforce-lv2
    bankstown-lv2
    start-pipewire
    lsp-plugins
    swaybg
    dconf
    nh
    playerctl
    tree
    btop
    libarchive
    grim
    slurp
    mako
    wrappers.waybar-master
    start-waybar-sound
    wrappers.mango
    tack
    wrappers.kanshi
    microfetch
    pcmanfm
    ly
    dwlb
  ];
}
