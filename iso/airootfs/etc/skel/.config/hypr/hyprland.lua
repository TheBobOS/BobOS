-- BobOS — Hyprland (Wayland, animations)
-- Format LUA (Hyprland 0.56+) : le format .conf affiche une popup de
-- dépréciation et sera supprimé en 0.57. Tout est donc décrit ici en Lua.

----------------------------
---- MONITEUR ---------------
----------------------------

hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
})

----------------------------
---- AUTOSTART --------------
----------------------------

hl.on("hyprland.start", function()
    hl.exec_cmd("waybar &")
    hl.exec_cmd("nm-applet &")
    hl.exec_cmd("mako --icon-size 22 &")           -- notifications
    hl.exec_cmd("hypridle &")                      -- extinction / verrouillage
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &")
    -- écran : résolution + Hz max auto (VM → 1080p, cf. bobos-screen)
    hl.exec_cmd("bobos-screen &")
    -- jeu d'accueil : Snake dans sa fenêtre au démarrage du bureau.
    -- « pgrep » évite d'ouvrir 50 serpents si la session est relancée.
    hl.exec_cmd("pgrep -x bob-snake >/dev/null || kitty --title 'Snake BobOS' -e bob-snake &")
end)

-- Réglages écran persos choisis dans Paramètres → Écran (bobos-res écrit
-- ce fichier). Optionnel : absent = simple retour silencieux.
local ok, err = pcall(require, "user")
if not ok then
    print("[bobos] config hypr/user.lua ignorée : " .. tostring(err))
end

----------------------------
---- ENVIRONNEMENT ----------
----------------------------

hl.env("XCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")

-- Portefeuille / presse-papiers avec historique (cliphist)
hl.env("WAYLAND_DISPLAY", os.getenv("WAYLAND_DISPLAY") or "wayland-1")

----------------------------
---- ASPECT / DÉCORATION ----
----------------------------

hl.config({
    general = {
        gaps_in    = 5,
        gaps_out   = 10,
        border_size = 2,
        col = {
            active_border   = { colors = { "rgba(ff00ffff)", "rgba(00ffccff)" }, angle = 45 },
            inactive_border = "rgba(555555aa)",
        },
        layout = "dwindle",
    },

    decoration = {
        rounding         = 10,
        active_opacity   = 1.0,
        inactive_opacity = 0.9,
        blur = {
            enabled = true,
            size    = 6,
            passes  = 2,
        },
    },

    animations = {
        enabled = true,
    },

    input = {
        kb_layout    = "fr",
        follow_mouse = 1,
        touchpad = {
            natural_scroll = true,
        },
    },

    dwindle = {
        preserve_split = true,
    },

    master = {
        new_status = "master",
    },
})

-- Clavier choisi pendant l'installation (bobos-target-fixes écrit ce fichier
-- seulement si l'utilisateur en a choisi un autre que fr).
pcall(require, "keyboard")

----------------------------
---- ANIMATIONS -------------
----------------------------

hl.curve("myBezier", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.0 } } })

hl.animation({ leaf = "windows",    enabled = true, speed = 4, bezier = "myBezier", style = "slide" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 4, bezier = "default",   style = "popin 80%" })
hl.animation({ leaf = "border",     enabled = true, speed = 8, bezier = "default" })
hl.animation({ leaf = "fade",       enabled = true, speed = 4, bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "default",   style = "slide" })

----------------------------
---- RACCOURCIS -------------
----------------------------

local mainMod = "SUPER"

-- Applications
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd("kitty"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd("kitty -e yazi"))   -- yazi est un TUI : il lui FAUT un terminal
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("firefox"))
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("code"))
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd("wofi --show drun"))
hl.bind(mainMod .. " + I", hl.dsp.exec_cmd("bobos-settings"))
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd("bobos-power"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd("kitty --title 'Snake BobOS' -e bob-snake &"))
hl.bind(mainMod .. " + SHIFT + I", hl.dsp.exec_cmd("kitty -e bobfetch &"))
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("bobos-power --logout"))
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + F", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))

-- Sécurité / session (« & » indispensable : hyprlock ne rend pas la main)
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("hyprlock &"))
hl.bind("XF86ScreenSaver", hl.dsp.exec_cmd("hyprlock &"), { locked = true })

-- Captures d'écran
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd("bobos-shot region"))
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd("bobos-shot window"))
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.exec_cmd("bobos-shot full"))

-- Navigation
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

for i = 1, 5 do
    hl.bind(mainMod .. " + " .. i,             hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. i,     hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Touches média (fonctionnelles sans bureau : wpctl / playerctl étaient
-- installés mais aucune touche n'était liée, audit UX-06)
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"))
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"))
hl.bind("XF86AudioNext",        hl.dsp.exec_cmd("playerctl next"))
hl.bind("XF86AudioPrev",        hl.dsp.exec_cmd("playerctl previous"))
hl.bind("XF86AudioPlay",        hl.dsp.exec_cmd("playerctl play-pause"))
hl.bind("XF86AudioPause",       hl.dsp.exec_cmd("playerctl play-pause"))
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl set 5%+"), { repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"), { repeating = true })
