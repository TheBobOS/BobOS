#!/usr/bin/env bash
# BobOS — profil archiso
set -euo pipefail

iso_name="bobos"
iso_label="BOBOS_$(date +%Y%m)"
iso_publisher="RicPC <bob@bob.xem.yt>"
iso_application="BobOS"
iso_version="$(date +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux' 'uefi.systemd-boot')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '19' '-b' '1M')
file_permissions=(
  ['/etc/shadow']='0:0:0400'
  ['/etc/gshadow']='0:0:0400'
  ['/etc/sudoers.d/bobos']='0:0:0440'
  ['/etc/doas.conf']='0:0:0440'
  ['/etc/polkit-1/rules.d/50-bobos.rules']='0:0:0444'
  ['/usr/local/bin/bobos-create-user']='0:0:0755'
  ['/usr/bin/bob']='0:0:0755'
  ['/usr/bin/bob-update']='0:0:0755'
  ['/usr/bin/bob-fetch']='0:0:0755'
  ['/usr/bin/bob-fixme']='0:0:0755'
  ['/usr/bin/bob-setup']='0:0:0755'
  ['/usr/bin/bobcoin']='0:0:0755'
  ['/usr/bin/bob-say']='0:0:0755'
  ['/usr/bin/bob-firewall']='0:0:0755'
  ['/usr/bin/bob-slot-machine']='0:0:0755'
  ['/usr/bin/bob-app-killer']='0:0:0755'
  ['/usr/bin/bob-martian-eq']='0:0:0755'
  ['/usr/bin/crepes-galactiques']='0:0:0755'
  ['/usr/bin/bobos-splash']='0:0:0755'
  ['/usr/bin/calamares']='0:0:0755'
  ['/usr/bin/bobos-install']='0:0:0755'
  ['/usr/bin/bobos-install-cli']='0:0:0755'
  ['/usr/bin/bobos-target-fixes']='0:0:0755'
  ['/usr/bin/bobos-mount-iso']='0:0:0755'
  ['/usr/bin/bobos-res']='0:0:0755'
  ['/usr/bin/bobos-screen']='0:0:0755'
  ['/usr/bin/bobos-power']='0:0:0755'
  ['/usr/bin/bobos-settings']='0:0:0755'
  ['/usr/bin/neofetch']='0:0:0755'
)
