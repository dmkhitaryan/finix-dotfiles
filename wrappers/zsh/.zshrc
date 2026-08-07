# Created by newuser for 5.9

npins () {
    command npins "$@"
    if [[ "$1" == "update" ]]; then
        local old_nixpkgs_path=$(echo "$NIX_PATH" | grep -o 'nixpkgs=[^:]*' | cut -d= -f2)
        local nixpkgs_path=$(command npins -d "$HOME/dotfiles/npins" get-path nixpkgs)

        if [[ -n "$nixpkgs_path" && "$old_nixpkgs_path" != "$nixpkgs_path" ]]; then
            echo "Updating nixpkgs..."
            export NIX_PATH=$(echo "$NIX_PATH" | sed "s|nixpkgs=[^:]*|nixpkgs=$nixpkgs_path|")
            echo "Updated nixpkgs from $old_nixpkgs_path to $nixpkgs_path."
        fi
    fi
}

nrun () {
    command nix run -f "$HOME/dotfiles/nixos/wrappers" "$@"
}

playlist-fetcher() {
    "$HOME/dotfiles/scripts/playlist-fetcher.sh" "$@"
  }

lazy-splitter() {
    "$HOME/dotfiles/scripts/lazy-splitter.sh" "$@"
}

hacky-tiling() {
    "$HOME/dotfiles/scripts/hacky-tiling.sh" "$@"
}

command_not_found_handler() {
  command-not-found "$@"
}

alias nhb="nh os boot -f /home/kibter/dotfiles/nixos/system.nix"
alias nhs="nh os switch -f /home/kibter/dotfiles/nixos/system.nix"
alias nrs="sudo nixos-rebuild switch"
alias garmin="nix-shell /home/kibter/dotfiles/shells/gaming --run 'lutris'"

HISTSIZE=2000
SAVEHIST=2000
HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
mkdir -p "${HISTFILE:h}"

setopt APPEND_HISTORY
setopt INC_APPEND_HISTORY
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE

autoload -U compinit && compinit
autoload -U bashcompinit && bashcompinit
autoload -U colors && colors

bindkey -e

bindkey $'\e[3~' delete-char       # Delete
bindkey $'\e[7~' beginning-of-line # Home
bindkey $'\e[8~' end-of-line       # End
bindkey $'\e[D' backward-char      # Left
bindkey $'\e[C' forward-char       # Right
bindkey $'\e[A' up-line-or-history
bindkey $'\e[B' down-line-or-history

# Ctrl+Left / Ctrl+Right
bindkey -M emacs $'\eOd' backward-word
bindkey -M emacs $'\eOc' forward-word

# Shift+Left / Shift+Right
bindkey -M emacs $'\e[d' backward-char
bindkey -M emacs $'\e[c' forward-char

PROMPT='%F{magenta}%n@%m%f:%F{blue}%~%f > '

export XCURSOR_PATH="$HOME/.local/share/icons:$XCURSOR_PATH"


if [[ -o interactive ]] && [[ "$TERM" == rxvt-unicode* ]]; then
  clear
fi
