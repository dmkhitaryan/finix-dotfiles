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
      overlays = [ # TODO: move overlays to overlays.nix, add comments.
        (import ./hosts/necomac/apple-silicon-support/packages/overlay.nix)
        (final: prev: {
          libpcap = prev.libpcap.override { withRdma = false; };
        })

        (
          final: prev:
          let
            php84NoGettext = prev.php84.withExtensions (
              { enabled, ... }:
              prev.lib.filter (ext: (ext.extensionName or null) != "gettext") enabled
            );
          in
          {
            lsp-plugins =
              (prev.lsp-plugins.override {
                php84 = php84NoGettext;

                buildVST3 = true;
                buildVST2 = false;
                buildCLAP = false;
                buildLV2 = true;
                buildLADSPA = false;
                buildJACK = false;
                buildGStreamer = false;
              }).overrideAttrs
                (old: {
                  buildInputs = builtins.filter (
                    p:
                    let
                      name = prev.lib.getName p;
                    in
                    name != "jack2" && name != "ladspa-header" && name != "gstreamer" && name != "gst-plugins-base"
                  ) (old.buildInputs or [ ]);
                });
          }
        )
        (final: prev: {
          spandsp = prev.spandsp.overrideAttrs (old: {
            checkPhase =
              builtins.replaceStrings
                [ "ademco_contactid_tests|dtmf_rx_tests" ]
                [ "ademco_contactid_tests|modem_echo_tests|dtmf_rx_tests" ]
                old.checkPhase;
          });
        })

        (final: prev: {
          gst_all_1 = prev.gst_all_1 // {
            gstreamer =
              (prev.gst_all_1.gstreamer.override {
                withRust = false;
              }).overrideAttrs
                (old: {
                  mesonFlags = (old.mesonFlags or [ ]) ++ [
                    "-Ddoc=disabled"
                  ];

                  nativeBuildInputs = builtins.filter (p: !(builtins.isAttrs p && prev.lib.getName p == "hotdoc")) (
                    old.nativeBuildInputs or [ ]
                  );
                });
          };
        })

        (final: prev: {
          llvmPackages = prev.llvmPackages.overrideScope (
            llvmFinal: llvmPrev: {
              clang-unwrapped = llvmPrev.clang-unwrapped.override {
                enableClangToolsExtra = false;
                enableManpages = false;

                devExtraCmakeFlags = [
                  # Keep Clang from OOMing while still allowing the rest of the
                  # system build to use more cores.
                  "-DLLVM_PARALLEL_COMPILE_JOBS=3"
                  "-DLLVM_PARALLEL_LINK_JOBS=1"
                ];
              };
            }
          );
        })

        (final: prev: {
          v4l-utils = prev.v4l-utils.override {
            withGUI = false;
            withBPF = false;
          };
        })

        (
          final: prev:
          let
            dummy = prev.runCommand "dummy-nix-tests-run" { } "mkdir -p $out";
            dummyTests = dummy // {
              tests.run = dummy;
            };
          in
          {
            nixVersions = prev.nixVersions // {
              latest = prev.nixVersions.latest.override {
                nix-util-tests = dummyTests;
                nix-store-tests = dummyTests;
                nix-expr-tests = dummyTests;
                nix-fetchers-tests = dummyTests;
                nix-flake-tests = dummyTests;
                nix-functional-tests = null;
              };
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
          libei = prev.libei.override {
            systemdLibs = prev.basu;
          };
        })

        (final: prev: {
          xwayland = prev.xwayland.override {
            systemd = prev.systemdLibs;
          };
        })

        (final: prev: {
          xdg-desktop-portal =
            (prev.xdg-desktop-portal.override {
              enableGeoLocation = false;
              enableSystemd = false;
            }).overrideAttrs
              (old: {
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

        (final: prev: {
          pipewire =
            (prev.pipewire.override {
              enableSystemd = false;
              ffadoSupport = false;
              rocSupport = false;
            }).overrideAttrs
              (old: {
                buildInputs = builtins.filter (p: p != prev.modemmanager) (old.buildInputs or [ ]);

                mesonFlags = (old.mesonFlags or [ ]) ++ [
                  "-Dlogind=disabled"
                  # No WWAN/LTE/5G modem on this Asahi host; keep normal BlueZ audio only.
                  "-Dbluez5-backend-native-mm=disabled"
                ];
              });
        })

        (final: prev: {
          ffmpeg = prev.ffmpeg.override {
            withSdl2 = false;
            buildFfplay = false;
          };
        })

        (final: prev: {
          noto-fonts-color-emoji = final.stdenvNoCC.mkDerivation {
            pname = "noto-fonts-color-emoji";
            version = "2.051";

            src = final.fetchurl {
              url = "https://github.com/googlefonts/noto-emoji/raw/v2.051/fonts/NotoColorEmoji.ttf";
              hash = "sha256-cqY1yz0vNSTFFiDN3kBrIXIE6KagbGoJb/jtS1/W4ns=";
            };

            dontUnpack = true;

            installPhase = ''
              runHook preInstall

              install -Dm644 "$src" \
                "$out/share/fonts/truetype/noto/NotoColorEmoji.ttf"

              runHook postInstall
            '';

            meta = prev.noto-fonts-color-emoji.meta;
          };
        })
        (final: prev: {
          xdg-desktop-portal-gtk =
            let
              gsdSchemas = final.stdenvNoCC.mkDerivation {
                pname = "gnome-settings-daemon-gsettings-schemas-minimal";
                inherit (prev.gnome-settings-daemon) version;

                src = prev.gnome-settings-daemon.src;

                dontConfigure = true;
                dontBuild = true;

                installPhase = ''
                  runHook preInstall

                  schemaDir="$out/share/gsettings-schemas/gnome-settings-daemon-gsettings-schemas-minimal/glib-2.0/schemas"
                  mkdir -p "$schemaDir"

                  cp data/org.gnome.settings-daemon.peripherals.gschema.xml.in \
                    "$schemaDir/org.gnome.settings-daemon.peripherals.gschema.xml"

                  cp data/org.gnome.settings-daemon.plugins.xsettings.gschema.xml.in \
                    "$schemaDir/org.gnome.settings-daemon.plugins.xsettings.gschema.xml"

                  runHook postInstall
                '';
              };
            in
            prev.xdg-desktop-portal-gtk.overrideAttrs (old: {
              mesonFlags = (old.mesonFlags or [ ]) ++ [
                "-Dwallpaper=disabled"
                "-Dlockdown=disabled"
              ];

              buildInputs =
                builtins.filter (p: p != prev.gnome-desktop && prev.lib.getName p != "gnome-settings-daemon") (
                  old.buildInputs or [ ]
                )
                ++ [
                  gsdSchemas
                ];
            });
        })

        (final: prev: {
          libopenmpt = prev.libopenmpt.override {
            usePulseAudio = false;
          };
        })
        (final: prev: {
          libcamera = prev.libcamera.overrideAttrs (old: {
            nativeBuildInputs = builtins.filter (
              p:
              let
                name = prev.lib.getName p;
              in
              name != "sphinx" && name != "graphviz" && name != "doxygen"
            ) (old.nativeBuildInputs or [ ]);

            mesonFlags = (old.mesonFlags or [ ]) ++ [
              "-Dpycamera=disabled"
            ];

            buildInputs = builtins.filter (p: prev.lib.getName p != "pybind11") (old.buildInputs or [ ]);
          });
        })

        (final: prev: {
          fftw = prev.fftw.overrideAttrs (old: {
            nativeBuildInputs = builtins.filter (p: prev.lib.getName p != "gfortran-wrapper") (
              old.nativeBuildInputs or [ ]
            );

            configureFlags = (old.configureFlags or [ ]) ++ [
              "--disable-fortran"
            ];
          });

          fftwSinglePrec = prev.fftwSinglePrec.overrideAttrs (old: {
            nativeBuildInputs = builtins.filter (p: prev.lib.getName p != "gfortran-wrapper") (
              old.nativeBuildInputs or [ ]
            );

            configureFlags = (old.configureFlags or [ ]) ++ [
              "--disable-fortran"
            ];
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
