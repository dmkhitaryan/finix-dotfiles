{
  pkgs,
}:
let
  inherit (pkgs) lib;
  wlrootsNoX = pkgs.wlroots_0_20.override {
    enableXWayland = false;
  };

  scenefxNoX = pkgs.scenefx.override {
    wlroots_0_20 = wlrootsNoX;
  };

  mango = pkgs.mango.override {
    enableXWayland = false;
    wlroots_0_20 = wlrootsNoX;
    scenefx = scenefxNoX;
  };

  mangoSession = pkgs.writeShellScript "mango-session" ''
    ${lib.getExe' pkgs.dbus "dbus-run-session"} -- \
      ${lib.getExe mango} \
      -c ${builtins.toString ./config.conf}

    status=$?

    for _ in $(${lib.getExe' pkgs.coreutils "seq"} 20); do
    ${lib.getExe' pkgs.util-linux "findmnt"} \
      -rn -M "$XDG_RUNTIME_DIR/doc" >/dev/null 2>&1 || break

    ${lib.getExe' pkgs.coreutils "sleep"} 0.05
    done

    exit "$status"
  '';
in
pkgs.symlinkJoin {
  name = "mango-wrapped-${mango.version}";
  paths = [ mango ];
  nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
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
    Exec=${mangoSession}
    Icon=mango
    Type=Application
    EOF
  '';
  meta.mainProgram = "mango";
}
