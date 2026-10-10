final: prev:
let
  wildStdenv =
    let
      p = prev.stdenv;
      ok = plat: plat.isLinux && plat.isElf;
    in
    if ok p.buildPlatform && ok p.hostPlatform && ok p.targetPlatform then prev.useWildLinker p else p;

  php84ForLsp = prev.php84.buildEnv {
    systemdSupport = false;
    valgrindSupport = false;

    extensions =
      { enabled, ... }:
      prev.lib.filter (ext: (ext.extensionName or null) != "gettext") enabled;
  };

  orc = prev.orc.override {
    buildDevDoc = false;
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
      orc = final.orc;
    };
  };

  llvmTargets =
    if final.stdenv.hostPlatform.isx86_64 then
      "X86;AMDGPU"
    else if final.stdenv.hostPlatform.isAarch64 then
      "AArch64"
    else
      throw "Add the LLVM backend list for this host architecture";

  trimLlvm =
    llvmPkgs:
    llvmPkgs.overrideScope (
      _: llvmPrev: {
        llvm =
          (llvmPrev.llvm.override {
            stdenv = wildStdenv;
            enableManpages = false;
            enablePFM = false;
            enablePolly = false;
            enableTerminfo = false;

            devExtraCmakeFlags = [
              "-DLLVM_TARGETS_TO_BUILD=${llvmTargets}"
              #              "-DLLVM_PARALLEL_COMPILE_JOBS=10"
              #              "-DLLVM_PARALLEL_LINK_JOBS=2"
              "-DLLVM_BUILD_TESTS=OFF"
              "-DLLVM_INCLUDE_TESTS=OFF"
              "-DLLVM_INCLUDE_EXAMPLES=OFF"
              "-DLLVM_INCLUDE_BENCHMARKS=OFF"
            ];
          }).overrideAttrs
            (_: {
              doCheck = false;
            });

        clang-unwrapped =
          (llvmPrev.clang-unwrapped.override {
            stdenv = wildStdenv;
            enableClangToolsExtra = false;
            enableManpages = false;

            devExtraCmakeFlags = [
              "-DLLVM_TARGETS_TO_BUILD=${llvmTargets}"
              #              "-DLLVM_PARALLEL_COMPILE_JOBS=10"
              #              "-DLLVM_PARALLEL_LINK_JOBS=2"
              "-DCLANG_ENABLE_OBJC_REWRITER=OFF"
              "-DCLANG_INCLUDE_TESTS=OFF"
            ];
          }).overrideAttrs
            (_: {
              doCheck = false;
            });
      }
    );

  trimLlvmOverridable =
    llvmPkgs:
    (trimLlvm llvmPkgs)
    // {
      override = args: trimLlvmOverridable (llvmPkgs.override args);
    };

  llvm21 = trimLlvmOverridable prev.llvmPackages_21;
  llvm22 = trimLlvmOverridable prev.llvmPackages_22;

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
      gtkSupport = false;
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

  pythonPackageOverrides =
    _: pyPrev:
    let
      noTests = {
        doCheck = false;
        doInstallCheck = false;
        checkInputs = [ ];
        nativeCheckInputs = [ ];
      };

      wrapBuilder =
        builder: args:
        if builtins.isFunction args then
          builder (finalAttrs: (args finalAttrs) // noTests)
        else
          builder (args // noTests);
    in
    {
      buildPythonPackage = wrapBuilder pyPrev.buildPythonPackage;
      buildPythonApplication = wrapBuilder pyPrev.buildPythonApplication;
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

  nnn = prev.nnn.override {
    gnused = prev.busybox;
  };

  iwd = prev.iwd.override {
    coreutils = prev.busybox;
  };

  alsa-ucm-conf = prev.alsa-ucm-conf.override {
    coreutils = prev.busybox;
  };

  alsa-ucm-conf-asahi = prev.alsa-ucm-conf-asahi.override {
    alsa-ucm-conf = final.alsa-ucm-conf;
  };

  alsa-lib = prev.alsa-lib.override {
    alsa-ucm-conf = final.alsa-ucm-conf;
  };

  libjpeg_turbo = prev.libjpeg_turbo.override {
    enableJpeg8 = true; # Potentially breaking. YOLO.
  };

  alejandra = prev.alejandra.overrideAttrs (old: {
    env = (old.env or { }) // {
      #CARGO_PROFILE_RELEASE_OPT_LEVEL = "s";
      CARGO_PROFILE_RELEASE_LTO = "fat";
    };
  });

  nil =
    (prev.nil.override {
      nix = final.nixVersions.latest;
    }).overrideAttrs
      (old: {
        env = old.env // {
          #CARGO_PROFILE_RELEASE_OPT_LEVEL = "s";
          CARGO_PROFILE_RELEASE_LTO = "fat";
          CFG_DEFAULT_FORMATTER = prev.lib.getExe final.alejandra;
        };
        doCheck = false;
        doInstallCheck = false;
      });

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

  # Set default llvmPackages to LLVM 22.
  llvmPackages = llvm22;

  v4l-utils = prev.v4l-utils.override {
    withGUI = false;
    withBPF = false;
    udev = prev.libudev-zero;
  };

  nixVersions = prev.nixVersions // {
    latest = prev.nixVersions.latest.overrideScope (
      final: old: {
        nix-util-tests = dummyTests;
        nix-store-tests = dummyTests;
        nix-expr-tests = dummyTests;
        nix-fetchers-tests = dummyTests;
        nix-flake-tests = dummyTests;
        nix-functional-tests = null;
        nix-manual = dummyNixManual;

        nix-store = old.nix-store.override {
          withAWS = false;
        };

        nix-util = old.nix-util.overrideAttrs (oldAttrs: {
          postPatch = (oldAttrs.postPatch or "") + ''
            substituteInPlace unix/file-descriptor.cc \
              --replace-fail \
                '#include <fcntl.h>' \
                $'#include <fcntl.h>\n#include <sys/syscall.h>'
          '';
        });
      }
    );
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

  oo7-server = prev.oo7-server.overrideAttrs (old: {
    env = (old.env or { }) // {
      CARGO_PROFILE_RELEASE_OPT_LEVEL = "z";
      CARGO_PROFILE_RELEASE_LTO = "thin";
      CARGO_PROFILE_RELEASE_CODEGEN_UNITS = "1";
    };
  });

  oo7-portal = prev.oo7-portal.overrideAttrs (old: {
    env = (old.env or { }) // {
      CARGO_PROFILE_RELEASE_OPT_LEVEL = "z";
      CARGO_PROFILE_RELEASE_LTO = "thin";
      CARGO_PROFILE_RELEASE_CODEGEN_UNITS = "1";
    };
  });

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

  libepoxy = prev.libepoxy.overrideAttrs (old: {
    buildInputs = (old.buildInputs or [ ]) ++ [ prev.libGL ];
    mesonFlags = builtins.filter (p: !(prev.lib.hasPrefix "-Degl=" p)) (old.mesonFlags or [ ]) ++ [
      "-Degl=yes"
    ];
  });

  gtk3 = prev.gtk3.override {
    x11Support = false;
    xineramaSupport = false;
    libepoxy = final.libepoxy;
    gettext = null;
  };

  git = prev.git.override {
    coreutils = prev.busybox;
    curl = prev.curlMinimal;
    gnugrep = prev.busybox;
    gnused = prev.busybox;
    gawk = prev.busybox;
  };

  gitMinimal =
    (final.git.override {
      withManual = false;
      osxkeychainSupport = false;
      pythonSupport = false;
      perlSupport = false;
      rustSupport = false;
      withpcre2 = false;
      curl = if prev.stdenv.hostPlatform.isFreeBSD then prev.curlMinimal else prev.curl;
    }).overrideAttrs
      (old: {
        doInstallCheck = false;

        postPatch =
          (old.postPatch or "")
          + prev.lib.optionalString prev.stdenv.hostPlatform.isMusl ''
            substituteInPlace git-sh-i18n.sh \
              --replace-fail '${prev.gettext}/bin/gettext.sh' 'gettext.sh' \
              --replace-fail 'export PATH=${prev.gettext}/bin:$PATH' ':'
          '';
      });

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

  firefox-unwrapped =
    (prev.firefox-unwrapped.override {
      pkgsCross = prev.pkgsCross // {
        # glibc, no overlays.
        wasm32-wasip1 = (import prev.path { localSystem = "aarch64-linux"; }).pkgsCross.wasm32-wasip1;
      };
      enablePGO = false;
      enableDebugSymbols = false;
      enableLTO = false;
    }).overrideAttrs
      (old: {
        patches = (old.patches or [ ]) ++ [
          (prev.fetchpatch {
            name = "audio-thread-priority-musl-pthread_t.patch";
            url = "https://github.com/padenot/audio_thread_priority/commit/9c37971cf57f9b6bab44a247ebc7f610cf8186bd.patch";
            stripLen = 1;
            extraPrefix = "third_party/rust/audio_thread_priority/";
            excludes = [ ".github/*" ];
            hash = "sha256-ab9o5n72F78iM1io+OelLnajSMVpZ1bb65Sj2OAJmsE=";
          })
        ];

        configureFlags =
          builtins.filter (
            p:
            !(prev.lib.hasPrefix "--with-onnx-runtime=" p)
            #   && !(prev.lib.hasPrefix "--with-wasi-sysroot=" p)
            && !(prev.lib.hasPrefix "--enable-default-toolkit=" p)
          ) (old.configureFlags or [ ])
          ++ [
            "--without-onnx-runtime"
            #    "--without-wasm-sandboxed-libraries"
            "--enable-default-toolkit=cairo-gtk3-wayland-only"
          ];

        postPatch = (old.postPatch or "") + ''
          sed -i '1i #include <cstdint>' third_party/parakeet.cpp/src/backend.hpp
          sed -i 's/\("files":{\)[^}]*/\1/' \
            third_party/rust/audio_thread_priority/.cargo-checksum.json
            sed -i '/#include <linux\/prctl.h>/d' \
              third_party/libwebrtc/rtc_base/platform_thread_types.cc
        '';
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
      x11Support = false;

      udev = prev.libudev-zero;
      libdrm = final.libdrm;
    }).overrideAttrs
      (old: {
        doCheck = false;

        patches = (old.patches or [ ]) ++ [ ../../patches/pipewire-libudev_zero.patch ];

        buildInputs = builtins.filter (
          p: p != prev.modemmanager && p != prev.elogind && p != prev.libcamera
        ) (old.buildInputs or [ ]);

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
            && !prev.lib.hasPrefix "-Dlibcamera=" flag
          ) (old.mesonFlags or [ ]))
          ++ [
            "-Ddocs=disabled"
            "-Dinstalled_tests=disabled"
            "-Dman=disabled"
            "-Dlogind=disabled"
            "-Dbluez5-backend-native-mm=disabled"
            "-Dlogind=disabled"
            "-Dlibcamera=disabled"
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

  ffmpeg-headless =
    (prev.ffmpeg.override {
      withSdl2 = false;
      buildFfplay = false;

      # Disable NVIDIA, AMD or Intel video APIs.
      withAmf = false;
      withCuda = false;
      withCudaLLVM = false;
      withCudaNVCC = false;
      withCuvid = false;
      withNvcodec = false;
      withNvdec = false;
      withNvenc = false;
      withNpp = false;
      withMfx = false;
      withVpl = false;
      withVaapi = false;
      withVdpau = false;

      # Disable GUI/display integration.
      withXlib = false;
      withXcb = false;
      withXcbShape = false;
      withXcbShm = false;
      withXcbxfixes = false;
      withOpengl = false;
      withOpenal = false;

      # Disable docs/manpages.
      withDocumentation = false;
      withHtmlDoc = false;
      withManPages = false;
      withPodDoc = false;
      withTxtDoc = false;
      withDoc = false;
    }).overrideAttrs
      (_: {
        doCheck = false;
        doInstallCheck = false;
      });

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

    #  stripIdlelib = true;
    #  stripTests = true;
  };

  python314 = prev.python314.override {
    packageOverrides = pythonPackageOverrides;

    #  stripIdlelib = true;
    #  stripTests = true;
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

  handlr-regex = prev.handlr-regex.overrideAttrs (old: {
    doCheck = false;
  });
}
