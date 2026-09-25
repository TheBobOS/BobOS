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
PACSTRAP_DIR="$WORK/x86_64/pacstrap_dir"
LOG="$OUT/build.log"

# Les marqueurs _run_once du build précédent feraient ignorer les étapes
# (nouveaux paquets / airootfs jamais appliqués) → on repart de zéro.
# Le cache de paquets (/var/tmp/bobos-pkgcache) est conservé.
echo "[build] nettoyage du workdir..."
rm -rf "$WORK"

# --- Calamares (l'installateur graphique « de Plasma ») ---------------------
# Pas dans les repos officiels d'Arch → on le compile une fois dans un chroot
# jetable (host non modifié), puis on extract ses fichiers dans l'airootfs.
CALA_VER="3.4.3"
CALA_PKG="/var/tmp/bobos-calamares/out/calamares-${CALA_VER}-1-x86_64.pkg.tar.zst"

build_calamares() {
    if [[ -f "$CALA_PKG" ]]; then
        echo "[build] Calamares ${CALA_VER} déjà compilé ($CALA_PKG)"
    else
        echo "[build] compilation de Calamares ${CALA_VER} (1re fois : ~10 min)..."
        local cache="/var/tmp/bobos-calamares"
        local ch="$cache/chroot"
        rm -rf "$ch"
        mkdir -p "$ch/etc/pacman.d" "$cache/out"

        # keyring Arch dans le chroot (host = Artix mais gnupg hôte vérifie les sigs Arch)
        cp -a /etc/pacman.d/gnupg "$ch/etc/pacman.d/gnupg"

        # chroot minimal avec les makedepends (pacstrap officiel via iso/pacman.conf)
        pacstrap -C "$(pwd)/iso/pacman.conf" -M "$ch" \
            base-devel cmake ninja git curl \
            extra-cmake-modules libglvnd \
            qt6-base qt6-declarative qt6-svg qt6-tools qt6-translations qt6-wayland \
            kcoreaddons kpmcore libpwquality yaml-cpp

        # builder non-root (makepkg refuse root)
        arch-chroot "$ch" useradd -m builder
        install -d -m 0755 "$cache/src"
        cp calamares/PKGBUILD "$cache/src/"
        curl -fL -o "$cache/src/calamares-${CALA_VER}.tar.gz" \
            "https://codeberg.org/Calamares/calamares/releases/download/v${CALA_VER}/calamares-${CALA_VER}.tar.gz"
        echo "[build] vérification du sha256 du tarball..."
        ( cd "$cache/src" && echo "144cbbf6bdcebfb21685950db4f0777218519df095f62f4aa392f28348110d18  calamares-${CALA_VER}.tar.gz" | sha256sum -c - )
        arch-chroot "$ch" mkdir -p /build
        cp "$cache/src/PKGBUILD" "$cache/src/calamares-${CALA_VER}.tar.gz" "$ch/build/"
        arch-chroot "$ch" chown -R builder:builder /build
        arch-chroot "$ch" su builder -c 'cd /build && makepkg -s --noconfirm'
        cp "$ch"/build/calamares-*.pkg.tar.* "$cache/out/"
        rm -rf "$ch"
        echo "[build] Calamares compilé → $CALA_PKG"
    fi

    # extraction des fichiers du paquet dans l'airootfs (hors /etc/calamares :
    # nos configs du dépôt font foi et ne doivent pas être écrasées)
    echo "[build] extraction de Calamares dans iso/airootfs..."
    bsdtar -xf "$CALA_PKG" -C iso/airootfs \
        --exclude '.PKGINFO' --exclude '.MTREE' --exclude '.BUILDINFO' \
        --exclude '.INSTALL' \
        --exclude 'etc/calamares' --exclude 'etc/calamares/*'
    chmod 0755 iso/airootfs/usr/bin/calamares 2>/dev/null || true
}

build_calamares

# mkarchiso appelle pacstrap avec -G : personne ne peuple le keyring dans le
# chroot. GPGDir n'est PAS root-prefixé (le build vérifie avec le keyring host,
# OK), mais l'ISO embarque le contenu du chroot → sans seed, la live system
# n'aurait AUCUNE clé et pacman y serait cassé. On copie donc le keyring host
# (212 clés, vérifie les sigs Arch actuelles) dans le chroot avant pacstrap —
# pacstrap saute sa propre étape si le dossier existe déjà.
seed_keyring() {
    echo "[build] seed du keyring pacman dans le chroot (clé de l'ISO live)..."
    install -d -m 0755 "$PACSTRAP_DIR/etc/pacman.d"
    rm -rf "$PACSTRAP_DIR/etc/pacman.d/gnupg"
    cp -a /etc/pacman.d/gnupg "$PACSTRAP_DIR/etc/pacman.d/gnupg"
}

mkdir -p "$OUT"
seed_keyring

echo "[build] mkarchiso — profil : iso/ → $OUT (log : $LOG)"
if ! mkarchiso -v -w "$WORK" -o "$OUT" iso/ 2>&1 | tee -a "$LOG"; then
    echo "[build] échec — re-seed du keyring + reprise (étapes finies gardées)..."
    seed_keyring
    mkarchiso -v -w "$WORK" -o "$OUT" iso/ 2>&1 | tee -a "$LOG"
fi

echo
echo "[build] Terminé :"
ls -lh "$OUT"/*.iso 2>/dev/null || true
