# WhatToDo installer for WoW Forever (Windows PowerShell 5.1+).
# Run:  irm https://raw.githubusercontent.com/Diogen8/WhatToDo/main/install/install.ps1 | iex
# 1. installs Git if missing (winget), 2. finds the WoW Forever folder (or asks),
# 3. clones the addon into Interface\AddOns\WhatToDo (or updates it),
# 4. adds a "WhatToDo update" task: at Windows logon and every hour, a hidden "git pull".
$ErrorActionPreference = 'Stop'
$Repo = 'https://github.com/Diogen8/WhatToDo.git'
$TaskName = 'WhatToDo update'

function Say([string]$uk, [string]$en) { Write-Host "$uk  /  $en" -ForegroundColor Cyan }
function Fail([string]$uk, [string]$en) { Write-Host "$uk  /  $en" -ForegroundColor Red }

function Find-Git {
    $cmd = Get-Command git -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($p in @("$env:ProgramFiles\Git\cmd\git.exe", "${env:ProgramFiles(x86)}\Git\cmd\git.exe", "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe")) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    return $null
}

function Find-Wow {
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($key in @('HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft', 'HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft')) {
        try {
            $ip = (Get-ItemProperty $key -ErrorAction Stop).InstallPath
            if ($ip) {
                $ip = $ip.TrimEnd('\')
                $candidates.Add((Join-Path $ip '_forever_'))
                $candidates.Add((Join-Path (Split-Path $ip -Parent) '_forever_'))
            }
        } catch {}
    }
    foreach ($root in (Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root })) {
        foreach ($rel in @('World of Warcraft\_forever_', 'Games\World of Warcraft\_forever_', 'Program Files (x86)\World of Warcraft\_forever_',
                           'Program Files\World of Warcraft\_forever_', 'Battle.net\World of Warcraft\_forever_', 'Blizzard\World of Warcraft\_forever_')) {
            $candidates.Add((Join-Path $root $rel))
        }
    }
    foreach ($c in $candidates) {
        if ((Test-Path (Join-Path $c 'Wow.exe')) -or (Test-Path (Join-Path $c 'Interface'))) { return $c }
    }
    return $null
}

# 1. Git
$git = Find-Git
if (-not $git) {
    Say 'Встановлюю Git...' 'Installing Git...'
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Fail 'Не знайдено winget. Встановіть Git з https://git-scm.com і запустіть скрипт ще раз.' 'winget not found. Install Git from https://git-scm.com and run this again.'
        return
    }
    winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements --silent | Out-Host
    $git = Find-Git
    if (-not $git) { Fail 'Не вдалося встановити Git.' 'Could not install Git.'; return }
}

# 2. WoW Forever folder
$wow = Find-Wow
if (-not $wow) {
    Say 'Не знайшов папку WoW Forever.' 'WoW Forever folder not found.'
    $wow = Read-Host 'Вкажіть шлях до папки _forever_ / Enter the path of the _forever_ folder (e.g. D:\World of Warcraft\_forever_)'
    $wow = $wow.Trim('"', ' ')
    if (-not (Test-Path $wow)) { Fail 'Такої папки немає.' 'That folder does not exist.'; return }
}
Say "WoW Forever: $wow" "WoW Forever: $wow"

# 3. Clone or update
$addons = Join-Path $wow 'Interface\AddOns'
New-Item -ItemType Directory -Force -Path $addons | Out-Null
$target = Join-Path $addons 'WhatToDo'
if (Test-Path (Join-Path $target '.git')) {
    Say 'Оновлюю WhatToDo...' 'Updating WhatToDo...'
    & $git -C $target pull --ff-only
} else {
    if (Test-Path $target) {
        $backup = "$target.old-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
        Move-Item $target $backup
        Say "Стару папку перенесено в $backup" "Old folder moved to $backup"
    }
    Say 'Завантажую WhatToDo...' 'Downloading WhatToDo...'
    & $git clone $Repo $target
}
if ($LASTEXITCODE -ne 0) { Fail 'Git завершився з помилкою.' 'Git failed.'; return }

# 4. Auto-update: hidden git pull at logon and every hour
$vbs = Join-Path $target 'install\update.vbs'
$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$vbs`""
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
$hourly = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650)
$registered = $false
try {
    $logon = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($logon, $hourly) -Settings $settings -Description 'Keeps the WhatToDo WoW addon up to date (git pull).' -Force | Out-Null
    $registered = $true
} catch {
    try {
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $hourly -Settings $settings -Description 'Keeps the WhatToDo WoW addon up to date (git pull).' -Force | Out-Null
        $registered = $true
    } catch {}
}
if ($registered) {
    Say "Автооновлення: завдання '$TaskName' у Планувальнику завдань." "Auto-update: task '$TaskName' in Task Scheduler."
} else {
    $startup = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\WhatToDo update.vbs'
    Set-Content -Path $startup -Encoding ASCII -Value ('CreateObject("WScript.Shell").Run "wscript.exe ""' + $vbs + '""", 0, False')
    Say 'Автооновлення: при кожному вході в Windows (папка Автозавантаження).' 'Auto-update: at every Windows logon (Startup folder).'
}

Write-Host ''
Say 'Готово! Перезапустіть гру, щоб WhatToDo з''явився.' 'Done! Restart the game to load WhatToDo.'
Say 'Також потрібні Auctionator і Yield (CurseForge).' 'Also install Auctionator and Yield (CurseForge).'
