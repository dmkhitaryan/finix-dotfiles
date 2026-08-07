{ config, pkgs, lib, wrappers, ... }:
let

xdg-utils-perlless = pkgs.callPackage ./xdg-utils-perlless.nix { };

start-pipewire = pkgs.writeShellScriptBin "start-pipewire" ''
  export ALSA_CONFIG_UCM2="${pkgs.alsa-ucm-conf-asahi}/share/alsa/ucm2"

  /run/wrappers/bin/sudo -n \
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

  /run/wrappers/bin/sudo -n \
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

  termfilechooser =
    pkgs.xdg-desktop-portal-termfilechooser.overrideAttrs (old: {
      nativeBuildInputs =
        (old.nativeBuildInputs or [ ])
        ++ [ pkgs.makeWrapper ];

      postInstall = (old.postInstall or "") + ''
        wrapProgram \
          "$out/share/xdg-desktop-portal-termfilechooser/yazi-wrapper.sh" \
          --prefix PATH : ${lib.makeBinPath [
            pkgs.yazi
            pkgs.gnused
            pkgs.coreutils
            pkgs.findutils
          ]}

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
in
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./apple-silicon-support
    ];

  # Use latest kernel.
  hardware.asahi.enable = true;
  hardware.asahi.peripheralFirmwareDirectory = ./vendorfw;

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

 services.nix-daemon = {
    enable = true;
    package = pkgs.nixVersions.latest;
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [
        "root"
        "@wheel"
      ];
    };
  };

  boot.loader.efi.canTouchEfiVariables = false;
  boot.kernelParams = [ 
    "appledrm.show_notch=1"
    "zswap.enabled=1"
    "zswap.max_pool_percent=20" 
   ]; 
  boot.kernelPatches = [
    { 
      name = "apple-use-pmp";
      patch = ./patches/apple-use-pmp.patch;
    }
  ];

  xdg.portal = {
    enable = true;
    portals = [
    pkgs.xdg-desktop-portal-gtk
    pkgs.xdg-desktop-portal-gnome
    termfilechooser
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
     alsa.support32Bit = true;
     packages = [ pkgs.asahi-audio ];
  };
    brightnessctl.enable = true;
    wireplumber.enable = true;
    sudo.enable = true;
    nano.enable = true;
    nano.defaultEditor = true;
    bash.enable = true;
    niri.enable = true;
    gnome-keyring.enable = true;
    xwayland-satellite.enable = true;
  #  regreet = {
  #    enable = true;
  #    compositor = {
  #      extraArgs = [
  #        "-d"
 #         "-s"
#	  "-m"
#	  "-last"
#	];
#	environment = {
#	  XKB_DEFAULT_LAYOUT = "us";
#	  XKB_DEFAULT_VARIANT = "qwerty";
#	};
 #     };
 #   };
  };

  services.dbus.packages = [
    pkgs.dconf
    pkgs.thunar
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
    pkgs.iosevka
    pkgs.cozette
  ];

  services = {
#    greetd.enable = true;
#    greetd.settings = {
#      default_session = {
#        command = ''
#          ${pkgs.tuigreet}/bin/tuigreet \
#          --time \
#          --remember \
#          --cmd "${pkgs.dbus}/bin/dbus-run-session -- ${pkgs.niri}/bin/niri --session"
#        '';
#        user = "greeter";
#      };
#    };
    ly.enable = true;
    openssh.enable = true;
    polkit.enable = true;
    sysklogd.enable = true;
    dbus.enable = true;
    mdevd.enable = true;
    keventd.enable = false;
    dhcpcd.enable = true;
    iwd.enable = true;
    seatd.enable = true;
    rtkit.enable = true;
    bluetooth.enable = true;
 };

  networking.hostName = "necomac"; # Define your hostname.

  # Set your time zone.
  time.timeZone = "Asia/Yerevan";

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.jagerroni = {
    isNormalUser = true;
    description = "nya~";
    extraGroups = [ "wheel" "video" "rtkit" "input" "render" "audio" "pipewire" config.services.seatd.group ];
    password = "$6$a8et2Z1h9803iBBe$zHp5WQcBd532CxLjoQik09hmAtactwVehG1CfLCG3uWZ8bA5HU9WubOFdT2UpupoYJ.IG32k0SusxvU9CMqkT.";
    packages = with pkgs; [];
  };

  hardware.graphics.enable = true;

  finit.services = {
    speakersafetyd = {
      enable = true;
      description = "Apple Silicon Speaker Safety Interlock Daemon";
      command = ''${pkgs.speakersafetyd}/bin/speakersafetyd -c ${pkgs.speakersafetyd}/share/speakersafetyd'';
      runlevels = "2345";
      conditions = "usr/audio";
    };
  };
  environment.pathsToLink = [
    "/share/wireplumber"
    "/share/icons"
  ];

 environment.etc."xdg/xdg-desktop-portal/niri-portals.conf".text = ''
    [preferred]
    default=gnome;gtk;
    org.freedesktop.impl.portal.FileChooser=termfilechooser;
 '';


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
    command = "/run/current-system/sw/bin/initctl";
    args = [ "poweroff" ];
  }
  {
    users = [ "jagerroni" ];
    groups = [ ];
    runAs = "root";
    requirePassword = false;
    command = "/run/current-system/sw/bin/initctl";
    args = [ "reboot" ];
  }
];

  environment.variables.LV2_PATH = lib.makeSearchPath "lib/lv2" [
    pkgs.triforce-lv2
    pkgs.bankstown-lv2
    pkgs.lsp-plugins    
  ];

  security.pam.environment.NH_FLAKE.default = "/home/jagerroni/dotfiles";

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    wget
    (git.override {
      perlSupport = false;
    })
    nixos-rebuild-ng
    iputils
    iproute2
    flameshot
    libnotify
    wl-clipboard-rs
    foot
    adwaita-icon-theme
    catppuccin-cursors.frappeLavender  
    fuzzel
    wrappers.firefox   
    xdg-utils-perlless
    legcord        
    ashell
    asahi-audio
    alsa-ucm-conf-asahi
    speakersafetyd
    triforce-lv2
    bankstown-lv2
    start-pipewire
    lsp-plugins
    ashell-battery-capacity
    swaybg
    yazi
    papirus-icon-theme
    dconf
    start-ashell
    thunar
    fastfetch
    nh
    playerctl
  ];
}
