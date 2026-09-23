final: prev:
let
  php84ForLsp = prev.php84.buildEnv {
    systemdSupport = false;
    valgrindSupport = false;

    extensions =
      { enabled, ... }:
      prev.lib.filter (ext: (ext.extensionName or null) != "gettext") enabled;
  };

  gstAll1Scoped = prev.gst_all_1.overrideScope (
    _: gstPrev: {
      gstreamer = gstPrev.gstreamer.override {
        withRust = false;
        enableDocumentation = false;
      };

      gst-plugins-base = gstPrev.gst-plugins-base.override {
        enableDocumentation = false;
      };
    }
  );

  # Preserve the effect of the later gst_all_1 overlay from the old definition.
  gstAll1 = gstAll1Scoped // {
    gstreamer = gstAll1Scoped.gstreamer.override {
      enableDocumentation = false;
    };

    gst-plugins-base = gstAll1Scoped.gst-plugins-base.override {
      enableDocumentation = false;
    };
  };

  trimLlvm =
    llvmPkgs:
    llvmPkgs.overrideScope (
      _: llvmPrev: {
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

  dummy = prev.runCommand "dummy-nix-tests-run" { } "mkdir -p $out";
  dummyTests = dummy // {
    tests.run = dummy;
  };

  dummyNixManual =
    prev.runCommand "nix-manual-disabled"
      {
        outputs = [
          "out"
          "man"
        ];
      }
      ''
        mkdir -p "$out" "$man"
      '';

  libcameraBase = prev.libcamera.override {
    udev = prev.libudev-zero;
  };

  mkCanberra =
    pkg:
    (pkg.override {
      gst_all_1 = final.gst_all_1;
      withSystemd = false;
    }).overrideAttrs
      (old: {
        postConfigure = (old.postConfigure or "") + ''
          sed -i '/^finish_cmds=.*ldconfig -n .*libdir/c\finish_cmds=""' libtool
        '';
      });

  trimFftw =
    pkg:
    pkg.overrideAttrs (old: {
      nativeBuildInputs = builtins.filter (p: prev.lib.getName p != "gfortran-wrapper") (
        old.nativeBuildInputs or [ ]
      );

      configureFlags = (old.configureFlags or [ ]) ++ [
        "--disable-fortran"
      ];
    });

  pythonPackageOverrides = _: pyPrev: {
    pytest-xdist = pyPrev.pytest-xdist.overridePythonAttrs (_: {
      doCheck = false;
    });

    python-dbusmock = pyPrev.python-dbusmock.overridePythonAttrs (_: {
      doCheck = false;
    });
  };

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
{
  libpcap = prev.libpcap.override {
    withRdma = false;
  };

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

  spandsp = prev.spandsp.overrideAttrs (old: {
    checkPhase =
      builtins.replaceStrings
        [ "ademco_contactid_tests|dtmf_rx_tests" ]
        [ "ademco_contactid_tests|modem_echo_tests|dtmf_rx_tests" ]
        old.checkPhase;
  });

  gst_all_1 = gstAll1;

  llvmPackages_21 = llvm21;
  llvmPackages_22 = llvm22;

  # Default llvmPackages is LLVM 21 on your current nixpkgs.
  llvmPackages = llvm21;

  v4l-utils = prev.v4l-utils.override {
    withGUI = false;
    withBPF = false;
    udev = prev.libudev-zero;
  };

  nixVersions = prev.nixVersions // {
    latest = prev.nixVersions.latest.override {
      nix-util-tests = dummyTests;
      nix-store-tests = dummyTests;
      nix-expr-tests = dummyTests;
      nix-fetchers-tests = dummyTests;
      nix-flake-tests = dummyTests;
      nix-functional-tests = null;
      nix-manual = dummyNixManual;

      nix-store = prev.nixVersions.latest.libs.nix-store.override {
        withAWS = false;
      };
    };
  };

  onetbb = prev.onetbb.overrideAttrs (old: {
    disabledTests =
      (old.disabledTests or [ ])
      ++ prev.lib.optionals prev.stdenv.hostPlatform.isMusl [
        "test_scheduler_mix"
      ];
  });

  libei = prev.libei.override {
    systemdLibs = final.basu;
  };

  kmod = prev.kmod.override {
    withDevdoc = false;
  };

  basu = prev.basu.overrideAttrs (old: {
    nativeBuildInputs = builtins.filter (x: x != prev.getent) old.nativeBuildInputs;

    postPatch = (old.postPatch or [ ]) ++ [
      ''
        substituteInPlace meson.build \
        --replace-fail \
          "        getent_result = run_command('getent', 'passwd', '65534')" \
          "        getent_result = run_command('false')"
      ''
    ];
  });

  serd = prev.serd.overrideAttrs (old: {
    outputs = builtins.filter (
      output:
      !builtins.elem output [
        "doc"
        "man"
      ]
    ) (old.outputs or [ ]);

    postPatch = (old.postPatch or "") + ''
      substituteInPlace meson.build \
        --replace-fail \
          "subdir('doc')" \
          "# subdir('doc')"
    '';

    nativeBuildInputs = builtins.filter (
      p:
      !builtins.elem (prev.lib.getName p) [
        "doxygen"
        "mandoc"
        "sphinx"
        "sphinxygen"
      ]
    ) (old.nativeBuildInputs or [ ]);
  });

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

  elfutils = prev.elfutils.override {
    enableDebuginfod = false;
  };

  fontforge = prev.fontforge.override {
    withGTK = false;
    withPython = false;
    withExtras = false;
  };

  sqlite = prev.sqlite.overrideAttrs {
    doCheck = false;
    doInstallCheck = false;
  };

  wayland = prev.wayland.override {
    withDocumentation = false;
    withTests = false;
  };

  libdrm = prev.libdrm.override {
    withIntel = false;
    withValgrind = false;
  };

  mako =
    (prev.mako.override {
      systemdMinimal = final.basu;
    }).overrideAttrs
      {
        mesonFlags = [ "-Dsd-bus-provider=basu" ];
      };

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

  seatd = prev.seatd.override {
    systemdSupport = false;
  };

  libusb1 = prev.libusb1.override {
    udev = prev.libudev-zero;
  };

  libcamera = libcameraBase.overrideAttrs (old: {
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

  libinput = prev.libinput.override {
    udev = prev.libudev-zero; # mdevd.
    wacomSupport = false;
  };

  wlroots = prev.wlroots.override {
    libinput = final.libinput;
  };

  greetd = prev.greetd.overrideAttrs (old: {
    nativeBuildInputs = builtins.filter (p: p != prev.scdoc) (old.nativeBuildInputs or [ ]);
    postInstall = "";
  });

  linux-pam = prev.linux-pam.override {
    withLogind = false;
  };

  pam = final.linux-pam;

  procps = prev.procps.override {
    withSystemd = false;
  };

  at-spi2-core = prev.at-spi2-core.override {
    systemdSupport = false;
  };

  polkit =
    (prev.polkit.override {
      useSystemd = false;
      useConsoleKit = true;
    }).overrideAttrs
      (old: {
        buildInputs = builtins.filter (p: p != prev.elogind) (old.buildInputs or [ ]);
      });

  libcanberra = mkCanberra prev.libcanberra;
  libcanberra-gtk3 = mkCanberra prev.libcanberra-gtk3;

  xdg-desktop-portal-wlr =
    (prev.xdg-desktop-portal-wlr.override {
      systemdLibs = final.basu;
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

  bluez = prev.bluez.override {
    udev = prev.libudev-zero;
  };

  xdg-desktop-portal-termfilechooser =
    (prev.xdg-desktop-portal-termfilechooser.override {
      systemdLibs = final.basu;
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

  rtkit =
    (prev.rtkit.override {
      systemdLibs = final.basu;
    }).overrideAttrs
      (old: {
        mesonFlags = (old.mesonFlags or [ ]) ++ [
          (prev.lib.mesonEnable "libsystemd" false)
        ];
      });

  util-linux = prev.util-linux.override {
    systemdSupport = false;
  };

  dbus = prev.dbus.override {
    enableSystemd = false;
  };

  xwayland = prev.xwayland.overrideAttrs (old: {
    buildInputs = builtins.filter (p: p != prev.systemd) (old.buildInputs or [ ]);
  });

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

  firefox-unwrapped = prev.firefox-unwrapped.overrideAttrs (old: {
    configureFlags =
      builtins.filter (flag: !(prev.lib.hasPrefix "--with-onnx-runtime=" flag)) (
        old.configureFlags or [ ]
      )
      ++ [
        "--without-onnx-runtime"
      ];
  });

  scenefx = prev.scenefx.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      find include -name clipped_region.h -print -exec \
        sed -i 's/__always_inline/inline __attribute__((always_inline))/g' {} +
    '';
  });

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

        patches = (old.patches or [ ]) ++ [ ../../patches/pipewire-libudev_zero.patch ];

        buildInputs = builtins.filter (p: p != prev.modemmanager && p != prev.elogind) (
          old.buildInputs or [ ]
        );

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
            && !prev.lib.hasPrefix "-Dlogind=" flag
          ) (old.mesonFlags or [ ]))
          ++ [
            "-Ddocs=disabled"
            "-Dinstalled_tests=disabled"
            "-Dman=disabled"
            "-Dlogind=disabled"
            "-Dbluez5-backend-native-mm=disabled"
            "-Dlogind=disabled"
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

  ffmpeg = prev.ffmpeg.override {
    withSdl2 = false;
    buildFfplay = false;
  };

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

  xdg-desktop-portal-gtk = prev.xdg-desktop-portal-gtk.overrideAttrs (old: {
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

  libopenmpt = prev.libopenmpt.override {
    usePulseAudio = false;
  };

  fftw = trimFftw prev.fftw;
  fftwSinglePrec = trimFftw prev.fftwSinglePrec;

  python313 = prev.python313.override {
    packageOverrides = pythonPackageOverrides;
  };

  python314 = prev.python314.override {
    packageOverrides = pythonPackageOverrides;
  };

  writeShellScript =
    name: text:
    prev.writeScript name ''
      #!${final.bashNonInteractive}/bin/bash
      ${text}
    '';

  linux-firmware = prev.linux-firmware.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
            rm -rf \
              $out/lib/firmware/amdgpu \
              $out/lib/firmware/radeon \
              $out/lib/firmware/nvidia \
              $out/lib/firmware/i915 \
              $out/lib/firmware/intel \
              $out/lib/firmware/mediatek \
              $out/lib/firmware/ath10k \
              $out/lib/firmware/ath11k \
              $out/lib/firmware/ath12k \
              $out/lib/firmware/ath9k_htc \
              $out/lib/firmware/mrvl \
              $out/lib/firmware/rtlwifi \
              $out/lib/firmware/rtw88 \
              $out/lib/firmware/rtw89 \
              $out/lib/firmware/ti-connectivity \
              $out/lib/firmware/qcom \
        	$out/lib/firmware/mellanox \
              $out/lib/firmware/microchip \
      	$out/lib/firmware/cavium \
              $out/lib/firmware/netronome \
              $out/lib/firmware/qed \
              $out/lib/firmware/liquidio \
              $out/lib/firmware/inside-secure \
              $out/lib/firmware/ueagle-atm \
              $out/lib/firmware/av7110 \
              $out/lib/firmware/cirrus \
              $out/lib/firmware/sof

            rm -f $out/lib/firmware/iwlwifi-*

            # Removing firmware families can leave WHENCE-generated symlinks
            # pointing at deleted targets.
            find -L $out/lib/firmware -type l -delete
            find $out/lib/firmware -type d -empty -delete
    '';
  });

  nh-unwrapped = prev.nh-unwrapped.overrideAttrs (old: {
    doCheck = false;
    doInstallCheck = false;
    nativeCheckInputs = [ ];
  });
}
