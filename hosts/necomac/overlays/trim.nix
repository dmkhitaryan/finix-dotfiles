final: prev: let
  inherit (prev) lib;
  inherit (import ./lib.nix lib) dropNamed dropPkgs testsOff;

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
      (lib.filter (ext: !lib.elem (ext.extensionName or null) ["gettext" "opcache"]) enabled);
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
      nativeBuildInputs = dropNamed ["gfortran-wrapper"] (old.nativeBuildInputs or []);
      # LLVM's openmp drags python.
      buildInputs = dropNamed ["openmp"] (old.buildInputs or []);
      propagatedBuildInputs = dropNamed ["openmp"] (old.propagatedBuildInputs or []);
      configureFlags =
        lib.filter (f: f != "--enable-openmp") (old.configureFlags or [])
        ++ ["--disable-fortran"];
    });

  gsdSchemas = final.stdenvNoCC.mkDerivation {
    pname = "gnome-settings-daemon-gsettings-schemas-minimal";
    inherit (prev.gnome-settings-daemon) version src;

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
in {
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
        + lib.optionalString prev.stdenv.hostPlatform.isMusl ''
          substituteInPlace git-sh-i18n.sh \
            --replace-fail '${prev.gettext}/bin/gettext.sh' 'gettext.sh' \
            --replace-fail 'export PATH=${prev.gettext}/bin:$PATH' ':'
        '';
    });

  writeShellScript = name: text:
    prev.writeScript name ''
      #!${final.bashNonInteractive}/bin/bash
      ${text}
    '';

  udevCheckHook = prev.emptyDirectory;

  libpcap = prev.libpcap.override {
    withRdma = false;
  };

  libjpeg_turbo = prev.libjpeg_turbo.override {
    enableJpeg8 = true; # Potentially breaking. YOLO.
  };

  libnotify = prev.libnotify.override {
    withIntrospection = false;
  };

  dconf = prev.dconf.override {
    withIntrospection = false;
  };

  elfutils = prev.elfutils.override {
    enableDebuginfod = false;
  };

  fontforge = prev.fontforge.override {
    withGTK = false;
    withPython = false;
    withExtras = false;
  };

  libdrm = prev.libdrm.override {
    withIntel = false;
    withValgrind = false;
  };

  libva = prev.libva.override {
    minimal = true;
  };

  libopenmpt = prev.libopenmpt.override {
    usePulseAudio = false;
  };

  libcanberra = mkCanberra prev.libcanberra;
  libcanberra-gtk3 = mkCanberra prev.libcanberra-gtk3;

  fftw = trimFftw prev.fftw;
  fftwSinglePrec = trimFftw prev.fftwSinglePrec;

  xdg-desktop-portal-gtk = prev.xdg-desktop-portal-gtk.overrideAttrs (old: {
    mesonFlags = (old.mesonFlags or []) ++ ["-Dwallpaper=disabled" "-Dlockdown=disabled"];
    buildInputs =
      dropNamed ["gnome-settings-daemon"] (dropPkgs [prev.gnome-desktop] (old.buildInputs or []))
      ++ [gsdSchemas];
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
      buildInputs = dropNamed [
        "jack2"
        "ladspa-header"
        "gstreamer"
        "gst-plugins-base"
        "libxrandr"
        "libglvnd"
        "glu"
      ] (old.buildInputs or []);

      configurePhase = ''
        runHook preConfigure

        make $makeFlags config \
          SUB_FEATURES="ui standalone launcher xdg jack pipewire gst clap ladspa vst2"

        runHook postConfigure
      '';

      # No dlmopen on musl.
      postPatch =
        (old.postPatch or "")
        + lib.optionalString prev.stdenv.hostPlatform.isMusl ''
          substituteInPlace modules/lsp-runtime-lib/src/main/ipc/Library.cpp \
            --replace-fail \
              "::dlmopen(LM_ID_NEWLM, str, RTLD_NOW)" \
              "::dlopen(str, RTLD_NOW)"
        '';
    });

  # The clang ffmpeg fix in toolchain.nix carries over through `prev.ffmpeg`.
  ffmpeg-headless =
    (prev.ffmpeg.override {
      withSdl2 = false;
      buildFfplay = false;

      # No NVIDIA, AMD or Intel video APIs.
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

      withXlib = false;
      withXcb = false;
      withXcbShape = false;
      withXcbShm = false;
      withXcbxfixes = false;
      withOpengl = false;
      withOpenal = false;

      withDocumentation = false;
      withHtmlDoc = false;
      withManPages = false;
      withPodDoc = false;
      withTxtDoc = false;
      withDoc = false;
    }).overrideAttrs
    testsOff;

  linux-firmware = prev.linux-firmware.overrideAttrs (old: {
    postInstall = let
      unused = [
        "amdgpu"
        "radeon"
        "nvidia"
        "i915"
        "intel"
        "mediatek"
        "ath10k"
        "ath11k"
        "ath12k"
        "ath9k_htc"
        "mrvl"
        "rtlwifi"
        "rtw88"
        "rtw89"
        "ti-connectivity"
        "qcom"
        "mellanox"
        "microchip"
        "cavium"
        "netronome"
        "qed"
        "liquidio"
        "inside-secure"
        "ueagle-atm"
        "av7110"
        "cirrus"
        "sof"
        "dell"
        "lenovo"
        "amdnpu"
        "ql2900"
        "xe"
        "ti"
        "rtl_bt"
        "dsp56k"
      ];
    in
      (old.postInstall or "")
      + ''
        rm -rf ${lib.concatMapStringsSep " " (n: "$out/lib/firmware/${n}") unused}
        rm -f $out/lib/firmware/iwlwifi-*

        # Clean up dangling WHENCE symlinks.
        find -L $out/lib/firmware -type l -delete
        find $out/lib/firmware -type d -empty -delete
      '';
  });
}
