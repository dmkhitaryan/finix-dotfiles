{
  lib,
  stdenv,
  fetchgit,
  meson,
  ninja,
  pkg-config,
  libva,
  libdrm,
}:

stdenv.mkDerivation {
  pname = "libva-v4l2-request";
  version = "1.2";

  src = fetchgit {
    url = "https://xff.cz/git/libva-v4l2_request";
    rev = "refs/tags/1.2";
    hash = "sha256-a7AjZdiOVueMRsQylOpgc7HVLuaj5tb99BfZzOvY6Uc=";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
  ];

  buildInputs = [
    libva
    libdrm
  ];

  hardeningDisable = [ "fortify" ]; # musl moment.

  mesonFlags = [
    "-Ddriverdir=${placeholder "out"}/lib/dri"
  ];

  meta = {
    description = "VA-API driver for V4L2 stateless request decoders";
    homepage = "https://xff.cz/git/libva-v4l2_request";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
}
