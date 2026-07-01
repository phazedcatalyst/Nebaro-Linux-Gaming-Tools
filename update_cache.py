#!/usr/bin/env python3
"""Refresh ~/.config/conky/weather_cache.json and steam_cache.json.
Run via cron:
  */10 * * * * python3 /home/phazed/.config/conky/update_cache.py --weather
  0    * * * * python3 /home/phazed/.config/conky/update_cache.py --steam
"""
import json, re, sys, time
from pathlib import Path
from datetime import datetime, date
import urllib.request

DIR    = Path.home() / '.config/conky'
STEAM  = DIR / 'steam_cache.json'
WEATHER= DIR / 'weather_cache.json'
VDF    = Path.home() / '.steam/steam/userdata/122356994/config/localconfig.vdf'


def parse_playtime():
    with open(VDF, encoding='utf-8', errors='ignore') as f:
        content = f.read()
    rows = []
    for m in re.finditer(r'"(\d{4,})"\s*\{(.*?)\n\t+\}', content, re.DOTALL):
        appid, block = m.group(1), m.group(2)
        pt  = re.search(r'"Playtime"\s+"(\d+)"', block)
        ptd = re.search(r'"PlaytimeDisconnected"\s+"(\d+)"', block)
        if pt:
            total = int(pt.group(1)) + (int(ptd.group(1)) if ptd else 0)
            rows.append({'appid': appid, 'minutes': total})
    return sorted(rows, key=lambda x: x['minutes'], reverse=True)


def fetch_name(appid):
    try:
        url = f"https://store.steampowered.com/api/appdetails?appids={appid}&filters=basic"
        with urllib.request.urlopen(url, timeout=8) as r:
            data = json.loads(r.read())
        if data.get(appid, {}).get('success'):
            return data[appid]['data']['name']
    except Exception:
        pass
    return f"App {appid}"


def update_steam():
    existing_names = {}
    if STEAM.exists():
        try:
            existing_names = json.load(open(STEAM)).get('names', {})
        except Exception:
            pass

    games = parse_playtime()
    total_mins = sum(g['minutes'] for g in games)
    names = dict(existing_names)

    for g in games[:20]:
        appid = g['appid']
        if appid not in names or names[appid].startswith('App '):
            names[appid] = fetch_name(appid)
            time.sleep(0.35)

    cache = {
        'updated':      datetime.now().isoformat(),
        'total_minutes':total_mins,
        'total_hours':  round(total_mins / 60, 1),
        'game_count':   len(games),
        'names':        names,
        'top': [
            {
                'name':    names.get(g['appid'], f"App {g['appid']}"),
                'hours':   round(g['minutes'] / 60, 1),
            }
            for g in games[:10]
        ],
    }
    STEAM.write_text(json.dumps(cache, indent=2))
    print(f"Steam: {len(games)} games, {total_mins//60}h total")


def day_abbr(date_str):
    try:
        return date.fromisoformat(date_str).strftime('%a').upper()
    except Exception:
        return '???'


def cond_short(desc):
    d = desc.lower()
    if 'thunder'                     in d: return 'STORM'
    if 'blizzard'                    in d: return 'BLZRD'
    if 'snow'                        in d: return 'SNOW'
    if 'sleet' in d or 'ice'         in d: return 'SLEET'
    if 'rain'  in d or 'drizzle'     in d: return 'RAIN'
    if 'fog'   in d or 'mist'        in d: return 'FOG'
    if 'overcast'                    in d: return 'OVCST'
    if 'cloud'                       in d: return 'CLDLY'
    if 'partly'                      in d: return 'P.CLR'
    if 'sunny' in d or 'clear'       in d: return 'CLEAR'
    return 'FAIR'


def update_weather():
    try:
        url = "https://wttr.in/?format=j1"
        with urllib.request.urlopen(url, timeout=8) as r:
            data = json.loads(r.read())

        curr = data['current_condition'][0]
        areas = data.get('nearest_area', [])
        area  = areas[0].get('areaName',  [{}])[0].get('value', '') if areas else ''
        state = areas[0].get('region',    [{}])[0].get('value', '') if areas else ''
        loc   = f"{area}, {state}" if state else area

        cache = {
            'updated':  datetime.now().isoformat(),
            'temp_f':   int(curr['temp_F']),
            'temp_c':   int(curr['temp_C']),
            'feels_f':  int(curr['FeelsLikeF']),
            'humidity': int(curr['humidity']),
            'wind_mph': int(curr['windspeedMiles']),
            'wind_dir': curr['winddir16Point'],
            'desc':     curr['weatherDesc'][0]['value'],
            'location': loc,
            'forecast': [
                {
                    'day':   day_abbr(d['date']),
                    'cond':  cond_short(d['hourly'][4]['weatherDesc'][0]['value']) if d.get('hourly') else '?',
                    'max_f': int(d['maxtempF']),
                    'min_f': int(d['mintempF']),
                }
                for d in data['weather'][:3]
            ],
        }
        WEATHER.write_text(json.dumps(cache, indent=2))
        print(f"Weather: {cache['temp_f']}°F  {cache['desc']}  @ {cache['location']}")
    except Exception as e:
        print(f"Weather failed: {e}")


if __name__ == '__main__':
    if '--steam'   in sys.argv: update_steam()
    elif '--weather' in sys.argv: update_weather()
    else:
        update_weather()
        update_steam()
