{
  pkgs,
}:
pkgs.symlinkJoin {
  name = "ashell-wrapped-${pkgs.ashell.version}";
  paths = [ pkgs.ashell ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram "$out/bin/ashell" \
      --add-flags "-c ${builtins.toString ./config.toml}"
  '';
  meta.mainProgram = "ashell";
}
