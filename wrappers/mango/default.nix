{pkgs}: let
  inherit (pkgs) lib;
  wlrootsNoX =
    (pkgs.wlroots_0_20.override {
      enableXWayland = false;
    }).overrideAttrs (old: {
      mesonFlags =
        builtins.filter (f: !(pkgs.lib.hasPrefix "-Dbackends=" f)) (old.mesonFlags or [])
        ++ ["-Dbackends=drm,libinput"];
    });

  scenefxNoX =
    (pkgs.scenefx.override {
      wlroots_0_20 = wlrootsNoX;
    }).overrideAttrs (old: {
      patches =
        (old.patches or [])
        ++ [
          (builtins.fetchurl {
            name = "scenefx-always-inline-musl.patch";
            url = "https://github.com/wlrfx/scenefx/commit/84648eb290c22f61dc58a9626c16b30f2177272f.patch";
            sha256 = "sha256:1wnryhfh92mvyh807638smp7ifrdbp49cyxsq8mjyiy97jvhmpiv";
          })
        ];
      mesonFlags = ["-Dexamples=false"];
    });

  mango = pkgs.mango.override {
    enableXWayland = false;
    wlroots_0_20 = wlrootsNoX;
    scenefx = scenefxNoX;
  };

  mangoSession = pkgs.writeShellScript "mango-session" ''
    ${lib.getExe' pkgs.util-linux "setsid"} \
      ${lib.getExe' pkgs.dbus "dbus-run-session"} -- \
        ${lib.getExe mango} \
        -c ${builtins.toString ./config.conf} &

    session=$!

    wait "$session"
    status=$?

    # Graceful shutdown of everything belonging to this desktop session.
    kill -TERM -- "-$session" 2>/dev/null || true
    ${lib.getExe' pkgs.busybox "sleep"} 0.2

    # Catch anything that ignored SIGTERM.
    kill -KILL -- "-$session" 2>/dev/null || true

    for _ in $(${lib.getExe' pkgs.busybox "seq"} 20); do
      ${lib.getExe' pkgs.util-linux "findmnt"} \
        -rn -M "$XDG_RUNTIME_DIR/doc" >/dev/null 2>&1 || break

      ${lib.getExe' pkgs.busybox "sleep"} 0.05
    done

    exit "$status"
  '';
in
  pkgs.symlinkJoin {
    name = "mango-wrapped-${mango.version}";
    paths = [mango];
    nativeBuildInputs = [pkgs.makeBinaryWrapper];
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

    passthru = {
      session = mangoSession;
    };

    meta.mainProgram = "mango";
  }
