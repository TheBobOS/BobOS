# BobOS — Zsh + Powerlevel10k + solde BobCoin

# Powerlevel10k
if [[ -f /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme ]]; then
  source /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme
fi
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

# Prompt custom : solde BobCoin en temps réel
POWERLEVEL9K_LEFT_PROMPT_ELEMENTS+=(custom_bobcoin)
POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS+=(custom_bobcoin)
POWERLEVEL9K_CUSTOM_BOBCOIN='bobcoin --prompt'
POWERLEVEL9K_CUSTOM_BOBCOIN_FOREGROUND='#00ffcc'

# Alias BobOS
alias ll='eza -la --icons'
alias cat='bat'
alias fixme='bob fixme'
alias update='bob-update'
alias fetch='bob-fetch'

# Plugins / autoloads bob
[[ -f /etc/zsh/bob/aliases.zsh ]] && source /etc/zsh/bob/aliases.zsh

# yazi : y <répertoire>
y() {
  local tmp="$(mktemp -t yazi-cwd.XXXXXX)" cwd
  yazi "$@" --cwd-file="$tmp"
  IFS= read -r -d '' cwd < "$tmp" 2>/dev/null || true
  [[ "$cwd" != "$PWD" ]] && cd -- "$cwd"
  rm -f -- "$tmp"
}

# Bienvenue
[[ -f /etc/motd ]] && cat /etc/motd

# Wizard premier boot (seulement au login tty — jamais dans un terminal ouvert)
if [[ -z "${WAYLAND_DISPLAY:-}" && -z "${DISPLAY:-}" && ! -f ~/.config/bobos/setup-done ]]; then
  bob-setup || true
fi

# Lancement automatique de Hyprland sur tty1 (live BobOS)
if [[ -z "${WAYLAND_DISPLAY:-}" && "${XDG_VTNR:-}" == "1" ]] && command -v Hyprland &>/dev/null; then
  # start-hyprland = lanceur recommandé (env/session) ; fallback Hyprland brut
  if command -v start-hyprland &>/dev/null; then
    exec start-hyprland
  else
    exec Hyprland
  fi
fi
