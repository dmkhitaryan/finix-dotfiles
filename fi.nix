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
        (import ./hosts/necomac/apple-silicon-support/packages/overlay.nix)
        #        (final: prev: {
        #	  libpcap = prev.libpcap.override { withRdma = false; };
        #        })

        (
          final: prev:
          let
            php84NoGettext = prev.php84.withExtensions (
              { enabled, ... }:
              prev.lib.filter (ext: (ext.extensionName or null) != "gettext") enabled
            );
          in
          {
            lsp-plugins = prev.lsp-plugins.override {
              php84 = php84NoGettext;
            };
          }
        )

        (final: prev: {
          onetbb = prev.onetbb.overrideAttrs (old: {
            disabledTests =
              (old.disabledTests or [ ])
              ++ prev.lib.optionals prev.stdenv.hostPlatform.isMusl [
                "test_scheduler_mix"
              ];
          });
        })

        (final: prev: {
          xdg-desktop-portal = prev.xdg-desktop-portal.overrideAttrs (old: {
            doCheck = false;

            buildInputs = builtins.filter (dep: prev.lib.getName dep != "flatpak") (old.buildInputs or [ ]);

            mesonFlags = (old.mesonFlags or [ ]) ++ [
              "-Dflatpak-interfaces=disabled"
            ];
          });
        })

        (final: prev: {
          lsp-plugins = prev.lsp-plugins.overrideAttrs (old: {
            postPatch =
              (old.postPatch or "")
              + prev.lib.optionalString prev.stdenv.hostPlatform.isMusl ''
                substituteInPlace modules/lsp-runtime-lib/src/main/ipc/Library.cpp \
                  --replace-fail \
                    "::dlmopen(LM_ID_NEWLM, str, RTLD_NOW)" \
                    "::dlopen(str, RTLD_NOW)"
              '';
          });
        })

        (final: prev: {
          firefox-unwrapped = prev.firefox-unwrapped.overrideAttrs (old: {
            configureFlags =
              builtins.filter (flag: !(prev.lib.hasPrefix "--with-onnx-runtime=" flag)) (
                old.configureFlags or [ ]
              )
              ++ [
                "--without-onnx-runtime"
              ];
          });
        })

        (final: prev: {
          scenefx = prev.scenefx.overrideAttrs (old: {
            postPatch =
              (old.postPatch or "")
              + prev.lib.optionalString prev.stdenv.hostPlatform.isMusl ''
                sed -i '1i#include <linux/stddef.h>' \
                  include/scenefx/types/fx/clipped_region.h
              '';
          });
        })
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
      ];
      specialArgs = {
        finix = sources.finix;
        modulesPath = toString sources.nixpkgs + "/nixos/modules";
      };
    };
  };

}
