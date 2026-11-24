# Simple home screen (Projectivy Launcher)

Target layout: one screen, two rows, nothing else.

```
┌───────────────────────────────────────────────────────────────┐
│ [YouTube] [Netflix] [Disney+] [HBO Max] [Prime] [Apple TV]    │
│ [PC]  [HDMI 2]  [HDMI 3]                        [Settings]    │
└───────────────────────────────────────────────────────────────┘
          solid dark background · no previews · no ads
```

The TV still boots to this home screen. Google's home screen is never deleted.

## 1. Check the starting point (PC)

```powershell
powershell -ExecutionPolicy Bypass -File .\tv-cleanup.ps1 192.168.0.69 launcher
```
This shows which home screen is active and which packages handle the HDMI inputs. Keep the output: it tells us what to undo if something goes wrong.

## 2. Install Projectivy (TV)

Play Store > search **Projectivy Launcher** > Install > open it once.

## 3. Build the layout (TV, with the remote)

Menu names below can differ a little between Projectivy versions. Long-pressing OK on any tile shows its options.

1. **Rows:** Projectivy shows apps in rows (it calls them categories). Delete or hide every default row except one, and name that row "Apps".
2. **App tiles:** add YouTube, Netflix, Disney+, HBO Max, Prime Video and Apple TV to that row. Long-press a tile and choose Move to set the order.
3. **Source tiles:** add a second row named "Sources". Use Projectivy's option for adding TV inputs as tiles, then add each HDMI input you use. Rename the one your PC is on to "PC".
4. **Settings tile:** add the Settings app to the end of the Sources row, so you can always reach the TV's menus.
5. **Hide everything else:** hide the Play Store and any other leftover apps. They stay installed and are still reachable through Settings > Apps.
6. **Wallpaper:** pick a solid dark colour or a single still image. Turn off any animated or rotating wallpaper, which is the biggest drain on a weak TV.
7. **Extras off:** turn off any clock, weather or recommendation widgets for now. The custom info screen comes later.

## 4. Make it the home screen

**First try Projectivy's own option.** In Projectivy's settings, turn on **Override current launcher** (the wording may be slightly different). When the TV asks, allow Projectivy's accessibility service. Press Home on the remote: Projectivy should open.

**If Home still shows Google's screen**, run this from the PC:
```powershell
powershell -ExecutionPolicy Bypass -File .\tv-cleanup.ps1 192.168.0.69 home-lock
```
It sets Projectivy as the default home screen. Then it asks, one package at a time, whether to hide the old one. Answer **N** unless Home still goes to the old screen.

**Undo:**
```powershell
powershell -ExecutionPolicy Bypass -File .\tv-cleanup.ps1 192.168.0.69 home-unlock
```

## 5. Test

- [ ] Power the TV off and on: it lands on Projectivy.
- [ ] Each Sources tile switches to the right HDMI input.
- [ ] The Input/Source button on the remote still works.
- [ ] Home returns to Projectivy from inside Netflix, YouTube and the other apps.
- [ ] If you use HDMI-CEC, waking the PC still switches the TV to it.

If a source tile or the Input button stops working after `home-lock`, run `home-unlock`. Some Skyworth input menus live inside the stock home screen, and this brings it back.

## Later: custom info screen

Planned as a separate step. Options include a Projectivy widget/row, or a small full-screen app tile that shows a custom dashboard (clock, weather, PC stats, gaming hours from the Conky widget). Nothing is needed now. The layout above leaves room for a third row.
