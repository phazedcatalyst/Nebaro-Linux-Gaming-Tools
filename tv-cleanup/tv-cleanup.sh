#!/bin/bash
# Debloat + speed up an Android TV television (e.g. Skyworth SWTV-20NA) over ADB.
#
# Usage:  ./tv-cleanup.sh <tv-ip> [scan|basic|clean|speed|restore|launcher|home-lock|home-unlock]
#   scan     list what's installed that this script knows about (changes nothing)
#   basic    streaming-only: keep YouTube/Netflix/Disney+/HBO Max/Prime/Apple TV,
#            Play Store and HDMI inputs; remove the rest; apply speed tweaks
#   clean    remove bloat, asking per group
#   speed    shorter animations, trim caches, stop background apps
#   restore  put back every app this script removed (from the log file)
#   launcher     show which home screen is active; home-lock / home-unlock
#                make Projectivy Launcher the home screen, or undo it
#
# Nothing here is permanent: removed apps stay on the system partition and come
# back with `restore` or a factory reset.

set -u
IP="${1:-}"
CMD="${2:-scan}"
[ -z "$IP" ] && { sed -n '4,13p' "$0"; exit 1; }
command -v adb >/dev/null || { echo "adb not found. Install android-tools (Arch/Fedora) or adb (Debian/Ubuntu)."; exit 1; }

DEV="$IP:5555"
LOG="$(cd "$(dirname "$0")" && pwd)/removed-${IP}.txt"
a() { adb -s "$DEV" "$@" </dev/null; }  # never let adb eat our stdin

# ── package groups: "package|what it is" ────────────────────────────────────
# Google extras nobody on a streaming-only TV needs.
SAFE=(
  "com.google.android.tvrecommendations|recommendation feeds on the home screen"
  "com.google.android.backdrop|Ambient Mode photo screensaver (plain screensaver remains)"
  "com.google.android.apps.tv.dreamx|Ambient Mode (Google TV builds)"
  "com.google.android.videos|Google Play Movies & TV"
  "com.google.android.play.games|Google Play Games"
  "com.google.android.youtube.tvmusic|YouTube Music"
  "com.google.android.music|Google Play Music (dead service)"
  "com.google.android.youtube.tvkids|YouTube Kids"
  "com.google.android.feedback|feedback / crash report sender"
  "com.google.android.tv.bugreportsender|bug report sender"
  "com.android.printspooler|printing"
  "com.google.android.syncadapters.calendar|calendar sync"
)
# Real features. Only remove what you don't use.
OPTIONAL=(
  "com.google.android.katniss|Google Assistant (voice button on the remote stops working)"
  "com.google.android.apps.mediashell|Chromecast built-in (needed to cast from your phone)"
  "com.google.android.marvin.talkback|TalkBack screen reader"
)
# Never removed: launcher, Settings, Play Store, Google Play services, setup,
# remote service, keyboard, and anything from Skyworth/Realtek/MediaTek or the
# Android TV input framework (those run the HDMI inputs and picture settings).
PROTECT_RE='skyworth|coocaa|realtek|rtk|mediatek|mtk|tvinput|^com\.android\.tv$|launcher|settings|vending|gms|gsf|setupwraith|tungsten|remote|inputmethod|leanback'

# Apps `basic` mode keeps and checks for: "name|package [package...]"
WANTED=(
  "YouTube|com.google.android.youtube.tv"
  "Netflix|com.netflix.ninja"
  "Disney+|com.disney.disneyplus"
  "HBO Max|com.wbd.stream com.hbo.hbonow"
  "Prime Video|com.amazon.amazonvideo.livingroom"
  "Apple TV|com.apple.atve.androidtv.appletv"
)
wanted_pkg() { local e; for e in "${WANTED[@]}"; do [[ " ${e#*|} " == *" $1 "* ]] && return 0; done; return 1; }

connect() {
  adb connect "$DEV" >/dev/null 2>&1
  if ! a get-state >/dev/null 2>&1; then
    echo "Can't reach $DEV. On the TV:"
    echo "  Settings > Device Preferences > About > click 'Android TV OS build' 7 times"
    echo "  Settings > Device Preferences > Developer options > turn on USB debugging"
    echo "  (and 'Network debugging' / 'ADB over network' if it's listed)"
    echo "Then run this again and choose 'Allow' on the TV's popup."
    exit 1
  fi
  INSTALLED="$(a shell pm list packages 2>/dev/null | tr -d '\r' | sed 's/^package://')"
}
present() { grep -qx "$1" <<<"$INSTALLED"; }
alexa_pkgs() { grep -iE 'alexa' <<<"$INSTALLED" | grep -viE "$PROTECT_RE"; }

show_group() {  # name, array...
  local name="$1"; shift
  echo "── $name"
  for e in "$@"; do present "${e%%|*}" && printf '   %-48s %s\n' "${e%%|*}" "${e#*|}"; done
}

scan() {
  show_group "SAFE to remove" "${SAFE[@]}"
  show_group "OPTIONAL (features)" "${OPTIONAL[@]}"
  echo "── Alexa integration (optional)"
  alexa_pkgs | sed 's/^/   /' || echo "   none"
  echo "── Third-party apps you installed"
  a shell pm list packages -3 | tr -d '\r' | sed 's/^package:/   /'
  echo "── Skyworth / chipset packages (never touched; listed so you can see them)"
  grep -iE 'skyworth|coocaa|realtek|rtk|mediatek|mtk' <<<"$INSTALLED" | sed 's/^/   /' || echo "   none"
}

remove() {
  local pkg="$1" out
  grep -qiE "$PROTECT_RE" <<<"$pkg" && { echo "   - $pkg is protected, skipped"; return; }
  out="$(a shell pm uninstall --user 0 "$pkg" 2>&1 | tr -d '\r')"
  if [ "$out" != "Success" ]; then
    out="$(a shell pm disable-user --user 0 "$pkg" 2>&1 | tr -d '\r')"
    grep -q "disabled" <<<"$out" || { echo "   ✗ $pkg ($out)"; return; }
  fi
  echo "$pkg" >>"$LOG"; echo "   ✓ $pkg"
}

ask_remove() {  # pkg, description
  local ans
  read -rp "   Remove $2? [y/N] " ans
  [[ $ans =~ ^[Yy] ]] && remove "$1"
}

clean() {
  local e pkg ans
  show_group "SAFE" "${SAFE[@]}"
  read -rp "Remove all SAFE packages above? [y/N] " ans
  if [[ $ans =~ ^[Yy] ]]; then
    for e in "${SAFE[@]}"; do pkg="${e%%|*}"; present "$pkg" && remove "$pkg"; done
  fi
  echo "── OPTIONAL — answer per app"
  for e in "${OPTIONAL[@]}"; do
    pkg="${e%%|*}"; present "$pkg" && ask_remove "$pkg" "${e#*|}"
  done
  for pkg in $(alexa_pkgs); do ask_remove "$pkg" "Alexa: $pkg"; done
  echo "Logged to $LOG. Undo with: $0 $IP restore"
}

speed() {
  for k in window_animation_scale transition_animation_scale animator_duration_scale; do
    a shell settings put global "$k" 0.5
  done
  echo "   ✓ animations set to 0.5x"
  a shell pm trim-caches 999G >/dev/null 2>&1 && echo "   ✓ app caches trimmed"
  a shell am kill-all >/dev/null 2>&1 && echo "   ✓ background apps stopped"
  echo "Also worth doing on the TV itself:"
  echo "   Home screen > Customize channels: turn off every channel row you don't use"
  echo "   Settings > Device Preferences > Home screen: turn OFF video previews and audio previews"
  echo "   Settings > Device Preferences > About > Usage & diagnostics: OFF"
  echo "   Settings > Apps > See all apps: turn off notifications for apps that nag"
}

# Streaming-only profile: keep the WANTED apps, Play Store and input switching;
# strip the rest. Only real features and your own installed apps are asked about.
basic() {
  local e pkg
  echo "── Removing Google extras"
  for e in "${SAFE[@]}"; do pkg="${e%%|*}"; present "$pkg" && remove "$pkg"; done
  echo "── Features (keep what you use)"
  for e in "${OPTIONAL[@]}"; do
    pkg="${e%%|*}"; present "$pkg" && ask_remove "$pkg" "${e#*|}"
  done
  for pkg in $(alexa_pkgs); do ask_remove "$pkg" "Alexa: $pkg"; done
  echo "── Other apps you installed (Play Store can reinstall any of them later)"
  for pkg in $(a shell pm list packages -3 | tr -d '\r' | sed 's/^package://'); do
    wanted_pkg "$pkg" && continue
    grep -qiE "$PROTECT_RE" <<<"$pkg" && continue
    ask_remove "$pkg" "$pkg"
  done
  echo "── Speed tweaks"
  speed
  echo "── Your apps"
  INSTALLED="$(a shell pm list packages 2>/dev/null | tr -d '\r' | sed 's/^package://')"
  for e in "${WANTED[@]}"; do
    local found=""
    for pkg in ${e#*|}; do present "$pkg" && found=1; done
    [ -n "$found" ] && echo "   ✓ ${e%%|*}" || echo "   ✗ ${e%%|*} not installed. Get it from the Play Store."
  done
  echo "Removals logged to $LOG. Undo with: $0 $IP restore. Now restart the TV."
}

# ── home screen (launcher) ──────────────────────────────────────────────────
PROJECTIVY=com.spocky.projengmenu
HOMELOG="$(dirname "$LOG")/home-${IP}.txt"
HOME_INTENT=(-a android.intent.action.MAIN -c android.intent.category.HOME)
# Only real home-screen apps may be hidden. Settings and setup apps also register as
# "home" (fallback screens) and must never be disabled.
HOME_SAFE_RE='launcher|leanback'
HOME_NEVER_RE='settings|setup|tungsten|provision|tvinput|skyworth|coocaa|realtek|rtk|mediatek|mtk|^android$|^com\.android\.tv$'
hideable_home() { grep -iE "$HOME_SAFE_RE" <<<"$1" | grep -viqE "$HOME_NEVER_RE"; }
components() { tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -E '^[A-Za-z0-9_.]+/[A-Za-z0-9_.$]+$'; }
current_home() { a shell cmd package resolve-activity --brief "${HOME_INTENT[@]}" | components | tail -1; }
all_homes() { a shell cmd package query-activities --brief "${HOME_INTENT[@]}" | components | sort -u; }

launcher() {
  echo "── Home screen in use:  $(current_home)"
  echo "── All installed home screens"; all_homes | sed 's/^/   /'
  if present "$PROJECTIVY"; then echo "── Projectivy: installed"
  else echo "── Projectivy: NOT installed. Get \"Projectivy Launcher\" from the Play Store."; fi
  echo "── Input / source packages (these must keep working)"
  grep -iE 'tvinput|^com\.android\.tv$|skyworth|realtek|rtk|mediatek|mtk' <<<"$INSTALLED" | sed 's/^/   /'
}

home_lock() {
  local proj h pkg ans out
  present "$PROJECTIVY" || { echo "Install Projectivy Launcher from the Play Store first."; return; }
  proj="$(all_homes | grep "^$PROJECTIVY/" | head -1)"
  [ -z "$proj" ] && { echo "Projectivy is installed but isn't offering a home screen. Open it once, then retry."; return; }
  [ -f "$HOMELOG" ] || echo "home=$(current_home)" >"$HOMELOG"
  echo "── Making Projectivy the home screen ($proj)"
  echo "   $(a shell cmd package set-home-activity "$proj" | tr -d '\r')"
  echo "Press Home on the remote now. If Projectivy opens, you are done (answer N below)."
  for h in $(all_homes | grep -v "^$PROJECTIVY/"); do
    pkg="${h%%/*}"
    hideable_home "$pkg" || { echo "   - $pkg is not a launcher (Settings/setup/system), never hidden"; continue; }
    read -rp "   Still getting the old home screen? Hide $pkg? [y/N] " ans
    [[ $ans =~ ^[Yy] ]] || continue
    out="$(a shell pm disable-user --user 0 "$pkg" | tr -d '\r')"
    if grep -q disabled <<<"$out"; then echo "disabled=$pkg" >>"$HOMELOG"; echo "   ✓ hidden $pkg"
    else echo "   ✗ $pkg ($out)"; fi
  done
  echo "Undo any time with: $0 $IP home-unlock"
}

home_unlock() {
  local l orig
  [ -f "$HOMELOG" ] || { echo "No log at $HOMELOG — nothing to undo."; return; }
  while read -r l; do
    case "$l" in disabled=*) a shell pm enable "${l#disabled=}" >/dev/null; echo "   ↺ ${l#disabled=}" ;; esac
  done <"$HOMELOG"
  orig="$(grep -m1 '^home=' "$HOMELOG" | cut -d= -f2-)"
  [ -n "$orig" ] && a shell cmd package set-home-activity "$orig" >/dev/null && echo "   home screen set back to $orig"
  mv "$HOMELOG" "$HOMELOG.restored"
}

restore() {
  [ -f "$LOG" ] || { echo "No log at $LOG — nothing to restore."; exit 0; }
  sort -u "$LOG" | while read -r pkg; do
    a shell cmd package install-existing "$pkg" >/dev/null 2>&1
    a shell pm enable "$pkg" >/dev/null 2>&1
    echo "   ↺ $pkg"
  done
  mv "$LOG" "$LOG.restored"
}

connect
case "$CMD" in
  scan) scan ;; basic) basic ;; clean) clean ;; speed) speed ;; restore) restore ;;
  launcher) launcher ;; home-lock) home_lock ;; home-unlock) home_unlock ;;
  *) echo "unknown command: $CMD"; exit 1 ;;
esac
