<#
Debloat + speed up an Android TV television (e.g. Skyworth SWTV-20NA) over ADB.
Windows PowerShell version of tv-cleanup.sh.

Usage:
  powershell -ExecutionPolicy Bypass -File .\tv-cleanup.ps1 <tv-ip> [scan|basic|clean|speed|restore]

  scan     list what's installed that this script knows about (changes nothing)
  basic    streaming-only: keep YouTube/Netflix/Disney+/HBO Max/Prime/Apple TV,
           Play Store and HDMI inputs; remove the rest; apply speed tweaks
  clean    remove bloat, asking per group
  speed    shorter animations, trim caches, stop background apps
  restore  put back every app this script removed (from the log file)

Nothing here is permanent: removed apps stay on the system partition and come
back with `restore` or a factory reset. adb is downloaded from Google next to
this script if it isn't already installed.
#>
param(
    [Parameter(Position = 0)][string]$Ip,
    [Parameter(Position = 1)][ValidateSet('scan', 'basic', 'clean', 'speed', 'restore')][string]$Cmd = 'scan'
)
$ErrorActionPreference = 'Continue'   # adb writes normal output to stderr; don't abort on it
if (-not $Ip) { Write-Host "Usage: .\tv-cleanup.ps1 <tv-ip> [scan|basic|clean|speed|restore]"; exit 1 }

$Here = Split-Path -Parent $PSCommandPath
$Dev = "${Ip}:5555"
$Log = Join-Path $Here "removed-$Ip.txt"

# -- adb: use an installed one, else fetch Google's platform-tools -------------
$Adb = (Get-Command adb -ErrorAction SilentlyContinue).Source
if (-not $Adb) {
    $Adb = Join-Path $Here 'platform-tools\adb.exe'
    if (-not (Test-Path $Adb)) {
        Write-Host "Downloading adb (Google platform-tools)..."
        $zip = Join-Path $env:TEMP 'platform-tools.zip'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip' -OutFile $zip -UseBasicParsing -ErrorAction Stop
        Expand-Archive $zip -DestinationPath $Here -Force -ErrorAction Stop
        Remove-Item $zip
    }
}
# Run adb against the TV; return plain text (stderr records turned into their message only).
function A { $out = & $Adb -s $Dev @args 2>&1; ((@($out) | ForEach-Object { "$_" }) -join "`n").Replace("`r", '').Trim() }
function Lines($s) { $s -split "`n" | Where-Object { $_ } | ForEach-Object { $_ -replace '^package:', '' } }

# -- package groups ------------------------------------------------------------
# Google extras nobody on a streaming-only TV needs.
$Safe = [ordered]@{
    'com.google.android.tvrecommendations'     = 'recommendation feeds on the home screen'
    'com.google.android.backdrop'              = 'Ambient Mode photo screensaver (plain screensaver remains)'
    'com.google.android.apps.tv.dreamx'        = 'Ambient Mode (Google TV builds)'
    'com.google.android.videos'                = 'Google Play Movies & TV'
    'com.google.android.play.games'            = 'Google Play Games'
    'com.google.android.youtube.tvmusic'       = 'YouTube Music'
    'com.google.android.music'                 = 'Google Play Music (dead service)'
    'com.google.android.youtube.tvkids'        = 'YouTube Kids'
    'com.google.android.feedback'              = 'feedback / crash report sender'
    'com.google.android.tv.bugreportsender'    = 'bug report sender'
    'com.android.printspooler'                 = 'printing'
    'com.google.android.syncadapters.calendar' = 'calendar sync'
}
# Real features. Only remove what you don't use.
$Optional = [ordered]@{
    'com.google.android.katniss'         = 'Google Assistant (voice button on the remote stops working)'
    'com.google.android.apps.mediashell' = 'Chromecast built-in (needed to cast from your phone)'
    'com.google.android.marvin.talkback' = 'TalkBack screen reader'
}
# Never removed: launcher, Settings, Play Store, Google Play services, setup,
# remote service, keyboard, and anything from Skyworth/Realtek/MediaTek or the
# Android TV input framework (those run the HDMI inputs and picture settings).
$ProtectRe = 'skyworth|coocaa|realtek|rtk|mediatek|mtk|tvinput|^com\.android\.tv$|launcher|settings|vending|gms|gsf|setupwraith|tungsten|remote|inputmethod|leanback'
$OemRe = 'skyworth|coocaa|realtek|rtk|mediatek|mtk'

$Wanted = [ordered]@{
    'YouTube'     = @('com.google.android.youtube.tv')
    'Netflix'     = @('com.netflix.ninja')
    'Disney+'     = @('com.disney.disneyplus')
    'HBO Max'     = @('com.wbd.stream', 'com.hbo.hbonow')
    'Prime Video' = @('com.amazon.amazonvideo.livingroom')
    'Apple TV'    = @('com.apple.atve.androidtv.appletv')
}
$WantedPkgs = $Wanted.Values | ForEach-Object { $_ }

# -- helpers -------------------------------------------------------------------
function Connect-Tv {
    & $Adb connect $Dev 2>&1 | Out-Null
    if ((A get-state) -ne 'device') {
        Write-Host "Can't reach $Dev. On the TV:"
        Write-Host "  Settings > Device Preferences > About > click 'Android TV OS build' 7 times"
        Write-Host "  Settings > Device Preferences > Developer options > turn on USB debugging"
        Write-Host "  (and 'Network debugging' / 'ADB over network' if it's listed)"
        Write-Host "Then run this again and choose 'Allow' on the TV's popup."
        Write-Host "If the popup just appeared, accept it and run the command again."
        exit 1
    }
    $script:Installed = @(Lines (A shell pm list packages))
}
function Present($p) { $script:Installed -contains $p }
function AlexaPkgs { $script:Installed | Where-Object { $_ -match 'alexa' -and $_ -notmatch $ProtectRe } }
function ThirdParty { Lines (A shell pm list packages -3) }

function Show-Group($name, $group) {
    Write-Host "-- $name"
    foreach ($k in $group.Keys) { if (Present $k) { Write-Host ("   {0,-48} {1}" -f $k, $group[$k]) } }
}

function Remove-Pkg($p) {
    if ($p -match $ProtectRe) { Write-Host "   - $p is protected, skipped"; return }
    $out = A shell pm uninstall --user 0 $p
    if ($out -ne 'Success') {
        $out = A shell pm disable-user --user 0 $p
        if ($out -notmatch 'disabled') { Write-Host "   x $p ($out)"; return }
    }
    Add-Content -Path $Log -Value $p
    Write-Host "   OK $p"
}
function Ask-Remove($p, $desc) {
    $ans = Read-Host "   Remove $desc? [y/N]"
    if ($ans -match '^[Yy]') { Remove-Pkg $p }
}

# -- commands ------------------------------------------------------------------
function Do-Scan {
    Show-Group 'SAFE to remove' $Safe
    Show-Group 'OPTIONAL (features)' $Optional
    Write-Host '-- Alexa integration (optional)'
    $al = @(AlexaPkgs); if ($al) { $al | ForEach-Object { "   $_" } } else { '   none' }
    Write-Host '-- Third-party apps you installed'
    ThirdParty | ForEach-Object { "   $_" }
    Write-Host '-- Skyworth / chipset packages (never touched; listed so you can see them)'
    $oem = @($script:Installed | Where-Object { $_ -match $OemRe })
    if ($oem) { $oem | ForEach-Object { "   $_" } } else { '   none' }
}

function Do-Clean {
    Show-Group 'SAFE' $Safe
    if ((Read-Host 'Remove all SAFE packages above? [y/N]') -match '^[Yy]') {
        foreach ($k in $Safe.Keys) { if (Present $k) { Remove-Pkg $k } }
    }
    Write-Host '-- OPTIONAL - answer per app'
    foreach ($k in $Optional.Keys) { if (Present $k) { Ask-Remove $k $Optional[$k] } }
    foreach ($p in @(AlexaPkgs)) { Ask-Remove $p "Alexa: $p" }
    Write-Host "Logged to $Log. Undo with: .\tv-cleanup.ps1 $Ip restore"
}

function Do-Speed {
    foreach ($k in 'window_animation_scale', 'transition_animation_scale', 'animator_duration_scale') {
        A shell settings put global $k 0.5 | Out-Null
    }
    Write-Host '   OK animations set to 0.5x'
    A shell pm trim-caches 999G | Out-Null; Write-Host '   OK app caches trimmed'
    A shell am kill-all | Out-Null; Write-Host '   OK background apps stopped'
    Write-Host 'Also worth doing on the TV itself:'
    Write-Host "   Home screen > Customize channels: turn off every channel row you don't use"
    Write-Host '   Settings > Device Preferences > Home screen: turn OFF video previews and audio previews'
    Write-Host '   Settings > Device Preferences > About > Usage & diagnostics: OFF'
    Write-Host '   Settings > Apps > See all apps: turn off notifications for apps that nag'
}

function Do-Basic {
    Write-Host '-- Removing Google extras'
    foreach ($k in $Safe.Keys) { if (Present $k) { Remove-Pkg $k } }
    Write-Host '-- Features (keep what you use)'
    foreach ($k in $Optional.Keys) { if (Present $k) { Ask-Remove $k $Optional[$k] } }
    foreach ($p in @(AlexaPkgs)) { Ask-Remove $p "Alexa: $p" }
    Write-Host '-- Other apps you installed (Play Store can reinstall any of them later)'
    foreach ($p in @(ThirdParty)) {
        if ($WantedPkgs -contains $p -or $p -match $ProtectRe) { continue }
        Ask-Remove $p $p
    }
    Write-Host '-- Speed tweaks'
    Do-Speed
    Write-Host '-- Your apps'
    $script:Installed = @(Lines (A shell pm list packages))
    foreach ($name in $Wanted.Keys) {
        if ($Wanted[$name] | Where-Object { Present $_ }) { Write-Host "   OK $name" }
        else { Write-Host "   x  $name not installed. Get it from the Play Store." }
    }
    Write-Host "Removals logged to $Log. Undo with: .\tv-cleanup.ps1 $Ip restore. Now restart the TV."
}

function Do-Restore {
    if (-not (Test-Path $Log)) { Write-Host "No log at $Log - nothing to restore."; return }
    Get-Content $Log | Sort-Object -Unique | ForEach-Object {
        A shell cmd package install-existing $_ | Out-Null
        A shell pm enable $_ | Out-Null
        Write-Host "   restored $_"
    }
    Move-Item $Log "$Log.restored" -Force
}

Connect-Tv
switch ($Cmd) {
    'scan'    { Do-Scan }
    'basic'   { Do-Basic }
    'clean'   { Do-Clean }
    'speed'   { Do-Speed }
    'restore' { Do-Restore }
}
