{
  description = "Minimal finix flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    finix.url = "github:finix-community/finix";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    finix,
    ...
  }: let
    pkgs = import nixpkgs {
      system = "aarch64-linux";
      config.allowUnfree = true;
      overlays = [
        (import ./apple-silicon-support/packages/overlay.nix)
#        (final: prev: {
#          xdg-utils = final.callPackage ./xdg-utils-perlless.nix {};
#        })
      ];
    };
  in {
    nixosConfigurations.necomac = finix.lib.finixSystem {
      inherit (pkgs) lib;

      modules = with finix.nixosModules; [
        {
          nixpkgs.pkgs = nixpkgs.lib.mkDefault pkgs;
        }
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
        openssh
        mango
      ];

      specialArgs = {
        modulesPath = toString nixpkgs + "/nixos/modules";
        wrappers = import ./wrappers { inherit pkgs; };
      };
    };
  };
}
