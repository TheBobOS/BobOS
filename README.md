# BobOS

OS de l'espace. Basé sur Arch Linux (rolling) + kernel Xanmod + Hyprland,
livré en ISO bootable avec installateur graphique (Calamares) — tout est
cuit dans l'image : aucune installation réseau nécessaire.

## Caractéristiques

- **Base** : Arch Linux + `linux-xanmod` (+ kernel stock en secours pour les
  vieux CPU sans AVX2, ex. HP Pavilion p6)
- **Desktop** : Hyprland (Wayland) + waybar (icônes Papirus) + wofi + kitty
- **Installateur** : Calamares hors-ligne (effacer le disque présélectionné,
  GRUB BIOS + UEFI, ext4)
- **Premier boot** : autologin tty1, `bob-setup` (versions de la stack dev),
  sélecteur de résolution manuel dans Paramètres → Écran
- **Apps préinstallées** : Firefox, Steam, VS Code, Discord, OBS, mpv, Okular,
  Kate, Thunar, htop, cmatrix, neofetch (wrapper fastfetch)
- **Stack dev** : Python, pip, Node.js, Bun, Docker (+ compose)
- **Sécurité** : `doas` (`/etc/doas.conf` NOPASSWD pour le wheel), polkit
  pour éteindre/gérer le réseau sans mot de passe, pare-feu nftables
- **Dépôt custom** `[bob-core]` (hyprland, xanmod, p10k, bob-*)

## Structure

```
bobos/
├── build.sh            # build complet : Calamares → keyring → ISO (sudo)
├── iso/                # profil archiso
│   ├── airootfs/       # contenu de l'image (scripts, configs, skel)
│   ├── packages.x86_64 # paquets de l'ISO
│   ├── pacman.conf     # repos (bob-core EN DERNIER, SigLevel = Never)
│   └── profiledef.sh   # perms des fichiers (chown/chmod explicites !)
├── calamares/          # PKGBUILD de Calamares (compilé au build)
├── packages/           # PKGBUILDs des paquets custom bob-*
├── plan-summary.md     # plan de conception
└── out/                # ISO générée + log (ignoré par git)
```

## Build

Nécessite une machine Arch (ou Arch-adjacente) avec `archiso` et le sudo :

```
sudo ./build.sh
```

Le résultat atterrit dans `out/bobos-<date>-x86_64.iso`.
Calamares est compilé une seule fois puis mis en cache dans
`/var/tmp/bobos-calamares/` ; le cache de paquets (`/var/tmp/bobos-pkgcache/`)
est conservé d'un build à l'autre.

## Tester en VM

```
qemu-system-x86_64 -m 8192 -smp 4 -enable-kvm \
  -drive file=out/bobos-*.iso,format=raw,media=cdrom
```

Disque à ≥ **20 Go** pour l'installation (racine ~8,7 Go décompressée).

## Dépôt bob-core

À ajouter dans `/etc/pacman.conf` **après** vos dépôts officiels :

```
[bob-core]
SigLevel = Never
Server = https://bob.xem.yt/os/x86_64
```

```
sudo pacman -Syy
sudo pacman -S bob-os-meta   # toute la stack BobOS d'un coup
```

Ou les paquets un par un : `bob`, `bobcoin`, `crepes-galactiques`, …

> `SigLevel = Never` ne concerne **que** `[bob-core]` : les dépôts Arch
> gardent `Required DatabaseOptional`.

## Licence

BobOS est sous licence [GPL-3.0](LICENSE).
