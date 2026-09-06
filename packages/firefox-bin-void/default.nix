{
  lib,
  stdenv,
  fetchurl,
  libarchive,
  autoPatchelfHook,
  patchelfUnstable,
  wrapGAppsHook3,

  adwaita-icon-theme,
  alsa-lib,
  curl,
  dbus-glib,
  gtk3,
  libva,
  libxtst,
  nspr,
  nss_latest,
  pciutils,
  pipewire,

}:
let
  firefoxXbps = fetchurl rec {
    pname = "firefox";
  version = "155.0_1";
    url = "https://repo-default.voidlinux.org/current/aarch64/${pname}-${version}.aarch64-musl.xbps";
  hash = "sha256-tfMuPiNZaiknWjaV5t+B+VYVlIaz+p/JzprVr3+l37I=";
  };

  libffiXbps = fetchurl rec {
    pname = "libffi";
  version = "3.3_2";
    url = "https://repo-default.voidlinux.org/current/aarch64/${pname}-${version}.aarch64-musl.xbps";
  hash = "sha256-TjJ/vXRSO3tnn/ESz65cTgKtsqLa6fIhXbETkREBv7Q=";
  };

  libjpegXbps = fetchurl rec {
    pname = "libjpeg-turbo";
  version = "3.1.4.1_1";
    url = "https://repo-default.voidlinux.org/current/aarch64/${pname}-${version}.aarch64-musl.xbps";
  hash = "sha256-S163ZgGp58lPnU2C/9Vp5hgu8MUVXJHmH/nX+jUjRuQ=";
  };

  nsprFixed = nspr.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace nspr/pr/include/md/_linux.h \
        --replace-fail \
          '#if (defined(__GLIBC__) && __GLIBC__ >= 2) || defined(ANDROID)' \
          '#if 1'
    '';
  });

  nssFixed = nss_latest.override {
    nspr = nsprFixed;
  };
in

stdenv.mkDerivation rec {
  pname = "firefox-void-bin";
  version = builtins.head (lib.splitString "_" firefoxXbps.version);

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [
    libarchive
    autoPatchelfHook
    patchelfUnstable
    wrapGAppsHook3
  ];

  buildInputs = [
    gtk3
    adwaita-icon-theme
    alsa-lib
    dbus-glib
    libxtst
    nssFixed
    nsprFixed
  ];

  runtimeDependencies = [
    curl
    pciutils
    libva.out
  ];

  appendRunpaths = [
    "${pipewire}/lib"
  ];

  patchelfFlags = [
    "--no-clobber-old-sections"
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"

    bsdtar -xf ${firefoxXbps} -C "$out"

    mv "$out/usr/lib" "$out/lib"
    mv "$out/usr/share" "$out/share"

    mkdir -p "$out/bin"

    rm -f "$out/usr/bin/firefox"
    ln -s ../lib/firefox/firefox "$out/bin/firefox"

    rm -rf "$out/usr"

    # Void ABI compatibility libraries.
    mkdir -p "$out/lib/void-compat"

    mkdir "$TMPDIR/libffi"
    bsdtar -xf ${libffiXbps} -C "$TMPDIR/libffi"

    cp -a \
      "$TMPDIR/libffi/usr/lib/libffi.so.7"* \
      "$out/lib/void-compat/"

    mkdir "$TMPDIR/libjpeg"
    bsdtar -xf ${libjpegXbps} -C "$TMPDIR/libjpeg"

    cp -a \
      "$TMPDIR/libjpeg/usr/lib/libjpeg.so.8"* \
      "$out/lib/void-compat/"

    runHook postInstall
  '';

  preFixup = ''
    # Let autoPatchelf find the Void compatibility libraries.
    addAutoPatchelfSearchPath "$out/lib/void-compat"
  '';

  postFixup = ''
    firefoxDir="$out/lib/firefox"
    muslInterp="${stdenv.cc.libc}/lib/ld-musl-aarch64.so.1"

    # autoPatchelf fixes DT_NEEDED/RPATH, but Void executables still carry
    # the FHS musl PT_INTERP.
    find "$firefoxDir" -type f -print0 |
      while IFS= read -r -d "" file; do
        interp="$(
          patchelf --print-interpreter "$file" 2>/dev/null || true
        )"

        if [ "$interp" = "/lib/ld-musl-aarch64.so.1" ]; then
          echo "patching interpreter: $file"
          patchelf \
            --no-clobber-old-sections \
            --set-interpreter "$muslInterp" \
            "$file"
        fi
      done
  '';

  passthru = {
    inherit
      gtk3
      firefoxXbps
      libffiXbps
      libjpegXbps
      ;

    applicationName = "Firefox";
    binaryName = "firefox";
    libName = "firefox";

    withFFmpeg = true;
    withGSSAPI = false;
    withALSA = true;
    withPipewire = true;
    withSndio = true;
    withJACK = true;

    requireSigning = true;
    allowAddonSideload = false;
  };

  meta = {
    description = "Mozilla Firefox binary from Void Linux aarch64-musl";
    homepage = "https://www.mozilla.org/firefox/";
    license = lib.licenses.mpl20;
    platforms = [ "aarch64-linux" ];
    mainProgram = "firefox";
  };
}
