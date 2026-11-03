{
  lib,
  stdenv,
  fetchFromGitHub,
  pkg-config,
  nss_latest,
  efivar,
  util-linux,
  popt,
  nspr,
  mandoc,
}: let
  efivar-clang = efivar.overrideAttrs (old: {
    makeFlags =
      (old.makeFlags or [])
      ++ [
        "CC=clang"
        "CCLD=clang"
      ];
  });
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "pesign";
    version = "117";

    src = fetchFromGitHub {
      owner = "rhboot";
      repo = finalAttrs.pname;
      tag = finalAttrs.version;
      hash = "sha256-lMaHsf/kIjxPyQ/Yh08yyNSimZZi9tFmBj4vXJ32zHM=";
    };

    # nss-util is missing because it is already contained in nss
    # Red Hat seems to be shipping a separate nss-util:
    # https://centos.pkgs.org/7/centos-x86_64/nss-util-devel-3.44.0-4.el7_7.x86_64.rpm.html
    # containing things we already have in `nss`.
    # We can ignore all the errors pertaining to a missing
    # nss-util.pc I suppose.
    buildInputs = [
      efivar-clang
      util-linux
      nss_latest
      popt
      nspr
      mandoc
    ];

    nativeBuildInputs = [pkg-config];

    patches = lib.optional stdenv.hostPlatform.isMusl ./musl.patch;

    makeFlags = [
      "INSTALLROOT=$(out)"
    ];

    postInstall = ''
      mv $out/usr/bin $out/bin
      mv $out/usr/share $out/share

      rm -rf $out/usr
      rm -rf $out/etc
      rm -rf $out/run
    '';

    env = {
      CC = "${stdenv.cc}/bin/clang";
      CCLD = "${stdenv.cc}/bin/clang";
    };

    meta = {
      description = "Signing tools for PE-COFF binaries. Compliant with the PE and Authenticode specifications";
      homepage = "https://github.com/rhboot/pesign";
      license = lib.licenses.gpl2Only;
      maintainers = [];
      # efivar is currently Linux-only.
      platforms = lib.platforms.linux;
    };
  })
