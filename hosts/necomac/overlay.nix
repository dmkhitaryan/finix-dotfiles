final: prev: let
  wildStdenv = let
    p = prev.stdenv;
    ok = plat: plat.isLinux && plat.isElf;
  in
    if
      ok p.buildPlatform
      && ok p.hostPlatform
      && ok p.targetPlatform
      && (p.cc.bintools ? override)
    then prev.useWildLinker p
    else p;

  # Early bootstrap stages have no compiler.
  isClang =
    (prev.stdenv.cc or null)
    != null
    && (prev.stdenv.cc.isClang or false);

  # rustc for the host only. nixpkgs also builds std for wasm32/bpf targets,
  # which need LLVM backends the trimmed LLVM doesn't build; nothing here
  # uses them.
  rustcHostOnly = rprev: {
    rustc-unwrapped = rprev.rustc-unwrapped.overrideAttrs (old: {
      configureFlags =
        map (
          flag:
            if prev.lib.hasPrefix "--target=" flag
            then
              "--target="
              + prev.lib.concatStringsSep "," (
                builtins.filter (t:
                  !builtins.elem t [
                    "wasm32-unknown-unknown"
                    "wasm32v1-none"
                    "bpfel-unknown-none"
                    "bpfeb-unknown-none"
                  ])
                (prev.lib.splitString "," (prev.lib.removePrefix "--target=" flag))
              )
            else flag
        )
        (old.configureFlags or []);
    });
  };

  # Every versioned Rust set nixpkgs defines (rust_1_99, rust_1_100, ...).
  # Only attribute *names* of prev are read here, which is safe in an overlay.
  rustSetNames =
    builtins.filter (n: builtins.match "rust_[1-9]+_[0-9]+" n != null)
    (builtins.attrNames prev);

  patchRustSet = r:
    r
    // {
      packages =
        r.packages
        // {
          stable = r.packages.stable.overrideScope (_: rustcHostOnly);
        };
    };

  rustOverrides = builtins.listToAttrs (map (n: {
      name = n;
      value =
        if isClang
        then patchRustSet prev.${n}
        else prev.${n};
    })
    rustSetNames);

  php84ForLsp = prev.php84.buildEnv {
    systemdSupport = false;
    valgrindSupport = false;

    extensions = {enabled, ...}:
      map (
        ext:
          if (ext.extensionName or null) == "pcntl"
          then ext.overrideAttrs {doCheck = false;}
          else ext
      )
      (prev.lib.filter (ext: (ext.extensionName or null) != "gettext") enabled);
  };

  gstAll1 = prev.gst_all_1.overrideScope (
    _: gstPrev: {
      gstreamer =
        (gstPrev.gstreamer.override {
          withRust = false;
          enableDocumentation = false;
        }).overrideAttrs (old: {
          postFixup =
            (old.postFixup or "")
            + ''
              rm -f $out/libexec/gstreamer-1.0/gst-plugins-doc-cache-generator
            '';
        });

      gst-plugins-base = gstPrev.gst-plugins-base.override {
        enableDocumentation = false;
        enableX11 = false;
      };
    }
  );

  llvmTargets =
    if prev.stdenv.hostPlatform.isx86_64
    then "X86;AMDGPU"
    else if prev.stdenv.hostPlatform.isAarch64
    then "AArch64"
    else throw "Add the LLVM backend list for this host architecture";

  trimLlvm = llvmPkgs:
    llvmPkgs.overrideScope (
      self: llvmPrev: let
        libllvm =
          (llvmPrev.libllvm.override {
            #stdenv = wildStdenv;
            enableManpages = false;
            enablePFM = false;
            enablePolly = false;
            enableTerminfo = false;

            devExtraCmakeFlags = [
              "-DLLVM_TARGETS_TO_BUILD=${llvmTargets}"
              "-DLLVM_BUILD_TESTS=OFF"
              "-DLLVM_INCLUDE_TESTS=OFF"
              "-DLLVM_INCLUDE_EXAMPLES=OFF"
              "-DLLVM_INCLUDE_BENCHMARKS=OFF"
            ];
          }).overrideAttrs
          (old: {
            doCheck = false;
          });

        libclang =
          (llvmPrev.libclang.override {
            stdenv = wildStdenv;
            libllvm = libllvm;
            enableClangToolsExtra = false;
            enableManpages = false;

            devExtraCmakeFlags = [
              "-DLLVM_TARGETS_TO_BUILD=${llvmTargets}"
              "-DCLANG_ENABLE_OBJC_REWRITER=OFF"
              "-DCLANG_INCLUDE_TESTS=OFF"
            ];
          }).overrideAttrs
          (old: {
            doCheck = false;

            # Not using extra tools in Clang. Create empty stub.
            postInstall =
              ''
                touch $out/bin/run-clang-tidy
              ''
              + (old.postInstall or "");
          });
      in {
        inherit libllvm libclang;
        llvm = libllvm;
        clang-unwrapped = libclang;
        # nixpkgs picks libc++ clang when stdenv is already clang.
        clang = self.libstdcxxClang;
        # OMPD's GDB plugin links libpython; nothing at runtime needs it.
        openmp = llvmPrev.openmp.override {ompdGdbSupport = false;};
      }
    );

  trimLlvmOverridable = llvmPkgs:
    (trimLlvm llvmPkgs)
    // {
      override = args: trimLlvmOverridable (llvmPkgs.override args);
    };

  llvm21 = trimLlvmOverridable prev.llvmPackages_21;
  llvm22 = trimLlvmOverridable prev.llvmPackages_22;

  dummy = prev.runCommand "dummy-nix-tests-run" {} "mkdir -p $out";
  dummyTests =
    dummy
    // {
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

  mkCanberra = pkg:
    (pkg.override {
      gst_all_1 = final.gst_all_1;
      withSystemd = false;
      gtkSupport = false;
    }).overrideAttrs
    (old: {
      postConfigure =
        (old.postConfigure or "")
        + ''
          sed -i '/^finish_cmds=.*ldconfig -n .*libdir/c\finish_cmds=""' libtool
        '';
    });

  trimFftw = pkg:
    pkg.overrideAttrs (old: {
      nativeBuildInputs = builtins.filter (p: prev.lib.getName p != "gfortran-wrapper") (
        old.nativeBuildInputs or []
      );

      # Under clang, OpenMP is LLVM's separate openmp package, which drags python.
      buildInputs = builtins.filter (p: prev.lib.getName p != "openmp") (old.buildInputs or []);
      propagatedBuildInputs = builtins.filter (p: prev.lib.getName p != "openmp") (
        old.propagatedBuildInputs or []
      );

      configureFlags =
        builtins.filter (f: f != "--enable-openmp") (old.configureFlags or [])
        ++ [
          "--disable-fortran"
        ];
    });

  pythonPackageOverrides = _: pyPrev: let
    noTests = {
      doCheck = false;
      doInstallCheck = false;
      checkInputs = [];
      nativeCheckInputs = [];
    };

    wrapBuilder = builder: args:
      if builtins.isFunction args
      then builder (finalAttrs: (args finalAttrs) // noTests)
      else builder (args // noTests);
  in {
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

  nsprAarchFix = prev.nspr.overrideAttrs (old: {
    postPatch =
      (old.postPatch or "")
      + ''
        substituteInPlace nspr/pr/include/md/_linux.h \
          --replace-fail \
            '#if (defined(__GLIBC__) && __GLIBC__ >= 2) || defined(ANDROID)' \
            '#if 1'
      '';
  });

  nssFixed = prev.nss_latest.override {nspr = nsprAarchFix;};
in
  # Clang-only fixes. Names are always defined (so stdenv isn't forced while
  # nixpkgs builds its stages); outside the clang set they're the unchanged
  # originals, so the gcc toolchain set stays identical.
  {
    doctest =
      if isClang
      then
        prev.doctest.overrideAttrs (old: {
          doCheck = false;
          cmakeFlags = (old.cmakeFlags or []) ++ ["-DDOCTEST_WITH_TESTS=OFF"];
        })
      else prev.doctest;

    diffutils =
      if isClang
      then prev.diffutils.overrideAttrs {doCheck = false;}
      else prev.diffutils;

    # busybox's Kbuild hardcodes HOSTCC=gcc.
    busybox =
      if isClang
      then
        prev.busybox.overrideAttrs (old: {
          postPatch =
            (old.postPatch or "")
            + "\n"
            + ''
              mkdir -p "$TMPDIR/hostcc-shim"
              ln -s "$(command -v cc)" "$TMPDIR/hostcc-shim/gcc"
              export PATH="$TMPDIR/hostcc-shim:$PATH"
            '';
        })
      else prev.busybox;

    # Old Tcl channel struct; clang makes this warning a hard error.
    expect =
      if isClang
      then
        prev.expect.overrideAttrs (old: {
          env =
            (old.env or {})
            // {
              NIX_CFLAGS_COMPILE =
                toString (old.env.NIX_CFLAGS_COMPILE or "")
                + " -Wno-error=incompatible-pointer-types";
            };
        })
      else prev.expect;

    # saslutil.c uses time()/clock() without <time.h>; musl doesn't pull it in.
    cyrus_sasl =
      if isClang
      then
        prev.cyrus_sasl.overrideAttrs (old: {
          env =
            (old.env or {})
            // {
              NIX_CFLAGS_COMPILE =
                toString (old.env.NIX_CFLAGS_COMPILE or "")
                + " -include time.h";
            };
        })
      else prev.cyrus_sasl;

    # PATH_MAX without <limits.h>; musl doesn't pull it in.
    bubblewrap =
      if isClang
      then
        prev.bubblewrap.overrideAttrs (old: {
          env =
            (old.env or {})
            // {
              NIX_CFLAGS_COMPILE =
                toString (old.env.NIX_CFLAGS_COMPILE or "")
                + " -include limits.h";
            };
        })
      else prev.bubblewrap;

    # musl's ioctl(int, int, ...) vs libv4l2's v4l2_ioctl(int, unsigned long, ...).
    ffmpeg =
      if isClang
      then
        prev.ffmpeg.overrideAttrs (old: {
          configureFlags =
            (old.configureFlags or [])
            ++ ["--extra-cflags=-Wno-error=incompatible-function-pointer-types"];
        })
      else prev.ffmpeg;

    haskellPackages =
      if isClang
      then
        prev.haskellPackages.override (old: {
          overrides = prev.lib.composeExtensions (old.overrides or (_: _: {})) (_: hprev: {
            # Expected-output tests trip over cc-wrapper's --target warning.
            doctest = prev.haskell.lib.dontCheck hprev.doctest;
          });
        })
      else prev.haskellPackages;

    # LLVM bintools has no standalone `as`; let clang assemble.
    libaom =
      if isClang
      then
        prev.libaom.overrideAttrs (old: {
          cmakeFlags = (old.cmakeFlags or []) ++ ["-DCMAKE_ASM_COMPILER=cc"];
        })
      else prev.libaom;

    gnutls =
      if isClang
      then prev.gnutls.overrideAttrs {doCheck = false;}
      else prev.gnutls;
  }
  // rustOverrides
  // {
    libpcap = prev.libpcap.override {
      withRdma = false;
    };

    nnn = prev.nnn.override {
      gnused = final.busybox;
    };

    iwd = prev.iwd.override {
      coreutils = final.busybox;
    };

    alsa-ucm-conf = prev.alsa-ucm-conf.override {
      coreutils = final.busybox;
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

    imv = prev.imv.override {
      withWindowSystem = "wayland";
    };

    cairo = prev.cairo.override {
      x11Support = false;
    };

    pango = prev.pango.override {
      x11Support = false;
    };

    orc = prev.orc.override {
      buildDevDoc = false;
    };

    jemalloc = prev.jemalloc.overrideAttrs {
      doCheck = false;
    };

    openapv = prev.openapv.overrideAttrs {
      doCheck = false;
    };

    glslang = prev.glslang.overrideAttrs {
      doCheck = false;
    };

    wild = (import prev.path {localSystem = "aarch64-linux";}).wild;

    # m1n1 builds its own bare-metal rustc (aarch64-none-elf override in its
    # package.nix). Take it from stock nixpkgs instead.
    m1n1 = (import prev.path {localSystem = "aarch64-linux";}).m1n1;

    netbsd = prev.netbsd.overrideScope (_: nprev: {
      fts =
        if isClang
        then
          nprev.fts.overrideAttrs (old: {
            postPatch =
              (old.postPatch or "")
              + "\n"
              + ''
                sed -i '/#include <ssp\/ssp.h>/d' lib/libc/include/namespace.h
              '';
          })
        else nprev.fts;
    });

    libglvnd = prev.libglvnd.overrideAttrs (old: {
      buildInputs = builtins.filter (
        p:
          !(builtins.elem (prev.lib.getName p) [
            "libx11"
            "libxext"
            "xorgproto"
          ])
      ) (old.buildInputs or []);

      configureFlags =
        (old.configureFlags or [])
        ++ [
          "--disable-x11"
          "--disable-glx"
        ];

      # Upstream postFixup patches libGLX.so, but it's disabled now.
      postFixup = "";
    });

    alejandra = prev.alejandra.overrideAttrs (old: {
      env =
        (old.env or {})
        // {
          #CARGO_PROFILE_RELEASE_OPT_LEVEL = "s";
          CARGO_PROFILE_RELEASE_LTO = "fat";
        };
    });

    libxkbcommon = prev.libxkbcommon.overrideAttrs (old: {
      outputs = builtins.filter (
        output:
          !builtins.elem output [
            "doc"
          ]
      ) (old.outputs or []);

      nativeBuildInputs = builtins.filter (
        p:
          !(builtins.elem (prev.lib.getName p) [
            "xvfb"
            "doxygen"
          ])
      ) (old.nativeBuildInputs or []);

      buildInputs = builtins.filter (
        p: !(builtins.elem (prev.lib.getName p) ["libxcb"])
      ) (old.buildInputs or []);

      mesonFlags =
        builtins.filter (
          p:
            !(prev.lib.hasPrefix "-Denable-docs=" p)
            && !(prev.lib.hasPrefix "-Denable-x11=" p)
            && !(prev.lib.hasPrefix "-Dx-locale-root=" p)
        ) (old.mesonFlags or [])
        ++ [
          "-Denable-docs=false"
          "-Denable-x11=false"
        ];
    });

    nil =
      (prev.nil.override {
        nix = final.nixVersions.latest;
      }).overrideAttrs
      (old: {
        env =
          old.env
          // {
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
        buildVST3 = false;
        buildVST2 = false;
        buildCLAP = false;
        buildLV2 = true;
        buildLADSPA = false;
        buildJACK = false;
        buildGStreamer = false;
      }).overrideAttrs
      (old: {
        buildInputs = builtins.filter (
          p: let
            name = prev.lib.getName p;
          in
            !(builtins.elem name [
              "jack2"
              "ladspa-header"
              "gstreamer"
              "gst-plugins-base"
              "libxrandr"
              "libglvnd"
              "glu"
            ])
        ) (old.buildInputs or []);

        configurePhase = ''
          runHook preConfigure

          make $makeFlags config \
            SUB_FEATURES="ui standalone launcher xdg jack pipewire gst clap ladspa vst2"

          runHook postConfigure
        '';

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
        ["ademco_contactid_tests|dtmf_rx_tests"]
        ["ademco_contactid_tests|modem_echo_tests|dtmf_rx_tests"]
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

    nixVersions =
      prev.nixVersions
      // {
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
              postPatch =
                (oldAttrs.postPatch or "")
                + ''
                  substituteInPlace unix/file-descriptor.cc \
                    --replace-fail \
                      '#include <fcntl.h>' \
                      $'#include <fcntl.h>\n#include <sys/syscall.h>'
                '';

              env =
                (oldAttrs.env or {})
                // {
                  NIX_CFLAGS_COMPILE =
                    toString (oldAttrs.env.NIX_CFLAGS_COMPILE or "")
                    + " -Wno-error=sign-compare";
                };
            });
          }
        );
      };

    onetbb = prev.onetbb.overrideAttrs (old: {
      disabledTests =
        (old.disabledTests or [])
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

      postPatch =
        (old.postPatch or [])
        ++ [
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
      ) (old.outputs or []);

      postPatch =
        (old.postPatch or "")
        + ''
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
      ) (old.nativeBuildInputs or []);
    });

    libtiff = prev.libtiff.overrideAttrs (old: {
      nativeBuildInputs = builtins.filter (p: p != prev.sphinx) (old.nativeBuildInputs or []);

      outputs = builtins.filter (
        output:
          !builtins.elem output [
            "doc"
            "man"
          ]
      ) (old.outputs or []);
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
      env =
        (old.env or {})
        // {
          CARGO_PROFILE_RELEASE_OPT_LEVEL = "z";
          CARGO_PROFILE_RELEASE_LTO = "thin";
          CARGO_PROFILE_RELEASE_CODEGEN_UNITS = "1";
        };
    });

    oo7-portal = prev.oo7-portal.overrideAttrs (old: {
      env =
        (old.env or {})
        // {
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
        mesonFlags = ["-Dsd-bus-provider=basu"];
      };

    libgudev =
      (prev.libgudev.override {
        udev = prev.libudev-zero;
      }).overrideAttrs
      (old: {
        doCheck = false;
        mesonFlags =
          builtins.filter (p: !prev.lib.hasPrefix "-Dtests=" p) (old.mesonFlags or [])
          ++ [
            "-Dtests=disabled"
          ];
        # clang doesn't accept bare -export-dynamic; the linker spelling works for both.
        postPatch =
          (old.postPatch or "")
          + "\n" # Just in case so we don't remove it with formatting.
          + ''
            find . -name meson.build -exec \
              sed -i "s/'-export-dynamic'/'-Wl,--export-dynamic'/g" {} +
          '';
      });

    libusb1 = prev.libusb1.override {
      udev = prev.libudev-zero;
    };

    libva = prev.libva.override {
      minimal = true;
    };

    seatd =
      (prev.seatd.override {
        systemdSupport = false;
      }).overrideAttrs (old: {
        # clang warns (-Wsign-compare) on musl; seatd uses -Werror.
        mesonFlags = (old.mesonFlags or []) ++ ["-Dwerror=false"];
      });

    libcamera = libcameraBase.overrideAttrs (old: {
      nativeBuildInputs = builtins.filter (
        p: let
          name = prev.lib.getName p;
        in
          name != "sphinx" && name != "graphviz" && name != "doxygen"
      ) (old.nativeBuildInputs or []);

      mesonFlags =
        (old.mesonFlags or [])
        ++ [
          "-Dpycamera=disabled"
        ];

      buildInputs = builtins.filter (p: prev.lib.getName p != "pybind11") (old.buildInputs or []);
    });

    libinput = prev.libinput.override {
      udev = prev.libudev-zero; # mdevd.
      wacomSupport = false;
    };

    wlroots = prev.wlroots.override {
      libinput = final.libinput;
    };

    greetd = prev.greetd.overrideAttrs (old: {
      nativeBuildInputs = builtins.filter (p: p != prev.scdoc) (old.nativeBuildInputs or []);
      postInstall = "";
    });

    linux-pam = prev.linux-pam.override {
      withLogind = false;
    };

    pam = final.linux-pam;

    procps = prev.procps.override {
      withSystemd = false;
    };

    at-spi2-core =
      (prev.at-spi2-core.override {
        systemdSupport = false;
      }).overrideAttrs (old: {
        buildInputs = builtins.filter (
          p:
            !(builtins.elem (prev.lib.getName p) [
              "libx11"
              "libxtst"
              "libxi"
              "libxext"
            ])
        ) (old.buildInputs or []);

        mesonFlags = (old.mesonFlags or []) ++ ["-Dx11=disabled"];
      });

    libepoxy = prev.libepoxy.overrideAttrs (old: {
      buildInputs = (old.buildInputs or []) ++ [final.libGL];
      mesonFlags =
        builtins.filter (p: !(prev.lib.hasPrefix "-Degl=" p)) (old.mesonFlags or [])
        ++ [
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
      coreutils = final.busybox;
      curl = prev.curlMinimal;
      gnugrep = final.busybox;
      gnused = final.busybox;
      gawk = final.busybox;
    };

    gitMinimal =
      (final.git.override {
        withManual = false;
        osxkeychainSupport = false;
        pythonSupport = false;
        perlSupport = false;
        rustSupport = false;
        withpcre2 = false;
        curl =
          if prev.stdenv.hostPlatform.isFreeBSD
          then prev.curlMinimal
          else prev.curl;
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
        buildInputs = builtins.filter (p: p != prev.elogind) (old.buildInputs or []);
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
          ) (old.mesonFlags or [])
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
          ) (old.mesonFlags or [])
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
        mesonFlags =
          (old.mesonFlags or [])
          ++ [
            (prev.lib.mesonEnable "libsystemd" false)
          ];
      });

    util-linux = prev.util-linux.override {
      systemdSupport = false;
    };

    dbus =
      (prev.dbus.override {
        enableSystemd = false;
        x11Support = false;
      }).overrideAttrs (old: {
        # AppArmor is off in the kernel; libapparmor doesn't build with clang.
        buildInputs = builtins.filter (p: prev.lib.getName p != "libapparmor") (old.buildInputs or []);
        mesonFlags =
          builtins.filter (f: !prev.lib.hasPrefix "-Dapparmor=" f) (old.mesonFlags or [])
          ++ ["-Dapparmor=disabled"];
      });

    xwayland = prev.xwayland.overrideAttrs (old: {
      buildInputs = builtins.filter (p: p != prev.systemd) (old.buildInputs or []);
    });

    wireplumber =
      (prev.wireplumber.override {
        enableDocs = false;
        enableGI = false;
        pipewire = final.pipewire;
      }).overrideAttrs
      (old: {
        postPatch =
          (old.postPatch or "")
          + ''
            substituteInPlace po/meson.build \
              --replace-fail \
                "python_po = pymod.find_installation('python3')" \
                "python_po = pymod.find_installation('python3', required: false)"
          '';

        buildInputs = builtins.filter (p: p != prev.systemdLibs) (old.buildInputs or []);

        mesonFlags =
          (builtins.filter (
            flag:
              !prev.lib.hasPrefix "-Dsystemd=" flag
              && !prev.lib.hasPrefix "-Dsystemd-system-service=" flag
              && !prev.lib.hasPrefix "-Dsystemd-system-unit-dir=" flag
          ) (old.mesonFlags or []))
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

        buildInputs = builtins.filter (dep: prev.lib.getName dep != "flatpak") (old.buildInputs or []);

        mesonFlags =
          (old.mesonFlags or [])
          ++ [
            "-Dflatpak-interfaces=disabled"
          ];
      });

    firefox-unwrapped =
      (prev.firefox-unwrapped.override {
        pkgsCross =
          prev.pkgsCross
          // {
            # glibc, no overlays.
            wasm32-wasip1 = (import prev.path {localSystem = "aarch64-linux";}).pkgsCross.wasm32-wasip1;
          };
        enablePGO = false;
        enableDebugSymbols = false;
        enableLTO = false;
        nspr = nsprAarchFix;
        nss_latest = nssFixed;
      }).overrideAttrs
      (old: {
        patches =
          (old.patches or [])
          ++ [
            (prev.fetchpatch {
              name = "audio-thread-priority-musl-pthread_t.patch";
              url = "https://github.com/padenot/audio_thread_priority/commit/9c37971cf57f9b6bab44a247ebc7f610cf8186bd.patch";
              stripLen = 1;
              extraPrefix = "third_party/rust/audio_thread_priority/";
              excludes = [".github/*"];
              hash = "sha256-ab9o5n72F78iM1io+OelLnajSMVpZ1bb65Sj2OAJmsE=";
            })
          ];

        configureFlags =
          builtins.filter (
            p:
              !(prev.lib.hasPrefix "--with-onnx-runtime=" p)
              && !(prev.lib.hasPrefix "--enable-default-toolkit=" p)
          ) (old.configureFlags or [])
          ++ [
            "--without-onnx-runtime"
            #    "--without-wasm-sandboxed-libraries"
            "--enable-default-toolkit=cairo-gtk3-wayland-only"
          ];

        postPatch =
          (old.postPatch or "")
          + "\n"
          + ''
            sed -i '1i #include <cstdint>' third_party/parakeet.cpp/src/backend.hpp
            sed -i 's/\("files":{\)[^}]*/\1/' \
              third_party/rust/audio_thread_priority/.cargo-checksum.json
              sed -i '/#include <linux\/prctl.h>/d' \
                third_party/libwebrtc/rtc_base/platform_thread_types.cc
          '';
      });

    scenefx = prev.scenefx.overrideAttrs (old: {
      postPatch =
        (old.postPatch or "")
        + ''
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

        patches = (old.patches or []) ++ [../../patches/pipewire-libudev_zero.patch];

        buildInputs = builtins.filter (
          p:
            !(builtins.elem (prev.lib.getName p) [
              "modemmanager"
              "elogind"
              "libcamera"
            ])
        ) (old.buildInputs or []);

        nativeBuildInputs = builtins.filter (
          p:
            if prev.lib.isDerivation p
            then
              !(builtins.elem (prev.lib.getName p) [
                "docutils"
                "doxygen"
                "graphviz"
              ])
            else true
        ) (old.nativeBuildInputs or []);

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
          ) (old.mesonFlags or []))
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
        ) (old.outputs or []);
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
        withVaapi = true;
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
      (old: {
        doCheck = false;
        doInstallCheck = false;

        configureFlags =
          (old.configureFlags or [])
          ++ ["--extra-cflags=-Wno-error=incompatible-function-pointer-types"];
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
      mesonFlags =
        (old.mesonFlags or [])
        ++ [
          "-Dwallpaper=disabled"
          "-Dlockdown=disabled"
        ];

      buildInputs =
        builtins.filter (p: p != prev.gnome-desktop && prev.lib.getName p != "gnome-settings-daemon") (
          old.buildInputs or []
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

    writeShellScript = name: text:
      prev.writeScript name ''
        #!${final.bashNonInteractive}/bin/bash
        ${text}
      '';

    linux-firmware = prev.linux-firmware.overrideAttrs (old: {
      postInstall =
        (old.postInstall or "")
        + ''
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
                 $out/lib/firmware/sof \
                 $out/lib/firmware/dell \
                 $out/lib/firmware/lenovo \
                 $out/lib/firmware/amdnpu \
                 $out/lib/firmware/ql2900 \
                 $out/lib/firmware/xe \
                 $out/lib/firmware/ti \
                 $out/lib/firmware/rtl_bt \
                 $out/lib/firmware/dsp56k

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
      nativeCheckInputs = [];
    });

    handlr-regex = prev.handlr-regex.overrideAttrs (old: {
      doCheck = false;
    });
  }
