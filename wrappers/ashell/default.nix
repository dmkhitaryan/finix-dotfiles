{
  pkgs,
}:
pkgs.symlinkJoin {
  name = "ashell-wrapped-${pkgs.ashell.version}";
  paths = [ pkgs.ashell ];
  nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
  postBuild = ''
    wrapProgram "$out/bin/ashell" \
      --add-flags "-c ${builtins.toString ./config.toml}"
  '';
  meta.mainProgram = "ashell";
}
