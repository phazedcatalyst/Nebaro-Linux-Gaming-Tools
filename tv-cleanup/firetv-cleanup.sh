#!/bin/bash
# Debloat + speed up a Fire TV Edition television (e.g. Skyworth) over ADB.
#
# Usage:  ./firetv-cleanup.sh <tv-ip> [scan|basic|clean|speed|restore]
#   scan     list what's installed that this script knows about (changes nothing)
#   basic    streaming-only: keep YouTube/Netflix/Disney+/HBO Max/Prime/Apple TV,
#            Appstore and HDMI inputs; remove the rest; apply speed tweaks
#   clean    remove bloat, asking per group. Removal is per-user and reversible.
#   speed    shorter animations, trim caches, stop background apps
#   restore  put back every app this script removed (from the log file)
#
# Nothing here is permanent: removed apps stay on the system partition and come
# back with `restore` or a factory reset.

set -u
IP="${1:-}"
CMD="${2:-scan}"
[ -z "$IP" ] && { sed -n '4,11p' "$0"; exit 1; }
command -v adb >/dev/null || { echo "adb not found. Install android-tools (Arch/Fedora) or adb (Debian/Ubuntu)."; exit 1; }

DEV="$IP:5555"
LOG="$(cd "$(dirname "$0")" && pwd)/removed-${IP}.txt"
a() { adb -s "$DEV" "$@" </dev/null; }  # never let adb eat our stdin

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
# (YouTube and Netflix casting are built into those apps and keep working.)
OPTIONAL=(
  "com.amazon.vizzini|Alexa voice assistant (voice remote button stops working)"
  "com.amazon.alexa.externalmediaplayer.fireos|Alexa music playback"
  "com.amazon.imdb.tv.android.app|Freevee (service shut down)"
  "com.amazon.cloud9|Silk browser"
  "com.amazon.awvflingreceiver|Amazon cast-to-TV receiver"
  "com.amazon.whisperplay.contentservice|Amazon phone casting / Alexa app remote"
  "com.amazon.tv.parentalcontrols|parental controls"
)
# Never removed: launcher, settings, Appstore (com.amazon.venezia), keyboard,
# OTA updater, tcomm, Live TV / inputs (com.amazon.tv.livetv), Prime Video
# (com.amazon.firebat, com.amazon.avod*), and any Skyworth/MediaTek package
# (those drive the HDMI inputs and picture settings).

# Apps `basic` mode keeps and checks for: "name|package [package...]"
WANTED=(
  "YouTube|com.amazon.firetv.youtube com.google.android.youtube.tv"
  "Netflix|com.netflix.ninja"
  "Disney+|com.disney.disneyplus"
  "HBO Max|com.hbo.hbonow com.wbd.stream"
  "Prime Video|com.amazon.firebat com.amazon.avod com.amazon.avod.thirdpartyclient"
  "Apple TV|com.apple.atve.amazon.appletv"
)
wanted_pkg() { local e; for e in "${WANTED[@]}"; do [[ " ${e#*|} " == *" $1 "* ]] && return 0; done; return 1; }

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

# Streaming-only profile: keep the WANTED apps, the Appstore and input switching;
# strip the rest. Only Alexa and your own installed apps are asked about.
basic() {
  local e pkg ans
  echo "── Removing telemetry, ads and Amazon extras"
  for e in "${SAFE[@]}" "${OPTIONAL[@]}"; do
    pkg="${e%%|*}"
    [ "$pkg" = com.amazon.vizzini ] && continue
    present "$pkg" && remove "$pkg"
  done
  if present com.amazon.vizzini; then
    read -rp "Remove Alexa too? Saves memory, but the remote's voice button stops working. [y/N] " ans
    [[ $ans =~ ^[Yy] ]] && remove com.amazon.vizzini
  fi
  echo "── Other apps you installed (Appstore can reinstall any of them later)"
  for pkg in $(a shell pm list packages -3 | tr -d '\r' | sed 's/^package://'); do
    wanted_pkg "$pkg" && continue
    read -rp "   Uninstall $pkg? [y/N] " ans
    [[ $ans =~ ^[Yy] ]] && a shell pm uninstall "$pkg" | tr -d '\r' | sed 's/^/     /'
  done
  echo "── Speed tweaks"
  speed
  echo "── Your apps"
  INSTALLED="$(a shell pm list packages 2>/dev/null | tr -d '\r' | sed 's/^package://')"
  for e in "${WANTED[@]}"; do
    local found=""
    for pkg in ${e#*|}; do present "$pkg" && found=1; done
    [ -n "$found" ] && echo "   ✓ ${e%%|*}" || echo "   ✗ ${e%%|*} not installed. Search for it in the Appstore."
  done
  echo "Removals logged to $LOG. Undo with: $0 $IP restore. Now restart the TV."
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
  *) echo "unknown command: $CMD"; exit 1 ;;
esac
