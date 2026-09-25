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

## Mettre à jour son OS

Trois portes d'entrée, **un seul** moteur de mise à jour (`bob-update`) :

| Où | Comment |
|---|---|
| **Clic dans le menu d'applications** | « Mettre à jour BobOS » → menu wofi avec la liste des paquets → confirmation |
| **Clic sur `⬆ N` dans la barre** | idem (le compteur est actualisé toutes les 5 min) |
| **Dans Paramètres** | « Mises à jour — mise à jour graphique » |
| **Terminal** | `bobos-update` (graphique), `bob-update` (interactif), ou `bobos-update --check` (juste le nombre) |

Le système **vérifie tout seul une fois par jour** (minuteur systemd, à 12 h)
et au démarrage de la session : s'il y a des mises à jour, tu reçois une
notification et le compteur apparaît dans la barre. Rien n'est installé sans
ton accord.

La mise à jour elle-même lit les **news Arch** d'abord, met à jour le
**trousseau de clés** avant les paquets (sinon la MAJ échoue quand Arch change
ses clés), garde `pacman` interactif, montre les `.pacnew` et cleans le cache
en gardant 2 versions par paquet (c'est ce qui permet à `bob fixme` de
revenir en arrière).

> Sur une VM, la disponibilité des MAJ dépend du réseau : sans réseau,
> `bobos-update` affiche « tout est à jour » (les bases ne sont pas
> rafraîchies, rien n'est installé).

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

## Machines virtuelles

BobOS fonctionne **sur toutes les VM** : les pilotes nécessaires sont déjà
dans le noyau, il n'y a rien à installer.

| Hyperviseur | Ce qui est déjà là | À installer ? |
|---|---|---|
| **VirtualBox** | `vboxvideo` (accélération 3D) et `vboxsf` (dossiers partagés) sont **dans le noyau** ; les modes d'écran sont fournis par le pilote DRM | rien pour que ça marche. Guest Additions = en plus (redimensionnement auto de la fenêtre, presse-papiers partagé) → voir plus bas |
| **QEMU / KVM / Proxmox** | `virtio_*` est intégré au noyau (GPU, réseau, disque) | rien ; `qemu-guest-agent` est déjà dans l'ISO (gel/dégel des FS à l'extinction, commandes depuis l'hôte) |
| **VMware** (Workstation, Fusion, ESXi) | `vmwgfx` (affichage SVGA) et `vmxnet3` (réseau paravirtuel) sont **dans le noyau** | rien pour booter et avoir le bureau ; `open-vm-tools` est **déjà dans l'ISO** (souris absolue, dossiers partagés, presse-papiers) |
| **Hyper-V / Azure / GCP / AWS** | tout est dans le noyau | rien (bien utiliser UEFI + GPT, et une VM **64 bits**) |

`bobfetch` affiche l'hyperviseur détecté et l'intégration disponible : c'est la
première chose à regarder quand « ça marche pas ».

### Notes selon l'hyperviseur

**VirtualBox** — dossier partagé : le module `vboxsf` est dans le noyau, mais
le montage se fait avec `mount -t vboxsf` (ou via l'agent, voir plus bas).
L'accélération 3D passe par `vboxvideo` : elle exige *3D Acceleration* activée
dans la VM, sinon Hyprland bascule en rendu logiciel (lisible mais mou).
Le presse-papiers partagé demande l'agent (AUR, voir plus bas).

**VMware** — ça marche : le noyau fournit `vmwgfx` (affichage) et `vmxnet3`
(réseau), donc le bureau s'affiche et le réseau fonctionne sans installation.
Deux points à connaître :

- **Souris** : sans agent, la souris est une souris absolue USB (fine) ou
  relative qui « colle » aux bords si tu as laissé *Virtual mouse device*
  désactivé. BobOS embarque `open-vm-tools` et l'active sur le système
  installé, donc la souris absolue est gérée. Si le pointeur reste collé :
  dans les réglages de la VM, mets *Devices → Mouse → Virtual device → Show
  cursor at edges* (ou désactive la souris virtuelle).
- **Dossiers partagés / presse-papiers** : ils passent par `vmhgfs` et
  `vmtoolsd`. `vmtoolsd` est activé chez nous ; si les dossiers
  `/mnt/hgfs` restent vides, c'est que le noyau n'a pas `vmhgfs` en module
  (rare) : dans ce cas, passe par un partage réseau (sshfs/samba) — le
  réseau, lui, fonctionne.
- **3D** : dépend de la config 3D de la VM et du pilote hôte ; on ne peut pas
  le garantir, mais le rendu logiciel reste utilisable.

**KVM / QEMU / Proxmox** — c'est la combination la plus confortable :
`virtio-gpu` pour l'affichage, `qemu-guest-agent` (déjà dans l'ISO) pour que
l'hôte puisse geler proprement les systèmes de fichiers à l'extinction.

### Réglages recommandés

**VirtualBox** (et c'est aussi le plus souvent la cause des échecs) :

| Réglage | Valeur |
|---|---|
| Type / Version | **Linux** → **Other/Unknown (64-bit)** (une VM 32 bits ne boot pas, cf. message i686 ci-dessus) |
| Mémoire | 4096 Mo mini (8192 confortable, le live charge Firefox/Steam en RAM) |
| Processeurs | 2–4, et **cocher l'accélération matérielle** (VT-x/AMD-V) |
| Écran | 1280x800 ou 1920x1080 ; **Display/Graphique → 3D Acceleration activé** |
| Stockage | disque **dynamique de 40 Go** (l'installateur refuse en dessous de 20 Go) |
| Réseau | NAT par défaut ;bridge en pont seulement si besoin |

BobOS ne force jamais un mode d'écran que le pilote n'annonce pas : dans une
fenêtre de VM étroite (1280x800), il garde 1280x800 au lieu de forcer un
1080p hors plage qui donnerait un écran noir. Pour choisir à la main :
Paramètres → Écran, ou `bobos-res`.

**QEMU / KVM** :

```
qemu-system-x86_64 \
  -cpu host -m 8192 -smp 4 \
  -enable-kvm \
  -device virtio-gpu-pci -vga virtio \
  -drive file=bobos.iso,format=raw,if=virtio,media=cdrom \
  -drive file=vm.qcow2,format=qcow2,if=virtio \
  -audiodev none -display gtk,show-cursor=on
```

`-cpu host` (ou `qemu64`) : ne jamais `-cpu i686`/`pentium3`, ça force le
32 bits. `-vga virtio` + `virtio-gpu` = accélération matérielle ; sans ça
QEMU marche quand même, en logiciel.

### Guest Additions VirtualBox (optionnel)

Ce qui manque sans les Additions, c'est **uniquement l'agent utilisateur**
(redimensionnement auto de la fenêtre, presse-papiers partagé, montage
automatique des dossiers). L'affichage, l'accélération et les dossiers
partagés fonctionnent déjà. Comme Arch ne fournit plus
`virtualbox-guest-utils` (sa dépendance `VIRTUALBOX-GUEST-MODULES` n'a aucun
fournisseur dans les dépôts officiels), il faut le compiler depuis l'AUR :

```bash
git clone https://aur.archlinux.org/virtualbox-guest-dkms.git
cd virtualbox-guest-dkms && makepkg -si      #DKMS + vboxvideo
sudo pacman -S virtualbox-guest-utils
systemctl enable vboxservice && sudo usermod -aG vboxsf $USER
```

C'est volontairement **hors ISO** : ces modules DKMS sont recompilés à chaque
mise à jour de noyau, et on ne veut pas d'un module tiers qui casse le boot.

## Licence

BobOS est sous licence [GPL-3.0](LICENSE).

