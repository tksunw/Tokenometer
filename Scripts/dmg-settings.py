# dmgbuild settings for the Tokenometer installer window.
# Invoked by make-dmg.sh: dmgbuild -s dmg-settings.py -D app=... -D background=...
app = defines.get("app")  # noqa: F821 — `defines` is injected by dmgbuild
background = defines.get("background")  # noqa: F821

format = "UDZO"
files = [(app, "Tokenometer.app")]
symlinks = {"Applications": "/Applications"}

icon_size = 112
window_rect = ((200, 120), (660, 400))
icon_locations = {
    "Tokenometer.app": (170, 200),
    "Applications": (490, 200),
}
