{
pkgs,
}:
pkgs.symlinkJoin {
  name = "mango-wrapped-${pkgs.mango.version}";
  paths = [ pkgs.mango ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram "$out/bin/mango" \
      --add-flags "-c ${./config.conf}"
  '';
  meta.mainProgram = "mango";
}
