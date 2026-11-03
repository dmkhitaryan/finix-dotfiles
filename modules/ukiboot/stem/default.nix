{
  fetchFromCodeberg,
  stdenv,
  lib,
  meson,
  ninja,
  python3,
}: let
  efi-defs = fetchFromCodeberg {
    owner = "Gardenhouse";
    repo = "efi-defs";
    rev = "e81d17b654ce7d77e32605242b50898799dc6c46";
    hash = "sha256-WjnbRRl8Ruc136E8S47G1HYTPmgjOO9TsFpNOD1K2r0=";
  };
in
  stdenv.mkDerivation rec {
    pname = "stem";
    version = "0.1";

    src = fetchFromCodeberg {
      owner = "Gardenhouse";
      repo = pname;
      rev = "7104f3e75c0a24c92749cd265cdeb40263799422";
      hash = "sha256-H2eYvGbV7QkLmYwyyQiZRF4nz+U85usIwmTAUUHiLAo=";
    };
    out = [
      "out"
      "lib"
    ];

    nativeBuildInputs = [
      ninja
      meson
      (python3.withPackages (ps: [ps.pyelftools]))
    ];

    postPatch = ''
      cp -r ${efi-defs} subprojects/efi-defs
      chmod -R u+w subprojects/efi-defs
    '';

    meta = {
      description = "Minimal implementation of a UKI compatible efi stub";
      homepage = "https://codeberg.org/${src.owner}/${pname}";
      license = lib.licenses.gpl3Only;
      maintainers = [
        "z4il"
      ];
    };
  }
