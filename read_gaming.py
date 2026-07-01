#!/usr/bin/env python3
"""Read steam_cache.json + wow_hours.json and print pipe-delimited line for Conky/Lua."""
import json
from pathlib import Path

DIR = Path.home() / '.config/conky'

# Steam
try:
    s = json.loads((DIR / 'steam_cache.json').read_text())
    total_h  = s.get('total_hours', 0)
    game_cnt = s.get('game_count', 0)
    top      = s.get('top', [])[:5]
    max_h    = top[0]['hours'] if top else 1
    games    = [(g['name'].replace('|',' ')[:20], g['hours'],
                 round(g['hours'] / max_h * 100)) for g in top]
except Exception:
    total_h, game_cnt, games = 0, 0, []

while len(games) < 5:
    games.append(('---', 0, 0))

# WoW
wow_chars = []
wow_total = 0
try:
    w = json.loads((DIR / 'wow_hours.json').read_text())
    chars = w.get('characters', [])
    if chars:
        for c in chars:
            hrs = c.get('days', 0) * 24 + c.get('hours', 0) + c.get('mins', 0) / 60
            wow_chars.append((c.get('name', '?').replace('|', ' ')[:14],
                              c.get('class', '').replace('|', ' ')[:10],
                              round(hrs, 1)))
        wow_total = sum(x[2] for x in wow_chars)
        wow_chars.sort(key=lambda x: x[2], reverse=True)
        wow_chars = wow_chars[:5]
        max_wow = max((x[2] for x in wow_chars), default=1) or 1
        wow_chars = [(n, cl, h, round(h / max_wow * 100)) for n, cl, h in wow_chars]
except Exception:
    wow_chars = []

# Treat placeholder entries (0 hours) as no data
if wow_chars and all(entry[2] == 0 for entry in wow_chars):
    wow_chars = []
    wow_total = 0

row = [str(total_h), str(game_cnt)]
for name, hrs, pct in games:
    row += [name, str(hrs), str(pct)]

row += [str(len(wow_chars)), str(round(wow_total, 1))]
for entry in wow_chars[:5]:
    row += [entry[0], entry[1], str(entry[2]), str(entry[3])]

print('|'.join(row))
