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
    # scripts retirés de BobOS (bob-fetch, bobos-install-cli)
    rm -f iso/airootfs/usr/bin/bob-fetch iso/airootfs/usr/bin/bobos-install-cli
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
    if command -v nft >/dev/null; then
        for r in iso/airootfs/etc/bobos/firewall*.nft; do
            unshare -rn nft -c -f "$r" >/dev/null 2>&1 \
                && echo "  ✓ $(basename "$r")" || { echo "  ✗ $(basename "$r") : syntaxe nft invalide"; fail=1; }
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

    echo "[check] profil : exécutables airootfs épinglés dans profiledef.sh ?"
    while IFS= read -r f; do
        rel="/${f#iso/airootfs/}"
        # les .so n'ont pas besoin du bit x (dlopen), on les ignore
        case "$rel" in *.so|*.so.*) continue ;; esac
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
