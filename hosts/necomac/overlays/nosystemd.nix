# No systemd/logind: basu for sd-bus, libudev-zero (mdevd) for udev.
final: prev: let
  inherit (prev) lib;
  inherit (import ./lib.nix lib) dropNamed dropPkgs dropOutputs replaceFlags useBasu;
in {
  basu = prev.basu.overrideAttrs (old: {
    nativeBuildInputs = dropPkgs [prev.getent] old.nativeBuildInputs;

    postPatch =
      (old.postPatch or "")
      + ''
        substituteInPlace meson.build \
        --replace-fail \
          "        getent_result = run_command('getent', 'passwd', '65534')" \
          "        getent_result = run_command('false')"
      '';
  });

  libei = prev.libei.override {
    systemdLibs = final.basu;
  };

  mako =
    (prev.mako.override {
      systemdMinimal = final.basu;
    }).overrideAttrs
    {
      mesonFlags = ["-Dsd-bus-provider=basu"];
    };

  rtkit =
    (prev.rtkit.override {
      systemdLibs = final.basu;
    }).overrideAttrs
    (old: {
      mesonFlags = (old.mesonFlags or []) ++ [(lib.mesonEnable "libsystemd" false)];
    });

  xdg-desktop-portal-wlr =
    (prev.xdg-desktop-portal-wlr.override {
      systemdLibs = final.basu;
    }).overrideAttrs
    (old: {
      mesonFlags = useBasu (old.mesonFlags or []);
    });

  xdg-desktop-portal-termfilechooser =
    (prev.xdg-desktop-portal-termfilechooser.override {
      systemdLibs = final.basu;
    }).overrideAttrs
    (old: {
      mesonFlags = useBasu (old.mesonFlags or []);
    });

  xdg-desktop-portal =
    (prev.xdg-desktop-portal.override {
      enableGeoLocation = false;
      enableSystemd = false;
    }).overrideAttrs
    (old: {
      doCheck = false;
      buildInputs = dropNamed ["flatpak"] (old.buildInputs or []);
      mesonFlags = (old.mesonFlags or []) ++ ["-Dflatpak-interfaces=disabled"];
    });

  libgudev =
    (prev.libgudev.override {
      udev = prev.libudev-zero;
    }).overrideAttrs
    (old: {
      doCheck = false;
      mesonFlags = replaceFlags ["-Dtests="] ["-Dtests=disabled"] (old.mesonFlags or []);
      # clang doesn't take bare -export-dynamic.
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

  libinput = prev.libinput.override {
    udev = prev.libudev-zero; # mdevd.
    wacomSupport = false;
  };

  wlroots = prev.wlroots.override {
    libinput = final.libinput;
  };

  bluez = prev.bluez.override {
    udev = prev.libudev-zero;
  };

  v4l-utils = prev.v4l-utils.override {
    withGUI = false;
    withBPF = false;
    udev = prev.libudev-zero;
  };

  libcamera =
    (prev.libcamera.override {
      udev = prev.libudev-zero;
    }).overrideAttrs
    (old: {
      nativeBuildInputs = dropNamed ["sphinx" "graphviz" "doxygen"] (old.nativeBuildInputs or []);
      buildInputs = dropNamed ["pybind11"] (old.buildInputs or []);
      mesonFlags = (old.mesonFlags or []) ++ ["-Dpycamera=disabled"];
    });

  seatd =
    (prev.seatd.override {
      systemdSupport = false;
    }).overrideAttrs (old: {
      # -Wsign-compare on musl with clang.
      mesonFlags = (old.mesonFlags or []) ++ ["-Dwerror=false"];
    });

  linux-pam = prev.linux-pam.override {
    withLogind = false;
  };

  pam = final.linux-pam;

  procps = prev.procps.override {
    withSystemd = false;
  };

  util-linux = prev.util-linux.override {
    systemdSupport = false;
    translateManpages = false;
  };

  polkit =
    (prev.polkit.override {
      useSystemd = false;
      useConsoleKit = true;
      withIntrospection = false;
    }).overrideAttrs
    (old: {
      buildInputs = dropPkgs [prev.elogind] (old.buildInputs or []);
    });

  dbus =
    (prev.dbus.override {
      enableSystemd = false;
      x11Support = false;
    }).overrideAttrs (old: {
      # AppArmor is off in the kernel, and libapparmor doesn't build with clang.
      buildInputs = dropNamed ["libapparmor"] (old.buildInputs or []);
      mesonFlags = replaceFlags ["-Dapparmor="] ["-Dapparmor=disabled"] (old.mesonFlags or []);
    });

  at-spi2-core =
    (prev.at-spi2-core.override {
      systemdSupport = false;
    }).overrideAttrs (old: {
      buildInputs = dropNamed ["libx11" "libxtst" "libxi" "libxext"] (old.buildInputs or []);
      mesonFlags = (old.mesonFlags or []) ++ ["-Dx11=disabled"];
    });

  xwayland = prev.xwayland.overrideAttrs (old: {
    buildInputs = dropPkgs [prev.systemd] (old.buildInputs or []);
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

      buildInputs = dropPkgs [prev.systemdLibs] (old.buildInputs or []);

      mesonFlags =
        replaceFlags
        ["-Dsystemd=" "-Dsystemd-system-service=" "-Dsystemd-system-unit-dir="]
        ["-Dsystemd-system-service=false" "-Dsystemd=disabled"]
        (old.mesonFlags or []);
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

      patches = (old.patches or []) ++ [../../../patches/pipewire-libudev_zero.patch];

      buildInputs = dropNamed ["modemmanager" "elogind" "libcamera" "libmysofa"] (old.buildInputs or []);
      nativeBuildInputs = dropNamed ["docutils" "doxygen" "graphviz"] (old.nativeBuildInputs or []);

      mesonFlags =
        replaceFlags
        [
          "-Ddocs="
          "-Dinstalled_tests="
          "-Dman="
          "-Dlogind="
          "-Dbluez5-backend-native-mm="
          "-Dlibcamera="
        ]
        [
          "-Ddocs=disabled"
          "-Dinstalled_tests=disabled"
          "-Dman=disabled"
          "-Dlogind=disabled"
          "-Dbluez5-backend-native-mm=disabled"
          "-Dlibcamera=disabled"
          "-Dlibmysofa=disabled"
        ]
        (old.mesonFlags or []);

      outputs = dropOutputs ["doc" "man" "installedTests"] (old.outputs or []);
    });
}
