{
  pkgs,
  hostName,
  wireplumber,
  udevPkg,
}:
let
  # TODO: drop once https://github.com/NixOS/nixpkgs/pull/549633
  # hits nixos-unstable
  libcava1 = pkgs.libcava.overrideAttrs (old: {
    version = "1.0.0";

    src = pkgs.fetchFromGitHub {
      owner = "LukashonakV";
      repo = "cava";
      tag = "1.0.0";
      hash = "sha256-0r5aAmTs+FcmS501tNYKxG9H+Pq6i32BDRBEjWW6M74=";
    };
  });

  waybar-master =
    (pkgs.waybar.override {
      cavaSupport = false;
      evdevSupport = false;
      gpsSupport = false;
      inputSupport = false;
      jackSupport = false;
      mpdSupport = false;
      #    mprisSupport = false;
      niriSupport = false;
      nlSupport = true;
      pipewireSupport = false;
      pulseSupport = false;
      rfkillSupport = false;
      sndioSupport = false;
      systemdSupport = false;
      traySupport = false;
      udevSupport = true;
      upowerSupport = false;
      wireplumberSupport = true;
      withMediaPlayer = false;

      inherit wireplumber;
      udev = udevPkg;
    }).overrideAttrs
      (old: {
        version = "0.15.0";

        src = pkgs.fetchFromGitHub {
          owner = "Alexays";
          repo = "Waybar";
          rev = "master";
          hash = "sha256-G6AcGuevhkYflQHhJq9GnLhEMgcI51Y6MYKBQvdRPDc=";
        };

        mesonFlags = old.mesonFlags ++ [
          "-Dmango=true"
          "-Dwwan=disabled"
        ];
      });

  config =
    if hostName == "necoarc" then
      pkgs.writeText "waybar-config-necoarc.jsonc" ''
        {
          "battery": {
            "bat": "BAT0"
          },
          "include": [
            "${builtins.toString ./config.jsonc}"
          ]
        }
      ''
    else if hostName == "necomac" then
      pkgs.writeText "waybar-config-necomac.jsonc" ''
        {
          "battery": {
            "bat": "macsmc-battery"
          },
          "include": [
            "${builtins.toString ./config.jsonc}"
          ]
        }
      ''
    else
      builtins.toString ./config.jsonc;

in
pkgs.symlinkJoin {
  name = "waybar-master-wrapped-${waybar-master.version}";
  paths = [ waybar-master ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram "$out/bin/waybar" \
      --add-flags "--config ${config}" \
      --add-flags "--style ${builtins.toString ./style.css}"
  '';
  meta.mainProgram = "waybar";
}
