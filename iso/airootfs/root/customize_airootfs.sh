#!/usr/bin/env bash
# customize_airootfs.sh — exécuté par mkarchiso EN ROOT dans le chroot,
# juste APRÈS l'installation des paquets (donc après le passage de pacman
# qui écrase /etc/pacman.conf avec celui du paquet `pacman`).
# C'est ici qu'on dépose nos fichiers système, de façon déterministe.
set -euo pipefail

echo "[customize] dépôts, miroir, locale et nettoyage…"

# --- 1. /etc/pacman.conf : live et cible strictement identiques ----------
# (avant : le live gardait le pacman.conf d'Arch, sans bob-core, avec un
#  mirrorlist entièrement commenté → « pacman -S » ne trouvait aucun serveur)
install -Dm644 /dev/stdin /etc/pacman.conf <<'PCONF'
# /etc/pacman.conf — BobOS
[options]
HoldPkg           = pacman glibc
Architecture      = auto
Color
ILoveCandy
CheckSpace
VerbosePkgLists
SigLevel          = Required DatabaseOptional
LocalFileSigLevel = Optional
ParallelDownloads = 5

[core]
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch

[extra]
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch

[multilib]
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch

# bob-core EN DERNIER : les paquets identiques vont à extra (versions
# cohérentes et complètes), bob-core ne sert que ses paquets uniques et ses
# versions plus récentes. Le dépôt est en HTTPS, mais n'est pas signé.
[bob-core]
SigLevel = Never
Server = https://bob.xem.yt/os/x86_64
PCONF

# --- 2. Une vraie liste de miroirs (plus de « tout commenté ») ------------
install -Dm644 /dev/stdin /etc/pacman.d/mirrorlist <<'MIRRORS'
## Arch Linux — miroirs BobOS
## Serveur utilisé par défaut (rapide, CDN mondial)
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch

## Repli si geo.mirror est injoignable (conservés, uncomment si besoin)
#Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
#Server = https://ftp.acc.umu.se/mirror/archlinux/$repo/os/$arch
#Server = https://mirror.freedif.org/archlinux/$repo/os/$arch
MIRRORS

# --- 3. Locale française (avant : LANG non défini → zsh affichait <00e9>) --
if ! grep -q '^fr_FR.UTF-8 UTF-8' /etc/locale.gen 2>/dev/null; then
    printf 'fr_FR.UTF-8 UTF-8\n' >> /etc/locale.gen
fi
locale-gen >/dev/null 2>&1 || echo "[customize] locale-gen a échoué (non bloquant)"
install -Dm644 /dev/stdin /etc/locale.conf <<'LOCALE'
LANG=fr_FR.UTF-8
LOCALE

# --- 4. Nettoyage : scripts retirés de BobOS (ils restent dans git) ------
# (bob-fetch téléchargeait des paquets non signés depuis une page HTML ;
#  bobos-install-cli était un second installateur, source de bugs)
rm -f /usr/bin/bob-fetch /usr/bin/bobos-install-cli

# --- 4b. Un seul lanceur d'installateur dans le menu ----------------------
# Le paquet Calamares installe calamares.desktop, qui affiche « Install System »
# À CÔTÉ de « Installer BobOS » (qui, lui, règle QT_QPA_PLATFORM et le journal).
# On le masque : un seul chemin d'installation, le nôtre.
if [[ -f /usr/share/applications/calamares.desktop ]]; then
    if ! grep -q '^NoDisplay=' /usr/share/applications/calamares.desktop; then
        printf '\nNoDisplay=true\n' >> /usr/share/applications/calamares.desktop
    fi
    echo "[customize] calamares.desktop masqué (NoDisplay=true)"
fi

# --- 5. Miroirs à jour automatiquement (au boot du live) ------------------
ln -sf /usr/lib/systemd/system/reflector.timer \
      /etc/systemd/system/timers.target.wants/reflector.timer 2>/dev/null || true

echo "[customize] terminé."
