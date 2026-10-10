{
  dri-pkgconfig-stub,
  epoll-shim,
  evdev-proto,
  bash,
  libepoxy,
  fetchurl,
  font-util,
  lib,
  libdecor,
  libgbm,
  libGL,
  libx11,
  libxau,
  libxfont_2,
  libdrm,
  libtirpc,
  # Disable withLibunwind as LLVM's libunwind will conflict and does not support the right symbols.
  withLibunwind ? !(stdenv.hostPlatform.useLLVM or false),
  libunwind,
  libxkbfile,
  libxshmfence,
  libxcvt,
  mesa-gl-headers,
  meson,
  ninja,
  openssl,
  pkg-config,
  pixman,
  stdenv,
  wayland,
  wayland-protocols,
  wayland-scanner,
  xkbcomp,
  xkeyboard_config,
  xorgproto,
  xtrans,
  defaultFontPath ? "",
  gitUpdater,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "xwayland";
  version = "24.1.13";

  src = fetchurl {
    url = "mirror://xorg/individual/xserver/xwayland-${finalAttrs.version}.tar.xz";
    hash = "sha256-FzrqPW95YJFkwEUo4cjkybYPzVk5HDydrUZnKX1yf7Y=";
  };

  postPatch = ''
    substituteInPlace os/utils.c \
      --replace-fail '/bin/sh' '${lib.getExe' bash "sh"}'
  '';

  depsBuildBuild = [
    pkg-config
  ];
  nativeBuildInputs = [
    pkg-config
    meson
    ninja
    wayland-scanner
  ];
  buildInputs = [
    dri-pkgconfig-stub
    libdecor
    libgbm
    libepoxy
    font-util
    libGL
    libxau
    libxfont_2
    libdrm
    libxkbfile
    libxshmfence
    libxcvt
    mesa-gl-headers
    openssl
    pixman
    wayland
    wayland-protocols
    xkbcomp
    xorgproto
    xtrans
  ]
  ++ lib.optionals stdenv.hostPlatform.isFreeBSD [
    epoll-shim
    evdev-proto
  ]
  ++ lib.optionals withLibunwind [
    libunwind
  ];
  mesonFlags = [
    (lib.mesonBool "xcsecurity" true)
    (lib.mesonBool "secure-rpc" false)
    (lib.mesonBool "xdmcp" false)
    (lib.mesonBool "xwayland_ei" false)
    (lib.mesonBool "systemd_notify" false)
    (lib.mesonBool "xvfb" false)
    (lib.mesonBool "libunwind" false)
    (lib.mesonOption "default_font_path" defaultFontPath)
    (lib.mesonOption "xkb_bin_dir" "${xkbcomp}/bin")
    (lib.mesonOption "xkb_dir" "${xkeyboard_config}/etc/X11/xkb")
    (lib.mesonOption "xkb_output_dir" "${placeholder "out"}/share/X11/xkb/compiled")
    (lib.mesonBool "libunwind" withLibunwind)
  ];

  passthru.updateScript = gitUpdater {
    # No nicer place to find latest release.
    url = "https://gitlab.freedesktop.org/xorg/xserver.git";
    rev-prefix = "xwayland-";
  };

  meta = {
    description = "X server for interfacing X11 apps with the Wayland protocol";
    homepage = "https://gitlab.freedesktop.org/xorg/xserver";
    license = lib.licenses.mit;
    mainProgram = "Xwayland";
    maintainers = with lib.maintainers; [
      emantor
      k900
    ];
    platforms = lib.platforms.linux ++ lib.platforms.freebsd;
  };
})
