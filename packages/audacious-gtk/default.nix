{
  lib,
  stdenv,
  audacious-plugins,
  fetchFromGitHub,
  meson,
  ninja,
  pkg-config,
  gtk3,
  withPlugins ? false,
}:

stdenv.mkDerivation( finalAttrs: {
  pname = "audacious";
  version = "4.6.1";

  src = fetchFromGitHub {
    owner = "audacious-media-player";
    repo = "audacious";
    rev = "${finalAttrs.pname}-${finalAttrs.version}";
    hash = "sha256-f1ugxM57dYDDq/G+16bXs6++KXnaLwT+mcPY0R371tY=";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
  ];

  buildInputs = [
    gtk3
  ];

  mesonFlags = [
    "-Dgtk=true"
    "-Dqt=false"
    "-Dbuildstamp=NixOS"
  ];

  postInstall = lib.optionalString withPlugins ''
    ln -s ${audacious-plugins}/lib/audacious $out/lib
    ln -s ${audacious-plugins}/share/audacious/Skins $out/share/audacious/
  '';

  meta = {
    description = "Lightweight and versatile audio player";
    homepage = "https://audacious-media-player.org";
    downloadPage = "https://github.com/audacious-media-player/audacious";
    mainProgram = "audacious";
    platforms = lib.platforms.linux;
    license = with lib.licenses; [
      bsd2
      bsd3 # https://github.com/audacious-media-player/audacious/blob/master/COPYING
      gpl2
      gpl3
      lgpl2Plus # http://redmine.audacious-media-player.org/issues/46
    ];
  };
})
