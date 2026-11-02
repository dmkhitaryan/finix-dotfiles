final: prev: let
  inherit (prev) lib;
  inherit (import ./lib.nix lib) dropNamed replaceFlags addCflags testsOff;

  # Stock pkgs (glibc, no overlays) to use since it's build-time only.
  stock = import prev.path {localSystem = "aarch64-linux";};

  dummy = prev.runCommand "dummy-nix-tests-run" {} "mkdir -p $out";
  dummyTests = dummy // {tests.run = dummy;};

  dummyNixManual = prev.runCommand "nix-manual-disabled" {outputs = ["out" "man"];} ''
    mkdir -p "$out" "$man"
  '';

  nspr = prev.nspr.overrideAttrs (old: {
    postPatch =
      (old.postPatch or "")
      + ''
        substituteInPlace nspr/pr/include/md/_linux.h \
          --replace-fail \
            '#if (defined(__GLIBC__) && __GLIBC__ >= 2) || defined(ANDROID)' \
            '#if 1'
      '';
  });

  smallRelease = old: {
    env =
      (old.env or {})
      // {
        CARGO_PROFILE_RELEASE_OPT_LEVEL = "z";
        CARGO_PROFILE_RELEASE_LTO = "thin";
        CARGO_PROFILE_RELEASE_CODEGEN_UNITS = "1";
      };
  };
in {
  wild = stock.wild;

  # m1n1 builds its own bare-metal rustc, reuse cached.
  m1n1 = stock.m1n1;

  nixVersions =
    prev.nixVersions
    // {
      latest = prev.nixVersions.latest.overrideScope (_: old: {
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

        nix-util = addCflags "-Wno-error=sign-compare" (old.nix-util.overrideAttrs (oldAttrs: {
          postPatch =
            (oldAttrs.postPatch or "")
            + ''
              substituteInPlace unix/file-descriptor.cc \
                --replace-fail \
                  '#include <fcntl.h>' \
                  $'#include <fcntl.h>\n#include <sys/syscall.h>'
            '';
        }));
      });
    };

  nil =
    (prev.nil.override {
      nix = final.nixVersions.latest;
    }).overrideAttrs
    (old:
      {
        env =
          old.env
          // {
            CARGO_PROFILE_RELEASE_LTO = "fat";
            CFG_DEFAULT_FORMATTER = lib.getExe final.alejandra;
          };
      }
      // testsOff);

  alejandra = prev.alejandra.overrideAttrs (old: {
    env = (old.env or {}) // {CARGO_PROFILE_RELEASE_LTO = "fat";};
  });

  oo7-server = prev.oo7-server.overrideAttrs smallRelease;
  oo7-portal = prev.oo7-portal.overrideAttrs smallRelease;
  uutils-diffutils = prev.uutils-diffutils.overrideAttrs smallRelease;

  # The wrapper puts gdb on PATH for nim-gdb.
  nim = prev.nim.overrideAttrs (old: {
    wrapperArgs =
      map (
        a:
          if lib.hasPrefix "--prefix PATH : " a && lib.hasInfix "gdb" a
          then "--prefix PATH : ${placeholder "out"}/bin"
          else a
      )
      old.wrapperArgs;

    postInstall =
      (old.postInstall or "")
      + "\n"
      + ''
        rm -f $out/bin/nim-gdb
      '';
  });

  btop = prev.btop.overrideAttrs (old: {
    patches = (old.patches or []) ++ [../../../patches/btop-init-order.patch];
  });

  chawan = prev.chawan.overrideAttrs (finalAttrs: old: {
    version = "0.5.1";
    src = prev.fetchFromSourcehut {
      owner = "~bptato";
      repo = "chawan";
      tag = "v${finalAttrs.version}";
      hash = "sha256-inNywc8qc4dhvWT68BZWUTQtWmwhnZvp7nLDOzoqCno=";
    };
  });

  # Trim further from X11 and wrapper.
  discordo =
    (prev.discordo.override {
      wl-clipboard = prev.stash-clipboard;
      buildGoModule = final.buildGo127Module;
    }).overrideAttrs (old: {
      version = "0-unstable-2026-10-27";
      src = final.fetchFromGitHub {
        owner = "ayn2op";
        repo = "discordo";
        rev = "9836b13d738458ecd35d8907a004004e04e27d55";
        hash = "sha256-1naeAZemSJlrubtE8zB/B/T8y3oDM4NN4qctWGXRcD0=";
      };
      vendorHash = "sha256-w6+PviH2olyPw6CxbA6U3VGEk9YKBbrNptFT0QGj6e4=";
      buildInputs = [];
      nativeBuildInputs = dropNamed ["make-wrapper-hook" "makeWrapper"] (old.nativeBuildInputs or []);
      doCheck = false;
    });

  # Drop X11, fix udev to mdevd's.
  servo =
    (prev.servo.override {
      udev = final.libudev-zero;
    }).overrideAttrs (old: {
      buildInputs =
        dropNamed ["libx11" "gst-plugins-bad" "gst-plugins-ugly"] (old.buildInputs or [])
        ++ [final.gst_all_1.gst-libav];

      postFixup = ''
        mkdir -p $out/resources
        cp -r ./resources $out/

        wrapProgram $out/bin/servoshell \
          --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [
          final.libxkbcommon
          final.vulkan-loader
          final.wayland
          final.libGL
        ]}
      '';
    });

  firefox-unwrapped =
    (prev.firefox-unwrapped.override {
      pkgsCross =
        prev.pkgsCross
        // {
          wasm32-wasip1 = stock.pkgsCross.wasm32-wasip1;
        };
      enablePGO = false;
      enableDebugSymbols = false;
      enableLTO = false;
      inherit nspr;
      nss_latest = prev.nss_latest.override {inherit nspr;};

      withJACK = false;
      withSndio = false;
      withGSSAPI = false;
      enableLocation = false;
      enableDataReporting = false;

      wrapGAppsHook3 = final.wrapGAppsHook3.override {makeWrapper = final.makeShellWrapper;};
    }).overrideAttrs
    (old: {
      nativeBuildInputs =
        dropNamed ["nodejs" "nodejs-slim"] (old.nativeBuildInputs or [])
        ++ [stock.nodejs-slim];

      configureFlags =
        replaceFlags
        ["--with-onnx-runtime=" "--enable-default-toolkit="]
        [
          "--without-onnx-runtime"
          #"--without-wasm-sandboxed-libraries"
          "--enable-default-toolkit=cairo-gtk3-wayland-only"
          "--disable-accessibility"
          "--enable-packed-relative-relocs"
          "--enable-linker=lld"
          "--disable-webdriver"
          "--disable-backgroundtasks"
          "--disable-bundled-fonts"
        ]
        (old.configureFlags or []);

      preConfigure =
        lib.concatStringsSep "\n"
        (lib.filter (l: !lib.hasInfix "LD_PRELOAD" l) (lib.splitString "\n" old.preConfigure));

      postPatch =
        (old.postPatch or "")
        + "\n"
        + ''
          sed -i '1i #include <cstdint>' third_party/parakeet.cpp/src/backend.hpp
          sed -i '/#include <linux\/prctl.h>/d' \
            third_party/libwebrtc/rtc_base/platform_thread_types.cc
        '';
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
      install -Dm644 "$src" "$out/share/fonts/truetype/noto/NotoColorEmoji.ttf"
      runHook postInstall
    '';

    meta = prev.noto-fonts-color-emoji.meta;
  };
}
