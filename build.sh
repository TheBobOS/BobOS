#!/usr/bin/env bash
# BobOS — build complet de l'ISO
set -euo pipefail
cd "$(dirname "$0")"

if [[ $EUID -ne 0 ]]; then
    echo "[build] besoin de root pour mkarchiso — relance : sudo ./build.sh"
    exit 1
fi

# archiso manquant ? on l'installe
if ! command -v mkarchiso &>/dev/null; then
    echo "[build] installation d'archiso..."
    pacman -S --needed --noconfirm archiso
fi

# /tmp est un tmpfs de 3.8G sur ce host → le workdir va sur le disque
WORK="/var/tmp/bobos-work"
OUT="$(pwd)/out"
LOCALREPO="/var/tmp/bobos-localrepo"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$OUT/build-$STAMP.log"          # un log par build (avant : 12 builds mélangés)
export PACKAGE_USERNAME="BobOS Build"
export PACKAGE_EMAIL="bob@bob.xem.yt"

# L'utilisateur réel : le workdir et l'arbre du profil lui appartiennent, pas
# à root (sinon git clean / checkout échouent ensuite).
BUILD_USER="${SUDO_USER:-${USER:-root}}"

echo "[build] nettoyage du workdir..."
rm -rf "$WORK"

# ---------------------------------------------------------------------------
# Calamares : compilé UNE fois dans un chroot jetable, puis servi par un dépôt
# local [bobos-local]. On ne l'extrait PLUS dans l'arbre du profil : ses
# fichiers appartenaient à aucun paquet, donc pacman ne pouvait ni les mettre à
# jour ni les désinstaller, et 359 fichiers de build traînaient dans git.
# ---------------------------------------------------------------------------
CALA_VER="3.4.3"
CALA_SHA256="144cbbf6bdcebfb21685950db4f0777218519df095f62f4aa392f28348110d18"
CALA_CACHE="/var/tmp/bobos-calamares"
CALA_PKG="$CALA_CACHE/out/calamares-${CALA_VER}-1-x86_64.pkg.tar.zst"

build_calamares() {
    if [[ -f "$CALA_PKG" ]]; then
        echo "[build] Calamares ${CALA_VER} déjà compilé ($CALA_PKG)"
        return
    fi

    echo "[build] compilation de Calamares ${CALA_VER} (1re fois : ~10 min)..."
    local ch="$CALA_CACHE/chroot"
    rm -rf "$ch"
    mkdir -p "$ch/etc/pacman.d" "$CALA_CACHE/out"

    # clé maîtresse du chroot NEUF (on ne recopie JAMAIS le trousseau de
    # l'hôte : l'ISO embarquerait une clé privée lisible par tous)
    pacstrap -C "$(pwd)/iso/pacman.conf" -M "$ch" \
        base-devel cmake ninja git curl \
        extra-cmake-modules libglvnd \
        qt6-base qt6-declarative qt6-svg qt6-tools qt6-translations qt6-wayland \
        kcoreaddons kpmcore libpwquality yaml-cpp
    arch-chroot "$ch" pacman-key --init
    arch-chroot "$ch" pacman-key --populate archlinux

    arch-chroot "$ch" useradd -m builder
    install -d -m 0755 "$CALA_CACHE/src"
    cp calamares/PKGBUILD "$CALA_CACHE/src/"
    curl -fL -o "$CALA_CACHE/src/calamares-${CALA_VER}.tar.gz" \
        "https://codeberg.org/Calamares/calamares/releases/download/v${CALA_VER}/calamares-${CALA_VER}.tar.gz"
    echo "[build] vérification du sha256 du tarball..."
    ( cd "$CALA_CACHE/src" \
      && echo "$CALA_SHA256  calamares-${CALA_VER}.tar.gz" | sha256sum -c - )

    arch-chroot "$ch" mkdir -p /build
    cp "$CALA_CACHE/src/PKGBUILD" "$CALA_CACHE/src/calamares-${CALA_VER}.tar.gz" "$ch/build/"
    arch-chroot "$ch" chown -R builder:builder /build
    arch-chroot "$ch" su builder -c 'cd /build && makepkg -s --noconfirm'
    cp "$ch"/build/calamares-[0-9]*.pkg.tar.zst "$CALA_CACHE/out/"
    rm -rf "$ch"
    echo "[build] Calamares compilé → $CALA_PKG"
}

make_local_repo() {
    echo "[build] dépôt local [bobos-local] (Calamares)..."
    rm -rf "$LOCALREPO"
    install -d -m 0755 "$LOCALREPO"
    install -m 0644 "$CALA_PKG" "$LOCALREPO/"
    # -n : uniquement les paquets absents de la base ; pas de signature (le
    # dépôt est en file://, local au build, et SigLevel=Optional côté pacman)
    repo-add -n "$LOCALREPO/bobos-local.db.tar.zst" "$LOCALREPO"/calamares-[0-9]*.pkg.tar.zst
}

# Nettoyage de l'arbre du profil : ces fichiers ne doivent plus exister dans
# l'image. Nécessite root (certains sont root:root à cause de l'ancienne
# extraction de Calamares).
clean_profile() {
    echo "[build] nettoyage de l'arbre du profil (artefacts de l'ancienne méthode)…"
    # Calamares : plus de fichiers-extraits à la main (désormais un paquet)
    rm -rf iso/airootfs/usr/lib/calamares \
           iso/airootfs/usr/include/libcalamares \
           iso/airootfs/usr/lib/cmake \
           iso/airootfs/usr/share/calamares \
           iso/airootfs/usr/share/locale \
           iso/airootfs/usr/share/polkit-1 \
           iso/airootfs/usr/share/icons/hicolor/scalable/apps/calamares.svg \
           iso/airootfs/usr/share/applications/calamares.desktop \
           iso/airootfs/usr/share/man/man8/calamares.8.gz \
           iso/airootfs/usr/bin/calamares
    rm -f iso/airootfs/usr/lib/libcalamares*.so*
    # scripts retirés de BobOS (bob-fetch, bobos-install-cli, neofetch)
    rm -f iso/airootfs/usr/bin/bob-fetch iso/airootfs/usr/bin/bobos-install-cli \
          iso/airootfs/usr/bin/neofetch
    # l'arbre redevient propriété de l'utilisateur (git clean, checkout…)
    chown -R "$BUILD_USER" iso/ 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Vérifications AVANT de lancer un build de 40 minutes : chacune de ces
# erreurs a déjà coûté un build complet à quelqu'un.
# ---------------------------------------------------------------------------
run_checks() {
    local fail=0
    echo "[check] syntaxe des scripts BobOS…"
    while IFS= read -r f; do
        # uniquement les scripts : un binaire (Calamares) ferait échouer
        # « bash -n » pour une raison sans rapport
        head -c2 "$f" 2>/dev/null | grep -q '#!' || continue
        bash -n "$f" 2>/dev/null || { echo "  ✗ $f"; fail=1; }
    done < <(find iso/airootfs/usr/bin iso/airootfs/usr/local/bin \
                  iso/airootfs/root -type f -name '*' 2>/dev/null)
    [[ $fail -eq 0 ]] && echo "  ✓ bash -n"

    echo "[check] sudoers (visudo)…"
    if command -v visudo >/dev/null; then
        visudo -cf iso/airootfs/etc/sudoers.d/bobos >/dev/null 2>&1 \
            && echo "  ✓ sudoers valide" || { echo "  ✗ sudoers INVALIDE"; fail=1; }
    fi

    echo "[check] doas.conf (doas -C)…"
    if command -v doas >/dev/null; then
        doas -C iso/airootfs/etc/doas.conf >/dev/null 2>&1 \
            && echo "  ✓ doas.conf valide" || { echo "  ✗ doas.conf INVALIDE"; fail=1; }
    fi

    echo "[check] règles nftables (nft -c -f)…"
    if command -v nft >/dev/null 2>&1; then
        # « nft --check » ne modifie RIEN mais il a besoin des privilèges
        # netlink. Deux stratégies, et surtout on distingue « l'outil n'a pas
        # pu démarrer » de « le fichier contient une vraie erreur » : le
        # premier saute le contrôle, le second bloque le build.
        nft_env_error() {
            case "$1" in
                *"cache initialization failed"*|*"Operation not permitted"*|\
                *"Cannot open netlink"*|*"netlink: Error"*|*"Permission denied"*|"") return 0 ;;
                *) return 1 ;;
            esac
        }
        nft_check() {
            local f="$1" out1="" out2="" rc1=0 rc2=0
            out1="$(unshare -rn nft -c -f "$f" 2>&1)" || rc1=$?
            if (( rc1 == 0 )); then
                return 0                                   # règles valides
            fi
            if ! nft_env_error "$out1"; then
                printf '%s\n' "$out1"                       # vraie erreur
                return 1
            fi
            # la 1re tentative manquait de privilèges → on réessaie directement
            out2="$(nft -c -f "$f" 2>&1)" || rc2=$?
            if (( rc2 == 0 )); then
                return 0
            fi
            if ! nft_env_error "$out2"; then
                printf '%s\n' "$out2"                       # vraie erreur
                return 1
            fi
            printf '%s\n' "${out1:-$out2}"
            return 2                                       # environnement
        }

        # auto-test : le vérificateur DOIT rejeter un fichier volontairement
        # faux, sinon ce contrôle ne prouve rien
        _bad="$(mktemp /tmp/bobos-nft-bad.XXXXXX.nft)"
        printf 'table inet bobos {\n  chain input {\n    type filter hook input priority filter; policy drop;\n    udp dport 53,80 accept\n  }\n}\n' > "$_bad"
        _rc=0; nft_check "$_bad" >/dev/null 2>&1 || _rc=$?
        rm -f "$_bad"
        if [[ $_rc -eq 1 ]]; then
            echo "  ✓ auto-test : une vraie erreur est bien détectée"
        else
            echo "  ✗ le vérificateur ne détecte PAS une vraie erreur (rc=$_rc)"
            fail=1
        fi

        for r in iso/airootfs/etc/bobos/firewall*.nft; do
            nft_check "$r" >/dev/null 2>&1; _rc=$?
            case $_rc in
                0) echo "  ✓ $(basename "$r")" ;;
                2) echo "  ⚠ $(basename "$r") : contrôle sauté (nft sans privilèges ici)" ;;
                *) echo "  ✗ $(basename "$r") : syntaxe nft INVALIDE"
                   nft_check "$r" 2>&1 | sed 's/^/      /' || true
                   fail=1 ;;
            esac
        done
    fi

    echo "[check] YAML de l'installateur…"
    if python3 -c 'import yaml' 2>/dev/null; then
        python3 - <<'PY' || fail=1
import glob, sys, yaml
bad = 0
for f in glob.glob('iso/airootfs/etc/calamares/**/*.conf', recursive=True):
    try:
        list(yaml.safe_load_all(open(f, encoding='utf-8')))
    except Exception as e:
        print(f'  ✗ {f}: {e}'); bad += 1
print('  ✓ YAML Calamares' if not bad else f'  ✗ {bad} fichier(s) YAML invalide(s)')
sys.exit(1 if bad else 0)
PY
    else
        echo "  (PyYAML absent : contrôle sauté)"
    fi

    echo "[check] paquets de l'ISO : doublons ?"
    if awk 'NF && !/^#/{print $1}' iso/packages.x86_64 | sort | uniq -d | grep -q .; then
        echo "  ✗ doublons dans packages.x86_64"; fail=1
    else
        echo "  ✓ pas de doublon"
    fi

    echo "[check] menu de démarrage BIOS (syslinux)…"
    # 1) toute config Include/CONFIG référencée doit exister, sinon ISOLINUX
    #    n'a « No command specified » et le PC ne démarre pas.
    _sl=iso/syslinux/syslinux.cfg
    _miss=""
    for f in $(grep -oE '^(INCLUDE|CONFIG) +[A-Za-z0-9_.-]+\.cfg' "$_sl" 2>/dev/null | awk '{print $2}' | sort -u); do
        [[ -f "iso/syslinux/$f" ]] || _miss="$_miss $f"
    done
    if [[ -z "$_miss" ]]; then
        echo "  ✓ toutes les configs référencées existent"
    else
        echo "  ✗ config(s) référencée(s) mais absente(s) :$_miss"; fail=1
    fi
    # 2) si whichsys.c32 est réintroduit, il faut les trois branches : il
    #    choisit selon ce que le FIRMWARE croit être le mode de démarrage, et
    #    un firmware BIOS (SeaBIOS, vieux portable) est détecté « pxe » même en
    #    bootant depuis le CD. Sans la branche correspondante : plantage.
    if grep -vE '^[[:blank:]]*#' "$_sl" | grep -q "whichsys"; then
        _br=""
        for br in pxe sys iso; do
            grep -q -- "-$br- " "$_sl" || _br="$_br -$br-"
        done
        if [[ -z "$_br" ]]; then
            echo "  ✓ whichsys : branches pxe/sys/iso toutes présentes"
        else
            echo "  ✗ whichsys utilisé mais branche(s) manquante(s)$_br"
            echo "      (le PC refusera de booter : « No command specified for ISOLINUX »)"
            fail=1
        fi
    else
        echo "  ✓ pas de whichsys (détection de firmware inutile : pas de netboot)"
    fi
    # 3) le menu doit exister
    if [[ -f iso/syslinux/archiso_sys.cfg ]]; then
        echo "  ✓ archiso_sys.cfg présent"
    else
        echo "  ✗ archiso_sys.cfg manquant"; fail=1
    fi

    # 4) chaque entrée doit charger un noyau ET être capable de démarrer le
    #    live. Trois pièges déjà payés :
    #      - un APPEND sans LINUX/INITRD associé (entrée morte),
    #      - l'absence de console=tty0 : tout part en série, écran VGA noir,
    #      - l'absence de masque firstboot : systemd-firstboot attend une
    #        saisie AVANT sysinit.target → le boot s'arrête, pas de bureau.
    echo "[check] entrées de boot : noyau, initramfs, console, firstboot…"
    _bmod=$(grep -cE '^[[:blank:]]*APPEND' iso/syslinux/archiso_sys-linux.cfg)
    _prob=$(awk '
        /^[[:blank:]]*#/ { next }
        /^LABEL/  { lbl=$2; next }
        /^LINUX/  { if ($2 != "") lin=1; next }
        /^INITRD/ { if ($2 != "") ini=1; next }
        /^APPEND/ {
            if (lbl == "")            { print "APPEND hors de tout LABEL (ligne " NR ")" }
            else if (!lin || !ini)   { print "entrée " lbl " : APPEND sans LINUX/INITRD" }
            else {
                if ($0 !~ /console=tty0/)                              print "entrée " lbl " : pas de console=tty0 (écran VGA noir)"
                if ($0 !~ /systemd\.mask=systemd-firstboot\.service/)   print "entrée " lbl " : firstboot non masqué (le boot bloque sur son invite)"
                n++
            }
            lin=0; ini=0
        }
    ' iso/syslinux/archiso_sys-linux.cfg)
    _nlab=$(grep -cE '^LABEL' iso/syslinux/archiso_sys-linux.cfg)
    if [[ -n "$_prob" ]]; then
        while read -r p; do echo "  ✗ $p"; done <<< "$_prob"
        fail=1
    elif [[ "$_nlab" -gt 0 && "$_nlab" -eq "$_bmod" ]]; then
        echo "  ✓ BIOS : $_bmod entrée(s), noyau + console + masque firstboot"
    else
        echo "  ✗ BIOS : $_bmod APPEND pour $_nlab LABEL"; fail=1
    fi
    # même contrôle sur les entrées systemd-boot (UEFI)
    for f in iso/efiboot/loader/entries/*.conf; do
        [[ -f "$f" ]] || continue
        # une entrée « efi » charge un binaire EFI (memtest) : pas de noyau,
        # pas d'options — elle n'a rien à prouver ici.
        grep -qE '^[[:blank:]]*efi[[:blank:]]' "$f" && continue
        grep -qE '^[[:blank:]]*linux[[:blank:]]' "$f" || continue
        if ! grep -qE '^options .*console=tty0' "$f"; then
            echo "  ✗ UEFI $(basename "$f") : pas de console=tty0 (écran VGA noir)"; fail=1
        fi
        if ! grep -qE '^options .*systemd\.mask=systemd-firstboot\.service' "$f"; then
            echo "  ✗ UEFI $(basename "$f") : firstboot non masqué (le boot bloque)"; fail=1
        fi
    done
    _nuefi=$(grep -lE '^options .*console=tty0 .*systemd\.mask=systemd-firstboot\.service' \
                  iso/efiboot/loader/entries/*.conf 2>/dev/null | wc -l)
    if [[ "$_nuefi" -gt 0 ]]; then
        echo "  ✓ UEFI : $_nuefi entrée(s) conformes"
    else
        echo "  ✗ UEFI : aucune entrée conforme"; fail=1
    fi
    # Pas de console série : avec « console=ttyS0 », /dev/console désigne la
    # dernière console de la ligne de commande et systemd ouvre un serial-getty
    # — l'utilisateur voit « bobos login: » à la place du bureau (constaté
    # dans une VM QEMU).
    if grep -qE 'console=ttyS[0-9]' iso/syslinux/archiso_sys-linux.cfg iso/efiboot/loader/entries/*.conf 2>/dev/null; then
        echo "  ✗ console série dans une entrée de boot : son invite de connexion masque le bureau"
        grep -nE 'console=ttyS[0-9]' iso/syslinux/archiso_sys-linux.cfg iso/efiboot/loader/entries/*.conf | sed 's/^/      /'
        fail=1
    else
        echo "  ✓ pas de console série (l'écran garde le bureau)"
    fi

    echo "[check] config d'initramfs du live : rien ne doit survivre sur la cible"
    # Un drop-in dans /etc/mkinitcpio.conf.d/ est une configuration du LIVE
    # (archiso). L'image étant copiée telle quelle dans la cible, si
    # bobos-target-fixes ne le retire pas, « mkinitcpio -P » fabrique un
    # initramfs ARCHISO : le système installé affiche
    # « ERROR: '' device did not show up after 30 seconds... » puis
    # [rootfs ~]#. Constaté sur une vraie installation.
    _mkd="iso/airootfs/etc/mkinitcpio.conf.d"
    if [[ -d "$_mkd" ]]; then
        shopt -s nullglob
        for f in "$_mkd"/*; do
            _b="$(basename "$f")"
            # on cherche une VRAIE ligne « rm … <fichier> », pas une mention
            # dans un commentaire
            if grep -E '^[[:blank:]]*rm -[a-zA-Z]+' iso/airootfs/usr/bin/bobos-target-fixes \
                 | grep -qF -- "$_b"; then
                echo "  ✓ drop-in live $_b : retiré de la cible"
            else
                echo "  ✗ drop-in live $_b : bobos-target-fixes ne le retire PAS"
                echo "      → initramfs archiso sur la cible → système installé non bootable"
                fail=1
            fi
        done
        shopt -u nullglob
    fi

    echo "[check] profil : exécutables airootfs épinglés dans profiledef.sh ?"
    while IFS= read -r f; do
        rel="/${f#iso/airootfs/}"
        # les .so n'ont pas besoin du bit x (dlopen), on les ignore
        case "$rel" in
            *.so|*.so.*) continue ;;
            # fichiers que clean_profile vient de supprimer de l'arbre
            /usr/bin/calamares|/usr/bin/bob-fetch|/usr/bin/bobos-install-cli|/usr/bin/neofetch) continue ;;
            */usr/lib/calamares/*) continue ;;
        esac
        grep -q "['\"]$rel['\"]" iso/profiledef.sh \
            || { echo "  ✗ $rel n'est pas épinglé (mkarchiso le Passera en 0644 !)"; fail=1; }
    done < <(find iso/airootfs -type f -perm -u+x \
                  -not -path "*/usr/lib/calamares/*" 2>/dev/null)
    [[ $fail -eq 0 ]] && echo "  ✓ épinglages"

    return $fail
}

build_calamares
make_local_repo
clean_profile

if ! run_checks; then
    echo "[build] ÉCHEC des vérifications — rien n'a été construit."
    exit 1
fi

mkdir -p "$OUT"
echo "[build] mkarchiso — profil : iso/ → $OUT (log : $LOG)"
# -r : supprime le workdir (14 Go laissés derrière à chaque build)
mkarchiso -v -r -w "$WORK" -o "$OUT" iso/ 2>&1 | tee "$LOG"

# --- Somme de contrôle de l'ISO -------------------------------------------
ISO="$(ls -t "$OUT"/bobos-*.iso 2>/dev/null | head -1 || true)"
if [[ -n "$ISO" ]]; then
    ( cd "$OUT" && sha256sum "$(basename "$ISO")" > "SHA256SUMS-$(date +%Y%m%d)" )
    # Signature de la somme si une clé GPG de build est configurée
    if [[ -n "${BOBOS_GPG_KEY:-}" ]] && command -v gpg >/dev/null; then
        ( cd "$OUT" && gpg --batch --yes --local-user "$BOBOS_GPG_KEY" \
            --detach-sign --armor "SHA256SUMS-$(date +%Y%m%d)" )
        echo "[build] sommes signée avec $BOBOS_GPG_KEY"
    fi
fi

echo
echo "[build] Terminé :"
ls -lh "$OUT"/bobos-*.iso 2>/dev/null || true
