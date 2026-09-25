# BobOS — aliases et plugins Bob (chargé par /etc/skel/.zshrc)

# garde martienne : intercepte rm -rf / avant que ça arrive
rm() {
    if printf '%s\n' "$@" | grep -qE '^\s*-\w*[rf]\w*\s+/$|^\s*/+\s*$'; then
        bob-say "rm -rf / ?!" || true
        echo "GARDE MARTIENNE : refusé." >&2
        return 1
    fi
    command rm "$@"
}

# raccourcis bob
alias bobup='bob-update'
alias bobfix='bob fixme'
alias bobfm='bob dotfiles apply'
alias slots='bob-slot-machine'
alias eq='bob-martian-eq on'
alias wall='bob-firewall'
alias say='bob-say'
alias bc='bobcoin balance'

# 'mine' maj le fichier last-mine pour bob-app-killer
mine() {
    bobcoin mine
    if command -v doas &>/dev/null; then
        doas touch /var/lib/bobcoin/last-mine 2>/dev/null || true
    else
        doas touch /var/lib/bobcoin/last-mine 2>/dev/null || true
    fi
}
