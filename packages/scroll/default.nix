{
  lib,
  sway,
  sway-unwrapped,
  libinput,
  libudev-zero,

  glslang,
  lcms,
  hwdata,
  libliftoff,
  lua54Packages,
  vulkan-loader,
  xwayland,
  seatd,
  libdisplay-info,
  libxcb-render-util,
  libxcb-errors,
  libgbm,
  readline,
  fetchFromGitHub,
  ...
}:

let
  libinput' = libinput.override {
    udev = libudev-zero;
    wacomSupport = false;
  };

  sway-unwrapped' = sway-unwrapped.override (
    o:
    let
      wlrootsAttr = lib.head (lib.filter (lib.hasPrefix "wlroots") (lib.attrNames o));
    in
    {
      libinput = libinput';

      ${wlrootsAttr} = o.${wlrootsAttr}.override {
        libinput = libinput';
      };

      # mdevd + seatd, no systemd integration.
      systemdSupport = false;
    }
  );

  scroll-unwrapped = sway-unwrapped'.overrideAttrs (old: {
    pname = "scroll";
    version = "1.12.18";

    src = fetchFromGitHub {
      owner = "dawsers";
      repo = "scroll";
      tag = "1.12.18";
      hash = "sha256-V6Aitjbm3GSB1+EAnoZ1kBzNV0olxV63B93S2qrWYos=";
    };

    mesonFlags = old.mesonFlags ++ [
      "-Dc_args=-Wno-error=maybe-uninitialized"
    ];

    passthru = (old.passthru or { }) // {
      providedSessions = [ "scroll" ];
    };

    patches = [ ];

    nativeBuildInputs = old.nativeBuildInputs ++ [
      glslang
      lcms
      hwdata
      libliftoff
    ];

    buildInputs = old.buildInputs ++ [
      lua54Packages.lua
      vulkan-loader
      xwayland
      seatd
      lcms
      libdisplay-info
      libxcb-render-util
      libxcb-errors
      libliftoff
      libgbm
      readline
    ];

    meta = old.meta // {
      mainProgram = "scroll";
    };
  });
in

sway.override {
  sway-unwrapped = scroll-unwrapped;
}
