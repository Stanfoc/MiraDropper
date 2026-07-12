<# : batch portion (this block is ignored by PowerShell, run by cmd.exe)
@echo off
REM =========================================================
REM  MiraDropper - Town of Us: Mira Installer / Updater / Remover
REM  "Unofficial, easy TOU Mira installer for Among sUs."
REM  Just double-click this file.
REM  The batch part below re-launches the file as PowerShell
REM  with script-blocking disabled, so nothing else is needed.
REM =========================================================
echo Starting the Town of Us: Mira tool...
echo.
set "TOU_BAT_DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath '%~f0' -Raw | Invoke-Expression"
echo.
echo The tool has finished. You can close this window.
pause
exit /b
: end batch portion #>

# =========================================================
#  PowerShell portion starts here
# =========================================================

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------
#  Logging setup
# ---------------------------------------------------------
# Put the log right next to this .bat (the batch launcher passes its own folder).
# Fall back to the current directory, then Desktop, if that ever isn't available.
$logDir = $env:TOU_BAT_DIR
if (-not $logDir -or -not (Test-Path $logDir)) { $logDir = (Get-Location).Path }
try {
    $LogPath = Join-Path $logDir "tou-mira-install-log.txt"
    "=== TOU Mira log - $(Get-Date) ===" | Out-File -FilePath $LogPath -Encoding UTF8
} catch {
    # Folder wasn't writable (e.g. run from a read-only location) -> use Desktop as a backup.
    $LogPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "tou-mira-install-log.txt"
    "=== TOU Mira log - $(Get-Date) ===" | Out-File -FilePath $LogPath -Encoding UTF8
}

function Log-Debug {
    param([string]$msg)
    Write-Host "[DEBUG] $msg" -ForegroundColor DarkGray
    "[DEBUG $(Get-Date -Format HH:mm:ss)] $msg" | Out-File -FilePath $LogPath -Append -Encoding UTF8
}
function Log-Info {
    param([string]$msg, [string]$color = "White")
    Write-Host $msg -ForegroundColor $color
    "[INFO ] $msg" | Out-File -FilePath $LogPath -Append -Encoding UTF8
}
function Confirm-Action {
    param([string]$msg)
    $resp = Read-Host "$msg (y/n)"
    while ($resp -notmatch '^[yYnN]$') { $resp = Read-Host "Please type y or n" }
    $yes = ($resp -match '^[yY]$')
    "[PROMPT] $msg -> $(if ($yes) {'YES'} else {'NO'})" | Out-File -FilePath $LogPath -Append -Encoding UTF8
    return $yes
}
function Abort-Clean {
    param([string]$msg)
    Write-Host ""
    Log-Info $msg "Yellow"
    Log-Info "A log was saved next to this script: $LogPath" "Cyan"
    Read-Host "Press Enter to close this window"
    exit 0
}

# ---------------------------------------------------------
#  Shared: locate the Among Us install
# ---------------------------------------------------------
function Find-AmongUs {
    $auPath = $null
    $doAuto = Confirm-Action "Want the script to auto-detect your Among Us folder? (n = you'll type the path yourself)"
    if ($doAuto) {
        Log-Debug "Auto-detect selected. Reading Steam library folders..."
        $steamRoot = $null
        try {
            $steamRoot = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -ErrorAction Stop).SteamPath
            Log-Debug "Steam path from registry: $steamRoot"
        } catch { Log-Debug "Couldn't read Steam path from registry." }

        $searchRoots = @()
        if ($steamRoot) {
            $vdf = Join-Path $steamRoot "steamapps\libraryfolders.vdf"
            if (Test-Path $vdf) {
                Log-Debug "Reading library list from $vdf"
                $vdfContent = Get-Content $vdf -Raw
                $m2 = [regex]::Matches($vdfContent, '"path"\s+"([^"]+)"')
                foreach ($m in $m2) {
                    $libPath = $m.Groups[1].Value -replace '\\\\', '\'
                    $searchRoots += (Join-Path $libPath "steamapps\common\Among Us")
                    Log-Debug "  Steam library found: $libPath"
                }
            }
        }
        $searchRoots += @(
            "C:\Program Files (x86)\Steam\steamapps\common\Among Us",
            "C:\Program Files\Steam\steamapps\common\Among Us",
            "D:\SteamLibrary\steamapps\common\Among Us",
            "D:\Steam\steamapps\common\Among Us",
            "E:\SteamLibrary\steamapps\common\Among Us"
        )
        foreach ($p in ($searchRoots | Select-Object -Unique)) {
            Log-Debug "  Checking: $p"
            if (Test-Path (Join-Path $p "Among Us.exe")) { $auPath = $p; Log-Debug "  -> Found."; break }
        }
        if ($auPath) {
            Write-Host ""
            Log-Info "Auto-detected Among Us at:" "Green"
            Write-Host "  $auPath"
            if (-not (Confirm-Action "Is this the correct folder?")) { $auPath = $null }
        } else { Log-Info "Auto-detect couldn't find Among Us." "Yellow" }
    }
    if (-not $auPath) {
        Write-Host ""
        Write-Host "Let's set the folder manually." -ForegroundColor Yellow
        Write-Host "In Steam: right-click Among Us -> Manage -> Browse Local Files."
        Write-Host "Copy the folder path from the top of that File Explorer window."
        Write-Host ""
        do {
            $auPath = (Read-Host "Paste the Among Us folder path").Trim('"').Trim()
            if (Test-Path (Join-Path $auPath "Among Us.exe")) { Log-Debug "Manual path validated: $auPath"; break }
            Write-Host "That folder doesn't contain 'Among Us.exe'." -ForegroundColor Red
            if (-not (Confirm-Action "Try entering the path again?")) { Abort-Clean "Okay, stopping here." }
        } while ($true)
    }
    return $auPath
}

# ---------------------------------------------------------
#  Shared: wipe the old mod files (BepInEx + loader) so an
#  update/reuse can't leave stale files behind. Game files stay.
# ---------------------------------------------------------
function Remove-OldMod {
    param([string]$moddedPath)
    Log-Debug "Wiping old mod files from $moddedPath (game files kept)."
    $modBits = @(
        "BepInEx",
        "dotnet",
        "winhttp.dll",
        "doorstop_config.ini",
        ".doorstop_version",
        "changelog.txt"
    )
    foreach ($bit in $modBits) {
        $target = Join-Path $moddedPath $bit
        if (Test-Path $target) {
            Remove-Item $target -Recurse -Force -ErrorAction SilentlyContinue
            Log-Debug "  Removed: $bit"
        }
    }
}

# ---------------------------------------------------------
#  Shared: pick a version, download, verify, extract.
#  Assumes $moddedPath already exists and is ready to receive
#  mod files. Handles the version menu, retry, stamp, shortcut,
#  and launch. Used by BOTH Install and Update.
# ---------------------------------------------------------
function Install-ModFiles {
    param([string]$moddedPath)

    Write-Host ""
    Log-Info "Fetching the recent Town of Us: Mira releases from GitHub..." "Cyan"
    Log-Debug "GET https://api.github.com/repos/AU-Avengers/TOU-Mira/releases"
    $headers = @{ "User-Agent" = "PowerShell" }
    try {
        $allReleases = Invoke-RestMethod -Uri "https://api.github.com/repos/AU-Avengers/TOU-Mira/releases" -Headers $headers
    } catch {
        Log-Info "Couldn't reach GitHub: $($_.Exception.Message)" "Red"
        Abort-Clean "Check your internet connection and try again."
    }

    $usable = @()
    foreach ($rel in $allReleases) {
        $a = $rel.assets | Where-Object { $_.name -match "steam-itch\.zip$" } | Select-Object -First 1
        if ($a) {
            $usable += [PSCustomObject]@{
                Tag = $rel.tag_name; Pre = $rel.prerelease; Asset = $a; Date = [datetime]$rel.published_at
            }
        }
        if ($usable.Count -ge 5) { break }
    }
    if ($usable.Count -eq 0) {
        Abort-Clean "Couldn't find any releases with a steam-itch.zip. Grab it manually from https://github.com/AU-Avengers/TOU-Mira/releases"
    }

    Write-Host ""
    Write-Host "Which version do you want?" -ForegroundColor Cyan
    for ($n = 0; $n -lt $usable.Count; $n++) {
        $preTag = if ($usable[$n].Pre) { " (beta)" } else { "" }
        $when = $usable[$n].Date.ToString('yyyy-MM-dd')
        if ($n -eq 0) {
            Write-Host "  [1] $($usable[$n].Tag)$preTag   released $when   <- latest / recommended" -ForegroundColor Green
        } else {
            Write-Host "  [$($n+1)] $($usable[$n].Tag)$preTag   released $when"
        }
    }
    Write-Host ""
    Write-Host "Tip: TOU Mira is client-side, so EVERYONE in your lobby must be on the SAME version." -ForegroundColor Yellow
    $verChoice = Read-Host "Choose a number (1-$($usable.Count))"
    while ($verChoice -notmatch '^\d+$' -or [int]$verChoice -lt 1 -or [int]$verChoice -gt $usable.Count) {
        $verChoice = Read-Host "Please type a number from the list (1-$($usable.Count))"
    }
    $chosen = $usable[[int]$verChoice - 1]
    Log-Info "Selected version: $($chosen.Tag)" "Green"

    $asset = $chosen.Asset
    $downloadUrl = $asset.browser_download_url
    $zipName = $asset.name
    $zipSizeMB = [math]::Round($asset.size / 1MB, 1)
    $chosenTag = $chosen.Tag
    Log-Debug "Download URL: $downloadUrl"

    # Version-skip check
    $versionFile = Join-Path $moddedPath ".tou-mira-version.txt"
    if (Test-Path $versionFile) {
        $installedTag = (Get-Content $versionFile -Raw).Trim()
        if ($installedTag -eq $chosenTag) {
            Write-Host ""
            Write-Host "This folder already has $chosenTag installed." -ForegroundColor Green
            if (-not (Confirm-Action "Re-install / repair it anyway?")) {
                Abort-Clean "Already on that version -- nothing to do!"
            }
        }
    }

    Write-Host ""
    Log-Info "Version: $chosenTag   Download: $zipName ($zipSizeMB MB)" "Green"
    if (-not (Confirm-Action "Download $chosenTag now?")) {
        Abort-Clean "Okay, stopping before downloading anything."
    }

    # --- Download with retry ---
    $tempZip = Join-Path $env:TEMP $zipName
    Log-Debug "Saving download to: $tempZip"
    $maxAttempts = 3; $attempt = 0; $downloaded = $false
    while (-not $downloaded -and $attempt -lt $maxAttempts) {
        $attempt++
        Log-Info "Downloading (attempt $attempt of $maxAttempts)..." "Cyan"
        try {
            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add("User-Agent", "PowerShell")
            Register-ObjectEvent -InputObject $webClient -EventName DownloadProgressChanged -SourceIdentifier WebDL -Action {
                Write-Progress -Activity "Downloading $using:zipName" -Status "$($EventArgs.ProgressPercentage)%" -PercentComplete $EventArgs.ProgressPercentage
            } | Out-Null
            $dlTask = $webClient.DownloadFileTaskAsync($downloadUrl, $tempZip)
            while (-not $dlTask.IsCompleted) { Start-Sleep -Milliseconds 200 }
            Unregister-Event -SourceIdentifier WebDL -ErrorAction SilentlyContinue
            Write-Progress -Activity "Downloading $zipName" -Completed
            $webClient.Dispose()
            if ($dlTask.IsFaulted) { throw $dlTask.Exception.InnerException }
            $downloaded = $true
            Log-Info "Download complete." "Green"
        } catch {
            Unregister-Event -SourceIdentifier WebDL -ErrorAction SilentlyContinue
            Log-Info "Download attempt $attempt failed: $($_.Exception.Message)" "Yellow"
            if (Test-Path $tempZip) { Remove-Item $tempZip -Force -ErrorAction SilentlyContinue }
            if ($attempt -lt $maxAttempts) { Start-Sleep -Seconds 3 }
        }
    }
    if (-not $downloaded) {
        Abort-Clean "Download failed after $maxAttempts tries. Check your connection (or GitHub status) and run the script again."
    }

    # --- Verify + detect wrapper folder ---
    # The steam-itch zip usually nests everything inside a single top folder
    # (e.g. "TouMirav1.6.3b2-x86-steam-itch/BepInEx/..."). We find BepInEx wherever
    # it lives and strip whatever comes before it, so files land at the game root.
    Log-Debug "Verifying the downloaded zip..."
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zipArchive = [System.IO.Compression.ZipFile]::OpenRead($tempZip)
    $bepEntry = $zipArchive.Entries | Where-Object { $_.FullName -match "(^|/)BepInEx/" } | Select-Object -First 1
    if (-not $bepEntry) {
        $zipArchive.Dispose(); Remove-Item $tempZip -Force
        Log-Info "That download didn't contain a BepInEx folder -- it may be corrupted or the wrong file." "Red"
        Abort-Clean "Nothing was installed. Try running the script again."
    }
    # Everything before "BepInEx/" is the wrapper prefix ("" if it's already at the root).
    $idx = $bepEntry.FullName.IndexOf("BepInEx/")
    $stripPrefix = $bepEntry.FullName.Substring(0, $idx)
    if ($stripPrefix) { Log-Debug "Zip has a wrapper folder; will strip: '$stripPrefix'" }
    else { Log-Debug "Zip has BepInEx at the root; no prefix to strip." }
    Log-Debug "Verified: BepInEx folder present in zip."

    # --- Extract ---
    Write-Host ""
    Write-Host "Ready to INSTALL the mod files into:" -ForegroundColor Yellow
    Write-Host "  $moddedPath"
    Write-Host "Your vanilla Among Us copy stays untouched."
    if (-not (Confirm-Action "Allow the script to install the mod files now?")) {
        $zipArchive.Dispose()
        Log-Info "Downloaded zip is still in your Temp folder if you want it: $tempZip" "Cyan"
        Abort-Clean "Okay, stopping before any mod files were installed."
    }
    $entries = $zipArchive.Entries | Where-Object { $_.Name -ne "" }
    $totalEntries = $entries.Count
    Log-Info "Extracting $totalEntries files..." "Cyan"
    $i = 0
    foreach ($entry in $entries) {
        $i++
        # Strip the wrapper prefix so contents land at the game root, not one level deep.
        $relPath = $entry.FullName
        if ($stripPrefix -and $relPath.StartsWith($stripPrefix)) {
            $relPath = $relPath.Substring($stripPrefix.Length)
        }
        if ([string]::IsNullOrWhiteSpace($relPath)) { continue }  # skip the wrapper dir entry itself
        $destPath = Join-Path $moddedPath $relPath
        $destDir = Split-Path $destPath -Parent
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destPath, $true)
        if ($i % 10 -eq 0 -or $i -eq $totalEntries) {
            $pct = [math]::Round(($i / $totalEntries) * 100)
            Write-Progress -Activity "Extracting mod files" -Status "$i of $totalEntries ($pct%)" -PercentComplete $pct
        }
    }
    $zipArchive.Dispose()
    Write-Progress -Activity "Extracting mod files" -Completed
    Log-Info "Install complete: $totalEntries files." "Green"

    $chosenTag | Out-File -FilePath $versionFile -Encoding UTF8 -Force
    Remove-Item $tempZip -Force
    Log-Debug "Wrote version stamp and removed temp zip."

    # --- Shortcut ---
    Write-Host ""
    if (Confirm-Action "Create/refresh a Desktop shortcut named 'Among Us (TOU Mira)'?") {
        try {
            $shortcutPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "Among Us (TOU Mira).lnk"
            $wsh = New-Object -ComObject WScript.Shell
            $sc = $wsh.CreateShortcut($shortcutPath)
            $sc.TargetPath = Join-Path $moddedPath "Among Us.exe"
            $sc.WorkingDirectory = $moddedPath
            $sc.Description = "Among Us with Town of Us: Mira"
            $sc.Save()
            Log-Info "Shortcut saved to your Desktop." "Green"
        } catch { Log-Info "Couldn't create the shortcut: $($_.Exception.Message)" "Yellow" }
    }

    # --- Done ---
    Write-Host ""
    Write-Host "=== Done! ===" -ForegroundColor Green
    Write-Host "Installed version: $chosenTag"
    Write-Host "Modded game folder: $moddedPath"
    Write-Host "Log saved next to this script: $LogPath"
    Write-Host ""
    Write-Host "Reminder: everyone in your lobby should be on this SAME version ($chosenTag)." -ForegroundColor Yellow
    Write-Host ""
    if (Confirm-Action "Launch the modded Among Us now to verify it worked?") {
        Start-Process (Join-Path $moddedPath "Among Us.exe")
        Write-Host ""
        Write-Host "If it opens with the Town of Us: Mira logo in the top-left corner, you're all set!" -ForegroundColor Green
    } else {
        Write-Host "You can launch it anytime from the Desktop shortcut or:" -ForegroundColor Cyan
        Write-Host "  $moddedPath\Among Us.exe"
    }
    Read-Host "Press Enter to close this window"
    exit 0
}

# ---------------------------------------------------------
#  Shared: warn if Among Us is running (with override)
# ---------------------------------------------------------
function Ensure-GameClosed {
    Log-Debug "Checking whether Among Us is currently running..."
    $auProcess = Get-Process -Name "Among Us" -ErrorAction SilentlyContinue
    if ($auProcess) {
        Write-Host ""
        Write-Host "It looks like Among Us is currently RUNNING." -ForegroundColor Red
        Write-Host "Changing game files while it's open can fail with file-lock errors."
        Write-Host "(If you're sure it's actually closed and this is a false alarm, you can override.)" -ForegroundColor DarkGray
        if (Confirm-Action "Try closing Among Us automatically now?") {
            try { $auProcess | Stop-Process -Force; Start-Sleep -Seconds 2; Log-Info "Closed Among Us." "Green" }
            catch { Log-Info "Couldn't close it automatically. Please close it manually." "Yellow" }
        }
        $auProcess = Get-Process -Name "Among Us" -ErrorAction SilentlyContinue
        if ($auProcess) {
            if (-not (Confirm-Action "Among Us still looks open. Override and continue ANYWAY (risky)?")) {
                Abort-Clean "Smart call -- close Among Us fully, then run the script again."
            }
            Log-Debug "User overrode the running-game check."
        }
    } else { Log-Debug "Among Us not running. Good." }
}

Write-Host "=== MiraDropper - Town of Us: Mira Tool ===" -ForegroundColor Cyan
Write-Host ""
Log-Debug "Log file created at $LogPath"

# ---------------------------------------------------------
#  Mode select
# ---------------------------------------------------------
Write-Host "What do you want to do?" -ForegroundColor Cyan
Write-Host "  [1] Install   - fresh setup (copies the game, then installs the mod)"
Write-Host "  [2] Update    - refresh the mod in an existing modded folder (no re-copy)"
Write-Host "  [3] Remove    - uninstall the mod / delete the modded copy"
$mode = Read-Host "Choose 1, 2, or 3"
while ($mode -notmatch '^[123]$') { $mode = Read-Host "Please type 1, 2, or 3" }
Log-Debug "Mode selected: $mode"

# =========================================================
#  MODE 3: REMOVE
# =========================================================
if ($mode -eq "3") {
    Write-Host ""
    Log-Info "=== Remove mode ===" "Cyan"
    $auPath = Find-AmongUs
    $moddedPath = Join-Path (Split-Path $auPath -Parent) "Among Us - TOU Mira"
    if (-not (Test-Path $moddedPath)) {
        Abort-Clean "No modded folder found at '$moddedPath' -- nothing to remove."
    }
    Write-Host ""
    Write-Host "This will DELETE the modded folder:" -ForegroundColor Yellow
    Write-Host "  $moddedPath"
    Write-Host "Your original (vanilla) Among Us install will NOT be touched."
    if (-not (Confirm-Action "Are you sure you want to delete the modded copy?")) {
        Abort-Clean "Okay, left everything in place."
    }
    Ensure-GameClosed
    Log-Info "Deleting modded folder..." "Yellow"
    Remove-Item $moddedPath -Recurse -Force
    Log-Info "Modded folder removed." "Green"
    $shortcutPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "Among Us (TOU Mira).lnk"
    if (Test-Path $shortcutPath) {
        if (Confirm-Action "Also remove the 'Among Us (TOU Mira)' desktop shortcut?") {
            Remove-Item $shortcutPath -Force; Log-Info "Shortcut removed." "Green"
        }
    }
    Write-Host ""
    Write-Host "=== Remove complete! ===" -ForegroundColor Green
    Write-Host "You can still play vanilla Among Us normally through Steam."
    Write-Host "(Switch Steam's beta back to 'None' if you want the latest vanilla version.)" -ForegroundColor Cyan
    Read-Host "Press Enter to close this window"
    exit 0
}

# =========================================================
#  MODE 2: UPDATE
# =========================================================
if ($mode -eq "2") {
    Write-Host ""
    Log-Info "=== Update mode ===" "Cyan"
    $auPath = Find-AmongUs
    $moddedPath = Join-Path (Split-Path $auPath -Parent) "Among Us - TOU Mira"
    if (-not (Test-Path $moddedPath)) {
        Abort-Clean "No modded folder found at '$moddedPath'. Run this tool again and choose [1] Install first."
    }
    $stamp = Join-Path $moddedPath ".tou-mira-version.txt"
    if (Test-Path $stamp) {
        Log-Info "Currently installed: $((Get-Content $stamp -Raw).Trim())" "Cyan"
    }
    Ensure-GameClosed
    Write-Host ""
    Write-Host "Update will wipe the old mod files (BepInEx + loader) from the modded folder" -ForegroundColor Yellow
    Write-Host "and install a fresh copy. Your copied game files are kept, so it's quick."
    if (-not (Confirm-Action "Proceed with the update?")) {
        Abort-Clean "Okay, nothing was changed."
    }
    Log-Info "Removing old mod files for a clean update..." "Cyan"
    Remove-OldMod $moddedPath
    Install-ModFiles $moddedPath   # handles version pick, download, extract, launch, and exits
}

# =========================================================
#  MODE 1: INSTALL (fresh)
# =========================================================
Write-Host ""
Log-Info "=== Install mode ===" "Cyan"

# Step 0: Confirm the Steam beta downgrade
Write-Host ""
Write-Host "Before this can work, you need to downgrade Among Us in Steam:" -ForegroundColor Yellow
Write-Host "  1. Right-click Among Us in your Steam library -> Properties"
Write-Host "  2. Go to the Betas tab"
Write-Host "  3. Select 'public_previous' from the dropdown"
Write-Host "  4. Wait for Steam to finish updating the game"
Write-Host ""
if (-not (Confirm-Action "Have you done the downgrade already?")) {
    Abort-Clean "No worries -- go do that first, then run this again."
}
Write-Host ""
Log-Debug "Beta downgrade confirmed."

Ensure-GameClosed

Write-Host ""
$auPath = Find-AmongUs
Log-Info "Using Among Us at: $auPath" "Green"

$parentDir = Split-Path $auPath -Parent
$moddedPath = Join-Path $parentDir "Among Us - TOU Mira"
Log-Debug "Modded install target: $moddedPath"

$skipCopy = $false
if (Test-Path $moddedPath) {
    Write-Host ""
    Write-Host "A 'Among Us - TOU Mira' folder already exists at:" -ForegroundColor Yellow
    Write-Host "  $moddedPath"
    Write-Host "  [1] Reuse it (keep game files; old mod files get wiped for a clean install)"
    Write-Host "  [2] Delete the whole folder and re-copy the game from scratch"
    Write-Host "  [3] Cancel"
    $choice = Read-Host "Choose 1, 2, or 3"
    while ($choice -notmatch '^[123]$') { $choice = Read-Host "Please type 1, 2, or 3" }
    Log-Debug "Existing-folder choice: $choice"
    switch ($choice) {
        "1" {
            $skipCopy = $true
            Log-Info "Reusing existing folder -- wiping old mod files for a clean install." "Cyan"
            Remove-OldMod $moddedPath
        }
        "2" {
            if (Confirm-Action "Really DELETE the whole modded folder and re-copy?") {
                Log-Info "Deleting old modded folder..." "Yellow"; Remove-Item $moddedPath -Recurse -Force
            } else { Abort-Clean "Okay, leaving it as-is and stopping." }
        }
        "3" { Abort-Clean "Cancelled." }
    }
}

if (-not $skipCopy) {
    Log-Debug "Enumerating source files..."
    $allFiles = Get-ChildItem -Path $auPath -Recurse -File
    $totalFiles = $allFiles.Count
    $totalBytes = ($allFiles | Measure-Object Length -Sum).Sum
    $totalMB = [math]::Round($totalBytes / 1MB, 0)

    # Disk space check
    $destDrive = (Get-Item $parentDir).PSDrive.Name
    $freeBytes = (Get-PSDrive $destDrive).Free
    $freeMB = [math]::Round($freeBytes / 1MB, 0)
    $neededBytes = $totalBytes + (300 * 1MB)
    Log-Debug "Need ~$totalMB MB + cushion; drive $destDrive has $freeMB MB free."
    if ($freeBytes -lt $neededBytes) {
        Write-Host ""
        Write-Host "Not enough free space on drive $destDrive." -ForegroundColor Red
        Write-Host "  Need about $([math]::Round($neededBytes/1MB,0)) MB, but only $freeMB MB is free."
        if (-not (Confirm-Action "Continue anyway (might run out of space mid-copy)?")) {
            Abort-Clean "Free up some space and try again."
        }
        Log-Debug "User overrode the disk-space warning."
    }

    Write-Host ""
    Write-Host "The script now wants to COPY your entire Among Us folder to:" -ForegroundColor Yellow
    Write-Host "  $moddedPath"
    Write-Host "Your original Among Us install will NOT be modified."
    if (-not (Confirm-Action "Allow the script to create this copy now?")) {
        Abort-Clean "Okay, stopping before any files were copied."
    }
    Log-Info "Copying $totalFiles files (~$totalMB MB)..." "Cyan"
    New-Item -ItemType Directory -Path $moddedPath -Force | Out-Null
    $i = 0
    foreach ($file in $allFiles) {
        $i++
        $relativePath = $file.FullName.Substring($auPath.Length).TrimStart('\')
        $destPath = Join-Path $moddedPath $relativePath
        $destDir = Split-Path $destPath -Parent
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        Copy-Item -Path $file.FullName -Destination $destPath -Force
        if ($i % 25 -eq 0 -or $i -eq $totalFiles) {
            $pct = [math]::Round(($i / $totalFiles) * 100)
            Write-Progress -Activity "Copying Among Us files" -Status "$i of $totalFiles ($pct%)" -PercentComplete $pct
        }
    }
    Write-Progress -Activity "Copying Among Us files" -Completed
    Log-Info "Copy complete: $totalFiles files." "Green"
}

Install-ModFiles $moddedPath   # version pick, download, extract, launch, and exits