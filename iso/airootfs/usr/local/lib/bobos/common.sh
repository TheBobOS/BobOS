#!/usr/bin/env bash
# /usr/local/lib/bobos/common.sh — fonctions partagées par les scripts BobOS.
# À sourcer : source /usr/local/lib/bobos/common.sh
#
# Règle d'or : un entier lu depuis un fichier n'est JAMAIS évalué par le shell
# ($(( var )) exécute ce que contient var, et un indice de tableau peut même
# contenir $(commande) → élévation de privilèges). On valide donc toujours.

# read_int <fichier> [défaut] : entier ≥ 0, sinon la valeur par défaut (0).
# La valeur n'est jamais réinterprétée par bash.
read_int() {
    local v="${2:-0}"
    if [[ -r "$1" ]]; then
        local raw
        raw="$(tr -cd '0-9' < "$1" 2>/dev/null | cut -c1-18)"
        [[ -n "$raw" ]] && v="$raw"
    fi
    [[ "$v" =~ ^[0-9]{1,18}$ ]] || v=0
    printf '%s\n' "$v"
}

# log <message…> : préfixe homogène
log() { printf '[bobos] %s\n' "$*"; }
log_err() { printf '[bobos] %s\n' "$*" >&2; }

# require_root : élévation SANS le piège « exec cmd || fallback » (exec remplace
# le shell, le repli n'est jamais atteint). On teste d'abord, puis on exec.
require_root() {
    [[ $EUID -eq 0 ]] && return 0
    if command -v doas &>/dev/null && doas true 2>/dev/null; then
        exec doas -E -- "$0" "$@"
    fi
    if command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
        exec sudo -E -- "$0" "$@"
    fi
    if command -v pkexec &>/dev/null; then
        exec pkexec "$0" "$@"
    fi
    log_err "élévation impossible (doas / sudo / pkexec ?)"
    exit 1
}

# bobos_state_dir : état par utilisateur (jamais /var/lib world-writable)
bobos_state_dir() {
    printf '%s/bobos\n' "${XDG_STATE_HOME:-$HOME/.local/state}"
}

# now_epoch : horodatage en secondes
now_epoch() { date +%s; }
