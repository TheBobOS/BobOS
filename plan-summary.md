**BobOS — Plan de build**

> ⚠️ Document de conception d'origine, conservé pour l'histoire. L'état
> réel de l'OS est dans le `README.md` ; l'audit complet (62 constats) et ce
> qui a été corrigé sont dans `RAPPORT-AUDIT.md`. Écarts connus avec ce plan :
> GRUB au lieu de rEFInd (Calamares), installateur graphique unique,
> `bob fixme` refait depuis le cache pacman, `bob dotfiles apply` non
> destructif, pas de Vesktop (Discord officiel), `bob-setup` n'affiche que
> des versions.

*Base système*
- Arch Linux (rolling, douleur assumée)
- Kernel `linux-xanmod` (perf gaming/latence)
- WM : Hyprland (Wayland, animations)

*Boot*
- rEFInd avec thème Bob animé (logo bob.xem.yt qui tourne) au lieu de GRUB/systemd-boot — un seul bootloader stylé plutôt que trois concurrents
- Écran de boot : gros ASCII "BOBOS" + KEKW clignotant intégré au thème rEFInd

*Package manager*
- `bob` (wrapper pacman, repo custom `[bob-core]`)
- Noms de paquets délirants (`bob -S crepes-galactiques`)
- Sous-commandes utiles : `bob-update`, `bob-fetch`, `bob dotfiles apply`, et le panic button `bob fixme` (rollback de la dernière update, façon Timeshift/snapshot)

*Shell & CLI*
- Zsh + Powerlevel10k + plugins Bob
- Prompt avec solde BobCoin en temps réel (script qui lit un fichier/état local et l'injecte dans le prompt)

*Fichiers & navigation*
- yazi comme file manager (TUI)

*Drivers*
- NVIDIA + AMDGPU préchargés à l'install (détection auto au lieu de choisir l'un ou l'autre)

*Son*
- PipeWire, equalizer pré-réglé "mode martien"

*Sécurité*
- `doas` à la place de sudo, mot de passe unique `bob` (gag assumé, pas pour un vrai OS)
- `bob-firewall` (wrapper iptables/nftables)
- `bob-say` (TTS qui gueule "arrête de toucher aux configs" sur un `rm -rf /`)

*Apps préinstallées*
- Firefox (thème sombre BobCord en homepage), Vesktop, VS Code, OBS, mpv, Discord, Steam

*Premier boot*
- `bob-setup` : wizard qui demande "t'es un dev ?" → installe node/python/docker si oui

*Gimmicks*
- Écran de veille : Machine à Sous Martienne en boucle
- App killer : script qui ferme tout si pas de minage dans l'heure
