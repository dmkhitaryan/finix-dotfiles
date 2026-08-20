{
  pkgs,
}:
let

  udevApi =
    if config.services.gardendevd.enable then
      pkgs.libudev-garden
    else if config.services.mdevd.enable || config.services.keventd.enable then
      pkgs.libudev-zero
    else
      null;

  overrideAttrs = lib.optionalAttrs (udevApi != null) {
    eudev = udevApi;

    libinput = pkgs.libinput.override {
      udev = udevApi;
      wacomSupport = false;
    };

    withSystemd = false;

    niri = pkgs.niri.override overrideAttrs;
in
pkgs.symlinkJoin {
  name = "niri-wrapped-${niri.version}";
  paths = [ niri ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram "$out/bin/niri" \
      --add-flags "-c ${./config.kdl}"

    rm "$out/share/wayland-sessions/niri.desktop"

    cat > "$out/share/wayland-sessions/niri.desktop" <<EOF
    [Desktop Entry]
    Encoding=UTF-8
    Name=Niri
    DesktopNames=Niri    Comment=mango WM
    Exec=${lib.getExe' pkgs.dbus "dbus-run-session"} -- $out/bin/niri-session
    Icon=niri
    Type=Application
    EOF
  '';
  meta.mainProgram = "niri";
}
