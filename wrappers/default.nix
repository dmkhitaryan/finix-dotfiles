{ pkgs ? (builtins.getFlake "/home/jagerroni/dotfiles").nixosConfigurations.necomac.pkgs }:

# To nix run: nix run -f ~/dotfiles/nixos/wrappers <program>
{
  firefox = (import ./firefox { inherit pkgs; });
  urxvt = (import ./urxvt { inherit pkgs; });
  zsh = (import ./zsh { inherit pkgs; });
  fuzzel = (import ./fuzzel { inherit pkgs; });
  waybar-master = (import ./waybar { inherit pkgs; });
  mango = (import ./mango { inherit pkgs; });
}
