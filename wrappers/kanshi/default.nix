{
  pkgs,
  hostName ? null,
  ...
}:
let
  config =
    if hostName == "necoarc" then
      builtins.toString ./config-necoarc
    else if hostName == "necomac" then
      builtins.toString ./config-necomac
    else
      "";
in
pkgs.symlinkJoin {
  name = "kanshi-wrapped-${pkgs.kanshi.version}";
  paths = [ pkgs.kanshi ];
  nativeBuildInputs = [ pkgs.makeWrapper ];

  postBuild = ''
    wrapProgram "$out/bin/kanshi" \
      --add-flags "-c ${config}"
  '';

  meta.mainProgram = "kanshi";
}
