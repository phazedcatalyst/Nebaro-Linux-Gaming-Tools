# Nebaro Launcher (Samsung Tizen TV)

A custom remote-friendly launcher app for Samsung Tizen TVs. It runs as an app (Samsung does not allow replacing Smart Hub itself).

## Customize
Edit `js/apps.js` (rows and tiles) and `css/style.css` (look).

## Install on your TV
1. TV: Apps panel -> press 1 2 3 4 5 on the remote -> Developer mode ON, enter your PC's IP, reboot TV.
2. PC: install Tizen Studio (with TV Extensions) and create a Samsung certificate profile.
3. Import this folder as a project, then Run As -> Tizen Web Application (or `tizen package -t wgt` and `tizen install`).
4. Find the app in your Apps list.

## App IDs
The IDs in `js/apps.js` are common values but differ by region and model. To check what's installed, in Tizen Studio run
`sdb shell 0 applist`, or in-app call `tizen.application.getAppsInfo()`. Wrong IDs simply fail to launch (logged to console).

## Limits
Web apps cannot switch HDMI inputs or change TV settings; use the remote's Source button for that.
