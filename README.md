# BobOS

OS de l'espace. Basé sur Arch Linux (rolling) + kernel Xanmod + Hyprland,
livré en ISO bootable avec installateur graphique (Calamares) — tout est
cuit dans l'image : aucune installation réseau nécessaire.

## Caractéristiques

- **Base** : Arch Linux + `linux-xanmod` (+ kernel stock en secours pour les
  vieux CPU sans AVX2, ex. HP Pavilion p6)
- **Desktop** : Hyprland (Wayland) + waybar (icônes Papirus) + wofi + kitty
- **Installateur** : Calamares hors-ligne (effacer le disque présélectionné,
  GRUB BIOS + UEFI, ext4, LUKS proposé, choix de la langue / du fuseau /
  du clavier), retiré du système installé
- **Premier boot** : plus d'autologin sur la cible (mot de passe demandé),
  verrouillage automatique (hypridle/hyprlock), `bob-setup` (versions de la
  stack dev), sélecteur de résolution manuel dans Paramètres → Écran
- **Apps préinstallées** : Firefox, Steam, VS Code, Discord, OBS, mpv, Okular,
  Kate, Thunar, htop, cmatrix, `bobfetch` (infos système, logo BobOS)
- **Snake au démarrage** : un `bob-snake` s'ouvre dans son terminal quand le
  bureau arrive (`SUPER+SHIFT+S` pour rejouer, `SUPER+SHIFT+I` pour
  `bobfetch`)
- **Commandes** : `bobfetch`, `bob-snake`, `bobfire…`, `shutdown` (éteint en
  disant « À plus dans l'bus »), `bob-*` pour le reste
- **Stack dev** : Python, pip, Node.js, Bun, Docker (+ compose)
- **Bureau complet** : notifications (mako), captures (grim/slurp), volume
  (pavucontrol), Bluetooth, veille/hibernation, Nerd Font + emoji, portail
  Hyprland (partage d'écran), Intel/AMD/NVIDIA (NVIDIA via DKMS)
- **Sécurité** : `doas` mot de passe demandé sur la cible, polkit en liste
  blanche, LUKS proposé, pare-feu nftables à deux profils (public strict /
  maison avec découverte LAN), Quad9 en DoT, microcode CPU
- **Dépôt custom** `[bob-core]` (linux-xanmod, p10k, bob-*)

## Structure

```
bobos/
├── build.sh            # build complet : vérifs → Calamares (paquet) → ISO
├── iso/                # profil archiso
│   ├── airootfs/       # contenu de l'image (scripts, configs, skel)
│   ├── packages.x86_64 # paquets de l'ISO
│   ├── pacman.conf     # dépôts (bob-core EN DERNIER, SigLevel = Never)
│   ├── profiledef.sh   # perms des fichiers (chown/chmod explicites !)
│   └── syslinux, efiboot
├── calamares/          # PKGBUILD de Calamares (compilé au build)
├── packages/           # PKGBUILDs des paquets custom bob-*
├── plan-summary.md     # plan de conception
├── RAPPORT-AUDIT.md    # audit complet (62 constats) + plan d'action
└── out/                # ISO + logs + sommes (ignoré par git)
```

## Build

Nécessite une machine Arch (ou Arch-adjacente) avec `archiso` et le sudo :

```
sudo ./build.sh
```

Le résultat atterrit dans `out/bobos-<date>-x86_64.iso`, avec son
`build-<horodatage>.log` et une somme SHA-256.

Avant de lancer mkarchiso, le build **vérifie** (au lieu de le découvrir après
40 minutes de compilation) :

- la syntaxe de tous les scripts BobOS (`bash -n`, `zsh -n` pour le shell) ;
- `visudo -cf` sur le fichier sudoers et `doas -C` sur doas.conf ;
- `nft -c -f` sur les règles du pare-feu ;
- le YAML de toute la configuration Calamares ;
- l'absence de doublon dans la liste de paquets ;
- que tout exécutable de l'airootfs est bien épinglé dans `profiledef.sh`
  (sans quoi mkarchiso le recopie en 0644 → « Permission denied ») ;
- que l'ISO contient bien `squashfs-tools` (sans quoi l'installateur plante).

Calamares (absent des dépôts Arch) est compilé une fois dans un chroot jetable
— l'hôte n'est jamais modifié — puis servi par un dépôt **local** `file://`
pendant le build : il entre dans l'image comme un vrai paquet, ce qui veut dire
qu'il est mis à jour et désinstallable par pacman, et que le dépôt git ne
contient plus 359 binaires.

Le cache de Calamares est dans `/var/tmp/bobos-calamares/`, celui des paquets
dans `/var/tmp/bobos-pkgcache/` : les deux sont conservés d'un build à l'autre.

## Tester en VM

```
qemu-system-x86_64 -m 8192 -smp 4 -enable-kvm \
  -drive file=out/bobos-*.iso,format=raw,media=cdrom
```

Disque à ≥ **20 Go** pour l'installation (racine ~8,7 Go décompressée).

### « This kernel requires an x86-64 CPU, but only detected an i686 CPU »

Ce message **ne vient pas de BobOS** : c'est le noyau 64 bits qui refuse de
démarrer parce que le processeur qu'il voit est un **i686**. Dans la quasi
totalité des cas, le problème est la machine virtuelle, pas le PC :

| Où | Quoi faire |
|---|---|
| **VirtualBox** | La VM a été créée en 32 bits. *Configuration → Général → Type* = **Linux**, *Version* = **Other/Unknown (64-bit)**. Si la liste ne propose que du 32 bits, il faut activer la virtualisation matérielle (VT-x/AMD-V) dans le BIOS du PC **et** cocher *Système → Accélération → Nested Paging + VT-x/AMD-V*. Recréer la VM marche aussi (c'est le plus simple). |
| **QEMU/KVM** | `-cpu host` ou `-cpu qemu64` (un `-cpu i686`/`pentium3` force le 32 bits). |
| **PC réel (Lenovo…)** | L'ISO démarre sur **tout** x86-64. Si ça échoue quand même : désactivez *CSM / Legacy Boot* dans le BIOS et rebootez en UEFI, ou à l'inverse expressez le disque en **GPT + UEFI**. |

## Dépôt bob-core

À ajouter dans `/etc/pacman.conf` **après** vos dépôts officiels :

```
[bob-core]
SigLevel = Never
Server = https://bob.xem.yt/os/x86_64
```

```
sudo pacman -Sy
sudo pacman -S bob-os-meta   # toute la stack BobOS d'un coup
```

Ou les paquets un par un : `bob`, `bobcoin`, `crepes-galactiques`, …

`bob-core` fournit notamment `linux-xanmod`, `linux-xanmod-headers` et
`zsh-theme-powerlevel10k-git`. Tout le reste vient des dépôts Arch.

Deux règles :

- `SigLevel = Never` ne concerne **que** `[bob-core]` : les dépôts Arch
  gardent `Required DatabaseOptional`.
- ⚠ Ce dépôt n'est **pas signé** (il fournit le noyau). Une compromission du
  serveur ou du domaine donnerait un paquet root à chaque machine au prochain
  `bob-update`. La correction prévue est un `bobos-keyring` + un dépôt signé
  (voir `RAPPORT-AUDIT.md`, SEC-02).

## Installation

- **Live** : root sans mot de passe et autologin (session jetable, c'est
  assumé), comme le live de n'importe quelle distribution.
- **Système installé** : `doas`/`sudo` **demandent le mot de passe**, il n'y a
  pas d'autologin, l'écran se verrouille tout seul (`SUPER+L`, hypridle) et le
  trousseau de clés pacman est créé sur la machine. Voir `bobos-target-fixes`.

## Licence

BobOS est sous licence [GPL-3.0](LICENSE).

