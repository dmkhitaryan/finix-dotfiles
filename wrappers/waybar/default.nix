{
pkgs,
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
    pkgs.waybar.overrideAttrs (old: {
      version = "0.15.0";

      src = pkgs.fetchFromGitHub {
        owner = "Alexays";
        repo = "Waybar";
        rev = "master";
        hash = "sha256-uFfKkAbLn4AgX0uZWlYNUxRUOdRp0x4WKXiOvQqhyy4=";
      };

      buildInputs = old.buildInputs ++ [
        pkgs.modemmanager
        libcava1
      ];

      mesonFlags = old.mesonFlags ++ [ "-Dmango=true" ];
  });
in
pkgs.symlinkJoin {
  name = "waybar-master-wrapped-${waybar-master.version}";
  paths = [ waybar-master ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram "$out/bin/waybar" \
      --add-flags "--config ${builtins.toString ./config.jsonc}" \
      --add-flags "--style ${builtins.toString ./style.css}"
  '';
  meta.mainProgram = "waybar";
}
