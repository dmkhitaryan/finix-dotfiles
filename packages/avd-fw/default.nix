{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  meson,
  ninja,
  pkgsCross,
}:

let
  armBuild = pkgsCross.arm-embedded.buildPackages;
in
  stdenvNoCC.mkDerivation {
    pname = "avd-fw";
    version = "unstable-2026-06-26";

    src = fetchFromGitHub {
      owner = "AsahiLinux";
      repo = "avd-fw";
      rev = "main";
      hash = "sha256-cq/gOgmbCg5IX0GSiS7Z5lBhpursB1Num8LSANw5fpI=";
    };

    nativeBuildInputs = [
      meson
      ninja
      armBuild.gccWithoutTargetLibc
      armBuild.binutils
    ];

    mesonFlags = [
      "--cross-file=arm-none-eabi-gcc.ini"
      "-Dfirmwaredir=firmware"
    ];

    hardeningDisable = [ "all" ];

    meta = {
      description = "Firmware for hardware decoding on Apple Silicon";
      homepage = "https://github.com/AsahiLinux/avd-fw";
      license = lib.license.mit;
      platforms = lib.platforms.linux;
    };
  }

