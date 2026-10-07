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
    udevPkg = pkgs.libudev-zero;
  };
  avd-fw = pkgs.callPackage ../../packages/avd-fw { };
  libva-v4l2-request = pkgs.callPackage ../../packages/libva-v4l2-request { };
  endcord = pkgs.callPackage ../../packages/endcord { };
  makoCustom = pkgs.callPackage ../../packages/mako { };

  xdg-open = pkgs.writeScriptBin "xdg-open" ''
    #!${pkgs.busybox}/bin/ash

    printf '%s\n' "$@" >> /tmp/xdg-open.args
    ls -l "$1" >> /tmp/xdg-open.args 2>&1
    file "$1" >> /tmp/xdg-open.args 2>&1

    exec ${lib.getExe pkgs.handlr-regex} open "$@"
  '';

  lspPluginsLv2 = pkgs.lsp-plugins.override {
    buildCLAP = false;
    buildGStreamer = false;
    buildJACK = false;
    buildLADSPA = false;
    buildLV2 = true;
    buildVST2 = false;
    buildVST3 = false;
  };

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

  fixAppleDrm = pkgs.writeScriptBin "fix-apple-drm" ''
    #!${pkgs.busybox}/bin/ash
    ${pkgs.busybox}/bin/chown root:video /dev/dri/card2
    ${pkgs.busybox}/bin/chmod 660 /dev/dri/card2
  '';

  mangoAutologin = pkgs.writeScriptBin "mango-autologin" ''
    #!${pkgs.busybox}/bin/ash
    ${config.providers.privileges.command} -n ${lib.getExe fixAppleDrm}
    exec ${wrappers.mango.session}
  '';

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

  start-webcamera = pkgs.writeScriptBin "start-webcamera" ''
    #!${pkgs.busybox}/bin/ash
    exec ${config.providers.privileges.command} -n \
      ${lib.getExe' pkgs.kmod "modprobe"} apple_isp
  '';

  start-pipewire = pkgs.writeScriptBin "start-pipewire" ''
    #!${pkgs.busybox}/bin/ash
    export ALSA_CONFIG_UCM2="${pkgs.alsa-ucm-conf-asahi}/share/alsa/ucm2"

    /run/wrappers/bin/doas -n \
      /run/current-system/sw/bin/initctl cond clear usr/audio

    pkill -u "$USER" -x pipewire-pulse 2>/dev/null || true
    pkill -u "$USER" -x wireplumber 2>/dev/null || true
    pkill -u "$USER" -x pipewire 2>/dev/null || true

    sleep 0.1

    pkill -KILL -u "$USER" -x pipewire-pulse 2>/dev/null || true
    pkill -KILL -u "$USER" -x wireplumber 2>/dev/null || true
    pkill -KILL -u "$USER" -x pipewire 2>/dev/null || true

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

  start-waybar-sound = pkgs.writeScriptBin "start-waybar-sound" ''
    #!${pkgs.busybox}/bin/ash

    until
      wpctl get-volume @DEFAULT_AUDIO_SINK@ >/dev/null 2>&1 &&
      wpctl get-volume @DEFAULT_AUDIO_SOURCE@ >/dev/null 2>&1
    do
      sleep 0.2
    done

    sleep 0.5

    exec waybar
  '';

  send-volume-notif = pkgs.writeScriptBin "send-volume-notif" ''
    #!${pkgs.busybox}/bin/ash

    wpctl set-volume --limit 1.5 @DEFAULT_AUDIO_SINK@ "$1"

    set -- $(wpctl get-volume @DEFAULT_AUDIO_SINK@)
    volume=$2

    volume=''${volume%%.*}''${volume#*.}
    volume=''${volume#0}
    volume=''${volume#0}

    notify-send -c device -h string:x-dunst-stack-tag:volume "Volume" "Volume set to: $volume%"
  '';

  send-brightness-notif = pkgs.writeScriptBin "send-brightness-notif" ''
    #!${pkgs.busybox}/bin/ash

    brightnessctl set "$1"
    brightness=$(brightnessctl get -P)
    notify-send -c device -h string:x-dunst-stack-tag:brightness "Brightness" "Brightness set to: $brightness%"
  '';

  termfilechooser = pkgs.xdg-desktop-portal-termfilechooser.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
      pkgs.makeWrapper
    ];

    postInstall = (old.postInstall or "") + ''
      wrapProgram \
        "$out/share/xdg-desktop-portal-termfilechooser/nnn-wrapper.sh" \
        --prefix PATH : ${
          lib.makeBinPath [
            pkgs.nnn
            pkgs.busybox
          ]
        }

      mkdir -p "$out/etc/xdg/xdg-desktop-portal-termfilechooser"

      cat > "$out/etc/xdg/xdg-desktop-portal-termfilechooser/config" <<EOF
      [filechooser]
      cmd=$out/share/xdg-desktop-portal-termfilechooser/nnn-wrapper.sh
      default_dir=\$HOME
      env=TERMCMD=foot -T nnn-filechooser
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

      udev = pkgs.libudev-zero;
    }).overrideAttrs
      (old: {
        mesonFlags =
          map (
            flag:
            if lib.hasPrefix "-Dtools=" flag then
              "-Dtools="
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
          ) (lib.filter (flag: !(lib.hasPrefix "-Dgallium-rusticl-enable-drivers=" flag)) old.mesonFlags)
          ++ [ "-Dgallium-va=disabled" ];

        postInstall = (old.postInstall or "") + ''
          rm -rf "$opencl/etc/OpenCL"
          mkdir -p "$spirv2dxil" "$opencl"
        '';

        postFixup =
          lib.replaceStrings
            [ "$out/lib/libgallium*.so $opencl/lib/libRusticlOpenCL.so" ]
            [ "$out/lib/libgallium*.so" ]
            (old.postFixup or "");
      });

  rtkitMusl = pkgs.rtkit.overrideAttrs (old: {
    postPatch =
      (old.postPatch or "")
      + lib.optionalString pkgs.stdenv.hostPlatform.isMusl ''
              substituteInPlace rtkit-daemon.c \
                --replace-fail \
                  '#include <sys/resource.h>' \
                  '#include <sys/resource.h>
        #include <sys/syscall.h>

        #define sched_getscheduler(pid) \
          syscall(SYS_sched_getscheduler, (pid))
        #define sched_setscheduler(pid, policy, param) \
          syscall(SYS_sched_setscheduler, (pid), (policy), (param))'
      '';
  });

in
{
  imports = [
    ./hardware-configuration.nix
    ./apple-silicon-support
    ../../modules/security/wrappers
    ../../modules/environment/path
    #./sddm.nix
  ];

  disabledModules = [
    "${sources.finix}/modules/security/wrappers"
    "${sources.finix}/modules/environment/path"
  ];

  # In flake setups, vendor directory must be set explicitly.
  hardware.asahi.enable = true;
  hardware.asahi.peripheralFirmwareDirectory = /boot/vendorfw;

  finit.path = lib.mkForce [
    config.programs.coreutils.package
    config.finit.package

    # required by finit on shutdown
    pkgs.util-linux.mount

    # for finit log rotation
    pkgs.gzip
  ];
  finit.runlevel = 3;
  finit.cgroups.system.settings = {
    "cpu.weight" = 100;
  };

  finit.services.nix-daemon = {
    environment.CURL_CA_BUNDLE = config.security.pki.caBundle;
  };

  finit.services.dbus.notify = lib.mkForce "none"; # we don't use systemd at all.

  finit.tasks.battery-charge-limit = {
    description = "Set battery limit (to 80%)";
    runlevels = "2345";
    command = pkgs.writeScript "battery-charge-limit" ''
      #!${pkgs.busybox}/bin/ash

      path=/sys/class/power_supply/macsmc-battery/charge_control_end_threshold

      while [ ! -e "$path" ]; do
        sleep 0.1
      done

      echo 80 > "$path"
    '';
  };

  finit.tasks.bluetooth-late = {
    conditions = [ "!service/greetd/ready" ];
    command = "${lib.getExe' pkgs.kmod "modprobe"} hci_bcm4377";
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
  boot.initrd.availableKernelModules = lib.mkForce [
    "apple-mailbox"
    "appledrm"
    "apple_nvmem_spmi"
    "nvme_apple"
    "pinctrl-apple-gpio"
    "macsmc"
    "macsmc-power"
    "macsmc-input"
    "macsmc-hwmon"
    "macsmc-reboot"
    "i2c-pasemi-platform"
    "tps6598x"
    "apple-dart"
    "dwc3"
    "dwc3-of-simple"
    "xhci-pci"
    "pcie-apple"
    "gpio_macsmc"
    "phy-apple-atc"
    "nvmem_apple_efuses"
    "spi-apple"
    "spi-hid-apple"
    "spi-hid-apple-of"
    "rtc-macsmc"
    "spmi-apple-controller"
    "apple-dockchannel"
    "dockchannel-hid"
    "apple-rtkit-helper"
    "usb-storage"
    "xhci-plat-hcd"
    "usbhid"
    "hid_generic"
    "ext4"
  ];
  boot.kernelPatches = [
    # ~20% battery boost on M1 Pro!
    {
      name = "apple-use-pmp";
      patch = ../../patches/apple-use-pmp.patch;
    }
  ];
  boot.initrd.kernelModules = [
    "mux_apple_display_crossbar"
  ];

  xdg.portal = {
    enable = true;
    #package = xdg-desktop-portal-rdmaless;
    portals = [
      pkgs.xdg-desktop-portal-gtk
      xdg-desktop-portal-wlr
      termfilechooser
    ];
  };

  programs = {
    coreutils.package = pkgs.busybox;

    limine = {
      enable = true;
      settings.editor_enabled = true; # Disable on systems that need security
      maxGenerations = 5;
    };

    pipewire = {
      enable = true;
      alsa.enable = true;
      package = pkgs.pipewire;
      packages = [ pkgs.asahi-audio ];

      settings = {
        "node.rules" = [
          {
            matches = [
              { "node.name" = "audio_effect.j314-convolver"; }
              { "node.name" = "effect_output.j314-convolver"; }
            ];

            actions = {
              "update-props" = {
                "node.pause-on-idle" = false;
                "session.suspend-timeout-seconds" = 0;
              };
            };
          }
        ];
      };
    };
    tuigreet.enable = true;
    brightnessctl.enable = true;
    wireplumber.enable = true;
    #wireplumber.package = pkgs.wireplumber;
    doas.enable = true;
    modprobe.blacklist = [
      "apple_isp"
      "sm4_ce"
      "sm4_ce_gcm"
      "hci_bcm4377"
    ];
    bash.enable = true;
  };

  services.dbus.packages = [
    pkgs.dconf
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
    pkgs.cozette
    pkgs.nerd-fonts.symbols-only
    pkgs.wqy_microhei
    pkgs.noto-fonts-color-emoji
  ];

  services = {
    #bootchart.enable = true;
    #bootchart.stop.conditions = [ "service/greetd/ready" ];
    openssh.enable = true;
    polkit.enable = true;
    polkit.package = lib.mkForce pkgs.polkit;
    anacron.enable = true;
    sysklogd.enable = true;
    dbus.enable = true;
    getty.enable = true;
    mdevd.enable = true;
    mdevd.nlgroups = 4;
    greetd.settings.initial_session = {
      user = "jagerroni";
      command = lib.getExe mangoAutologin;
    };
    keventd.enable = false;
    dhcpcd.enable = true;
    iwd.enable = true;
    seatd.enable = true;
    rtkit.enable = true;
    rtkit.package = rtkitMusl;
    # https://github.com/finix-community/finix/blob/37c6c49aac1ba686fc7b4def599e6a0a7e3ef0bc/modules/services/rtkit/default.nix#L42-L44
    rtkit.extraGroups = [ config.services.seatd.group ];
    bluetooth.enable = true;
    mdevd.hotplugRules = lib.mkMerge [
      # Run ahead of 'generic MODALIAS' (order 250).
      (lib.mkOrder 249 ''
        $MODALIAS=of:.*pmgr-pwrstate.* 0:0 660
        $MODALIAS=of:.*t6000-dart.* 0:0 660
      '')

      (lib.mkAfter ''
        SUBSYSTEM=input;.* root:input 660
        SUBSYSTEM=sound;.* root:audio 660
        SUBSYSTEM=media;.* root:video 660
      '')

      # Force Apple DRM mode to actually be ready before greetd (auto)login.
      ''
        card[0-9] root:video 660 =dri/
      ''
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

  hardware.graphics.enable = true;
  hardware.graphics.package = mesaAsahi;
  hardware.graphics.extraPackages = [ libva-v4l2-request ];
  hardware.firmware = [ avd-fw ];

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
    "/share/mime"
  ];

  environment.etc."xdg/xdg-desktop-portal/mango-portals.conf".text = ''
    [preferred]
    default=wlr;gtk;
    org.freedesktop.impl.portal.Screenshot=wlr;
    org.freedesktop.impl.portal.ScreenCast=wlr;
    org.freedesktop.impl.portal.Secret=oo7-portal;
    org.freedesktop.impl.portal.FileChooser=termfilechooser;
  ''; # TODO: decide on gtk/termfilechooser for the FileChooser portal.

  environment.etc."xdg/xdg-desktop-portal-wlr/config".text = ''
    [screencast]
    chooser_type=dmenu
    chooser_cmd=fuzzel --dmenu --prompt="Share: "
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
      runAs = "root";
      requirePassword = false;
      command = lib.getExe' pkgs.kmod "modprobe";
      args = [ "apple_isp" ];
    }
    {
      users = [ "jagerroni" ];
      runAs = "root";
      command = lib.getExe fixAppleDrm;
      requirePassword = false;
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
    lspPluginsLv2
  ];

  security.pam.environment.NH_FILE.default = "/home/jagerroni/dotfiles/fi.nix";
  security.pam.environment.NH_ATTRP.default = "finixConfigurations.necomac";
  security.pam.environment.NIX_PATH.default = "nixpkgs=flake:nixpkgs";
  security.pam.environment.NH_NOM.default = "no";

  security.pam.services.greetd.text = lib.mkForce ''
    # Account management.
    account required pam_unix.so # unix (order 10900)

    # Authentication management.
    auth sufficient pam_unix.so likeauth nullok try_first_pass # unix (order 12800)
    auth required pam_deny.so # deny (order 13600)

    # Password management.
    password sufficient pam_unix.so nullok yescrypt # unix (order 10200)

    # Session management.
    session required pam_env.so conffile=/etc/security/pam_env.conf readenv=0 # env (order 10100)
    session required pam_unix.so # unix (order 10200)
    session required pam_loginuid.so # loginuid (order 10300)
    session required pam_limits.so conf=/etc/security/limits.conf

    session optional ${pkgs.pam_rundir}/lib/security/pam_rundir.so
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

  environment.extraSetup = ''
    if [ -w $out/share/mime ] && [ -d $out/share/mime/packages ]; then
      XDG_DATA_DIRS=$out/share \
        PKGSYSTEM_ENABLE_FSYNC=0 \
        ${pkgs.buildPackages.shared-mime-info}/bin/update-mime-database \
          -V $out/share/mime > /dev/null
    fi
  '';

  system.activation.path = lib.mkForce (
    map lib.getBin [
      config.programs.coreutils.package
      pkgs.getent
      pkgs.stdenv.cc.libc # nscd in update-users-groups.pl
      pkgs.shadow
      pkgs.nettools # needed for hostname
      pkgs.util-linux # needed for mount and mountpoint
    ]
  );

  environment.systemPackages = with pkgs; [
    wget
    imv
    xdg-open
    shared-mime-info
    gitMinimal
    iputils
    iwmenu
    iproute2
    libnotify
    stash-clipboard
    foot
    adwaita-icon-theme
    wrappers.fuzzel
    wrappers.firefox.firefox-bin-void
    handlr-regex
    oo7-server-fix
    oo7-portal
    asahi-audio
    alsa-ucm-conf-asahi
    speakersafetyd
    triforce-lv2
    bankstown-lv2
    start-pipewire
    lspPluginsLv2
    swaybg
    dconf
    nh-unwrapped
    playerctl
    tree
    btop
    libarchive
    grim
    slurp
    makoCustom
    wrappers.mango
    send-volume-notif
    send-brightness-notif
    start-webcamera
    tack
    microfetch
    nnn
    micro
  ];
}
