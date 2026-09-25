# BobOS — Rapport d'audit complet

> **Date** : 25/09/2026 · **Commit analysé** : `5240d27` (branche `main`)
> **Image analysée** : `out/bobos-2026.09.24-x86_64.iso`, son dossier de travail `/var/tmp/bobos-work/` (encore présent) et `out/build.log`

---

## Sommaire

1. [Méthode et périmètre](#1-méthode-et-périmètre)
2. [Résumé](#2-résumé)
3. [Tableau récapitulatif](#3-tableau-récapitulatif)
4. [Sécurité](#4-sécurité)
5. [Installation et système installé](#5-installation-et-système-installé)
6. [Scripts `bob-*` / `bobos-*`](#6-scripts-bob---bobos-)
7. [Bureau et expérience utilisateur](#7-bureau-et-expérience-utilisateur)
8. [Réseau : pare-feu et DNS](#8-réseau--pare-feu-et-dns)
9. [Build, dépôt git et packaging](#9-build-dépôt-git-et-packaging)
10. [Features manquantes utiles](#10-features-manquantes-utiles)
11. [Plan d'action priorisé](#11-plan-daction-priorisé)
12. [Points forts à conserver](#12-points-forts-à-conserver)
13. [Annexe : checklist de validation en VM](#13-annexe--checklist-de-validation-en-vm)

---

## 1. Méthode et périmètre

**Ce qui a été fait**

- Lecture complète de tous les fichiers propres à BobOS : `build.sh`, profil archiso (`iso/profiledef.sh`, `iso/pacman.conf`, `iso/packages.x86_64`, syslinux, systemd-boot), les 21 scripts de `usr/bin` et `usr/local/bin`, les unités systemd, la configuration Calamares, les dotfiles de `/etc/skel`, le pare-feu, le DNS, polkit, doas et sudo, ainsi que les PKGBUILDs.
- Contrôle sur **l'image réellement construite** le 24/09 : le dossier `/var/tmp/bobos-work/x86_64/airootfs` était encore sur le disque. Ce contrôle a confirmé plusieurs bugs qui ne se voient pas dans les sources seules (trousseau pacman absent, modules NVIDIA, locale, polices…).
- Lecture du journal du dernier build (`out/build.log`, lignes 32266 à la fin).
- Tests reproduits dans un bac à sable :
  - `visudo -cf` sur `sudoers.d/bobos` : **en échec** ;
  - injection arithmétique bash dans `bob-app-killer` : **exécution de code confirmée** ;
  - regex de la « garde martienne » `rm` : **contournable** ;
  - `nft -c -f` sur le pare-feu : **erreur de syntaxe**, le pare-feu ne se charge jamais.

**Ce qui n'a pas été fait**

- Aucun boot en VM ni aucune installation réelle.
- Pas de ShellCheck (l'outil n'est pas installé sur la machine).
- L'API Lua d'Hyprland n'a pas été vérifiée.
- Les 359 fichiers Calamares compilés et commités dans le dépôt (code upstream) n'ont pas été audités ligne à ligne.

Les points marqués **(à confirmer)** s'appuient sur la documentation, pas sur un test.

**Légende de sévérité**

| Niveau | Signification |
|---|---|
| 🔴 **Critique** | Faille exploitable, système inutilisable ou destruction de données |
| 🟠 **Élevé** | Fonctionnalité majeure cassée ou risque sérieux |
| 🟡 **Moyen** | Bug gênant, fragilité, risque limité |
| 🔵 **Faible** | Qualité, cosmétique, dette technique |

---

## 2. Résumé

BobOS se présente comme un OS humoristique, mais **il s'installe réellement sur disque** et reçoit des données personnelles. La plupart des problèmes graves viennent d'une même cause : des réglages pensés pour le **live** (autologin, root sans mot de passe, identifiants `bob/bob`, services de démo) **sont recopiés tels quels sur le système installé**.

**62 constats** au total : 🔴 5 · 🟠 17 · 🟡 21 · 🔵 19.

**Les 10 points à corriger en premier :**

1. **INS-01** : **pacman ne peut rien installer ni mettre à jour**, ni sur le live ni sur le système installé. Le trousseau de clés est copié dans un dossier que `mkarchiso` n'utilise pas.
2. **SEC-01** : n'importe quel processus de l'utilisateur, ou n'importe qui devant l'écran, obtient **root sans mot de passe** (doas `nopass`, autologin, aucun verrouillage d'écran).
3. **INS-02** : **NVIDIA n'a aucun pilote sous XanMod**, le noyau par défaut des CPU récents. Hyprland ne peut donc pas démarrer sur ces PC.
4. **BOB-01** : `bob dotfiles apply` (présentée dans le motd) **donne tout le dossier personnel à root**, ce qui casse la session.
5. **SEC-02** : le dépôt `bob-core`, **qui fournit le noyau**, n'est pas signé (`SigLevel = Never`).
6. **BOB-02** : `bob-app-killer` **ferme Firefox, Steam, Discord et OBS toutes les heures**, même si l'utilisateur a « miné ». Le travail non sauvegardé est perdu.
7. **INS-03** : pas de langue, de fuseau horaire ni de choix de clavier à l'installation. **L'AZERTY est imposé** à tout le monde.
8. **SEC-03** : un fichier modifiable par tout le monde est évalué par bash dans un service. C'est une **élévation de privilèges locale** jusqu'à root.
9. **NET-01 / NET-02** : le pare-feu **ne se charge jamais** à cause d'une erreur de syntaxe, donc tout est ouvert. Une fois la syntaxe corrigée, il **couperait le réseau des conteneurs Docker**.
10. **INS-04** : l'installateur accepte un disque de **8 Go** alors que le système en occupe **9,3 Go**. L'installation échoue en plein milieu.

---

## 3. Tableau récapitulatif

| ID | Sév. | Titre |
|---|---|---|
| SEC-01 | 🔴 | Root sans mot de passe, autologin et pas de verrouillage sur le système installé |
| SEC-02 | 🔴 | Dépôt `bob-core` non signé (`SigLevel = Never`), noyau compris |
| SEC-03 | 🟠 | Élévation de privilèges via `/var/lib/bobcoin` (0777) et injection arithmétique bash |
| SEC-04 | 🟠 | `build.sh` copie le trousseau pacman de l'hôte, clé privée maîtresse comprise (latent) |
| SEC-05 | 🟠 | Identifiants `bob/bob` et `root/bob` ; l'installateur CLI les garde et les remet à chaque boot |
| SEC-06 | 🟡 | Aucun microcode CPU (`intel-ucode` / `amd-ucode`) |
| SEC-07 | 🟡 | Aucune option de chiffrement disque |
| SEC-08 | 🟡 | Port SSH 22 et DNS 53 ouverts en entrée sans raison |
| SEC-09 | 🟡 | Calamares accepte les mots de passe faibles, voire vides, par défaut |
| SEC-10 | 🔵 | Règle polkit trop large (tout `login1.*` et `NetworkManager.*`) |
| SEC-11 | 🔵 | `doas keepenv` transmet tout l'environnement à root |
| SEC-12 | 🔵 | Journal root au nom prévisible dans `/tmp` |
| SEC-13 | 🔵 | `bob-fetch` récupère des paquets non signés en lisant une page HTML |
| INS-01 | 🔴 | pacman inutilisable : pas de trousseau, dépôts du live vides |
| INS-02 | 🔴 | NVIDIA sans pilote sous XanMod (et nouveau blacklisté) |
| INS-03 | 🟠 | Pas de locale, fuseau ni clavier à l'installation ; AZERTY codé en dur |
| INS-04 | 🟠 | Espace requis de 8 Go alors que la racine fait 9,3 Go |
| INS-05 | 🟠 | Installateur CLI : élévation, stderr perdu, dépôts, rEFInd, clone de l'état du live |
| INS-06 | 🟠 | Suppression de XanMod par `rm` (base pacman incohérente) et test AVX2 insuffisant |
| INS-07 | 🟠 | L'installateur reste présent et lançable sur le système installé |
| INS-08 | 🟡 | Pas de synchronisation NTP alors que `DNSSEC=yes` : risque de perdre tout internet |
| INS-09 | 🟡 | Dual-boot : pas d'`os-prober` ; GRUB affiche « Arch Linux » |
| INS-10 | 🟡 | Initramfs du live construit avec une erreur (`nbd-client`) ; boot PXE inutilisable |
| INS-11 | 🟡 | Les entrées de boot « with speech » ne font rien |
| INS-12 | 🟡 | Live : overlay de 256 Mo et Docker actif, d'où des erreurs « disque plein » |
| INS-13 | 🔵 | Liens `.wants` systemd pointant vers des fichiers inexistants |
| INS-14 | 🔵 | `profiledef.sh` règle les droits de `/etc/gshadow`, qui n'existe pas |
| BOB-01 | 🔴 | `bob dotfiles apply` donne tout le dossier personnel à root |
| BOB-02 | 🟠 | `bob-app-killer` tue les applications toutes les heures, même après un minage |
| BOB-03 | 🟠 | `bob fixme` ne restaure rien ; `bob-update` ne prend aucun snapshot |
| BOB-04 | 🟡 | sudo cassé : `wheel` sans `%` et `Defaults` invalide |
| BOB-05 | 🟡 | `bob-update` : `--noconfirm`, trousseau non mis à jour en premier, pas de news Arch |
| BOB-06 | 🟡 | `bobcoin` : deux `doas` à chaque prompt, repli `/tmp` cassé, montants négatifs acceptés |
| BOB-07 | 🟡 | `bob-martian-eq` utilise la mauvaise option d'EasyEffects (à confirmer) |
| BOB-08 | 🔵 | `aliases.zsh` : `mine()` incohérent, alias qui masquent `bc` et `wall`, garde `rm` inefficace |
| BOB-09 | 🔵 | `bob` demande root pour `-Q`/`-Ss` ; aide en double ; variables inutilisées |
| BOB-10 | 🔵 | `bobos-screen` force 1080p sans retour arrière possible |
| BOB-11 | 🔵 | `bobos-power` : doas inutile ; `SUPER+M` quitte sans confirmation ; pas de veille |
| BOB-12 | 🔵 | `bob-slot-machine` : code mort et lecture de fichier non validée |
| BOB-13 | 🔵 | Code d'élévation copié dans 7 scripts, presets dans 2 installateurs |
| BOB-14 | 🔵 | `bobos-res` écrit une ligne `#` dans un fichier Lua |
| UX-01 | 🟠 | Polices : ni Nerd Font ni emoji (p10k, eza et emojis affichent des carrés) |
| UX-02 | 🟠 | Pas de `xdg-desktop-portal-hyprland` : partage d'écran cassé |
| UX-03 | 🟠 | GPU Intel : ni Vulkan ni VA-API moderne (Steam/Proton cassé sur Intel) |
| UX-04 | 🟡 | `SUPER+E` lance yazi sans terminal : rien ne s'ouvre |
| UX-05 | 🟡 | Zsh : historique non sauvé, pas de complétion, touches cassées, doublons |
| UX-06 | 🟡 | Briques de bureau absentes (notifications, captures, volume, verrouillage…) |
| UX-07 | 🔵 | Branding : `ID=arch`, GRUB « Arch », version codée en dur |
| UX-08 | 🔵 | Le splash ajoute 4 s à chaque boot ; bip au menu UEFI |
| UX-09 | 🔵 | Deux lanceurs d'installateur dans wofi |
| UX-10 | 🔵 | Tout le texte est en français codé en dur (pas d'i18n) |
| NET-01 | 🟠 | Le pare-feu ne se charge jamais (erreur de syntaxe `67,68`) : aucune protection |
| NET-02 | 🟠 | Une fois NET-01 corrigé, le pare-feu coupe Docker (`forward` en drop, `flush ruleset`) |
| NET-03 | 🟡 | DNS : IPv6 invalide, `Domains=~.`, `DNSSEC=yes` strict |
| NET-04 | 🟡 | IPv6 : découverte de voisins limitée en débit, DHCPv6 bloqué |
| NET-05 | 🔵 | Steam Remote Play et découverte réseau local bloqués |
| BLD-01 | 🟠 | Binaires Calamares commités dans git et extraits en root dans le dépôt |
| BLD-02 | 🟠 | Scripts BobOS livrés hors paquets : aucune mise à jour possible |
| BLD-03 | 🟡 | Priorité des dépôts pacman mal comprise ; README inexact |
| BLD-04 | 🟡 | Modules XanMod non compressés (+650 Mo) ; initramfs de plus de 200 Mo |
| BLD-05 | 🟡 | `build.sh` : journal sans fin, 14 Go laissés, cache fragile, pas de checksum |
| BLD-06 | 🔵 | Écarts entre `plan-summary.md` et ce qui est réellement fait |

---

## 4. Sécurité

### SEC-01 🔴 Root sans mot de passe, autologin et pas de verrouillage sur le système installé

**Où**
- [iso/airootfs/etc/doas.conf:3](iso/airootfs/etc/doas.conf#L3) : `permit keepenv nopass :wheel`
- [getty@tty1.service.d/autologin.conf:3](iso/airootfs/etc/systemd/system/getty@tty1.service.d/autologin.conf#L3)
- [bobos-target-fixes:88-95](iso/airootfs/usr/bin/bobos-target-fixes#L88) : l'autologin est **redirigé vers l'utilisateur installé** au lieu d'être supprimé
- [.zshrc:43-50](iso/airootfs/etc/skel/.zshrc#L43) : Hyprland démarre automatiquement sur tty1
- Aucun `hyprlock` ni `hypridle` dans `packages.x86_64`
- [partition.conf:30](iso/airootfs/etc/calamares/modules/partition.conf#L30) : LUKS désactivé

**Problème.** Sur le système installé, la chaîne complète est la suivante : l'ordinateur démarre, ouvre la session tty1 sans mot de passe, lance Hyprland, n'est jamais verrouillé, et `doas` donne root sans mot de passe. `users.conf` a pourtant `doAutologin: false`, mais `bobos-target-fixes` réactive l'autologin quand même.

**Impact**
- **À distance ou par logiciel** : une extension de navigateur malveillante, un `postinstall` npm, un mod de jeu ou une faille dans Discord deviennent root sans aucune alerte, avec un simple `doas <cmd>`.
- **Accès physique** : allumer le PC suffit pour avoir root et tout lire, et le disque n'est pas chiffré.

**Correction.** Garder le confort sur le live et durcir la cible dans `bobos-target-fixes` :

```bash
# --- Durcissement : la cible n'est pas un live ---
cat > /etc/doas.conf <<'DOAS'
# BobOS — root via doas, mot de passe demandé (mémorisé quelques minutes)
permit persist setenv { WAYLAND_DISPLAY XDG_RUNTIME_DIR DISPLAY XAUTHORITY } :wheel
DOAS
chown root:root /etc/doas.conf && chmod 0400 /etc/doas.conf
doas -C /etc/doas.conf        # valide la syntaxe (retirer `persist` si la build ne le gère pas)

printf '%%wheel ALL=(ALL:ALL) ALL\n' > /etc/sudoers.d/bobos
chmod 0440 /etc/sudoers.d/bobos
visudo -cf /etc/sudoers.d/bobos

# pas d'autologin sur la cible (sauf choix explicite, voir plus bas)
rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf
```

- Ajouter `hyprlock` et `hypridle` aux paquets. Lancer `hypridle` dans `hl.on("hyprland.start")`, ajouter un raccourci `SUPER+L` vers `hyprlock`, et fournir `~/.config/hypr/hypridle.conf` :
  ```ini
  general {
      lock_cmd = pidof hyprlock || hyprlock
      before_sleep_cmd = loginctl lock-session
  }
  listener {
      timeout = 600
      on-timeout = loginctl lock-session
  }
  ```
- Si l'autologin doit rester une option : utiliser `greetd` avec `tuigreet` et une `initial_session`, et ne l'activer que si l'utilisateur coche la case dans Calamares (`displayAutologin: true`).
- Voir SEC-07 pour le chiffrement.

---

### SEC-02 🔴 Dépôt `bob-core` non signé, noyau compris

**Où**
- [iso/pacman.conf:29-31](iso/pacman.conf#L29)
- [bobos-target-fixes:43-45](iso/airootfs/usr/bin/bobos-target-fixes#L43)
- [README.md:66-79](README.md#L66)

**Problème.** `SigLevel = Never` sur un dépôt distant. Le build du 24/09 en tire `linux-xanmod`, `linux-xanmod-headers` et `zsh-theme-powerlevel10k-git`. Le noyau et ses modules ne sont donc **vérifiés par personne**.

**Impact.** HTTPS ne protège que le transport. Si `bob.xem.yt` est compromis, si le nom de domaine expire et est racheté, ou si un proxy d'entreprise possède sa propre autorité de certification, alors **un paquet piégé devient root sur chaque machine BobOS** au prochain `bob-update`. Le même risque touche le build lui-même.

**Correction**
1. Créer une clé GPG dédiée au dépôt (« BobOS Repo Signing Key »), gardée hors ligne si possible.
2. Signer les paquets et la base :
   ```bash
   makepkg --sign --key <KEYID>
   repo-add --sign --key <KEYID> bob-core.db.tar.zst *.pkg.tar.zst
   ```
3. Publier un paquet **`bobos-keyring`** qui installe `/usr/share/pacman/keyrings/bobos.gpg`, `bobos-trusted` et `bobos-revoked`.
4. Passer `bob-core` en `SigLevel = Required`. À l'installation : `pacman-key --populate archlinux bobos`.
5. Tant que ce n'est pas fait, retirer du README la phrase qui recommande `SigLevel = Never` aux utilisateurs.

---

### SEC-03 🟠 Élévation de privilèges via `/var/lib/bobcoin` et injection arithmétique

**Où**
- [tmpfiles.d/bobcoin.conf:1-3](iso/airootfs/etc/tmpfiles.d/bobcoin.conf#L1) : dossier en `0777` **sans sticky bit**, fichiers en `0666`
- [bob-app-killer:9-11](iso/airootfs/usr/bin/bob-app-killer#L9) : `age=$((now - last_mine))`
- [bob-app-killer.service:7](iso/airootfs/etc/systemd/system/bob-app-killer.service#L7) : lancé chaque heure en tant que `bob`, qui a doas sans mot de passe
- [bobcoin:31,42](iso/airootfs/usr/bin/bobcoin#L31) et [bob-slot-machine:7,20](iso/airootfs/usr/bin/bob-slot-machine#L20) : `$((bal + 10))`, `(( bal < cost ))`

**Problème.** En bash, `$(( var ))` **évalue le contenu de la variable comme une expression**, et un indice de tableau peut contenir `$(commande)`. Test reproduit :

```bash
$ echo 'x[$(echo PWNED >&2)]' > lm
$ last_mine="$(cat lm)"; age=$(( $(date +%s) - last_mine ))
PWNED
```

**Impact.** N'importe quel compte local (un invité, un démon compromis, un conteneur qui monte `/var/lib`) écrit dans `/var/lib/bobcoin/last-mine`. Dans l'heure, le timer exécute le code en tant que `bob`, puis `doas` donne root. Même chaîne avec `balance` dès que l'utilisateur lance `bobcoin mine` ou `slots`. Le dossier 0777 sans sticky bit permet aussi de **remplacer les fichiers par des liens symboliques**.

**Correction**
- Valider tout entier lu depuis un fichier **avant** de faire un calcul avec :
  ```bash
  read_int() {  # read_int <fichier> → entier ≥ 0, jamais évalué
      local v
      v="$(cat -- "$1" 2>/dev/null || true)"
      [[ $v =~ ^[0-9]{1,18}$ ]] || v=0
      printf '%s\n' "$v"
  }
  last_mine="$(read_int "$MINE_FILE")"
  ```
- Garder l'état **par utilisateur** : `${XDG_STATE_HOME:-$HOME/.local/state}/bobcoin/{balance,last-mine}`. Supprimer `tmpfiles.d/bobcoin.conf`, ou au minimum passer en `d /var/lib/bobcoin 1777` (sticky) avec des fichiers en `0644`.
- Faire tourner `bob-app-killer` comme **timer utilisateur** (voir BOB-02), jamais comme service système lié à un nom d'utilisateur.

---

### SEC-04 🟠 `build.sh` copie le trousseau pacman de l'hôte (latent)

**Où** : [build.sh:46](build.sh#L46), [build.sh:90-95](build.sh#L90)

**Problème.** `cp -a /etc/pacman.d/gnupg` copie **tout** le trousseau de l'hôte, y compris la **clé privée maîtresse locale** créée par `pacman-key --init`. Aujourd'hui, la copie vers l'ISO tombe dans un mauvais dossier (voir INS-01) et n'a donc aucun effet. **Si quelqu'un « répare » ce chemin**, chaque ISO BobOS embarquera la même clé privée, lisible par tous. N'importe qui pourrait alors signer des paquets acceptés par toutes les installations. Autre problème : l'hôte est sous Artix, donc des clés Artix seraient également marquées comme fiables.

**Correction.** Ne jamais copier de trousseau. Générer une clé **par machine**, au premier démarrage du live et à l'installation (voir la correction d'INS-01). Supprimer `seed_keyring()` et l'appel de relance associé.

---

### SEC-05 🟠 Identifiants par défaut ; l'installateur CLI les garde

**Où**
- [bobos-create-user:12-13](iso/airootfs/usr/local/bin/bobos-create-user#L12) : `bob:bob` et `root:bob`
- [bobos-install-cli:69-74](iso/airootfs/usr/bin/bobos-install-cli#L69) : `rsync /` du live
- [bobos-install-cli:208](iso/airootfs/usr/bin/bobos-install-cli#L208)

**Problème.** Le chemin Calamares désactive `bobos-user.service`, mais **le chemin CLI ne le fait pas**. La cible installée par la CLI remet donc `bob:bob` et `root:bob` **à chaque démarrage**, et affiche « login : bob / mdp : bob ». Si l'utilisateur active plus tard `sshd` (déjà installé, port déjà ouvert, voir SEC-08), l'accès à distance est trivial.

**Correction.** Dans la CLI : supprimer le lien de `bobos-user.service`, forcer `passwd` pour l'utilisateur et pour root (ou `passwd -l root`), et réutiliser `bobos-target-fixes` (voir INS-05).

---

### SEC-06 🟡 Aucun microcode CPU

**Où** : `iso/packages.x86_64` ne contient ni `intel-ucode` ni `amd-ucode`, alors que le hook `microcode` est bien présent dans `mkinitcpio.conf` sur la cible.

**Impact.** Les correctifs de sécurité et d'errata CPU (Spectre et ses variantes, Downfall, Zenbleed…) ne sont jamais chargés. La stabilité en souffre aussi sur certains modèles.

**Correction.** Ajouter `intel-ucode` et `amd-ucode`. Avec mkinitcpio ≥ 38 et le hook `microcode`, ils sont intégrés automatiquement à l'initramfs, et GRUB n'a rien de plus à faire.

### SEC-07 🟡 Aucune option de chiffrement disque

**Où** : [partition.conf:30](iso/airootfs/etc/calamares/modules/partition.conf#L30) contient `enableLuksAutomatedPartitioning: false`.

**Correction.** Passer à `true`, ajouter `cryptsetup`, et régler `initcpiocfg` et `luksbootkeyfile` dans la séquence Calamares. Le hook `sd-encrypt` fonctionne avec les HOOKS systemd actuels. En complément, envisager plus tard le déverrouillage par TPM2 avec `systemd-cryptenroll`.

### SEC-08 🟡 Ports SSH 22 et DNS 53 ouverts en entrée

**Où** : [firewall.nft:18-22](iso/airootfs/etc/bobos/firewall.nft#L18)

**Problème.** `sshd` n'est pas activé, mais le port est ouvert : le jour où il le sera, avec des mots de passe faibles (SEC-09), il sera exposé immédiatement. Aujourd'hui, le pare-feu ne se charge de toute façon pas (NET-01) : **tous** les ports sont ouverts. Le 53 entrant ne sert à rien sur un poste client, car les réponses DNS passent déjà par `established,related`.

**Correction.** Voir le pare-feu complet en NET-02 : SSH commenté par défaut, pas de 53 entrant.

### SEC-09 🟡 Mots de passe faibles, voire vides, acceptés par défaut

**Où** : [users.conf:31-38](iso/airootfs/etc/calamares/modules/users.conf#L31) : `minLength: -1`, `minlen=0`, `allowWeakPasswordsDefault: true`

**Correction.** `minLength: 6` au minimum. Garder `allowWeakPasswords: true` (la case reste disponible) mais passer `allowWeakPasswordsDefault: false` (décochée par défaut).

### SEC-10 🔵 Règle polkit trop large

**Où** : [50-bobos.rules:3-6](iso/airootfs/etc/polkit-1/rules.d/50-bobos.rules#L3)

**Problème.** `org.freedesktop.login1.*` couvre aussi `set-user-linger`, `attach-device`, `set-reboot-parameter`… `NetworkManager.*` couvre aussi la modification des connexions **système**, VPN compris. Aujourd'hui c'est sans effet puisque wheel a déjà root sans mot de passe, mais ça le devient dès que SEC-01 est corrigé.

**Correction.** Passer à une liste blanche : `login1.power-off`, `login1.reboot`, `login1.suspend`, `login1.hibernate`, `NetworkManager.network-control`, `NetworkManager.wifi.scan`, `NetworkManager.settings.modify.own`, `NetworkManager.enable-disable-wifi`.

### SEC-11 🔵 `doas keepenv`

`keepenv` transmet **tout** l'environnement de l'utilisateur (`PATH`, `LD_PRELOAD`…) à la commande lancée en root. Le remplacer par une liste `setenv { … }` explicite, comme dans SEC-01. `bobos-install` fonctionne toujours, puisqu'il a seulement besoin de `WAYLAND_DISPLAY` et `XDG_RUNTIME_DIR`.

### SEC-12 🔵 Journal root au nom prévisible dans `/tmp`

**Où** : [bobos-install:47](iso/airootfs/usr/bin/bobos-install#L47) avec `tee /tmp/bobos-calamares.log` en root.

L'attaque par lien symbolique est bloquée par `fs.protected_symlinks=1` (actif par défaut), mais mieux vaut utiliser `/var/log/bobos-install.log` ou `mktemp`.

### SEC-13 🔵 `bob-fetch` récupère des paquets non signés

**Où** : [bob-fetch:27-31](iso/airootfs/usr/bin/bob-fetch#L27)

Le script lit la page d'index HTML du serveur (autoindex obligatoire) et télécharge en root des paquets non vérifiés. De plus, rien n'utilise ensuite `/var/cache/bob`. **Correction :** supprimer la commande, ou la remplacer par `pacman -Sw $(pacman -Slq bob-core)` une fois le dépôt signé.

---

## 5. Installation et système installé

### INS-01 🔴 pacman inutilisable : trousseau absent, dépôts du live vides

**Où** : [build.sh:20](build.sh#L20) (`PACSTRAP_DIR="$WORK/x86_64/pacstrap_dir"`) et [build.sh:90-98](build.sh#L90)

**Preuve**
- `mkarchiso`, ligne 1771 : `pacstrap_dir="${work_dir}/${arch}/airootfs"`. Le trousseau a donc été copié dans `/var/tmp/bobos-work/x86_64/pacstrap_dir/etc/pacman.d/gnupg`, un dossier que **personne ne lit**.
- Dans l'image construite, `/etc/pacman.d/` ne contient que `mirrorlist`. **Pas de `gnupg`.**
- Le live garde le `/etc/pacman.conf` d'origine d'Arch (core et extra seulement) avec un `mirrorlist` **entièrement commenté**.
- L'image n'a pas de `pacman-init.service`, alors que le profil `releng` d'archiso en fournit un.

**Impact**
- **Live** : `pacman -S` ne trouve aucun serveur.
- **Système installé** : `bobos-target-fixes` écrit bien les dépôts, mais sans trousseau **toute vérification de signature échoue**. `bob-update`, `bob -S` et `pacman -Syu` sont hors service. La tentation sera de passer `SigLevel = Never` partout, ce qui serait pire.

**Correction**
1. **Live** : copier depuis `/usr/share/archiso/configs/releng/airootfs/etc/systemd/system/` les fichiers `pacman-init.service` et `etc-pacman.d-gnupg.mount`, puis les activer :
   ```bash
   ln -s /etc/systemd/system/pacman-init.service \
     iso/airootfs/etc/systemd/system/multi-user.target.wants/pacman-init.service
   ```
2. **Cible**, dans `bobos-target-fixes` :
   ```bash
   echo "[fixes] initialisation du trousseau pacman (clé unique à cette machine)..."
   rm -rf /etc/pacman.d/gnupg
   pacman-key --init
   pacman-key --populate archlinux      # + bobos quand bobos-keyring existera (SEC-02)
   ```
3. Livrer **un seul** `pacman.conf` dans `iso/airootfs/etc/pacman.conf` (live et cible identiques), avec `Include = /etc/pacman.d/mirrorlist`. Fournir aussi un vrai `mirrorlist`, ou `reflector` avec `reflector.timer`. Le heredoc de `bobos-target-fixes` devient alors inutile. Aujourd'hui, un seul miroir (`geo.mirror.pkgbuild.com`) veut dire plus aucune mise à jour dès qu'il tombe.
4. Supprimer `seed_keyring()` (voir SEC-04).

---

### INS-02 🔴 NVIDIA sans pilote sous XanMod

**Où** : [packages.x86_64:53](iso/packages.x86_64#L53) (`nvidia-open`) et [packages.x86_64:21](iso/packages.x86_64#L21) (seuls les headers XanMod sont présents)

**Preuve** (image construite)
```
7.2.6-arch2-1/extramodules/nvidia.ko.zst, nvidia-drm.ko.zst, …   ← noyau stock : OK
7.2.6-x64v3-xanmod1-1/ : aucun module nvidia (seulement nvidia-wmi-ec-backlight.ko)
/usr/lib/modprobe.d/nvidia-utils.conf : blacklist nouveau
```

**Problème.** `nvidia-open` ne contient que des modules compilés pour le noyau `linux` d'Arch. Sous XanMod, le noyau prévu pour les CPU récents, il n'y a **ni `nvidia` ni `nouveau`** (blacklisté par `nvidia-utils`), donc aucun pilote DRM. Hyprland ne démarre pas.

**Correction** (au choix)
- **Simple** : remplacer `nvidia-open` par `nvidia-open-dkms`, et ajouter `dkms` et `linux-headers` (`linux-xanmod-headers` est déjà là). DKMS compile les modules pour les deux noyaux pendant le build. Le build est plus long, mais tout fonctionne hors ligne.
- **Propre** : publier dans `bob-core` un paquet `nvidia-open-xanmod` précompilé, lié à la version exacte de `linux-xanmod`.
- **En plus** : ne garder les paquets NVIDIA que si le matériel en a besoin. Dans `bobos-target-fixes` (nécessite `pciutils`) :
  ```bash
  if ! lspci -nn | grep -Eq '\[03(00|02)\].*\[10de:'; then
      pacman -Rns --noconfirm nvidia-open-dkms nvidia-utils lib32-nvidia-utils || true
  fi
  ```
- Pour Hyprland avec NVIDIA, définir les variables `LIBVA_DRIVER_NAME=nvidia`, `__GLX_VENDOR_LIBRARY_NAME=nvidia` et `NVD_BACKEND=direct` (paquet `libva-nvidia-driver`).

---

### INS-03 🟠 Pas de locale, de fuseau ni de clavier à l'installation

**Où**
- [settings.conf:14-29](iso/airootfs/etc/calamares/settings.conf#L14) : ni `locale`, ni `keyboard`, ni `localecfg`, ni `hwclock`
- [hyprland.lua:74](iso/airootfs/etc/skel/.config/hypr/hyprland.lua#L74) : `kb_layout = "fr"`
- [vconsole.conf](iso/airootfs/etc/vconsole.conf) : `KEYMAP=fr`

**Preuve.** Dans l'image, il n'y a ni `/etc/locale.conf` ni `/etc/localtime`, et `locale.gen` ne contient que `C.utf8`.

**Impact**
- `LANG` n'est pas défini, donc la locale est POSIX. Dans zsh, **« é » s'affiche `<00e9>`** dans la ligne de commande, alors que tout BobOS est en français avec des accents.
- L'heure est en UTC.
- Les utilisateurs non français **restent en AZERTY**, en console comme dans Hyprland.

**Correction**
1. Séquence Calamares :
   ```yaml
   sequence:
     - show: [ welcome, locale, keyboard, partition, users, summary ]
     - exec:
         - partition
         - mount
         - shellprocess@mountiso
         - unpackfs
         - machineid
         - fstab
         - locale
         - keyboard
         - localecfg
         - users
         - networkcfg
         - hwclock
         - services-systemd
         - shellprocess@fixes
         - grubcfg
         - bootloader
         - umount
     - show: [ finished ]
   ```
   Tous ces modules sont déjà compilés, dans `usr/lib/calamares/modules/`. Créer `/etc/calamares/modules/locale.conf` avec `region: "Europe"` et `zone: "Paris"`, sans GeoIP puisque l'installation est hors ligne.
2. Transmettre le clavier choisi à Hyprland, dans `bobos-target-fixes` :
   ```bash
   KBD=/etc/X11/xorg.conf.d/00-keyboard.conf
   layout=$(sed -nE 's/.*"XkbLayout"[[:space:]]+"([^"]+)".*/\1/p' "$KBD" 2>/dev/null | head -n1)
   variant=$(sed -nE 's/.*"XkbVariant"[[:space:]]+"([^"]*)".*/\1/p' "$KBD" 2>/dev/null | head -n1)
   if [[ -n $layout && -n $USER_NAME ]]; then
       home=$(getent passwd "$USER_NAME" | cut -d: -f6)
       mkdir -p "$home/.config/hypr"
       printf 'hl.config({ input = { kb_layout = "%s", kb_variant = "%s" } })\n' \
           "$layout" "$variant" > "$home/.config/hypr/keyboard.lua"
       chown -R "$USER_NAME:" "$home/.config/hypr"
   fi
   ```
   Ajouter ensuite `pcall(require, "keyboard")` dans `hyprland.lua`, **après** le bloc `hl.config`.
3. **Live** : ajouter `iso/airootfs/etc/locale.conf` (`LANG=fr_FR.UTF-8`) et une ligne `fr_FR.UTF-8 UTF-8` dans `locale.gen`, avec le hook pacman `40-locale-gen.hook` qu'utilisait le profil `releng` pour lancer `locale-gen` pendant le build. Solution minimale : `LANG=C.UTF-8`, qui ne demande aucune génération.

---

### INS-04 🟠 Espace requis de 8 Go alors que la racine fait 9,3 Go

**Où** : [welcome.conf:9](iso/airootfs/etc/calamares/modules/welcome.conf#L9)

**Preuve.** `du -sh airootfs` donne **9,3 Go**, sans compter les deux noyaux, les initramfs et les régénérations de `mkinitcpio -P`. Le README annonce lui-même au moins 20 Go.

**Correction.** `requiredStorage: 20`. Prévoir aussi une alerte si la batterie est faible, avec le test `power` dans `check:`.

---

### INS-05 🟠 Installateur CLI : suite de bugs

**Où** : [bobos-install-cli](iso/airootfs/usr/bin/bobos-install-cli)

| # | Ligne | Problème |
|---|---|---|
| a | [9](iso/airootfs/usr/bin/bobos-install-cli#L9) | `exec doas … 2>/dev/null \|\| exec sudo …` : le repli sur sudo **n'est jamais atteint**, puisque `exec` remplace le shell. C'est exactement le bug décrit dans les commentaires de `bobos-install`. Et `2>/dev/null` **envoie tout le stderr de l'installateur à la poubelle** : plus aucun message d'erreur visible. |
| b | — | Ne réécrit pas `pacman.conf` (contrairement à Calamares) : la cible n'a que core et extra et un mirrorlist commenté. |
| c | — | Garde `bobos-user.service` (voir SEC-05) et `bob-app-killer.timer`. |
| d | [144](iso/airootfs/usr/bin/bobos-install-cli#L144) | `refind-install` en chroot génère `refind_linux.conf` à partir du `/proc/cmdline` **du live** (`archisobasedir=…`). Le wiki Arch avertit explicitement de ce cas. Le démarrage UEFI a de fortes chances d'échouer ou de viser la mauvaise racine. **(à confirmer en VM)** |
| e | — | Deux chargeurs d'amorçage selon le chemin suivi (GRUB avec Calamares, rEFInd avec la CLI) : deux fois plus de cas à maintenir. |
| f | [54](iso/airootfs/usr/bin/bobos-install-cli#L54) | BIOS : table MBR uniquement, donc disques de plus de 2 Tio impossibles. |
| g | [70](iso/airootfs/usr/bin/bobos-install-cli#L70) | `rsync /` copie **l'état du live en cours** : `/home/bob`, `/root`, journaux, `machine-id`, connexions NetworkManager, hash `root:bob`… |
| h | [203-208](iso/airootfs/usr/bin/bobos-install-cli#L203) | Message de fin spécifique à virt-manager affiché sur du vrai matériel. |

**Correction**
- Soit **supprimer la CLI** et faire de Calamares le seul installateur.
- Soit la réécrire avec :
  - une élévation correcte, comme dans `bobos-install` :
    ```bash
    if [[ $EUID -ne 0 ]]; then
        if command -v doas >/dev/null && doas true 2>/dev/null; then exec doas "$0" "$@"; fi
        exec sudo "$0" "$@"
    fi
    ```
  - `unsquashfs -f -d /mnt /run/archiso/bootmnt/arch/x86_64/airootfs.sfs` au lieu de `rsync /`, pour partir de l'image propre comme Calamares ;
  - l'appel à **`/usr/bin/bobos-target-fixes "$USER_NAME"`** dans le chroot, pour mettre en commun presets, pacman.conf, trousseau et nettoyage ;
  - GPT partout (avec une partition `bios_grub` de 1 Mio en BIOS) ;
  - pour rEFInd, écrire `refind_linux.conf` **avant** `refind-install` (qui ne l'écrase pas s'il existe déjà) :
    ```bash
    ROOTUUID=$(findmnt -no UUID /)
    cat > /boot/refind_linux.conf <<EOF
    "Boot BobOS"           "root=UUID=$ROOTUUID rw quiet"
    "Boot BobOS (secours)" "root=UUID=$ROOTUUID rw single"
    EOF
    ```

---

### INS-06 🟠 Suppression de XanMod par `rm` et test AVX2 insuffisant

**Où** : [bobos-target-fixes:68-75](iso/airootfs/usr/bin/bobos-target-fixes#L68) et [bobos-install-cli:129-136](iso/airootfs/usr/bin/bobos-install-cli#L129)

**Problème**
1. Les fichiers sont supprimés à la main alors que pacman croit toujours `linux-xanmod` installé. Au prochain `pacman -Syu`, le noyau est **réinstallé**, son hook régénère l'initramfs, et le prochain `grub-mkconfig` propose un noyau qui **plante au boot**. `pacman -Qkk` signale aussi des milliers de fichiers manquants.
2. Le noyau construit est `7.2.6-x64v3-xanmod1`. **x86-64-v3** demande AVX2, mais aussi BMI1/2, FMA, MOVBE, F16C… Certaines VM ou certains CPU exposent AVX2 sans tout le reste.

**Correction**
```bash
if ! /usr/lib/ld-linux-x86-64.so.2 --help | grep -q 'x86-64-v3 (supported'; then
    echo "[fixes] CPU non x86-64-v3 → XanMod désinstallé proprement"
    pacman -Rdd --noconfirm linux-xanmod linux-xanmod-headers || true
fi
```

---

### INS-07 🟠 L'installateur reste présent sur le système installé

**Où**
- `unpackfs` copie tout le squashfs du live.
- `bobos-target-fixes` ne supprime ni `/usr/bin/calamares` et ses bibliothèques, ni `/etc/calamares`, ni `bobos-install*`, ni `bobos-installer.desktop` et `calamares.desktop`, ni `/usr/include/libcalamares`, ni `bobos-create-user`.

**Impact.** Les entrées « Installer BobOS » et « Install System » apparaissent dans wofi **sur le système installé**. Un clic, et on peut effacer son propre disque.

**Correction.** À court terme, à la fin de `bobos-target-fixes` :
```bash
rm -f /usr/share/applications/{bobos-installer,calamares}.desktop \
      /usr/bin/bobos-install /usr/bin/bobos-install-cli /usr/bin/bobos-mount-iso \
      /usr/local/bin/bobos-create-user /etc/systemd/system/bobos-user.service
rm -rf /etc/calamares
```
À terme, transformer Calamares en vrai paquet (BLD-01) et le désinstaller avec le module Calamares `packages` (`operations: - remove: [calamares, bobos-installer]`).

---

### INS-08 🟡 Pas de NTP alors que `DNSSEC=yes`

**Où.** `systemd-timesyncd` n'est pas activé (constaté dans l'image), alors que [resolved.conf.d/bobos.conf:9](iso/airootfs/etc/systemd/resolved.conf.d/bobos.conf#L9) contient `DNSSEC=yes`.

**Impact.** Si l'horloge dérive (pile CMOS vide, dual-boot avec Windows qui garde l'heure locale), la validation DNSSEC et TLS échoue, et **plus aucun site ne se résout**. Ce comportement contredit directement le commentaire du fichier (« JAMAIS de résolution morte »).

**Correction**
```bash
ln -s /usr/lib/systemd/system/systemd-timesyncd.service \
  iso/airootfs/etc/systemd/system/sysinit.target.wants/systemd-timesyncd.service
```
Passer aussi à `DNSSEC=allow-downgrade` (voir NET-03).

### INS-09 🟡 Dual-boot : pas d'`os-prober` ; GRUB affiche « Arch »

**Problème.** Calamares propose « installer à côté », mais `os-prober` n'est pas installé et GRUB le désactive par défaut : Windows **disparaît du menu**. Dans l'image, `/etc/default/grub` contient `GRUB_DISTRIBUTOR="Arch"`, car le module `grubcfg` n'est pas dans la séquence.

**Correction.** Ajouter le paquet `os-prober` et créer `/etc/calamares/modules/grubcfg.conf` :
```yaml
overwrite: false
keepDistributor: false
defaults:
    GRUB_TIMEOUT: 5
    GRUB_DEFAULT: "saved"
    GRUB_DISABLE_SUBMENU: true
    GRUB_DISABLE_RECOVERY: true
    GRUB_DISABLE_OS_PROBER: false
```

### INS-10 🟡 Initramfs du live construit avec une erreur ; PXE inutilisable

**Où** : [mkinitcpio.conf.d/archiso.conf:1](iso/airootfs/etc/mkinitcpio.conf.d/archiso.conf#L1) et [syslinux/archiso_pxe-linux.cfg](iso/syslinux/archiso_pxe-linux.cfg)

**Preuve** (journal du build)
```
==> ERROR: binary not found: 'nbd-client'
==> WARNING: errors were encountered during the build. The image may not be complete.
error: command failed to execute correctly
```

**Problème**
- Le hook `archiso_pxe_nbd` a besoin du paquet `nbd`, absent.
- Les entrées PXE démarrent **XanMod** (plantage sur les CPU non v3) avec `cms_verify=y`, alors que l'image n'est pas signée.
- `buildmodes=('iso')` ne produit de toute façon pas d'artefact `netboot`.

**Correction.** Si le PXE ne sert pas, **supprimer** les hooks `archiso_pxe_*` et `archiso_pxe.cfg`. Au passage, l'initramfs du live est plus petit. Ajouter aussi `pv` (avertissement « pv not found » pour `copytoram`).

### INS-11 🟡 Les entrées « with speech » ne font rien

**Où** : [03-archiso-speech-linux.conf](iso/efiboot/loader/entries/03-archiso-speech-linux.conf) et [archiso_sys-linux.cfg:24-31](iso/syslinux/archiso_sys-linux.cfg#L24)

**Problème.** `accessibility=on` ne sert qu'à `livecd-talk.service`, absent de BobOS, tout comme `espeakup` et `livecd-alsa-unmuter.service`.

**Correction.** Copier ces services depuis `releng` et ajouter `espeakup` et `alsa-utils`. Sinon, retirer les entrées.

### INS-12 🟡 Live : overlay de 256 Mo et Docker actif

**Problème**
- Le hook archiso limite l'overlay en écriture à `cow_spacesize=256M` par défaut. Firefox, Steam, Discord, les journaux et Docker le remplissent vite, d'où des erreurs « No space left on device » pendant la session live.
- Docker est activé sur le live, où son pilote `overlay2` sur overlayfs ne fonctionne pas correctement.

**Correction.** Ajouter `cow_spacesize=4G` à toutes les lignes `options` et `APPEND` : c'est un tmpfs qui ne consomme la RAM qu'à l'usage. Retirer `docker.service` des `.wants` du live, et l'activer sur la cible via `services-systemd` (de préférence `docker.socket`, démarré à la demande).

### INS-13 🔵 Liens `.wants` vers des fichiers inexistants

**Où.** `getty@tty1.service.wants/bobos-splash.service` et `timers.target.wants/bob-app-killer.timer` pointent vers `/usr/lib/systemd/system/…`, alors que les unités se trouvent dans `/etc/systemd/system/`.

**Problème.** systemd résout ces liens par leur **nom**, donc ça fonctionne, mais `systemctl disable` et `is-enabled` peuvent afficher des résultats trompeurs. **Correction :** faire pointer les liens vers `/etc/systemd/system/…`, ou placer les unités dans un paquet sous `/usr/lib/systemd/system`.

### INS-14 🔵 `/etc/gshadow` inexistant

[profiledef.sh:19](iso/profiledef.sh#L19) règle les droits de `/etc/gshadow`, qui n'existe pas dans le profil. Cela produit un avertissement à chaque build. Supprimer la ligne ou ajouter le fichier.

---

## 6. Scripts `bob-*` / `bobos-*`

### BOB-01 🔴 `bob dotfiles apply` donne tout le dossier personnel à root

**Où** : [bob:47-52](iso/airootfs/usr/bin/bob#L47)

**Problème.** Après l'élévation, le script tourne en root, donc `id -u` et `id -g` valent `0`. La ligne `chown -R "$(id -u):$(id -g)" "$tgt_home"` **donne tout `$HOME` à `root:root`**. Dans la foulée, `rsync -a` écrase `.zshrc`, `hyprland.lua`, etc. **sans sauvegarde**.

**Impact.** Hyprland, Firefox et zsh ne peuvent plus écrire leur configuration ni leur cache : la session est cassée. Il faut un `chown -R` manuel en root pour s'en sortir. Or cette commande est **affichée dans le motd**.

**Correction.** Cette commande n'a pas besoin de root, puisque `/etc/skel` est lisible par tout le monde :
```bash
dotfiles)
    [[ "${2:-}" == "apply" ]] || { echo "usage : bob dotfiles apply" >&2; exit 1; }
    backup="$HOME/.local/state/bobos/dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup"
    rsync -a --backup --backup-dir="$backup" /etc/skel/ "$HOME"/
    echo "Dotfiles BobOS appliqués. Anciens fichiers : $backup"
    ;;
```

---

### BOB-02 🟠 `bob-app-killer` tue les applications toutes les heures, même après un minage

**Où**
- [bob-app-killer:9-13](iso/airootfs/usr/bin/bob-app-killer#L9)
- [aliases.zsh:24-31](iso/airootfs/etc/zsh/bob/aliases.zsh#L24)
- [bob-app-killer.service:7](iso/airootfs/etc/systemd/system/bob-app-killer.service#L7)

**Problème**
1. `mine()` fait `touch /var/lib/bobcoin/last-mine` : cela change la **date de modification** du fichier mais son **contenu reste vide**. Le script lit le contenu : vide, donc 0. `age` vaut alors l'epoch actuel, toujours supérieur à 3600, et **la purge a lieu à chaque passage** (vérifié). Aucune action de l'utilisateur ne peut l'empêcher.
2. `User=bob` est codé en dur : si l'utilisateur installé s'appelle autrement, le service échoue toutes les heures et remplit le journal d'erreurs.
3. Firefox, Steam, Discord et OBS sont fermés au milieu d'un enregistrement, d'un formulaire ou d'une partie. **Le travail non sauvegardé est perdu.**

**Correction**
- Côté minage, écrire un vrai horodatage dans le dossier d'état de l'utilisateur :
  ```bash
  state="${XDG_STATE_HOME:-$HOME/.local/state}/bobcoin"
  mkdir -p "$state"
  date +%s > "$state/last-mine"
  ```
- Côté killer, lire ce fichier avec `read_int` (SEC-03).
- En faire une **unité utilisateur** (`/etc/systemd/user/bob-app-killer.{service,timer}`), **désactivée par défaut**, à activer depuis `bobos-settings` avec une option « Mode anti-flémard (ferme tes apps !) » qui lance `systemctl --user enable --now bob-app-killer.timer`.
- Envoyer une notification 5 minutes avant de fermer quoi que ce soit (`notify-send`, qui a besoin d'un démon de notifications, voir UX-06).

---

### BOB-03 🟠 `bob fixme` ne restaure rien

**Où**
- [bob-fixme:30-53](iso/airootfs/usr/bin/bob-fixme#L30)
- [bob-update:17-19](iso/airootfs/usr/bin/bob-update#L17), dont le commentaire annonce « snapshot avant update » alors qu'aucun snapshot n'est pris

**Problème**
1. `snapper` n'est pas installé et la racine est en **ext4** (`defaultFileSystemType: "ext4"`) : la branche snapper ne s'exécute jamais.
2. `snapper --csvout list single` n'est pas une syntaxe valide (`--type single` serait correct), et l'erreur est masquée par `|| true`.
3. La solution de repli **n'installe rien**. Elle affiche une liste puis écrit « fait. ». Pire, la regex `'\[\K[^\] ]+'` capture le **premier** crochet de chaque ligne de `pacman.log`, c'est-à-dire la **date**, et non le nom du paquet.
4. Le script n'agit que si `bob-update` a été utilisé : après un `pacman -Syu` direct, il répond « rien à rollback ».

**Correction**
- **Court terme** : un vrai retour arrière à partir du cache pacman :
  ```bash
  # paquets mis à jour pendant la dernière transaction ALPM
  start=$(grep -n '\[ALPM\] transaction started' /var/log/pacman.log | tail -1 | cut -d: -f1)
  mapfile -t files < <(
    tail -n +"$start" /var/log/pacman.log \
    | sed -nE 's/.*\[ALPM\] upgraded ([^ ]+) \(([^ ]+) -> [^)]+\)/\1 \2/p' \
    | while read -r name old; do
        ls /var/cache/pacman/pkg/"$name-$old"-*.pkg.tar.zst 2>/dev/null | head -n1
      done)
  (( ${#files[@]} )) || { echo "[bob-fixme] rien à restaurer depuis le cache" >&2; exit 1; }
  printf '  %s\n' "${files[@]}"
  read -rp "Restaurer ces versions ? [o/N] " ok
  [[ $ok == [oO] ]] && pacman -U "${files[@]}"
  ```
  Garder au moins 2 versions en cache (`paccache.timer` avec `-rk2`, paquet `pacman-contrib`).
- **Cible** : Btrfs par défaut, avec `snapper`, `snap-pac` (snapshot automatique avant et après chaque transaction pacman) et `grub-btrfs` (démarrer sur un snapshot depuis GRUB). Sous-volumes dans `/etc/calamares/modules/mount.conf` :
  ```yaml
  btrfsSubvolumes:
      - { mountPoint: /,           subvolume: /@ }
      - { mountPoint: /home,       subvolume: /@home }
      - { mountPoint: /var/cache,  subvolume: /@cache }
      - { mountPoint: /var/log,    subvolume: /@log }
      - { mountPoint: /.snapshots, subvolume: /@snapshots }
  ```
  `bob fixme` affiche alors la liste des snapshots `snap-pac` et lance `snapper rollback`.

---

### BOB-04 🟡 sudo cassé

**Où** : [sudoers.d/bobos:2-3](iso/airootfs/etc/sudoers.d/bobos#L2)

**Preuve**
```
$ visudo -cf sudoers.d/bobos
sudoers-test:2:11: unknown defaults entry "lecture_never"
```

**Problème**
1. `lecture_never` n'existe pas. La bonne syntaxe est `Defaults lecture=never`.
2. `wheel ALL=…` sans `%` désigne un **utilisateur** nommé `wheel`, pas le groupe. La règle ne s'applique donc à personne.

Le commentaire « comme doas : aucune boucle possible » est donc faux.

**Correction** (live ; pour la cible, voir SEC-01)
```
Defaults lecture=never
%wheel ALL=(ALL:ALL) NOPASSWD: ALL
```
Et toujours valider avec `visudo -cf` pendant le build.

### BOB-05 🟡 `bob-update` trop brutal

**Où** : [bob-update:24](iso/airootfs/usr/bin/bob-update#L24)

**Problème**
- `pacman -Syu --noconfirm` accepte automatiquement les réponses par défaut. Avec des conflits ou des remplacements de paquets, la réponse par défaut est souvent **N**, ce qui fait échouer la mise à jour sans explication.
- Le trousseau n'est pas mis à jour en premier : quand Arch change de clés de signature, la mise à jour échoue.
- Aucune lecture des news Arch (interventions manuelles) ni de gestion des `.pacnew`.

**Correction**
```bash
echo "[bob-update] news Arch récentes :"
curl -fsS https://archlinux.org/feeds/news/ | grep -oP '<title>\K[^<]+' | sed -n '2,5p' | sed 's/^/  • /' || true
read -rp "Continuer ? [O/n] " ok; [[ $ok == [nN] ]] && exit 0
pacman -Sy --needed archlinux-keyring   # d'abord le trousseau…
pacman -Su                              # …puis le reste (interactif)
command -v pacdiff >/dev/null && pacdiff -o | sed 's/^/[pacnew] /'
```

### BOB-06 🟡 `bobcoin` : doas à chaque prompt, repli cassé, montants négatifs

**Où** : [bobcoin:9-16, 35-48](iso/airootfs/usr/bin/bobcoin#L9)

**Problème**
- `ensure_ledger` lance **deux `doas`** à **chaque affichage du prompt** (via `POWERLEVEL9K_CUSTOM_BOBCOIN`). Cela ralentit le prompt et écrit deux lignes dans le journal d'authentification à chaque commande. Si doas demande un mot de passe (après SEC-01), **le prompt se bloque**.
- `LEDGER="${LEDGER:-/tmp/…}"` ne change jamais rien, puisque `LEDGER` est toujours défini : le repli vers `/tmp` est incohérent.
- `bobcoin send x -500` **augmente** le solde, et le montant est évalué (voir SEC-03).

**Correction.** Stocker l'état par utilisateur (`~/.local/state/bobcoin`, sans doas), valider avec `^[0-9]+$` et refuser les montants ≤ 0. Pour `--prompt`, se contenter de lire le fichier, sans créer ni `chmod` quoi que ce soit.

### BOB-07 🟡 `bob-martian-eq` : mauvaise option d'EasyEffects (à confirmer)

**Où** : [bob-martian-eq:20,27](iso/airootfs/usr/bin/bob-martian-eq#L20)

**Problème.** Dans EasyEffects 7, `-p/--presets` **affiche la liste** des presets, et c'est `-l/--load-preset <nom>` qui en charge un. `-p ""` ne décharge rien. **Vérifier avec `easyeffects --help`** sur la version livrée, car les chemins de presets ont aussi changé entre les versions majeures.

### BOB-08 🔵 `aliases.zsh`

**Où** : [aliases.zsh](iso/airootfs/etc/zsh/bob/aliases.zsh)

- [L26-30](iso/airootfs/etc/zsh/bob/aliases.zsh#L26) : les deux branches du `if/else` de `mine()` font la même chose (`doas`). Et `touch` ne sert à rien de toute façon (voir BOB-02).
- [L19](iso/airootfs/etc/zsh/bob/aliases.zsh#L19) `alias wall=…` masque la commande système `wall`. [L21](iso/airootfs/etc/zsh/bob/aliases.zsh#L21) `alias bc=…` masque la **calculatrice `bc`** que beaucoup de développeurs utilisent. Préférer `bfw` et `bcb`, par exemple.
- [L4-11](iso/airootfs/etc/zsh/bob/aliases.zsh#L4) : la garde `rm` ne bloque que l'argument `/` exact (la première alternative de la regex ne peut jamais correspondre, car chaque argument est sur sa propre ligne). **`rm -rf /*` et `rm -rf ~` passent** (vérifié). GNU `rm` protège déjà `/` avec `--preserve-root`. Pour un vrai garde-fou, bloquer `/*`, `~`, `$HOME` et les dossiers de premier niveau (`/usr`, `/etc`, `/home`…).

### BOB-09 🔵 `bob`

- [bob:62](iso/airootfs/usr/bin/bob#L62) : `-Q`, `-Ss`, `-Si` et `-Qi` ne demandent pas root, mais passent quand même par doas. Ne demander l'élévation que pour `-S`, `-R`, `-U`, `-Sy*` et `-D`.
- L'aide liste `bob fetch` deux fois ; `BOB_REPO_URL` et `BOB_CACHE` ne servent à rien ; `bob update` ne transmet pas ses arguments.

### BOB-10 🔵 `bobos-screen` force 1080p sans retour arrière

**Où** : [bobos-screen:40-57](iso/airootfs/usr/bin/bobos-screen#L40)

Le script vérifie seulement la largeur **déclarée par Hyprland**, pas que l'écran affiche vraiment l'image. Sur un vieil écran VGA, le résultat peut être « Hors plage » et un écran noir **sans moyen de revenir en arrière**. **Correction :** demander une confirmation avec un retour automatique au mode précédent au bout de 15 s, comme sur les autres OS.

### BOB-11 🔵 `bobos-power` et raccourcis

- [bobos-power:9-10](iso/airootfs/usr/bin/bobos-power#L9) : `doas systemctl poweroff` est inutile, car polkit l'autorise déjà. Après SEC-01, doas demanderait un mot de passe **sans terminal** et resterait bloqué. Utiliser `systemctl poweroff` directement.
- Ajouter **Verrouiller**, **Mettre en veille** et **Hiberner** au menu.
- [hyprland.lua:110](iso/airootfs/etc/skel/.config/hypr/hyprland.lua#L110) : `SUPER+M` quitte Hyprland **sans confirmation**, et tout le travail non sauvegardé est perdu. Passer par `bobos-power` ou utiliser une combinaison plus difficile à faire par erreur.

### BOB-12 🔵 `bob-slot-machine`

- La fonction `spin()` n'est jamais appelée (code mort).
- Le cadre du solde se décale dès que le nombre change de longueur.
- Le solde est lu sans validation (voir SEC-03).
- Le plan prévoyait d'en faire un économiseur d'écran, ce qui n'est pas fait.

### BOB-13 🔵 Code dupliqué

- Le bloc « si pas root, alors doas, sinon sudo » est copié dans 7 scripts.
- Les presets mkinitcpio et la suppression de XanMod sont copiés dans les 2 installateurs.

**Correction.** Créer `/usr/lib/bobos/common.sh` (fonctions `require_root`, `read_int`, `log`) et le charger avec `source`. Une correction faite à un endroit profite alors partout (INS-05 a et BOB-11 viennent justement de ces copies).

### BOB-14 🔵 `bobos-res` écrit une ligne `#` dans un fichier Lua

**Où** : [bobos-res:47](iso/airootfs/usr/bin/bobos-res#L47)

En Lua, un commentaire s'écrit `--`. La ligne `#` ne fonctionne que parce que Lua ignore une **première** ligne commençant par `#`, prévue pour les shebangs. Écrire `-- BobOS — …`.

---

## 7. Bureau et expérience utilisateur

### UX-01 🟠 Polices : ni Nerd Font ni emoji

**Preuve.** Dans l'image, `/usr/share/fonts/` ne contient que `Adwaita`, `gnu-free`, `encodings` et `misc`.

**Impact**
- [.p10k.zsh:2](iso/airootfs/etc/skel/.p10k.zsh#L2) règle `POWERLEVEL9K_MODE=nerdfont-v3`, et `ll` utilise `eza --icons` : **des carrés vides partout** dans le terminal.
- Les emojis de `bob-slot-machine`, de `bob-say` et de la barre ne s'affichent pas non plus.

**Correction.** Ajouter `ttf-meslo-nerd` (la police recommandée par p10k) ou `ttf-nerd-fonts-symbols`, ainsi que `noto-fonts`, `noto-fonts-emoji` et `noto-fonts-cjk`. Puis régler `font_family` dans un `kitty.conf` et `font-family` dans le CSS de waybar.

### UX-02 🟠 Pas de `xdg-desktop-portal-hyprland`

**Preuve.** Seuls les portails `gtk.portal` et `kwallet.portal` sont présents dans l'image.

**Impact.** Sous Wayland, **le partage d'écran ne fonctionne pas** : Discord, OBS (capture d'écran via PipeWire), les visioconférences dans Firefox. Pour un OS qui préinstalle OBS et Discord, c'est un manque majeur.

**Correction.** Ajouter `xdg-desktop-portal-hyprland` et garder `-gtk` pour les sélecteurs de fichiers.

### UX-03 🟠 GPU Intel : ni Vulkan ni VA-API moderne

**Preuve.** `icd.d` ne contient que `nvidia_icd.json` et `radeon_icd.json`. Côté VA-API, seul `i965` est présent.

**Impact**
- **Steam et Proton (DXVK) ne fonctionnent pas** sur les puces graphiques Intel, qui équipent la majorité des portables.
- Pas de décodage vidéo matériel sur Intel Gen 11 et plus récents : `i965` ne gère que jusqu'à Coffee Lake.

**Correction.** Ajouter `vulkan-intel`, `lib32-vulkan-intel` et `intel-media-driver`.

### UX-04 🟡 `SUPER+E` lance yazi sans terminal

**Où** : [hyprland.lua:111](iso/airootfs/etc/skel/.config/hypr/hyprland.lua#L111)

yazi est une application en mode texte : lancée sans terminal, **rien ne s'ouvre**. **Correction :** `hl.dsp.exec_cmd("kitty -e yazi")`.

### UX-05 🟡 Zsh

**Où** : [.zshrc](iso/airootfs/etc/skel/.zshrc)

- `HISTFILE` et `SAVEHIST` ne sont pas définis : **zsh ne garde aucun historique** d'une session à l'autre.
- `compinit` n'est jamais appelé : `zsh-completions` est installé **pour rien**, et la complétion reste minimale.
- Aucun `bindkey` : Début, Fin et Suppr affichent `~` ou des séquences brutes selon le terminal.
- [L10-11](iso/airootfs/etc/skel/.zshrc#L10) : `custom_bobcoin` est ajouté **à gauche et à droite**, donc le solde s'affiche deux fois.
- [L35](iso/airootfs/etc/skel/.zshrc#L35) : le motd est déjà affiché par `pam_motd` à la connexion. Ici il est **affiché une seconde fois**, et à chaque nouveau terminal kitty, **à travers `bat`** (l'alias `cat='bat'` est défini plus haut dans le fichier), avec cadre et numéros de ligne.

**Correction**
```zsh
HISTFILE=~/.zsh_history; HISTSIZE=50000; SAVEHIST=50000
setopt SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE
autoload -Uz compinit && compinit
bindkey -e
bindkey '^[[H' beginning-of-line  '^[[F' end-of-line  '^[[3~' delete-char
# supprimer : POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS+=(custom_bobcoin)
# supprimer : [[ -f /etc/motd ]] && cat /etc/motd   (pam_motd l'affiche déjà sur tty)
```
En bonus : `zsh-autosuggestions` et `zsh-syntax-highlighting`.

### UX-06 🟡 Briques de bureau absentes

Constaté dans l'image et dans `packages.x86_64` :

| Manque | Conséquence | Paquet(s) proposé(s) |
|---|---|---|
| Démon de notifications | `notify-send` ne fait rien (bob-say, alertes) | `swaync` ou `mako` |
| Verrouillage et mise en veille | voir SEC-01 | `hyprlock`, `hypridle` |
| Captures d'écran | aucune touche Impr. écran | `grim`, `slurp`, `hyprshot` |
| Touches volume, luminosité, média | inactives (`wpctl` et `playerctl` sont pourtant présents) | `brightnessctl` et des raccourcis `XF86Audio*` |
| Réglage du son | aucune interface | `pavucontrol` (et un module `wireplumber` pour waybar) |
| Bluetooth | pas de casque ni de manette | `bluez`, `bluez-utils`, `blueman` |
| Impression | impossible | `cups`, `system-config-printer` |
| Énergie sur portable | autonomie réduite | `power-profiles-daemon` |
| Fond d'écran | fond uni | `hyprpaper` et un fond BobOS |
| Presse-papiers | aucun historique | `cliphist` |
| Thème GTK/Qt sombre | applications en clair | `nwg-look`, `adw-gtk-theme`, un `qt6ct.conf` |
| Agent polkit natif | `polkit-gnome` est vieillissant | `hyprpolkitagent` |

### UX-07 🔵 Branding

- [os-release:3](iso/airootfs/etc/os-release#L3) : `ID=arch`. Utiliser `ID=bobos`, `ID_LIKE=arch`, et ajouter `VERSION_ID`, `LOGO=bobos`.
- GRUB affiche « Arch » (voir INS-09).
- [branding.desc:20](iso/airootfs/etc/calamares/branding/bobos/branding.desc#L20) : la version `2026.09.22` est codée en dur. La générer depuis `iso_version` dans `build.sh`.

### UX-08 🔵 Splash et bip

- `bobos-splash` ajoute **4 s à chaque démarrage**, y compris sur le système installé : le limiter au live, ou le rendre désactivable.
- [loader.conf:3](iso/efiboot/loader/loader.conf#L3) : `beep on` fait biper le menu UEFI.

### UX-09 🔵 Deux lanceurs d'installateur

« Installer BobOS » (`bobos-install`) et « Install System » (`calamares.desktop` → `pkexec calamares`) apparaissent tous les deux. Le second contourne le script (pas de `QT_QPA_PLATFORM`, pas de journal). Masquer `calamares.desktop` (`NoDisplay=true`) ou le supprimer.

### UX-10 🔵 Français codé en dur

Tous les scripts et menus sont en français. Pour une diffusion plus large : `gettext` (`$"…"` en bash) et des fichiers `.po` par langue.

---

## 8. Réseau : pare-feu et DNS

### NET-01 🟠 Le pare-feu ne se charge jamais (erreur de syntaxe)

**Où** : [firewall.nft:23](iso/airootfs/etc/bobos/firewall.nft#L23), `udp dport 67,68 accept`

**Preuve** (nftables 1.1.6, vérification dans un espace de noms réseau isolé) :
```
$ unshare -rn nft -c -f iso/airootfs/etc/bobos/firewall.nft
firewall.nft:23:19-20: Error: Basetype of type internet network service is not bitmask
        udp dport 67,68 accept
                  ^^
```

**Problème.** Pour lister plusieurs ports, nft exige des accolades : `{ 67, 68 }`. Comme `nft -f` est transactionnel, **tout le fichier est rejeté**. `nftables.service` échoue donc à chaque démarrage, et `bob-firewall on` aussi.

**Impact.** Le « pare-feu martien » annoncé dans le README et le motd **n'a jamais protégé aucune machine** : aucune règle n'est chargée, donc tout est accepté. L'unité apparaît en échec dans `systemctl --failed`. Cela rend aussi SEC-08 et NET-02 théoriques **pour l'instant**. Ils redeviennent réels dès que la syntaxe est corrigée.

**Correction.** Remplacer le fichier par la version de NET-02 (qui passe `nft -c`). Ajouter `unshare -rn nft -c -f iso/airootfs/etc/bobos/firewall.nft` aux vérifications de `build.sh`, pour qu'une erreur de syntaxe ne puisse plus jamais arriver dans une ISO sans être vue.

### NET-02 🟠 Le pare-feu coupe le réseau de Docker (une fois NET-01 corrigé)

**Où** : [firewall.nft:5, 33-35](iso/airootfs/etc/bobos/firewall.nft#L5) et [bob-firewall:30,37](iso/airootfs/usr/bin/bob-firewall#L30)

**Problème**
1. `chain forward { policy drop; }` dans la table `inet bobos`. Avec netfilter, **un paquet rejeté par n'importe quelle chaîne de base est perdu**, même si Docker l'accepte dans sa propre table. Les conteneurs n'ont donc **aucun accès réseau sortant**.
2. `flush ruleset` en tête de fichier, et dans `bob-firewall off` et `reload`, efface **toutes** les règles, y compris le NAT de Docker et de libvirt. Il faut ensuite redémarrer Docker.

**Correction.** Ne gérer **que** sa propre table et ne pas définir de chaîne `forward` :
```nft
#!/usr/sbin/nft -f
# BobOS — pare-feu martien. On ne touche QU'À notre table : Docker/libvirt gardent les leurs.
table inet bobos
delete table inet bobos

table inet bobos {
    chain input {
        type filter hook input priority filter; policy drop;

        ct state invalid drop
        ct state established,related accept
        iif "lo" accept

        # ICMP : ping limité, le reste (erreurs, PMTU) accepté
        icmp type echo-request limit rate 5/second accept
        icmp type echo-request drop
        ip protocol icmp accept
        # ICMPv6 : NDP / RA / PMTU indispensables → jamais limités
        icmpv6 type echo-request limit rate 5/second accept
        icmpv6 type echo-request drop
        meta l4proto ipv6-icmp accept

        # DHCP clients (v4 + v6)
        udp sport 67 udp dport 68 accept
        ip6 saddr fe80::/10 udp sport 547 udp dport 546 accept

        # SSH : décommenter si sshd est activé
        # tcp dport 22 accept

        counter drop
    }
    # pas de chaîne forward : on laisse Docker/libvirt gérer le routage
}
```
Dans `bob-firewall`, `off` devient `nft delete table inet bobos` et `reload` devient `nft -f "$RULES"`. Le fichier est atomique : on ne vide plus jamais toutes les règles. Valider avec `nft -c -f /etc/bobos/firewall.nft` avant de l'intégrer au build.

### NET-03 🟡 DNS

**Où** : [resolved.conf.d/bobos.conf:6-10](iso/airootfs/etc/systemd/resolved.conf.d/bobos.conf#L6)

**Problème**
- `2620:fe::fe::fe` n'est **pas une adresse IPv6 valide**, car elle contient deux `::`. La bonne adresse Quad9 est `2620:fe::9`.
- `Domains=~.` envoie **toutes** les requêtes vers Quad9 et ignore les DNS du réseau (DHCP). Les noms locaux (`box.lan`, intranet, NAS) et les portails captifs (hôtel, gare) ne fonctionnent plus.
- `DNSSEC=yes`, strict, casse sur certains réseaux et quand l'horloge est fausse (voir INS-08). Cela contredit le commentaire « JAMAIS de résolution morte ».
- `FallbackDNS=` n'est jamais utilisé tant que `DNS=` est défini.

**Correction**
```ini
[Resolve]
DNS=9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net 2620:fe::fe#dns.quad9.net 2620:fe::9#dns.quad9.net
DNSOverTLS=opportunistic
DNSSEC=allow-downgrade
# Domains=~.   ← retiré : les DNS du réseau local restent utilisés pour leurs domaines
LLMNR=no
MulticastDNS=no
```

### NET-04 🟡 IPv6

**Problème.** `ip6 nexthdr icmpv6 limit rate 5/second` limite aussi la **découverte de voisins et les annonces de routeur**, ce qui rend IPv6 instable dès qu'il y a du trafic. Rien n'autorise la réponse DHCPv6 (port 546), que conntrack ne rattache pas à la requête multicast. **Correction :** déjà incluse dans le pare-feu de NET-02.

### NET-05 🔵 Découverte en réseau local bloquée

Tout l'entrant étant bloqué, Steam Remote Play (UDP 27031-27036, TCP 27036-27037), KDE Connect (1714-1764) et LocalSend (53317) ne fonctionnent pas. Proposer deux **profils** dans `bob-firewall` : `maison`, qui ouvre ces ports sur le LAN (`ip saddr { 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12 }`), et `public`, qui reste strict.

---

## 9. Build, dépôt git et packaging

### BLD-01 🟠 Binaires Calamares commités dans git et extraits en root

**Où** : [build.sh:72-79](build.sh#L72)

**Preuve.** **359 des 474 fichiers suivis par git** sont des produits de compilation de Calamares : `.so`, headers, fichiers cmake, `.mo`, le binaire `calamares` de 2 Mo. Ils sont extraits **en root** dans l'arborescence source (`libcalamares.so*` appartiennent à `root:root`).

**Impact**
- Le dépôt est lourd et bruyant.
- Des fichiers root dans le dépôt de l'utilisateur font échouer `git clean` et `git checkout`.
- Dans l'image, ces fichiers **n'appartiennent à aucun paquet** : pacman ne peut ni les mettre à jour ni les retirer (d'où INS-07).

**Correction.** Utiliser un **dépôt local** pendant le build :
```bash
# build.sh
LOCALREPO=/var/tmp/bobos-localrepo
install -d "$LOCALREPO"
cp "$CALA_PKG" "$LOCALREPO/"
repo-add -n "$LOCALREPO/bobos-local.db.tar.zst" "$LOCALREPO"/*.pkg.tar.zst
```
```ini
# iso/pacman.conf — EN PREMIER pour que ses paquets gagnent
[bobos-local]
SigLevel = Optional TrustAll
Server = file:///var/tmp/bobos-localrepo
```
Ajouter `calamares` à `packages.x86_64`, supprimer l'étape `bsdtar -xf … -C iso/airootfs`, puis :
```bash
git rm -r --cached iso/airootfs/usr/include iso/airootfs/usr/lib/calamares \
  iso/airootfs/usr/lib/cmake iso/airootfs/usr/lib/libcalamares* \
  iso/airootfs/usr/share/calamares iso/airootfs/usr/share/locale \
  iso/airootfs/usr/share/man/man8/calamares.8.gz iso/airootfs/usr/bin/calamares \
  iso/airootfs/usr/share/polkit-1 iso/airootfs/usr/share/applications/calamares.desktop \
  iso/airootfs/usr/share/icons/hicolor/scalable/apps/calamares.svg
sudo chown -R "$USER:" iso/airootfs
```

### BLD-02 🟠 Scripts BobOS livrés hors paquets : aucune mise à jour possible

**Problème**
- Les 21 scripts, les unités, les dotfiles et la configuration sont copiés **en dur** dans `airootfs`. Une fois BobOS installé, **aucune correction ne peut jamais atteindre les utilisateurs** : même les corrections de ce rapport ne s'appliqueraient qu'aux nouvelles installations.
- Installer le paquet `bob` depuis `bob-core`, comme le propose le README, échouerait avec « exists in filesystem », puisque `/usr/bin/bob` existe déjà sans appartenir à aucun paquet.
- [packages/bob/PKGBUILD](packages/bob/PKGBUILD) ne peut pas être construit : les sources sont absentes à côté, les sommes sont en `SKIP`, et la licence `GPL3` n'est pas au format SPDX.
- Les PKGBUILDs de `bobcoin`, `crepes-galactiques` et `bob-os-meta`, cités par le README, **ne sont pas dans le dépôt**.

**Correction.** Un paquet par brique, construit depuis ce dépôt :

| Paquet | Contenu |
|---|---|
| `bobos-scripts` | `bob`, `bob-*`, `bobcoin`, `crepes-galactiques`, `/usr/lib/bobos/common.sh` |
| `bobos-desktop` | `bobos-settings`, `-screen`, `-res`, `-power`, les `.desktop` et les icônes |
| `bobos-skel` | dotfiles, installés dans `/etc/skel` |
| `bobos-branding` | `os-release`, `issue`, `motd`, logos, fond d'écran, thème GRUB |
| `bobos-system` | nftables, resolved, polkit, units dans `/usr/lib/systemd/system`, presets |
| `bobos-keyring` | clés du dépôt (SEC-02) |
| `bobos-installer` | configuration Calamares et `bobos-install*` (live uniquement, retiré après l'installation) |
| `bobos-meta` | dépend de tout ce qui précède |

Exemple de PKGBUILD :
```bash
pkgname=bobos-scripts
pkgver=1.1.0
pkgrel=1
pkgdesc="Outils en ligne de commande BobOS (bob, bob-update, bobcoin…)"
arch=('any')
url="https://bob.xem.yt/"
license=('GPL-3.0-or-later')
depends=('bash' 'pacman' 'pacman-contrib' 'rsync' 'jq')
source=(bob bob-update bob-fixme bobcoin crepes-galactiques common.sh)
sha256sums=('…')   # généré par `updpkgsums`
package() {
  install -Dm755 -t "$pkgdir/usr/bin" bob bob-update bob-fixme bobcoin crepes-galactiques
  install -Dm644 common.sh "$pkgdir/usr/lib/bobos/common.sh"
}
```

### BLD-03 🟡 Priorité des dépôts mal comprise ; README inexact

**Où** : [iso/pacman.conf:22-25](iso/pacman.conf#L22) et [README.md:21](README.md#L21)

**Problème**
- Le commentaire dit que bob-core « gagne toujours quand sa version est supérieure ». **C'est faux.** pacman prend le **premier dépôt** qui contient le paquet, sans comparer les versions. Avec `bob-core` en dernier, un paquet qui existe aussi dans core ou extra ne sera **jamais** pris dans bob-core, même s'il y est plus récent.
- Le README annonce que bob-core fournit hyprland. Selon le journal du build, **seuls** `linux-xanmod`, `linux-xanmod-headers` et `zsh-theme-powerlevel10k-git` viennent de bob-core (hyprland vient d'extra).
- Le README parle de « GRUB BIOS + UEFI », ce qui n'est vrai que pour Calamares (la CLI utilise rEFInd).

**Correction.** Corriger le commentaire et le README. Si un paquet d'extra doit un jour être remplacé, lui donner un nom distinct (`hyprland-bobos` avec `provides=`/`conflicts=`) plutôt que de jouer sur l'ordre des dépôts.

### BLD-04 🟡 Modules XanMod non compressés ; initramfs énormes

**Preuve**
- `/usr/lib/modules/7.2.6-x64v3-xanmod1-1` pèse **831 Mo**, avec 6 488 fichiers `.ko` non compressés. Le noyau stock ne pèse que **183 Mo**.
- `initramfs-linux.img` fait **222 Mo** et `initramfs-linux-xanmod.img` **207 Mo** (xz -9e, sans `autodetect`, avec les hooks PXE).

**Impact.** Environ 650 Mo de plus dans l'ISO et sur chaque installation, et un démarrage lent sur les vieilles machines (décompression et RAM).

**Correction**
- Construire XanMod avec `CONFIG_MODULE_COMPRESS_ZSTD=y` et `INSTALL_MOD_STRIP=1`.
- Retirer les hooks PXE (INS-10).
- Pour le live, envisager `COMPRESSION="zstd"`, plus rapide à décompresser.
- Sur la cible, `default` avec `autodetect` suffit.

### BLD-05 🟡 `build.sh`

- [L101-105](build.sh#L101) : `tee -a` fait grossir `build.log` indéfiniment (1,9 Mo, environ 12 builds mélangés). Créer un fichier par build : `LOG="$OUT/build-$(date +%Y%m%d-%H%M%S).log"`.
- **14 Go** restent dans `/var/tmp/bobos-work` après le build. `mkarchiso -r` supprime le dossier de travail à la fin.
- Le cache Calamares est identifié uniquement par la version : un changement du PKGBUILD à version égale est ignoré. Utiliser par exemple `CALA_KEY=$(sha256sum calamares/PKGBUILD | cut -c1-12)`.
- La relance en cas d'échec refait `seed_keyring` sur le mauvais chemin (voir INS-01).
- Pas de somme de contrôle ni de signature de l'ISO. Ajouter :
  ```bash
  ( cd "$OUT" && sha256sum bobos-*.iso > SHA256SUMS && gpg --detach-sign --armor SHA256SUMS )
  ```
- Pas de vérifications automatiques pendant le build : `bash -n` et `shellcheck` sur `iso/airootfs/usr/bin/*`, `visudo -cf`, `nft -c -f`, validation YAML de la configuration Calamares.

### BLD-06 🔵 Écarts entre `plan-summary.md` et la réalité

| Prévu dans le plan | État |
|---|---|
| rEFInd avec thème Bob animé et ASCII KEKW | ❌ GRUB avec Calamares ; rEFInd sans thème avec la CLI |
| Détection automatique NVIDIA/AMD | ❌ tout est installé, et NVIDIA est cassé sous XanMod (INS-02) |
| `bob fixme` (rollback de type snapshot) | ❌ ne fait rien (BOB-03) |
| `bob dotfiles apply` | ⚠️ destructeur (BOB-01) |
| Économiseur d'écran « Machine à sous » | ❌ absent (pas de gestion de l'inactivité) |
| Firefox avec thème sombre BobCord | ⚠️ seulement une page d'accueil locale |
| Vesktop | ❌ Discord officiel à la place |
| `bob-setup` : « t'es un dev ? » | ⚠️ affiche seulement des versions |

---

## 10. Features manquantes utiles

### Système et maintenance
| Feature | Intérêt | Comment |
|---|---|---|
| **Snapshots Btrfs** | rend `bob fixme` réel, permet de démarrer sur un snapshot | Btrfs par défaut, `snapper`, `snap-pac`, `grub-btrfs` (BOB-03) |
| **Nettoyage du cache pacman** | évite que `/var/cache` grossisse sans fin | `pacman-contrib`, `paccache.timer` (`-rk2`) |
| **Miroirs à jour** | un seul miroir, c'est plus aucune mise à jour s'il tombe | `reflector`, `reflector.timer` |
| **zram** | fluidité sur les machines avec peu de RAM (aucun swap aujourd'hui) | `zram-generator` (`zram-size = ram / 2`) |
| **TRIM SSD** | durée de vie et performances des SSD | activer `fstrim.timer` |
| **Mises à jour de firmware** | BIOS, SSD, périphériques | `fwupd` |
| **Notification de mises à jour** | savoir quand lancer `bob-update` | module waybar basé sur `checkupdates` |
| **News Arch avant mise à jour** | éviter les pièges des interventions manuelles | intégré à `bob-update` (BOB-05) |

### Sécurité
| Feature | Comment |
|---|---|
| Chiffrement LUKS2 (option) | SEC-07 ; plus tard `systemd-cryptenroll --tpm2-device=auto` |
| Secure Boot | `sbctl` (clés personnelles), ou `shim-signed` pour les PC déjà configurés |
| Écran de connexion | `greetd` et `tuigreet`, ou SDDM avec thème BobOS |
| Verrouillage et inactivité | `hyprlock` et `hypridle` (SEC-01) |
| Dépôt et ISO signés | SEC-02 et BLD-05 |
| Profils de pare-feu | NET-05 (`maison` / `public`) |

### Matériel
| Feature | Comment |
|---|---|
| Microcode | `intel-ucode`, `amd-ucode` (SEC-06) |
| Détection GPU au moment de l'installation | ne garder que les pilotes utiles (INS-02) |
| Intel complet | `vulkan-intel`, `lib32-vulkan-intel`, `intel-media-driver` (UX-03) |
| Bluetooth, impression, énergie, luminosité | UX-06 |

### Bureau
Notifications, capture d'écran, presse-papiers, fond d'écran, OSD pour le volume et la luminosité (`swayosd`), module de disposition clavier dans waybar, thème sombre GTK/Qt, `xdg-desktop-portal-hyprland`. Voir UX-02 et UX-06.

### Logiciels
| Feature | Comment |
|---|---|
| AUR | `paru` préinstallé, avec `bob -S` qui se replie sur l'AUR après confirmation |
| Flatpak et Flathub | `flatpak` et une source Flathub préconfigurée |
| Jeu | `gamemode`, `lib32-gamemode`, `mangohud`, `gamescope` |
| Docker sans root (option) | groupe `docker` proposé dans `bob-setup`, ou rootless Docker |

### Installateur et premier démarrage
- Modules Calamares `locale`, `keyboard`, `grubcfg`, `services-systemd`, `packages` (pour retirer les éléments propres au live), avec choix du noyau et du chiffrement.
- Une application de bienvenue **graphique**, dans le style de `bobos-settings` avec wofi, à la place de `bob-setup` sur tty (que la plupart des utilisateurs ne verront jamais, puisque Hyprland démarre juste après).
- Transmission du clavier choisi à Hyprland (INS-03).

### Outils de développement du projet
- **CI** (GitHub Actions ou Forgejo) : build de l'ISO dans un conteneur `archlinux:latest`, `shellcheck`, `visudo -c`, `nft -c`.
- **Test de démarrage automatisé** : QEMU sans affichage, puis vérification que `systemctl --failed` est vide, que `pacman-key --list-keys` fonctionne et que `curl` passe.
- Tests unitaires des scripts avec `bats` (`bobcoin`, `bob-fixme`, `bob`).
- Versions numérotées, `CHANGELOG.md` et notes de version.

---

## 11. Plan d'action priorisé

### Phase 0 : avant de diffuser une ISO (≈ 1 à 2 jours)
- [ ] **INS-01** : trousseau pacman (`pacman-init.service` et `pacman-key` sur la cible), `pacman.conf` et mirrorlist uniques
- [ ] **SEC-04** : supprimer `seed_keyring()`
- [ ] **INS-02** : `nvidia-open-dkms` et `linux-headers`
- [ ] **SEC-01** : doas avec mot de passe, pas d'autologin et `hyprlock`/`hypridle` sur la cible
- [ ] **BOB-01** : `bob dotfiles apply` sans root, avec sauvegarde
- [ ] **BOB-02** : app-killer en opt-in, en unité utilisateur, avec un horodatage réel
- [ ] **SEC-03** : valider les entiers, état par utilisateur, retirer le 0777
- [ ] **INS-04** : `requiredStorage: 20`
- [ ] **INS-07** : retirer l'installateur de la cible
- [ ] **NET-01**, **NET-02**, **NET-03** : pare-feu qui se charge vraiment, sans `flush ruleset` ni `forward` ; DNS corrigé
- [ ] **BOB-04** : sudoers valide
- [ ] **SEC-05** et **INS-05** : supprimer la CLI, ou la brancher sur `bobos-target-fixes`

### Phase 1 : un installateur propre (≈ 1 semaine)
- [ ] INS-03 (locale, clavier, fuseau), INS-06, INS-08, INS-09, INS-10, INS-12
- [ ] SEC-06 (microcode), SEC-07 (LUKS), SEC-08, SEC-09
- [ ] UX-01, UX-02, UX-03 (polices, portail, Intel)
- [ ] BLD-01 : Calamares en paquet, nettoyage de git

### Phase 2 : packaging et maintenance (≈ 2 semaines)
- [ ] BLD-02 : paquets `bobos-*` et `bobos-meta` ; les scripts sortent d'`airootfs`
- [ ] SEC-02 : dépôt signé et `bobos-keyring`
- [ ] BOB-03 : Btrfs, snapper, snap-pac, grub-btrfs ; vrai `bob fixme`
- [ ] BOB-05, BOB-06, BOB-13 (bibliothèque commune)
- [ ] BLD-05 : CI, shellcheck, checksums, test de démarrage QEMU

### Phase 3 : features (en continu)
- [ ] UX-05, UX-06 (bureau complet), NET-05, écran de connexion
- [ ] AUR et Flatpak, outils de jeu, application de bienvenue graphique
- [ ] Thème rEFInd ou GRUB animé (plan), économiseur « Machine à sous », Vesktop
- [ ] Traductions (UX-10), Secure Boot

---

## 12. Points forts à conserver

- La **somme SHA-256 du tarball Calamares** est vérifiée avant la compilation, qui se fait dans un **chroot jetable** : l'hôte reste propre.
- `set -euo pipefail` est utilisé presque partout, et les erreurs sont en général bien signalées.
- **Double noyau** (stock et XanMod), avec le noyau stock par défaut dans le menu du live : bon réflexe pour les vieux CPU.
- `bobos-install` gère l'élévation proprement (tester avant `exec`) et **se replie sur la CLI** si Calamares est absent.
- La CLI **vérifie que le disque est réellement démarrable** (signature MBR, `core.img`, `BOOTX64.EFI`) avant d'annoncer la réussite.
- `bobos-mount-iso` gère le cas Ventoy / clé USB (archiso #2068).
- Firefox : télémétrie et Studies désactivées ; DNS chiffré (DoT) par défaut.
- Le code est bien commenté, et le « pourquoi » des choix est expliqué, ce qui a rendu cet audit beaucoup plus simple.

---

## 13. Annexe : checklist de validation en VM

À lancer sur une installation fraîche (Calamares) après les corrections de la phase 0 :

```bash
systemctl --failed                                  # doit être vide
pacman-key --list-keys | head -3                    # trousseau présent
pacman -Syu --print | tail -3                       # dépôts joignables, signatures OK
doas true                                           # doit DEMANDER un mot de passe
sudo -l                                             # règle %wheel visible
visudo -c && doas -C /etc/doas.conf && echo OK
localectl; timedatectl | grep -E 'zone|synchronized'
echo $LANG                                          # fr_FR.UTF-8 (ou choix de l'installateur)
resolvectl status | head -20                        # DNS valides, pas d'erreur
systemctl is-active nftables                         # active (pas failed)
nft list ruleset | grep -c "table"                  # bobos + tables docker
docker run --rm alpine ping -c1 9.9.9.9             # réseau des conteneurs OK
fc-list | grep -iE 'nerd|emoji' | head -3           # polices présentes
lsmod | grep -E '^(nvidia|amdgpu|i915|xe) '         # pilote GPU chargé (sous XanMod ET stock)
ls /usr/share/applications | grep -i -E 'calamares|installer'   # doit être vide
stat -c '%U %a' /var/lib/bobcoin 2>/dev/null        # absent, ou non world-writable
```
