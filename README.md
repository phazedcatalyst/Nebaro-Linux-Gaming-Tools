# conky-gaming-widget

Three always-on desktop overlays built with Conky + Cairo Lua rendering. A **weather widget** shows current conditions and a 3-day forecast using your IP location. A **resource monitor widget** tracks live GPU, CPU, RAM, and network usage. A **gaming widget** tracks total hours played across Steam and WoW combined, breaking down your top games and WoW characters with glowing neon bars.

---

## Hardware target

- RTX 3090 / i7-12700K / 32GB RAM
- 3440×1440 OLED ultrawide
- KDE Plasma + Kvantum (Utterly Nord theme)

These specifics are baked into `draw.lua` label text and widget sizing. If your hardware differs, update the label strings and bar widths accordingly.

---

## How it works — data pipeline overview

Understanding the flow end-to-end is key to customizing or debugging anything.

```
wttr.in (public weather API, no key needed)
        │
        ▼
update_cache.py --weather        (run by cron, every 10 min)
        │  fetches current conditions + 3-day forecast
        │  maps verbose descriptions to 5-char abbreviations
        │  writes ~/.config/conky/weather_cache.json
        ▼
weather_cache.json               (intermediate cache — don't edit by hand)
        │
        ▼
weather.lua                      (Cairo renderer — separate Conky instance)
        │  reads cache, draws current temp + forecast panel
        ▼
Desktop overlay (top-left, anchored above the gaming widget)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Steam localconfig.vdf
        │
        ▼
update_cache.py --steam          (run by cron, hourly)
        │  reads VDF, parses playtime per appid
        │  fetches game names from Steam store API
        │  writes ~/.config/conky/steam_cache.json
        ▼
steam_cache.json                 (intermediate cache — don't edit by hand)

wow_tracker.sh                   (runs at login via KDE Autostart)
        │  polls for Wow.exe process
        │  on exit: prompts you via kdialog for class + /played time
        │  appends/updates ~/.config/conky/wow_hours.json
        ▼
wow_hours.json                   (persistent WoW /played store — safe to edit)

        ┌──────────────────┐
        │  steam_cache.json│
        │  wow_hours.json  │
        └──────────────────┘
                │
                ▼
        read_gaming.py           (called by Conky on each refresh cycle)
                │  reads both JSON files
                │  outputs a single pipe-delimited string
                ▼
        gaming.lua               (Cairo renderer)
                │  splits the pipe string into fields
                │  draws bars, labels, and glow effects
                ▼
        Desktop overlay (top-left, stacked below the weather widget)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        draw.lua                 (Cairo renderer — separate Conky instance)
                │  polls nvidia-smi, sensors, /proc/net/dev each tick
                ▼
        Desktop overlay (top-right)
```

Each widget is a fully independent Conky process. If the weather cache is stale the weather panel shows the last known data — Steam and WoW are completely unaffected, and vice versa.

---

## Files

| File | Purpose |
|------|---------|
| `gaming.conf` | Conky config — window geometry, refresh rate, calls `read_gaming.py` and loads `gaming.lua` |
| `gaming.lua` | Cairo renderer for the gaming overlay (Steam + WoW panels) |
| `draw.lua` | Cairo renderer for the system stats widget (GPU / CPU / RAM / net) |
| `update_cache.py` | Fetches weather from wttr.in; reads Steam VDF + game names; writes both JSON caches |
| `read_gaming.py` | Reads Steam + WoW JSON caches; prints one pipe-delimited line for Lua to parse |
| `wow_tracker.sh` | Background daemon: polls for `Wow.exe`, prompts for class + /played on exit |
| `wow_hours.json` | WoW character /played data — written by `wow_tracker.sh`, editable by hand |
| `steam_cache.json` | Auto-generated Steam library cache — do not edit manually |
| `weather_cache.json` | Auto-generated weather cache — do not edit manually |
| `install.sh` | Symlinks all files into `~/.config/conky/` |

---

## Section breakdown

### `update_cache.py` — weather data source

**Note:** The weather widget was a quick add-on to the original gaming/stats setup — it was bolted on after the fact because having live conditions on-screen alongside gaming stats made sense for a always-on desktop. It shares `update_cache.py` with the Steam updater rather than having its own dedicated script, and its renderer (`weather.lua`) is a separate Conky instance that sits above the gaming widget on the left side of the screen.

**Intent:** Pulls current weather conditions and a 3-day forecast from `wttr.in` — a free, no-account, no-API-key weather service that auto-detects your location from your public IP. The data is fetched as structured JSON, condensed into a small cache file, and read by the weather Conky widget on each refresh. Fetching every 10 minutes is enough granularity for a desktop display; going faster would just hammer a free public service unnecessarily.

**Data source:**

```
https://wttr.in/?format=j1
```

`wttr.in` uses your IP address for location — no configuration needed. If your IP resolves to the wrong city (common with VPNs or some ISPs), you can pin a location explicitly:

```
https://wttr.in/YourCity?format=j1
# or by zip code:
https://wttr.in/90210?format=j1
```

Update the `url` variable in `update_weather()` in `update_cache.py` to use a pinned location.

**What is cached:**

The raw wttr.in response contains a lot of data. The script distills it down to just what the widget needs:

| Field | Source in wttr.in | Description |
|-------|-------------------|-------------|
| `temp_f` / `temp_c` | `current_condition[0].temp_F/C` | Current temperature |
| `feels_f` | `current_condition[0].FeelsLikeF` | Feels-like temperature |
| `humidity` | `current_condition[0].humidity` | Relative humidity % |
| `wind_mph` | `current_condition[0].windspeedMiles` | Wind speed |
| `wind_dir` | `current_condition[0].winddir16Point` | Wind direction (e.g. `NNW`) |
| `desc` | `current_condition[0].weatherDesc` | Full text description |
| `location` | `nearest_area[0].areaName + region` | Resolved city, state |
| `forecast` | `weather[0..2]` | 3-day outlook |

**Condition abbreviations (`cond_short`):**

Weather descriptions from wttr.in are verbose (e.g. "Partly cloudy"). The `cond_short()` function maps these to compact 5-character labels for the widget's narrow display:

| Abbreviation | Matches description containing |
|---|---|
| `STORM` | thunder |
| `BLZRD` | blizzard |
| `SNOW` | snow |
| `SLEET` | sleet, ice |
| `RAIN` | rain, drizzle |
| `FOG` | fog, mist |
| `OVCST` | overcast |
| `CLDLY` | cloud |
| `P.CLR` | partly |
| `CLEAR` | sunny, clear |
| `FAIR` | (fallback) |

The 3-day forecast uses `hourly[4]` — the noon-ish hour — to represent each day's condition, since it's the most representative single point in the day.

**Output — `weather_cache.json` schema:**

```json
{
  "updated": "2025-07-01T14:00:00.000000",
  "temp_f": 74,
  "temp_c": 23,
  "feels_f": 76,
  "humidity": 58,
  "wind_mph": 9,
  "wind_dir": "SSW",
  "desc": "Partly cloudy",
  "location": "Columbus, Ohio",
  "forecast": [
    { "day": "TUE", "cond": "P.CLR", "max_f": 78, "min_f": 61 },
    { "day": "WED", "cond": "RAIN",  "max_f": 68, "min_f": 55 },
    { "day": "THU", "cond": "CLEAR", "max_f": 82, "min_f": 60 }
  ]
}
```

**Failure handling:** If the request fails (no internet, wttr.in down), the script prints an error to stdout and leaves the existing cache file untouched. The widget continues showing the last good data.

---

### `update_cache.py` — Steam data source

**Intent:** This is the bridge between Steam's internal data and the widget. Steam does not expose a public API for your own local playtime — instead it writes playtime directly into a local config file every session. This script reads that file, aggregates per-game totals, resolves app IDs to game names via the Steam store API, and caches everything so Conky doesn't have to do network calls on every refresh.

**Where Steam playtime lives:**

```
~/.steam/steam/userdata/<STEAM_USER_ID>/config/localconfig.vdf
```

- `~/.steam/steam/` is a symlink Steam creates at install time pointing to your actual Steam data directory (usually `~/.local/share/Steam`). This symlink is reliable across distros.
- `userdata/` contains one directory per Steam account that has ever logged in on this machine, named by Steam user ID (a numeric account ID, not your username).
- `localconfig.vdf` is a Valve Data Format (VDF) text file. It contains a `apps` section with an entry per game you've launched, including `"Playtime"` (minutes in online sessions) and `"PlaytimeDisconnected"` (minutes in offline mode). The script sums both fields for a true total.

**Finding your Steam user ID:**

```bash
ls ~/.steam/steam/userdata/
```

If you see multiple directories (multiple accounts), identify yours by checking which one has the most games:

```bash
grep -c '"Playtime"' ~/.steam/steam/userdata/*/config/localconfig.vdf
```

**Hardcoded path to change (line 15 of `update_cache.py`):**

```python
VDF = Path.home() / '.steam/steam/userdata/122356994/config/localconfig.vdf'
```

Replace `122356994` with your own Steam user ID. Everything else is relative to `Path.home()` and requires no changes.

**Game name resolution:**

App IDs are numeric (e.g., `292030` for The Witcher 3). The script hits the Steam store details API:

```
https://store.steampowered.com/api/appdetails?appids=<id>&filters=basic
```

Names are cached permanently in `steam_cache.json` under the `names` key — the API is only called for new games or entries that previously failed. A 350ms delay between requests avoids hitting Steam's rate limit.

**Output — `steam_cache.json` schema:**

```json
{
  "updated": "2025-07-01T14:00:00.000000",
  "total_minutes": 187340,
  "total_hours": 3122.3,
  "game_count": 185,
  "names": {
    "292030": "The Witcher 3: Wild Hunt",
    "...": "..."
  },
  "top": [
    { "name": "The Witcher 3: Wild Hunt", "hours": 412.5 },
    "..."
  ]
}
```

`top` contains your 10 most-played games, sorted by hours descending. The widget renders the top 5.

**Cron schedule (recommended):**

```
# Update Steam cache hourly (Steam writes playtime at session end, so hourly is plenty)
0 * * * * python3 /home/YOU/.config/conky/update_cache.py --steam

# Update weather every 10 minutes
*/10 * * * * python3 /home/YOU/.config/conky/update_cache.py --weather
```

---

### `wow_tracker.sh` — WoW /played tracking

**Intent:** World of Warcraft stores your /played time per character, but only shows it in-game via the `/played` chat command. This script acts as a session bookkeeper: it detects when WoW is running (via process name), and when it exits, pops up a kdialog prompt asking you to enter your character's class and the /played time you saw. It then writes or updates that character's entry in `wow_hours.json`.

**Why manual entry is required:**

Unlike Steam, WoW has no local file or API that exposes /played time. The game client tracks it server-side and only surfaces it in-game via the `/played` command in chat. There is no log file, addon export, or local database on disk that this widget (or any desktop tool) can read automatically.

The tracker's job is therefore to reduce the friction of manual entry as much as possible: catch the moment you exit the game and prompt you immediately while the number is still fresh in your head.

> **Future improvement:** Blizzard's Battle.net API does expose character data, but `/played` time is not part of the public endpoint. A potential future update could pull aggregate stats from the WoW Armory or a third-party site like Raider.IO or WarcraftLogs — but that requires OAuth setup and would only reflect data those services expose, not raw /played. For now, manual entry is the most accurate and least complex approach.

**How it detects WoW:**

The script polls `pgrep -x Wow.exe` on a loop. WoW runs under Wine/Proton, so the process name seen by Linux is `Wow.exe` exactly. Once the process disappears, the script triggers the kdialog prompt.

**Customization:**

- If your Wine process name differs, check with `ps aux | grep -i wow` while WoW is running and update the `pgrep` target in the script.
- If you don't use KDE, replace `kdialog` with `zenity` (GTK) or `yad`. The prompts are simple input dialogs.
- To disable the tracker entirely, just don't add it to Autostart — the widget will fall back to whatever is already in `wow_hours.json`.

**Output — `wow_hours.json` schema:**

```json
{
  "characters": [
    { "name": "Paladin", "class": "Paladin", "days": 38, "hours": 17, "mins": 39 },
    { "name": "Mage",    "class": "Mage",    "days": 12, "hours": 4,  "mins": 12 }
  ]
}
```

Each character's total hours are computed as `days * 24 + hours + mins / 60`. You can edit this file by hand at any time — it's the authoritative store. The tracker appends new entries or updates existing ones matched by `name`.

---

### `read_gaming.py` — data aggregator for Conky

**Intent:** Conky's Lua scripts can't import Python or read JSON natively in a clean way. This script acts as the glue layer: it reads both JSON caches, computes the display values (bar percentages, truncated names, totals), and prints everything as a single pipe-delimited string on stdout. Conky calls this script on each refresh cycle via the `${execi}` directive in `gaming.conf` and passes the output string to the Lua renderer.

**Where it reads from:**

```python
DIR = Path.home() / '.config/conky'
# Reads:
DIR / 'steam_cache.json'
DIR / 'wow_hours.json'
```

Both files are expected at `~/.config/conky/` — the same directory the script itself lives in after install. If you relocate the files, update the `DIR` constant.

**Output format:**

```
<steam_total_hours>|<game_count>|<name1>|<hrs1>|<pct1>|...(×5 games)...|<wow_char_count>|<wow_total_hours>|<name1>|<class1>|<hrs1>|<pct1>|...(×5 chars)
```

Bar percentages (`pct`) are relative to the top entry in each section — the most-played game/character is always 100%, and the rest scale proportionally. This keeps bars visually meaningful regardless of absolute hour counts.

Game names are truncated to 20 characters; WoW character names to 14 characters. Pipe characters in names are replaced with spaces to avoid breaking the delimiter.

If either JSON file is missing or malformed, that section silently falls back to placeholder `---` entries with 0 hours — the widget renders gracefully with empty bars rather than crashing.

---

### `gaming.lua` — Cairo renderer (gaming overlay)

**Intent:** Draws the gaming stats panel using Cairo 2D graphics called from Lua inside Conky. On each Conky refresh, it receives the pipe-delimited string from `read_gaming.py`, splits it, and renders the Steam and WoW sections with gradient bars and a neon glow aesthetic.

**Key customization points inside `gaming.lua`:**

- **Widget position:** Set via `gaming.conf` (`gap_x`, `gap_y`) or the `x`/`y` constants near the top of the Lua file.
- **Colors:** Look for `r, g, b` values near bar-drawing calls. The neon cyan/purple palette matches Utterly Nord — swap these for your theme.
- **Number of games/chars shown:** The script iterates over 5 entries by default. Change the loop bounds if you want more or fewer rows.
- **Font:** Uses JetBrains Mono. Change the `cairo_select_font_face` calls to use any installed monospace font.

---

### `draw.lua` — Cairo renderer (system stats widget)

**Intent:** Always-on system stats overlay. GPU data is polled via a single `nvidia-smi` call per refresh (multiple metrics in one call to minimize overhead). CPU temp comes from `sensors`. Network throughput is read from `/proc/net/dev`.

**Key customization points inside `draw.lua`:**

- **GPU label:** The string `"RTX 3090"` is hardcoded as a display label — change it to match your card.
- **CPU label:** Similarly `"i7-12700K"` is a static label.
- **Network interface:** The interface name (e.g., `enp2s0`) is hardcoded. Find yours with `ip link` and update accordingly.
- **RAM total display:** `"32g"` in the memory bar label is a static string — update it if your RAM differs.
- **Widget position and size:** Controlled by `gaming.conf` geometry and constants at the top of the file.

---

### `gaming.conf` — Conky configuration

**Intent:** Defines the Conky window itself — size, position, transparency, refresh rate, and what to execute. The gaming widget runs as a borderless, click-through overlay anchored to a fixed position on the desktop.

**Key settings to adjust for your display:**

```lua
gap_x = 20          -- pixels from right edge of screen
gap_y = 100         -- pixels from top edge of screen
minimum_width = 280 -- widget width in pixels
```

The gaming widget uses `alignment = 'top_left'` with `gap_y = 328`. That value is not arbitrary — it accounts for the weather widget sitting directly above it:

```
weather widget height (~260px) + gap (48px) + spacing (20px) = 328px
```

If you resize or remove the weather widget, adjust `gap_y` in `gaming.conf` accordingly. On an ultrawide display you may also want to increase `gap_x` to avoid overlapping a taskbar or dock.

**Refresh rate:**

```lua
update_interval = 2.0   -- seconds between redraws
```

`read_gaming.py` is called via `${execi 120 python3 ...}` — every 120 seconds — since the JSON caches only update hourly. The Cairo drawing itself redraws every `update_interval` seconds but re-uses the cached pipe string between `execi` calls.

---

## Dependencies

```bash
# Conky with Lua + Cairo support
sudo dnf install conky

# Sensor reading (CPU temp)
sudo dnf install lm_sensors
sudo sensors-detect   # first-time setup

# Font used in the widget
sudo dnf install jetbrains-mono-fonts
# or install "JetBrainsMono Nerd Font" from nerd-fonts for icon glyphs

# kdialog (WoW tracker prompts — KDE only)
# already installed on KDE Plasma; on GNOME replace with zenity
```

---

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

---

## Setup

**1. Find your Steam user ID**

```bash
ls ~/.steam/steam/userdata/
```

**2. Point the script at your VDF**

Edit `update_cache.py` line 15 — replace the numeric ID with yours:

```python
VDF = Path.home() / '.steam/steam/userdata/YOUR_STEAM_ID/config/localconfig.vdf'
```

**3. Prime the Steam cache (first run)**

```bash
python3 ~/.config/conky/update_cache.py --steam
```

This will take a minute on first run while it fetches game names from the Steam API.

**4. Add cron jobs**

```bash
crontab -e
```

Add:

```
0    * * * * python3 /home/YOU/.config/conky/update_cache.py --steam
*/10 * * * * python3 /home/YOU/.config/conky/update_cache.py --weather
```

Replace `YOU` with your actual username.

**5. Add wow_tracker.sh to KDE Autostart**

`System Settings → Autostart → Add → Add Script` and point it at `~/.config/conky/wow_tracker.sh`.

Or via terminal:

```bash
cp wow_tracker.sh ~/.config/autostart-scripts/
chmod +x ~/.config/autostart-scripts/wow_tracker.sh
```

**6. Launch Conky**

```bash
conky --config=~/.config/conky/gaming.conf --daemonize
```

Add the same command to KDE Autostart to have it start with your desktop session.

---

## WoW hours — manual editing

**WoW character times must be entered manually.** There is no local file, addon output, or offline API that exposes `/played` time — Blizzard tracks it server-side and only shows it in-game. The `wow_tracker.sh` script reduces the friction by catching the moment you quit and prompting you immediately, but the number itself has to come from you. See the `wow_tracker.sh` section above for the full reasoning and future improvement notes.

`wow_hours.json` is the source of truth for WoW /played data. You can edit it directly at any time — `wow_tracker.sh` only appends/updates, it never overwrites unrelated entries.

```json
{
  "characters": [
    { "name": "Paladin", "class": "Paladin", "days": 38, "hours": 17, "mins": 39 },
    { "name": "Mage",    "class": "Mage",    "days": 12, "hours": 4,  "mins": 12 }
  ]
}
```

To update after a session: run `/played` in WoW, note the `X days, X hours, X minutes` output, and update the matching character's entry. The widget reloads the file on its next `execi` cycle (every 2 minutes by default).

---

## Widget layout

### Weather widget (`weather.lua`)

Updated every 10 minutes (on `execi` interval), reads from `weather_cache.json`:

```
┌─────────────────────────────┐
│  Columbus, Ohio             │
│           74°F              │
│    Partly Cloudy            │
│  Feels 76°  Humidity 58%   │
│  Wind 9 mph SSW             │
├─────────────────────────────┤
│  TUE     WED     THU       │
│  P.CLR   RAIN    CLEAR     │
│  78/61   68/55   82/60     │
└─────────────────────────────┘
```

Location is auto-detected from your public IP via `wttr.in`. No account or API key required. If the location resolves incorrectly, pin it in `update_cache.py` — see the weather section above.

### Resource monitor (`draw.lua`)

Live system stats, updated every 2 seconds:

```
┌─────────────────────────────┐
│  HH:MM:SS                   │
│  Day · DD Month YYYY        │
├─────────────────────────────┤
│  GPU — RTX 3090             │
│  Usage  ████████████  XX%   │
│  VRAM   ████████     XXXXM  │
│  Temp XXX°C   Power XXXW    │
├─────────────────────────────┤
│  CPU — i7-12700K            │
│  Usage  ████████████  XX%   │
│  Temp XX°C    Freq X.XXGHz  │
├─────────────────────────────┤
│  MEMORY                     │
│  Used  ████████  XX.Xg/32g  │
├─────────────────────────────┤
│  NETWORK — enp2s0           │
│  ↑ Up  X.X MB/s             │
│  ↓ Down  X.X MB/s           │
├─────────────────────────────┤
│  uptime Xd Xh · load X.XX  │
└─────────────────────────────┘
```

GPU stats (utilization, VRAM %, VRAM used MB, temp, power draw) are pulled in a single `nvidia-smi --query-gpu` call per refresh. CPU temp reads from `sensors`. All bars are gradient-filled with a neon glow effect rendered in Cairo.

### Gaming widget (`gaming.lua`)

Updated every 2 minutes (on `execi` interval):

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
│  ████ Game 3           XXXh │
│  ████ Game 4           XXXh │
│  ████ Game 5           XXXh │
├─────────────────────────────┤
│  WoW CHARACTERS             │
│  XXXX total hrs             │
│  ████ Paladin  Pala    XXXh │
│  ████ Mage     Mage     XXh │
│  ...                        │
└─────────────────────────────┘
```

Bar widths are proportional to hours — the top entry in each section is always full width (100%), and the rest scale relative to it. If `wow_hours.json` contains only zero-hour entries, the WoW section is hidden entirely rather than showing empty bars.
