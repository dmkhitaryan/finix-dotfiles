{
  pkgs,
  hostName ? null,
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

  waybar-master = pkgs.waybar.overrideAttrs (old: {
    version = "0.15.0";

    src = pkgs.fetchFromGitHub {
      owner = "Alexays";
      repo = "Waybar";
      rev = "master";
      hash = "sha256-1JFW1v/v539cS0M3KwCf3NAo9ulNawyaOTxDe1naPe4=";
    };

    buildInputs = old.buildInputs ++ [
      pkgs.modemmanager
      libcava1
    ];

    mesonFlags = old.mesonFlags ++ [ "-Dmango=true" ];
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
