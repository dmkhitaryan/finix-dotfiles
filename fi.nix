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
        (final: prev: {
          libpcap = prev.libpcap.override { withRdma = false; };
        })

        (
          final: prev:
          let
            php84ForLsp = prev.php84.buildEnv {
              systemdSupport = false;
              valgrindSupport = false;

              extensions =
                { enabled, ... }:
                prev.lib.filter (ext: (ext.extensionName or null) != "gettext") enabled;
            };
          in
          {
            lsp-plugins =
              (prev.lsp-plugins.override {
                php84 = php84ForLsp;

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

                  postPatch =
                    (old.postPatch or "")
                    + prev.lib.optionalString prev.stdenv.hostPlatform.isMusl ''
                      substituteInPlace modules/lsp-runtime-lib/src/main/ipc/Library.cpp \
                        --replace-fail \
                          "::dlmopen(LM_ID_NEWLM, str, RTLD_NOW)" \
                          "::dlopen(str, RTLD_NOW)"
                    '';
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
          gst_all_1 = prev.gst_all_1.overrideScope (
            gstFinal: gstPrev: {
              gstreamer = gstPrev.gstreamer.override {
                withRust = false;
                enableDocumentation = false;
              };

              gst-plugins-base = gstPrev.gst-plugins-base.override {
                enableDocumentation = false;
              };
            }
          );
        })

        (
          final: prev:
          let
            trimLlvm =
              llvmPkgs:
              llvmPkgs.overrideScope (
                llvmFinal: llvmPrev: {
                  llvm = llvmPrev.llvm.override {
                    enableManpages = false;
                    enablePFM = false;
                    enablePolly = false;
                    enableTerminfo = false;

                    devExtraCmakeFlags = [
                      "-DLLVM_PARALLEL_COMPILE_JOBS=8"
                      "-DLLVM_PARALLEL_LINK_JOBS=2"
                    ];
                  };

                  clang-unwrapped = llvmPrev.clang-unwrapped.override {
                    enableClangToolsExtra = false;
                    enableManpages = false;

                    devExtraCmakeFlags = [
                      "-DLLVM_PARALLEL_COMPILE_JOBS=8"
                      "-DLLVM_PARALLEL_LINK_JOBS=2"
                    ];
                  };
                }
              );

            llvm21 = trimLlvm prev.llvmPackages_21;
            llvm22 = trimLlvm prev.llvmPackages_22;
          in
          {
            llvmPackages_21 = llvm21;
            llvmPackages_22 = llvm22;

            # Default llvmPackages is LLVM 21 on your current nixpkgs.
            llvmPackages = llvm21;
          }
        )

        (final: prev: {
          v4l-utils = prev.v4l-utils.override {
            withGUI = false;
            withBPF = false;
            udev = prev.libudev-zero;
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

                nix-store = prev.nixVersions.latest.libs.nix-store.override {
                  withAWS = false;
                };
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
          kmod = prev.kmod.override {
            withDevdoc = false;
          };
        })

        (final: prev: {
          libtiff = prev.libtiff.overrideAttrs (old: {
            nativeBuildInputs = builtins.filter (p: p != prev.sphinx) (old.nativeBuildInputs or [ ]);

            outputs = builtins.filter (
              output:
              !builtins.elem output [
                "doc"
                "man"
              ]
            ) (old.outputs or [ ]);
          });
        })

        (final: prev: {
          gst_all_1 = prev.gst_all_1 // {
            gstreamer = prev.gst_all_1.gstreamer.override {
              enableDocumentation = false;
            };

            gst-plugins-base = prev.gst_all_1.gst-plugins-base.override {
              enableDocumentation = false;
            };
          };
        })

        (final: prev: {
          elfutils = prev.elfutils.override {
            enableDebuginfod = false;
          };
        })

        (final: prev: {
          fontforge = prev.fontforge.override {
            withGTK = false;
            withPython = false;
            withExtras = false;
          };
        })

        (final: prev: {
          sqlite = prev.sqlite.overrideAttrs {
            doCheck = false;
            doInstallCheck = false;
          };
        })

        (final: prev: {
          wayland = prev.wayland.override {
            withDocumentation = false;
            withTests = false;
          };
        })

        (final: prev: {
          libdrm = prev.libdrm.override {
            withIntel = false;
            withValgrind = false;
          };
        })

        (final: prev: {
          m1n1 = prev.m1n1.overrideAttrs {
            doCheck = false;
          };
        })

        (final: prev: {
          mako =
            (prev.mako.override {
              systemdMinimal = prev.basu;
            }).overrideAttrs
              {
                mesonFlags = [ "-Dsd-bus-provider=basu" ];
              };
        })

        (final: prev: {
          libgudev =
            (prev.libgudev.override {
              udev = prev.libudev-zero;
            }).overrideAttrs
              (old: {
                doCheck = false;
                mesonFlags = builtins.filter (p: !prev.lib.hasPrefix "-Dtests=" p) (old.mesonFlags or [ ]) ++ [
                  "-Dtests=disabled"
                ];
              });
        })

        (final: prev: {
          seatd = (
            prev.seatd.override {
              systemdSupport = false;
            }
          );
        })

        (final: prev: {
          libusb1 = (
            prev.libusb1.override {
              udev = prev.libudev-zero;
            }
          );
        })

        (final: prev: {
          libcamera = (
            prev.libcamera.override {
              udev = prev.libudev-zero;
            }
          );
        })

        (final: prev: {
          libinput = prev.libinput.override {
            udev = prev.libudev-zero; # mdevd.
            wacomSupport = false;
          };

          wlroots = prev.wlroots.override {
            libinput = final.libinput;
          };
        })

        (final: prev: {
          greetd = prev.greetd.overrideAttrs (old: {
            nativeBuildInputs = builtins.filter (p: p != prev.scdoc) (old.nativeBuildInputs or [ ]);
            postInstall = "";
          });
        })

        (final: prev: {
          linux-pam = prev.linux-pam.override {
            withLogind = false;
          };
          pam = final.linux-pam;
        })

        (final: prev: {
          procps = prev.procps.override {
            withSystemd = false;
          };
        })

        (final: prev: {
          at-spi2-core = prev.at-spi2-core.override {
            systemdSupport = false;
          };
        })

        (final: prev: {
          polkit =
            (prev.polkit.override {
              useSystemd = false;
              useConsoleKit = true;
            }).overrideAttrs
              (old: {
                buildInputs = builtins.filter (p: p != prev.elogind) (old.buildInputs or [ ]);
              });
        })

        (final: prev: {
          libcanberra =
            (prev.libcanberra.override {
              gst_all_1 = final.gst_all_1;
              withSystemd = false;
            }).overrideAttrs
              (old: {
                postConfigure = (old.postConfigure or "") + ''
                  sed -i '/^finish_cmds=.*ldconfig -n .*libdir/c\finish_cmds=""' libtool
                '';
              });
        })

        (final: prev: {
          libcanberra-gtk3 =
            (prev.libcanberra-gtk3.override {
              gst_all_1 = final.gst_all_1;
              withSystemd = false;
            }).overrideAttrs
              (old: {
                postConfigure = (old.postConfigure or "") + ''
                  sed -i '/^finish_cmds=.*ldconfig -n .*libdir/c\finish_cmds=""' libtool
                '';
              });
        })

        (final: prev: {
          xdg-desktop-portal-wlr =
            (prev.xdg-desktop-portal-wlr.override {
              systemdLibs = prev.basu;
            }).overrideAttrs
              (old: {
                mesonFlags =
                  builtins.filter (
                    p: !(prev.lib.hasPrefix "-Dsd-bus-provider=" p) && !(prev.lib.hasPrefix "-Dsystemd=" p)
                  ) (old.mesonFlags or [ ])
                  ++ [
                    "-Dsd-bus-provider=basu"
                    "-Dsystemd=disabled"
                  ];
              });
        })

        (final: prev: {
          bluez = prev.bluez.override {
            udev = prev.libudev-zero;
          };
        })

        (final: prev: {
          rtkit =
            (prev.rtkit.override {
              systemdLibs = prev.basu;
            }).overrideAttrs
              (old: {
                mesonFlags = (old.mesonFlags or [ ]) ++ [
                  (prev.lib.mesonEnable "libsystemd" false)
                ];
              });
        })

        (final: prev: {
          util-linux = prev.util-linux.override {
            systemdSupport = false;
          };
        })

        (final: prev: {
          dbus = prev.dbus.override {
            enableSystemd = false;
          };
        })

        (final: prev: {
          xwayland = prev.xwayland.overrideAttrs (old: {
            buildInputs = builtins.filter (p: p != prev.systemd) (old.buildInputs or [ ]);
          });
        })

        (final: prev: {
          wireplumber =
            (prev.wireplumber.override {
              enableDocs = false;
              enableGI = false;
              pipewire = final.pipewire;
            }).overrideAttrs
              (old: {
                postPatch = (old.postPatch or "") + ''
                  substituteInPlace po/meson.build \
                    --replace-fail \
                      "python_po = pymod.find_installation('python3')" \
                      "python_po = pymod.find_installation('python3', required: false)"
                '';

                buildInputs = builtins.filter (p: p != prev.systemdLibs) (old.buildInputs or [ ]);

                mesonFlags =
                  (builtins.filter (
                    flag:
                    !prev.lib.hasPrefix "-Dsystemd=" flag
                    && !prev.lib.hasPrefix "-Dsystemd-system-service=" flag
                    && !prev.lib.hasPrefix "-Dsystemd-system-unit-dir=" flag
                  ) (old.mesonFlags or [ ]))
                  ++ [
                    "-Dsystemd-system-service=false"
                    "-Dsystemd=disabled"
                  ];
              });
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
            postPatch = (old.postPatch or "") + ''
              find include -name clipped_region.h -print -exec \
                sed -i 's/__always_inline/inline __attribute__((always_inline))/g' {} +
            '';
          });
        })

        (final: prev: {
          pipewire =
            (prev.pipewire.override {
              enableSystemd = false;
              systemdLibs = null;

              ffadoSupport = false;
              rocSupport = false;
              zeroconfSupport = false;

              udev = prev.libudev-zero;
              libdrm = final.libdrm;
            }).overrideAttrs
              (old: {
                doCheck = false;

                buildInputs = builtins.filter (p: p != prev.modemmanager) (old.buildInputs or [ ]);

                nativeBuildInputs = builtins.filter (
                  p:
                  if prev.lib.isDerivation p then
                    !(builtins.elem (prev.lib.getName p) [
                      "docutils"
                      "doxygen"
                      "graphviz"
                    ])
                  else
                    true
                ) (old.nativeBuildInputs or [ ]);

                mesonFlags =
                  (builtins.filter (
                    flag:
                    !prev.lib.hasPrefix "-Ddocs=" flag
                    && !prev.lib.hasPrefix "-Dinstalled_tests=" flag
                    && !prev.lib.hasPrefix "-Dman=" flag
                    && !prev.lib.hasPrefix "-Dlogind=" flag
                    && !prev.lib.hasPrefix "-Dbluez5-backend-native-mm=" flag
                  ) (old.mesonFlags or [ ]))
                  ++ [
                    "-Ddocs=disabled"
                    "-Dinstalled_tests=disabled"
                    "-Dman=disabled"
                    "-Dlogind=disabled"
                    "-Dbluez5-backend-native-mm=disabled"
                  ];

                outputs = builtins.filter (
                  output:
                  !builtins.elem output [
                    "doc"
                    "man"
                    "installedTests"
                  ]
                ) (old.outputs or [ ]);
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

        (final: prev: {
          python313 = prev.python313.override {
            packageOverrides = pyFinal: pyPrev: {
              pytest-xdist = pyPrev.pytest-xdist.overridePythonAttrs (_: {
                doCheck = false;
              });
              python-dbusmock = pyPrev.python-dbusmock.overridePythonAttrs (_: {
                doCheck = false;
              });
            };
          };

          python314 = prev.python314.override {
            packageOverrides = pyFinal: pyPrev: {
              pytest-xdist = pyPrev.pytest-xdist.overridePythonAttrs (_: {
                doCheck = false;
              });
              python-dbusmock = pyPrev.python-dbusmock.overridePythonAttrs (_: {
                doCheck = false;
              });
            };
          };
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
