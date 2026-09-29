let
  sources = import ./.tack;
  systems = [
    "x86_64-linux"
    "aarch64-linux"
  ];
  mkFinixSystem = sources.finix.lib.finixSystem;

  mkHost =
    {
      system,
      modules,
      overlays ? [ ],
      specialArgs ? { },
      pkgsSet ? "default",
    }:
    let
      pkgs = import sources.nixpkgs (
        {
          inherit overlays;
          config.allowUnfree = true;
        }
        // (
          if pkgsSet == "musl" then
            {
              localSystem = {
                inherit system;
                config = "aarch64-unknown-linux-musl";
              };
            }
          else
            {
              inherit system;
            }
        )
      );
    in
    mkFinixSystem {
      inherit (pkgs) lib;
      specialArgs = {
        inherit sources;
      }
      // specialArgs;
      modules = [ { nixpkgs.pkgs = sources.nixpkgs.lib.mkDefault pkgs; } ] ++ modules;
    };
in
{
  finixConfigurations = {
    necomac = mkHost {
      system = "aarch64-linux";
      pkgsSet = "musl";
      overlays = [
        # TODO: move overlays to overlays.nix, add comments.
        (import ./hosts/necomac/apple-silicon-support/packages/overlay.nix)
        (import ./hosts/necomac/overlay.nix)
      ];

      modules =
        with sources.finix.nixosModules;
        [
          (./hosts/necomac/configuration.nix)
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
          tuigreet
          rtkit
          gnome-keyring
          xwayland-satellite
          power-profiles-daemon
          upower
          pipewire
          wireplumber
          bluetooth
          doas
          anacron
        ]
        ++ (with sources.finix-community.nixosModules; [
          fastfetch
        ]);
      specialArgs = {
        finix = sources.finix;
        modulesPath = toString sources.nixpkgs + "/nixos/modules";
      };
    };

    necoarc = mkHost {
      system = "x86_64-linux";
      overlays = [ ];
      modules = with sources.finix.nixosModules; [
        (./hosts/necoarc/configuration.nix)
        nix-daemon
        nano
        chronyd
        brightnessctl
        openssh
        openbox
        sysklogd
        limine
        sudo
        polkit
        rtkit
        getty
        bash
        dhcpcd
        iwd
        gvfs
        ly
        gnome-keyring
        xwayland-satellite
        power-profiles-daemon
        pipewire
        wireplumber
        bluetooth
        docker
      ];
      specialArgs = {
        finix = sources.finix;
        modulesPath = toString sources.nixpkgs + "/nixos/modules";
      };
    };
  };

}
