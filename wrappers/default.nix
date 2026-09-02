{
  pkgs ? (import ../../.tack).nixpkgs,
  hostName ? null,
}:

# To nix run: nix run -f ~/dotfiles/nixos/wrappers <program>
{
  firefox = (import ./firefox { inherit pkgs; });
  urxvt = (import ./urxvt { inherit pkgs; });
  zsh = (import ./zsh { inherit pkgs; });
  fuzzel = (import ./fuzzel { inherit pkgs; });
  waybar-master = (import ./waybar { inherit pkgs hostName; });
  mango = (import ./mango { inherit pkgs; });
  kanshi = (import ./kanshi { inherit pkgs hostName; });
  niri = (import ./niri { inherit pkgs; });
  ashell = (import ./ashell { inherit pkgs; });
}
