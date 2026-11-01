let
  sources = import ./.tack;

  mkHost = {
    system,
    modules,
    overlays ? [],
    stdenv ? null,
    libc ? null,
  }: let
    pkgs = import sources.nixpkgs {
      inherit overlays;
      localSystem =
        if libc == null
        then {inherit system;}
        else {
          inherit system;
          config = libc;
        };
      config =
        {allowUnfree = true;}
        // (
          if stdenv == null
          then {}
          else {replaceStdenv = stdenv;}
        );
    };
  in
    sources.finix.lib.finixSystem {
      inherit (pkgs) lib;
      specialArgs = {
        inherit sources;
        finix = sources.finix;
        modulesPath = toString sources.nixpkgs + "/nixos/modules";
      };
      modules = [{nixpkgs.pkgs = pkgs.lib.mkDefault pkgs;}] ++ modules;
    };
in {
  finixConfigurations = {
    necomac = mkHost {
      system = "aarch64-linux";
      libc = "aarch64-unknown-linux-musl";
      stdenv = import ./hosts/necomac/stdenv.nix {cpu = "apple-m1";};
      overlays = map import [
        ./hosts/necomac/apple-silicon-support/packages/overlay.nix
        ./hosts/necomac/overlays/llvm.nix
        ./hosts/necomac/overlays/toolchain.nix
        ./hosts/necomac/overlays/musl.nix
        ./hosts/necomac/overlays/nosystemd.nix
        ./hosts/necomac/overlays/nox11.nix
        ./hosts/necomac/overlays/nodocs.nix
        ./hosts/necomac/overlays/notests.nix
        ./hosts/necomac/overlays/trim.nix
        ./hosts/necomac/overlays/apps.nix
      ];

      modules = with sources.finix.nixosModules;
        [
          ./hosts/necomac/configuration.nix
          nix-daemon
          brightnessctl
          openssh
          sysklogd
          limine
          polkit
          getty
          bash
          dhcpcd
          iwd
          tuigreet
          rtkit
          pipewire
          wireplumber
          bluetooth
          doas
          anacron
        ]
        ++ (with sources.finix-community.nixosModules; [
          bootchart
        ]);
    };

    necoarc = mkHost {
      system = "x86_64-linux";
      modules = with sources.finix.nixosModules;
        [
          ./hosts/necoarc/configuration.nix
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
        ]
        ++ (with sources.finix-community.nixosModules; [
          steam
        ]);
    };
  };
}
