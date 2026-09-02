{
  pkgs,
}:
let
  inherit (pkgs) lib;

  mango' = pkgs.mangowc;

  libinput = pkgs.libinput.override {
    udev = pkgs.libudev-zero;
    wacomSupport = false;
  };

  mango = mango'.override (
    o:
    let
      wlrootsAttr = lib.head (lib.filter (lib.hasPrefix "wlroots") (lib.attrNames o));
    in
    {
      inherit libinput;

      ${wlrootsAttr} = o.${wlrootsAttr}.override {
        inherit libinput;
      };
    }
  );
in
pkgs.symlinkJoin {
  name = "mango-wrapped-${mango.version}";
  paths = [ mango ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram "$out/bin/mango" \
      --add-flags "-c ${builtins.toString ./config.conf}"

    rm "$out/share/wayland-sessions/mango.desktop"

    cat > "$out/share/wayland-sessions/mango.desktop" <<EOF
    [Desktop Entry]
    Encoding=UTF-8
    Name=Mango
    DesktopNames=mango;wlroots
    Comment=mango WM
    Exec=${lib.getExe' pkgs.dbus "dbus-run-session"} -- $out/bin/mango
    Icon=mango
    Type=Application
    EOF
  '';
  meta.mainProgram = "mango";
}
