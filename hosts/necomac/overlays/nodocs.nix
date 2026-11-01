final: prev: let
  inherit (prev) lib;
  inherit (import ./lib.nix lib) dropNamed dropPkgs dropOutputs replaceFlags;
  noDoc = replaceFlags ["-Ddoc="] ["-Ddoc=disabled"];
in {
  orc = prev.orc.override {
    buildDevDoc = false;
  };

  ninja = prev.ninja.override {
    buildDocs = false;
  };

  kmod = prev.kmod.override {
    withDevdoc = false;
  };

  wayland = prev.wayland.override {
    withDocumentation = false;
    withTests = false;
  };

  greetd = prev.greetd.overrideAttrs (old: {
    nativeBuildInputs = dropPkgs [prev.scdoc] (old.nativeBuildInputs or []);
    postInstall = "";
  });

  libtiff = prev.libtiff.overrideAttrs (old: {
    nativeBuildInputs = dropPkgs [prev.sphinx] (old.nativeBuildInputs or []);
    outputs = dropOutputs ["doc" "man"] (old.outputs or []);
  });

  libjxl = prev.libjxl.overrideAttrs (old: {
    nativeBuildInputs = dropNamed ["asciidoc" "doxygen"] old.nativeBuildInputs;
    cmakeFlags = (old.cmakeFlags or []) ++ ["-DJPEGXL_ENABLE_DOXYGEN=OFF" "-DJPEGXL_ENABLE_MANPAGES=OFF"];
  });

  serd = prev.serd.overrideAttrs (old: {
    outputs = dropOutputs ["doc" "man"] (old.outputs or []);
    nativeBuildInputs = dropNamed ["doxygen" "mandoc" "sphinx" "sphinxygen"] (old.nativeBuildInputs or []);
    postPatch =
      (old.postPatch or "")
      + ''
        substituteInPlace meson.build \
          --replace-fail \
            "subdir('doc')" \
            "# subdir('doc')"
      '';
  });

  gst_all_1 = prev.gst_all_1.overrideScope (_: gstPrev: {
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

    gst-libav = gstPrev.gst-libav.overrideAttrs (old: {
      mesonFlags = noDoc (old.mesonFlags or []);
    });

    gst-plugins-good = gstPrev.gst-plugins-good.overrideAttrs (old: {
      mesonFlags = noDoc (old.mesonFlags or []);
    });
  });
}
