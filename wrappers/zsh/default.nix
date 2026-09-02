{ pkgs }:

let
  zdotdir = pkgs.writeTextDir ".zshrc" ''
    ${builtins.readFile ./.zshrc}
    source ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
  '';
in
pkgs.symlinkJoin {
  name = "zsh-wrapped-${pkgs.zsh.version}";
  paths = [
    pkgs.zsh
    pkgs.nix-zsh-completions
    pkgs.zsh-syntax-highlighting

    # For scripts:
    pkgs.ffmpeg
    pkgs.jq
    pkgs.yt-dlp

  ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram "$out/bin/zsh" \
      --set ZDOTDIR ${zdotdir} \
      --suffix PATH : "${pkgs.ffmpeg}/bin:${pkgs.jq}/bin:${pkgs.yt-dlp}/bin"
  '';
  meta.mainProgram = "zsh";
  shellPath = "/bin/zsh";
}
