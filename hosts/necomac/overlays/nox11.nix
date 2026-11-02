final: prev: let
  inherit (prev) lib;
  inherit (import ./lib.nix lib) dropNamed dropOutputs replaceFlags;
in {
  cairo = prev.cairo.override {
    x11Support = false;
  };

  pango = prev.pango.override {
    x11Support = false;
  };

  gtk3 = prev.gtk3.override {
    x11Support = false;
    xineramaSupport = false;
    libepoxy = final.libepoxy;
    gettext = null;
  };

  libglvnd = prev.libglvnd.overrideAttrs (old: {
    buildInputs = dropNamed ["libx11" "libxext" "xorgproto"] (old.buildInputs or []);
    configureFlags = (old.configureFlags or []) ++ ["--disable-x11" "--disable-glx"];
    # Upstream postFixup patches libGLX.so, but it's filtered out now.
    postFixup = "";
  });

  libepoxy = prev.libepoxy.overrideAttrs (old: {
    buildInputs = (old.buildInputs or []) ++ [final.libGL];
    doCheck = false;
    mesonFlags = replaceFlags ["-Degl=" "-Dtests="] ["-Degl=yes" "-Dtests=false"] (old.mesonFlags or []);
  });

  libxkbcommon = prev.libxkbcommon.overrideAttrs (old: {
    outputs = dropOutputs ["doc"] (old.outputs or []);
    nativeBuildInputs = dropNamed ["xvfb" "doxygen"] (old.nativeBuildInputs or []);
    buildInputs = dropNamed ["libxcb"] (old.buildInputs or []);
    mesonFlags =
      replaceFlags
      ["-Denable-docs=" "-Denable-x11=" "-Dx-locale-root="]
      ["-Denable-docs=false" "-Denable-x11=false"]
      (old.mesonFlags or []);
  });

  imv =
    (prev.imv.override {
      withWindowSystem = "wayland";
    }).overrideAttrs (old: {
      # Man pages pull asciidoc (and thus python).
      nativeBuildInputs = dropNamed ["asciidoc"] (old.nativeBuildInputs or []);
      mesonFlags = replaceFlags ["-Dman="] ["-Dman=disabled"] (old.mesonFlags or []);
      outputs = dropOutputs ["doc" "man"] (old.outputs or []);
    });
}
