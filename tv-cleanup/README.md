# Fire TV cleanup

`firetv-cleanup.sh` removes Amazon bloat and telemetry from a Fire TV Edition television (such as the Skyworth sets) and makes it a bit faster. It runs from your Linux PC over ADB on your home network.

## One-time setup on the TV

1. **Settings > My Fire TV > About**: click the device name 7 times to unlock Developer Options.
2. **Settings > My Fire TV > Developer Options**: turn on **ADB Debugging**.
3. Find the TV's IP in **Settings > Network** (press Play/Pause on your network).
4. On the PC, install adb: `sudo pacman -S android-tools`, `sudo dnf install android-tools`, or `sudo apt install adb`.

The first time you connect, the TV shows an "Allow USB debugging?" popup. Tick "Always allow" and choose OK.

## Use

```bash
./firetv-cleanup.sh 192.168.0.69 basic    # streaming-only profile (recommended)
./firetv-cleanup.sh 192.168.0.69 scan     # see what's there; changes nothing
./firetv-cleanup.sh 192.168.0.69 clean    # remove bloat (asks first)
./firetv-cleanup.sh 192.168.0.69 speed    # faster animations, clear caches
./firetv-cleanup.sh 192.168.0.69 restore  # undo everything clean removed
```

`basic` keeps YouTube, Netflix, Disney+, HBO Max, Prime Video, Apple TV, the Appstore and HDMI input switching. It removes telemetry, ads and Amazon extras, asks about Alexa and each app you installed yourself, applies the speed tweaks, then tells you which of the six apps still need installing.

Restart the TV after `basic` or `clean` (hold Select + Play/Pause for 5 seconds).

## Safety

- Apps are removed only for the current user (`pm uninstall --user 0`). They stay on the system partition, so `restore` or a factory reset brings them back.
- The launcher, Settings, Appstore, keyboard and system updater are never touched.
- Removed packages are logged to `removed-<ip>.txt` next to the script.
- Package names vary between Fire OS versions. The script only acts on the ones it finds.
