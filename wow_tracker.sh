#!/bin/bash
# wow_tracker.sh — Detects WoW sessions via process watch; prompts for class + time on exit.
# Runs continuously from KDE autostart.

WOW_PROC="Wow.exe"
JSON="$HOME/.config/conky/wow_hours.json"
UPDATE_SCRIPT="$HOME/.config/conky/update_cache.py"

WOW_CLASSES=(
    "Paladin"
    "Demon Hunter"
    "Death Knight"
    "Druid"
    "Hunter"
    "Mage"
    "Monk"
    "Priest"
    "Rogue"
    "Shaman"
    "Warlock"
    "Warrior"
    "Evoker"
)

# Give KDE session time to fully load before the watcher starts
sleep 20

while true; do

    # ── Wait for WoW to start ────────────────────────────────────────────────
    while ! pgrep -fi "$WOW_PROC" > /dev/null 2>&1; do
        sleep 15
    done

    START=$(date +%s)

    # ── Wait for WoW to exit ─────────────────────────────────────────────────
    while pgrep -fi "$WOW_PROC" > /dev/null 2>&1; do
        sleep 15
    done

    END=$(date +%s)
    CALC_MINS=$(( (END - START) / 60 ))

    # ── Ask: what class? ─────────────────────────────────────────────────────
    CLASS=$(kdialog \
        --title "WoW Session Ended" \
        --combobox "Session was about ${CALC_MINS} min.  What class did you play?" \
        "${WOW_CLASSES[@]}" 2>/dev/null)

    [ -z "$CLASS" ] && continue     # cancelled

    # ── Confirm / edit minutes ───────────────────────────────────────────────
    MINS=$(kdialog \
        --title "WoW Tracker — $CLASS" \
        --inputbox "Minutes played:" \
        "$CALC_MINS" 2>/dev/null)

    [ -z "$MINS" ] && continue      # cancelled
    [[ ! "$MINS" =~ ^[0-9]+$ ]] && continue   # not a number

    # ── Update wow_hours.json ────────────────────────────────────────────────
    python3 - <<PYEOF
import json, sys
from pathlib import Path

f    = Path("$JSON")
data = json.loads(f.read_text())
chars = data.get('characters', [])
cls   = "$CLASS"
add_m = int("$MINS")

matched = False
for c in chars:
    if c.get('name', '').strip().lower() == cls.lower():
        total   = c.get('days', 0) * 1440 + c.get('hours', 0) * 60 + c.get('mins', 0) + add_m
        c['days']  = total // 1440
        c['hours'] = (total % 1440) // 60
        c['mins']  = total % 60
        matched = True
        break

if not matched:
    chars.append({
        'name':  cls,
        'class': '',
        'days':  add_m // 1440,
        'hours': (add_m % 1440) // 60,
        'mins':  add_m % 60,
    })

data['characters'] = chars
f.write_text(json.dumps(data, indent=2))
PYEOF

    # ── Notify and refresh widget ────────────────────────────────────────────
    notify-send \
        --app-name="WoW Tracker" \
        --icon=applications-games \
        "WoW session saved" \
        "+${MINS} min  ·  ${CLASS}" 2>/dev/null

    python3 "$UPDATE_SCRIPT" --steam 2>/dev/null &

done
