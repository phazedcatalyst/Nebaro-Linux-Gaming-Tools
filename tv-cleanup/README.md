# Android TV cleanup

`tv-cleanup.sh` strips an Android TV television (written for a Skyworth SWTV-20NA on Android TV 11) down to the streaming apps you use, and makes it a bit faster. It runs from your Linux PC over ADB on your home network.

## Windows (PowerShell)

Open PowerShell (not as admin) and run:

```powershell
mkdir $HOME\tv-cleanup -Force; cd $HOME\tv-cleanup
iwr https://raw.githubusercontent.com/phazedcatalyst/Nebaro-Linux-Gaming-Tools/claude/new-session-dav8c7/tv-cleanup/tv-cleanup.ps1 -OutFile tv-cleanup.ps1
powershell -ExecutionPolicy Bypass -File .\tv-cleanup.ps1 192.168.0.69 scan
powershell -ExecutionPolicy Bypass -File .\tv-cleanup.ps1 192.168.0.69 basic
```

adb is downloaded automatically from Google the first time. The commands below (`scan`, `basic`, `clean`, `speed`, `restore`) are the same for both versions. On Linux use `./tv-cleanup.sh` instead.

## One-time setup on the TV

1. **Settings > Device Preferences > About**: click **Android TV OS build** 7 times to unlock Developer options.
2. **Settings > Device Preferences > Developer options**: turn on **USB debugging**. If you see **Network debugging** or **ADB over network**, turn that on too.
3. Find the TV's IP in **Settings > Network & Internet** (click your Wi-Fi network).
4. Linux only: install adb with `sudo pacman -S android-tools`, `sudo dnf install android-tools`, or `sudo apt install adb`.

The first time you connect, the TV shows an "Allow USB debugging?" popup. Tick "Always allow" and choose OK.

## Use

```bash
./tv-cleanup.sh 192.168.0.69 basic    # streaming-only profile (recommended)
./tv-cleanup.sh 192.168.0.69 scan     # see what's there; changes nothing
./tv-cleanup.sh 192.168.0.69 clean    # remove bloat, asking per group
./tv-cleanup.sh 192.168.0.69 speed    # faster animations, clear caches
./tv-cleanup.sh 192.168.0.69 restore  # undo everything removed
```

`basic` keeps YouTube, Netflix, Disney+, HBO Max, Prime Video, Apple TV, the Play Store and HDMI input switching. It removes Google extras (Play Movies, Play Games, YouTube Music/Kids, Ambient Mode, recommendation feeds, feedback senders). It asks about Google Assistant, Chromecast built-in, Alexa and each app you installed yourself, applies the speed tweaks, then tells you which of the six apps still need installing.

Restart the TV afterwards (Settings > Device Preferences > About > Restart).

## Simple home screen

See [HOME-SCREEN.md](HOME-SCREEN.md) for replacing the home screen with a two-row layout (apps + sources) using Projectivy Launcher, plus the `launcher`, `home-lock` and `home-unlock` commands.

## Safety

- Apps are removed only for the current user (`pm uninstall --user 0`). They stay on the system partition, so `restore` or a factory reset brings them back.
- The launcher, Settings, Play Store, Google Play services, the remote service, the keyboard and every Skyworth/Realtek/MediaTek/TV-input package are never touched.
- Removed packages are logged to `removed-<ip>.txt` next to the script.
- Package names vary between builds. The script only acts on the ones it finds.
