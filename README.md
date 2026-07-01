# conky-gaming-widget

Desktop overlay showing EST. total gaming hours (Steam + WoW combined), top Steam games, and WoW character /played time. Built with Conky + Cairo Lua rendering.

## Hardware target
- RTX 3090 / i7-12700K / 32GB
- 3440×1440 OLED ultrawide
- KDE Plasma + Kvantum (Utterly Nord)

## Files

| File | Purpose |
|------|---------|
| `gaming.conf` | Conky config — spawns the gaming overlay window |
| `gaming.lua` | Cairo renderer — draws the widget (Steam + WoW panels) |
| `draw.lua` | Cairo renderer — system stats widget (GPU / CPU / RAM / net) |
| `update_cache.py` | Reads Steam VDF + fetches game names; writes `steam_cache.json` |
| `read_gaming.py` | Parses both JSON files; prints pipe-delimited line for Lua |
| `wow_tracker.sh` | Watches for `Wow.exe` via process poll; prompts class + time via kdialog on exit |
| `wow_hours.json` | WoW character /played data (edited manually or by `wow_tracker.sh`) |
| `steam_cache.json` | Auto-generated Steam library cache (don't edit by hand) |

## Dependencies

```
# Conky with Lua + Cairo support
sudo dnf install conky

# Font used in the widget
sudo dnf install jetbrains-mono-fonts
# or install "JetBrainsMono Nerd Font" from nerd-fonts
```

## Install

```bash
# Clone
git clone <repo-url> ~/conky-gaming-widget

# Run the install script (symlinks files to ~/.config/conky/)
bash ~/conky-gaming-widget/install.sh
```

Or manually:
```bash
cp *.conf *.lua *.py *.sh *.json ~/.config/conky/
chmod +x ~/.config/conky/wow_tracker.sh
```

## Setup

**1. Point to your Steam VDF**

Edit `update_cache.py` line 15 — replace the Steam user ID with yours:
```python
VDF = Path.home() / '.steam/steam/userdata/YOUR_STEAM_ID/config/localconfig.vdf'
```

**2. Prime the Steam cache**
```bash
python3 ~/.config/conky/update_cache.py --steam
```

**3. Add a cron job to keep it fresh**
```
0 * * * * python3 /home/YOU/.config/conky/update_cache.py --steam
```

**4. Autostart the WoW tracker**

Add `wow_tracker.sh` to KDE Autostart (`System Settings → Autostart`) or:
```bash
cp wow_tracker.sh ~/.config/autostart-scripts/
chmod +x ~/.config/autostart-scripts/wow_tracker.sh
```

**5. Launch Conky**
```bash
conky --config=~/.config/conky/gaming.conf --daemonize
```

## WoW hours

`wow_hours.json` stores /played time per character. `wow_tracker.sh` auto-appends sessions via kdialog popup when `Wow.exe` exits. You can also edit the file directly:

```json
{
  "characters": [
    { "name": "Paladin", "class": "", "days": 38, "hours": 17, "mins": 39 }
  ]
}
```

## Widget layout

```
┌─────────────────────────────┐
│  EST. TOTAL GAMING · 2014–  │
│         4,XXX h             │
│   Steam XXXXh · WoW XXXXh  │
├─────────────────────────────┤
│  STEAM LIBRARY              │
│  185 games · XXXX total hrs │
│  ████ Game 1          XXXXh │
│  ████ Game 2           XXXh │
│  ...                        │
├─────────────────────────────┤
│  WoW CHARACTERS             │
│  XXXX total hrs             │
│  ████ Paladin          XXXh │
│  ...                        │
└─────────────────────────────┘
```
