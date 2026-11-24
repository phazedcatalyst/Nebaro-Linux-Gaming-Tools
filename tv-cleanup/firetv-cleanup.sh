#!/bin/bash
# Debloat + speed up a Fire TV Edition television (e.g. Skyworth) over ADB.
#
# Usage:  ./firetv-cleanup.sh <tv-ip> [scan|clean|speed|restore]
#   scan     list what's installed that this script knows about (changes nothing)
#   clean    remove bloat, asking per group. Removal is per-user and reversible.
#   speed    shorter animations, trim caches, stop background apps
#   restore  put back every app this script removed (from the log file)
#
# Nothing here is permanent: removed apps stay on the system partition and come
# back with `restore` or a factory reset.

set -u
IP="${1:-}"
CMD="${2:-scan}"
[ -z "$IP" ] && { sed -n '4,9p' "$0"; exit 1; }
command -v adb >/dev/null || { echo "adb not found. Install android-tools (Arch/Fedora) or adb (Debian/Ubuntu)."; exit 1; }

DEV="$IP:5555"
LOG="$(cd "$(dirname "$0")" && pwd)/removed-${IP}.txt"
a() { adb -s "$DEV" "$@"; }

# ── package groups: "package|what it is" ────────────────────────────────────
# Telemetry, ads, tutorials and junk. Nothing you'd notice is gone.
SAFE=(
  "com.amazon.device.crashmanager|crash report uploader"
  "com.amazon.dp.logger|usage logger"
  "com.amazon.tv.fw.metrics|framework metrics"
  "com.amazon.device.metrics|device metrics"
  "com.amazon.kso|sponsored content / ads on home screen"
  "com.amazon.hedwig|Amazon push notifications"
  "com.amazon.tv.legal.notices|legal notices viewer"
  "com.amazon.tv.releasenotes|release notes popup"
  "com.amazon.storm.lightning.tutorial|tutorial videos"
  "com.amazon.bueller.photos|Amazon Photos"
  "com.amazon.device.sync|cloud sync service"
  "com.amazon.sharingservice.android.client.proxy|sharing service"
  "com.amazon.wifilocker|saves wifi passwords to Amazon"
)
# Real features. Only remove what you don't use.
OPTIONAL=(
  "com.amazon.vizzini|Alexa voice assistant (voice remote button stops working)"
  "com.amazon.alexa.externalmediaplayer.fireos|Alexa music playback"
  "com.amazon.avod.thirdpartyclient|Prime Video"
  "com.amazon.firebat|Freevee"
  "com.amazon.imdb.tv.android.app|Freevee (older name)"
  "com.amazon.cloud9|Silk browser"
  "com.amazon.tv.livetv|Live TV tab"
  "com.amazon.awvflingreceiver|cast-to-TV receiver"
  "com.amazon.whisperplay.contentservice|phone casting / Alexa app remote"
  "com.amazon.tv.parentalcontrols|parental controls"
)
# Never removed: launcher, settings, Appstore (com.amazon.venezia), keyboard,
# OTA updater, tcomm. Removing those can leave the TV unusable.

connect() {
  adb connect "$DEV" >/dev/null 2>&1
  if ! a get-state >/dev/null 2>&1; then
    echo "Can't reach $DEV. On the TV: Settings > My Fire TV > Developer Options > ADB Debugging ON,"
    echo "then run this again and choose 'Allow' on the TV's popup."
    exit 1
  fi
  INSTALLED="$(a shell pm list packages 2>/dev/null | tr -d '\r' | sed 's/^package://')"
}
present() { grep -qx "$1" <<<"$INSTALLED"; }

show_group() {  # name, array...
  local name="$1"; shift
  echo "── $name"
  for e in "$@"; do present "${e%%|*}" && printf '   %-48s %s\n' "${e%%|*}" "${e#*|}"; done
}

scan() {
  show_group "SAFE to remove" "${SAFE[@]}"
  show_group "OPTIONAL (features)" "${OPTIONAL[@]}"
  echo "── Third-party apps you installed (uninstall from Settings > Applications if unused)"
  a shell pm list packages -3 | tr -d '\r' | sed 's/^package:/   /'
  echo "── Skyworth / OEM packages (review only, not touched)"
  grep -iE 'skyworth|coocaa|mediatek|mtk' <<<"$INSTALLED" | sed 's/^/   /' || echo "   none"
}

remove() {
  local pkg="$1" out
  out="$(a shell pm uninstall --user 0 "$pkg" 2>&1 | tr -d '\r')"
  if [ "$out" != "Success" ]; then
    out="$(a shell pm disable-user --user 0 "$pkg" 2>&1 | tr -d '\r')"
    grep -q "disabled" <<<"$out" || { echo "   ✗ $pkg ($out)"; return; }
  fi
  echo "$pkg" >>"$LOG"; echo "   ✓ $pkg"
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
    pkg="${e%%|*}"; present "$pkg" || continue
    read -rp "   Remove ${e#*|}? [y/N] " ans
    [[ $ans =~ ^[Yy] ]] && remove "$pkg"
  done
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
  echo "   Settings > Preferences > Privacy: turn OFF Device Usage Data, Collect App Usage Data, Interest-based Ads"
  echo "   Settings > Preferences > Featured Content: turn OFF video and audio autoplay"
  echo "   Settings > Preferences > Notification Settings: turn off app notifications"
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
  scan) scan ;; clean) clean ;; speed) speed ;; restore) restore ;;
  *) echo "unknown command: $CMD"; exit 1 ;;
esac
