# BobOS — Zsh + Powerlevel10k + solde BobCoin

# --- Historique (sans ça, zsh ne garde RIEN d'une session à l'autre) -------
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS
setopt AUTO_CD INTERACTIVE_COMMENTS

# --- Complétion (zsh-completions était installé pour rien) ----------------
autoload -Uz compinit && compinit -d "$HOME/.cache/zcompdump" 2>/dev/null
if [[ -r /usr/share/zsh/site-functions ]]; then
    fpath=(/usr/share/zsh/site-functions $fpath)
fi
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

# --- Touches du terminal (Début/Fin/Suppr) ---------------------------------
bindkey -e
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[[3~' delete-char
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word
bindkey '^[[3;5~' backward-kill-word   # Ctrl+Suppr

# --- Powerlevel10k --------------------------------------------------------
if [[ -f /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme ]]; then
  source /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme
fi
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

# --- Prompt : solde BobCoin (UNE seule fois, à gauche) --------------------
POWERLEVEL9K_LEFT_PROMPT_ELEMENTS+=(custom_bobcoin)
POWERLEVEL9K_CUSTOM_BOBCOIN='bobcoin --prompt'
POWERLEVEL9K_CUSTOM_BOBCOIN_FOREGROUND='#00ffcc'

# --- Alias BobOS ----------------------------------------------------------
alias ll='eza -la --icons --group-directories-first'
alias cat='bat --paging=never'
alias fixme='bob fixme'
alias update='bob-update'
alias lock='hyprlock'

# --- Plugins zsh ----------------------------------------------------------
[[ -r /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && \
  source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
[[ -r /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \
  source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# --- Plugins / aliases Bob ------------------------------------------------
[[ -r /etc/zsh/bob/aliases.zsh ]] && source /etc/zsh/bob/aliases.zsh

# yazi : y <répertoire> puis on suit le cwd dans lequel on a quitté
y() {
  local tmp="$(mktemp -t yazi-cwd.XXXXXX)" cwd
  yazi "$@" --cwd-file="$tmp"
  IFS= read -r -d '' cwd < "$tmp" 2>/dev/null || true
  [[ "$cwd" != "$PWD" ]] && cd -- "$cwd"
  rm -f -- "$tmp"
}

# NB : le motd est affiché par pam_motd à la connexion tty. Ne PAS le
# réafficher ici (avant : double affichage, et à travers `bat`, encadré et
# numéroté, à chaque nouveau terminal kitty).

# --- Wizard premier boot (tty uniquement, une seule fois) -----------------
if [[ -z "${WAYLAND_DISPLAY:-}" && -z "${DISPLAY:-}" && ! -f ~/.config/bobos/setup-done ]]; then
  bob-setup || true
fi

# --- Hyprland démarre sur tty1 (live BobOS) -------------------------------
if [[ -z "${WAYLAND_DISPLAY:-}" && "${XDG_VTNR:-}" == "1" ]] && command -v Hyprland &>/dev/null; then
  # start-hyprland = lanceur recommandé (env/session) ; fallback Hyprland brut
  if command -v start-hyprland &>/dev/null; then
    exec start-hyprland
  else
    exec Hyprland
  fi
fi
