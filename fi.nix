let
  sources = import ./.tack;
  systems = [
    "x86_64-linux"
    "aarch64-linux"
  ];
  mkFinixSystem = sources.finix.lib.finixSystem;

  mkHost = {
    system,
    modules,
    overlays ? [],
    specialArgs ? {},
    pkgsSet ? "default",
  }: let
    pkgs = import sources.nixpkgs (
      {
        inherit overlays;
        config =
          {
            allowUnfree = true;
          }
          // (
            if pkgsSet == "musl"
            then {
              replaceStdenv = {pkgs}: let
                clangCC = pkgs.clangStdenv.cc;
                # TODO: un-hardcode use of Apple CPU?
                rustHook = ''
                  case "''${pname:-}" in
                    rustc | rustc-unwrapped)
                      # nix-wrapped clang's hardening flags break rustc's wasm32 parts.
                      export NIX_HARDENING_ENABLE="''${NIX_HARDENING_ENABLE//zerocallusedregs/}"
                      ;;
                    *)
                      export RUSTFLAGS="''${RUSTFLAGS:-} -C target-cpu=apple-m1"
                      ;;
                  esac
                  # Skip test suites in the clang set; many fail on clang/musl for test-only reasons.
                  unset doCheck doInstallCheck
                '';
              in
                pkgs.overrideCC pkgs.clangStdenv (clangCC.override (old: {
                  # Some packages read stdenv.cc.cc.libgcc under clang; borrow gcc's.
                  cc = clangCC.cc // {libgcc = pkgs.stdenv.cc.cc.libgcc;};
                  bintools = pkgs.llvmPackages.bintools.override {
                    bintools = pkgs.llvmPackages.bintools-unwrapped.overrideAttrs (bOld: {
                      buildCommand =
                        bOld.buildCommand
                        + "\n"
                        + ''
                          rm -f $out/bin/windres $out/bin/*-windres
                        '';
                    });
                  };
                  extraBuildCommands =
                    (old.extraBuildCommands or "")
                    + ''
                      echo "-mcpu=apple-m1" >> $out/nix-support/cc-cflags
                      # lld rejects version scripts naming missing symbols; GNU ld ignored them.
                      echo "--undefined-version" >> $out/nix-support/cc-ldflags
                      echo ${pkgs.lib.escapeShellArg rustHook} >> $out/nix-support/setup-hook
                    '';
                }));
            }
            else {}
          );
      }
      // (
        if pkgsSet == "musl"
        then {
          localSystem = {
            inherit system;
            config = "aarch64-unknown-linux-musl";
          };
        }
        else {
          inherit system;
        }
      )
    );
  in
    mkFinixSystem {
      inherit (pkgs) lib;
      specialArgs =
        {
          inherit sources;
        }
        // specialArgs;
      modules = [{nixpkgs.pkgs = sources.nixpkgs.lib.mkDefault pkgs;}] ++ modules;
    };
in {
  finixConfigurations = {
    necomac = mkHost {
      system = "aarch64-linux";
      pkgsSet = "musl";
      overlays = [
        # TODO: move overlays to overlays.nix, add comments.
        (import ./hosts/necomac/apple-silicon-support/packages/overlay.nix)
        (import ./hosts/necomac/overlay.nix)
      ];

      modules = with sources.finix.nixosModules;
        [
          (./hosts/necomac/configuration.nix)
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
      specialArgs = {
        finix = sources.finix;
        modulesPath = toString sources.nixpkgs + "/nixos/modules";
      };
    };

    necoarc = mkHost {
      system = "x86_64-linux";
      overlays = [];
      modules = with sources.finix.nixosModules;
        [
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
        ]
        ++ (with sources.finix-community.nixosModules; [
          steam
        ]);
      specialArgs = {
        finix = sources.finix;
        modulesPath = toString sources.nixpkgs + "/nixos/modules";
      };
    };
  };
}
