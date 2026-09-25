# BobOS — aliases et fonctions Bob (chargé par /etc/skel/.zshrc)

# --- Garde martienne -------------------------------------------------------
# L'ancien test ne bloquait que « rm -rf / » : « rm -rf /* » et « rm -rf ~ »
# passaient (vérifié). On bloque ce qui détruit vraiment un système.
rm() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --preserve-root) return 0 ;;   # garde GNU : rm gère / lui-même
      # NOTE : en zsh, un « ~ » nu dans un motif de case est développé en
      # chemin d'accueil et ne matche donc JAMAIS la chaîne « ~ » : il faut
      # l'échapper (\~) ou lemettre entre quotes.
      /*|\~|~/*|\$HOME|\$HOME/*|/home|/home/*|/etc|/etc/*|/usr|/usr/*|/var|/var/*|/boot|/boot/*|.)
        bob-say "attention, destructive command" >/dev/null 2>&1 || true
        print -u2 "GARDE MARTIENNE : « rm $arg » refusé."
        return 1
        ;;
    esac
  done
  command rm "$@"
}

# --- Raccourcis ------------------------------------------------------------
alias bobup='bob-update'
alias bobfix='bob fixme'
alias bobfm='bob dotfiles apply'
alias slots='bob-slot-machine'
alias eq='bob-martian-eq on'
alias bfw='bob-firewall'      # « wall » et « bc » gardent leur vrai sens
alias bbc='bobcoin balance'
alias shot='bobos-shot region'

# --- minage : c'est bobcoin qui écrit un VRAI horodatage -------------------
# (avant : `doas touch` ne changeait que la date de modification, le fichier
# restait vide → bob-app-killer fermait les apps toutes les heures)
mine() {
  bobcoin mine
}
