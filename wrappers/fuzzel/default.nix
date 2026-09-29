{
  pkgs,
}:
let
  fuzzel = pkgs.fuzzel.override {
    svgBackend = "nanosvg";
  };
in
pkgs.symlinkJoin {
  name = "fuzzel-wrapped-${pkgs.fuzzel.version}";
  paths = [ fuzzel ];
  nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
  postBuild = ''
    wrapProgram "$out/bin/fuzzel" \
      --add-flags "--font=CozetteVector:size=15" \
      --add-flags "--icon-theme=Adwaita" \
  '';
  meta.mainProgram = "fuzzel";
}
