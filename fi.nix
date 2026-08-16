let
  sources = import ./.tack;
  systems = [ "x86_64-linux" "aarch64-linux" ];
  mkFinixSystem = sources.finix.lib.finixSystem;

  mkHost = {
    system,
    modules,
    overlays ? [ ],
    specialArgs ? { },
  }:
    let
      pkgs = import sources.nixpkgs {
        inherit system overlays;
        config.allowUnfree = true;
      };
    in
    mkFinixSystem {
      inherit (pkgs) lib;
      specialArgs = { inherit sources; } // specialArgs;
      modules = [ { nixpkgs.pkgs = sources.nixpkgs.lib.mkDefault pkgs; }] ++ modules;
    };
in
{
  finixConfigurations = {
    necomac = mkHost {
      system = "aarch64-linux";
      overlays = [ (import ./apple-silicon-support/packages/overlay.nix)];
      modules = with sources.finix.nixosModules; [
        (./configuration.nix)
        nix-daemon
        nano
        brightnessctl
        openssh
        sysklogd
        limine
        sudo
        polkit
        getty
        bash
        dhcpcd
        iwd
        niri
        gvfs
        regreet
        ly
        rtkit
        gnome-keyring
        xwayland-satellite
        power-profiles-daemon
        upower
        pipewire
        wireplumber
        bluetooth
      ];
      specialArgs = {
        finix = sources.finix;
        modulesPath = toString sources.nixpkgs + "/nixos/modules";
      };
    };
  };


}
