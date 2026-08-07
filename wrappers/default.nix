{ pkgs ? (builtins.getFlake "/home/jagerroni/dotfiles").nixosConfigurations.necomac.pkgs }:

# To nix run: nix run -f ~/dotfiles/nixos/wrappers <program>
{
  firefox = (import ./firefox { inherit pkgs; }).default;
  urxvt = (import ./urxvt { inherit pkgs; }).default;
  zsh = (import ./zsh { inherit pkgs; }).default;
}
