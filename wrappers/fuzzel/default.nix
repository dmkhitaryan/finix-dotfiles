{
  pkgs,
}:
pkgs.symlinkJoin {
  name = "fuzzel-wrapped-${pkgs.fuzzel.version}";
  paths = [ pkgs.fuzzel ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram "$out/bin/fuzzel" \
      --add-flags "--font=Iosevka" \
      --add-flags "--icon-theme=Adwaita"
  '';
  meta.mainProgram = "fuzzel";
}
