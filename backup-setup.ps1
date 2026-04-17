# ============================================================================
# AVTOMATSKI BACKUP SETUP - Windows
# ============================================================================
# Interaktivna skripta za nastavitev avtomatskega backupa z oddaljenega streznika.
# Pozeni v PowerShell (kot Administrator za Task Scheduler).
#
# Podpira:
#   - SFTP (priporoceno) - potrebuje OpenSSH (Windows 10+)
#   - FTP - vgrajen v PowerShell
#
# Uporaba:
#   PowerShell -ExecutionPolicy Bypass -File backup-setup.ps1
# ============================================================================

$ErrorActionPreference = "Stop"

# ============================================================================
# Pomozne funkcije
# ============================================================================
function Print-Header($text) {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Blue
    Write-Host "  $text" -ForegroundColor White
    Write-Host ("=" * 60) -ForegroundColor Blue
    Write-Host ""
}

function Print-Step($num, $total, $text) {
    Write-Host "[$num/$total] " -ForegroundColor Cyan -NoNewline
    Write-Host $text -ForegroundColor White
}

function Print-Ok($text) {
    Write-Host "  " -NoNewline
    Write-Host "[OK]" -ForegroundColor Green -NoNewline
    Write-Host " $text"
}

function Print-Warn($text) {
    Write-Host "  " -NoNewline
    Write-Host "[!]" -ForegroundColor Yellow -NoNewline
    Write-Host " $text"
}

function Print-Err($text) {
    Write-Host "  " -NoNewline
    Write-Host "[X]" -ForegroundColor Red -NoNewline
    Write-Host " $text"
}

function Ask($prompt, $default) {
    if ($default) {
        $result = Read-Host "  $prompt [$default]"
        if ([string]::IsNullOrWhiteSpace($result)) { return $default }
        return $result
    } else {
        return Read-Host "  $prompt"
    }
}

function Ask-Secret($prompt) {
    $secure = Read-Host "  $prompt" -AsSecureString
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
}

function Ask-YesNo($prompt, $default = "d") {
    $result = Read-Host "  $prompt [d/n]"
    if ([string]::IsNullOrWhiteSpace($result)) { $result = $default }
    return $result -match "^[dDyY]"
}

# Rekurzivni FTP download
function Download-FtpDirectory($ftpUrl, $localPath, $username, $password) {
    if (-not (Test-Path $localPath)) { New-Item -ItemType Directory -Path $localPath -Force | Out-Null }

    try {
        $request = [System.Net.FtpWebRequest]::Create($ftpUrl)
        $request.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectoryDetails
        $request.Credentials = New-Object System.Net.NetworkCredential($username, $password)
        $request.UseBinary = $true
        $request.UsePassive = $true

        $response = $request.GetResponse()
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        $listing = $reader.ReadToEnd()
        $reader.Close()
        $response.Close()
    } catch {
        Write-Host "    FTP napaka: $_" -ForegroundColor Red
        return
    }

    foreach ($line in $listing.Split("`n", [StringSplitOptions]::RemoveEmptyEntries)) {
        $line = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        # Parse FTP listing (Unix format: drwxr-xr-x ... dirname)
        $isDir = $line.StartsWith("d")
        $parts = $line -split "\s+", 9
        if ($parts.Count -lt 9) { continue }
        $name = $parts[8]

        if ($name -eq "." -or $name -eq "..") { continue }

        $itemUrl = "$ftpUrl/$name"
        $itemLocal = Join-Path $localPath $name

        if ($isDir) {
            Download-FtpDirectory "$itemUrl" "$itemLocal" $username $password
        } else {
            try {
                $fileRequest = [System.Net.FtpWebRequest]::Create($itemUrl)
                $fileRequest.Method = [System.Net.WebRequestMethods+Ftp]::DownloadFile
                $fileRequest.Credentials = New-Object System.Net.NetworkCredential($username, $password)
                $fileRequest.UseBinary = $true
                $fileRequest.UsePassive = $true

                $fileResponse = $fileRequest.GetResponse()
                $stream = $fileResponse.GetResponseStream()
                $fileStream = [System.IO.File]::Create($itemLocal)
                $stream.CopyTo($fileStream)
                $fileStream.Close()
                $stream.Close()
                $fileResponse.Close()
            } catch {
                Write-Host "    Napaka pri prenosu ${name}: $_" -ForegroundColor Yellow
            }
        }
    }
}

$TOTAL_STEPS = 7

# ============================================================================
# KORAK 1: Izbira protokola
# ============================================================================
Print-Header "AVTOMATSKI BACKUP SETUP (Windows)"
Write-Host "Ta skripta nastavi avtomatski dnevni backup z oddaljenega streznika."
Write-Host ""

Print-Step 1 $TOTAL_STEPS "Nacin prenosa"
Write-Host ""
Write-Host "    1) SFTP (priporoceno) - potrebuje OpenSSH" -ForegroundColor Cyan
Write-Host "    2) FTP - vgrajen v Windows" -ForegroundColor Cyan
Write-Host ""

$protoSel = Ask "Izbira" "1"

switch ($protoSel) {
    "1" { $protocol = "sftp" }
    "2" { $protocol = "ftp" }
    default { $protocol = "sftp" }
}
Print-Ok "Protokol: $protocol"

# ============================================================================
# KORAK 2: Preveri odvisnosti
# ============================================================================
Write-Host ""
Print-Step 2 $TOTAL_STEPS "Preverjam odvisnosti..."

if ($protocol -eq "sftp") {
    $sftpCmd = Get-Command sftp.exe -ErrorAction SilentlyContinue
    $sshCmd = Get-Command ssh.exe -ErrorAction SilentlyContinue
    $keygenCmd = Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue

    if ($sftpCmd -and $sshCmd -and $keygenCmd) {
        Print-Ok "OpenSSH najden: $($sftpCmd.Source)"
    } else {
        Print-Err "OpenSSH ni najden. Namesti ga:"
        Write-Host ""
        Write-Host "  Settings -> Apps -> Optional Features -> Add a feature -> OpenSSH Client" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Ali v PowerShell (kot Administrator):" -ForegroundColor Yellow
        Write-Host "  Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0" -ForegroundColor Cyan
        Write-Host ""
        exit 1
    }
} else {
    Print-Ok "FTP: vgrajen v PowerShell (.NET)"
}

# Preveri curl za FTP test
$curlCmd = Get-Command curl.exe -ErrorAction SilentlyContinue
if ($curlCmd) { Print-Ok "curl.exe najden" }
Print-Ok "Vse odvisnosti OK"

# ============================================================================
# KORAK 3: Podatki o strezniku
# ============================================================================
Write-Host ""
Print-Step 3 $TOTAL_STEPS "Podatki o oddaljenem strezniku"
Write-Host ""

$remoteIP = Ask "IP naslov ali hostname streznika"

if ($protocol -eq "ftp") {
    $remoteUser = Ask "FTP uporabnisko ime"
    $remotePass = Ask-Secret "FTP geslo"
    $remotePort = Ask "FTP port" "21"

    Write-Host ""
    Write-Host "  Testiram FTP povezavo na ${remoteIP}:${remotePort}..." -ForegroundColor White

    try {
        $testUrl = "ftp://${remoteIP}:${remotePort}/"
        $request = [System.Net.FtpWebRequest]::Create($testUrl)
        $request.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
        $request.Credentials = New-Object System.Net.NetworkCredential($remoteUser, $remotePass)
        $request.Timeout = 10000
        $request.UsePassive = $true
        $response = $request.GetResponse()
        $response.Close()
        Print-Ok "FTP povezava uspesna!"
    } catch {
        Print-Err "Ne morem se povezati na FTP ${remoteIP}:${remotePort}"
        Print-Err "Preveri IP, port, uporabnisko ime in geslo."
        exit 1
    }

    $remoteHostname = $remoteIP
} else {
    $remoteUser = Ask "SSH uporabnisko ime" "root"
    $remotePass = Ask-Secret "SSH geslo"
    $remotePort = Ask "SSH port" "22"

    Write-Host ""
    Write-Host "  Testiram SSH povezavo na ${remoteUser}@${remoteIP}:${remotePort}..." -ForegroundColor White

    $testResult = & ssh.exe -p $remotePort -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o "PasswordAuthentication=yes" "${remoteUser}@${remoteIP}" "hostname" 2>&1
    if ($LASTEXITCODE -eq 0) {
        $remoteHostname = ($testResult | Select-Object -First 1).Trim()
        Print-Ok "Povezava uspesna! Streznik: $remoteHostname"
    } else {
        Print-Warn "Avtomatski test ni uspel (morda potrebuje interaktivno geslo)."
        Print-Warn "Nadaljujem - preverite povezavo rocno po setupu."
        $remoteHostname = $remoteIP
    }
}

# ============================================================================
# KORAK 4: Kaj backupirati
# ============================================================================
Write-Host ""
Print-Step 4 $TOTAL_STEPS "Kaj zelis backupirati?"
Write-Host ""
Write-Host "  Vpisi poti na strezniku za backup."
Write-Host ""

$paths = @()
while ($true) {
    $path = Ask "Pot na strezniku (npr: /volume1/web)"
    if (-not [string]::IsNullOrWhiteSpace($path)) {
        $paths += $path
        Print-Ok "Dodano: $path"
    }
    Write-Host ""
    if (-not (Ask-YesNo "Dodaj se eno pot?")) { break }
}

if ($paths.Count -eq 0) {
    Print-Err "Nic ni izbrano!"
    exit 1
}

# ============================================================================
# KORAK 5: Kam shraniti + urnik
# ============================================================================
Write-Host ""
Print-Step 5 $TOTAL_STEPS "Kam shraniti backupe?"
Write-Host ""

$defaultBackupDir = Join-Path $env:USERPROFILE "backups\$remoteHostname"
$backupDir = Ask "Lokalna pot za backupe" $defaultBackupDir
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
Print-Ok "Mapa ustvarjena: $backupDir"

Write-Host ""
Write-Host "  Kdaj naj se backup izvaja?" -ForegroundColor White
Write-Host ""
Write-Host "    1) Vsak dan ob 4:00" -ForegroundColor Cyan
Write-Host "    2) Vsak dan ob 2:00" -ForegroundColor Cyan
Write-Host "    3) Vsakih 12 ur" -ForegroundColor Cyan
Write-Host "    4) Vsakih 6 ur" -ForegroundColor Cyan
Write-Host ""

$scheduleSel = Ask "Izbira" "1"

switch ($scheduleSel) {
    "1" { $scheduleTime = "04:00"; $scheduleRepeat = $null; $scheduleDesc = "vsak dan ob 4:00" }
    "2" { $scheduleTime = "02:00"; $scheduleRepeat = $null; $scheduleDesc = "vsak dan ob 2:00" }
    "3" { $scheduleTime = "04:00"; $scheduleRepeat = "12:00:00"; $scheduleDesc = "vsakih 12 ur" }
    "4" { $scheduleTime = "04:00"; $scheduleRepeat = "06:00:00"; $scheduleDesc = "vsakih 6 ur" }
    default { $scheduleTime = "04:00"; $scheduleRepeat = $null; $scheduleDesc = "vsak dan ob 4:00" }
}
Print-Ok "Urnik: $scheduleDesc"

$retention = Ask "Koliko dni hraniti stare backupe?" "14"
Print-Ok "Rotacija: $retention dni"

# ============================================================================
# KORAK 6: SSH kljuc (SFTP) ali FTP podatki
# ============================================================================
Write-Host ""
Print-Step 6 $TOTAL_STEPS "Nastavljam avtentikacijo..."
Write-Host ""

$sshKeyPath = ""

if ($protocol -eq "sftp") {
    $sshDir = Join-Path $env:USERPROFILE ".ssh"
    if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir -Force | Out-Null }
    $sshKeyPath = Join-Path $sshDir "id_ed25519_backup"

    if (Test-Path $sshKeyPath) {
        Print-Ok "SSH kljuc ze obstaja: $sshKeyPath"
    } else {
        & ssh-keygen.exe -t ed25519 -f $sshKeyPath -N '""' -q -C "backup@$env:COMPUTERNAME"
        Print-Ok "SSH kljuc ustvarjen: $sshKeyPath"
    }

    $pubKey = Get-Content "${sshKeyPath}.pub"
    Write-Host ""
    Write-Host "  ============================================" -ForegroundColor Yellow
    Write-Host "  POMEMBNO: Kopiraj ta javni kljuc na streznik!" -ForegroundColor Yellow
    Write-Host "  ============================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  $pubKey" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Na strezniku pozeni:" -ForegroundColor White
    Write-Host "    mkdir -p ~/.ssh && chmod 700 ~/.ssh" -ForegroundColor Cyan
    Write-Host "    echo '$pubKey' >> ~/.ssh/authorized_keys" -ForegroundColor Cyan
    Write-Host "    chmod 600 ~/.ssh/authorized_keys" -ForegroundColor Cyan
    Write-Host ""

    # Poskusi avtomatsko kopirati kljuc
    Print-Warn "Poskusam avtomatsko kopirati kljuc (vnesite geslo ko vas vpasa)..."
    try {
        $pubKeyContent = Get-Content "${sshKeyPath}.pub" -Raw
        & ssh.exe -p $remotePort -o StrictHostKeyChecking=no "${remoteUser}@${remoteIP}" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$pubKeyContent' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
        if ($LASTEXITCODE -eq 0) {
            Print-Ok "SSH kljuc uspesno kopiran!"
        } else {
            Print-Warn "Avtomatsko kopiranje ni uspelo. Kopirajte kljuc rocno (navodila zgoraj)."
        }
    } catch {
        Print-Warn "Avtomatsko kopiranje ni uspelo. Kopirajte kljuc rocno (navodila zgoraj)."
    }
} else {
    Print-Warn "FTP podatki bodo shranjeni v backup skripti."
    Print-Ok "FTP podatki pripravljeni"
}

# ============================================================================
# KORAK 7: Ustvari backup skripto in Task Scheduler
# ============================================================================
Write-Host ""
Print-Step 7 $TOTAL_STEPS "Ustvarjam backup skripto..."
Write-Host ""

$scriptPath = Join-Path $backupDir "run_backup.ps1"
$logPath = Join-Path $backupDir "backup.log"

# ---- Generiraj backup skripto ----
$scriptLines = @()
$scriptLines += "# Avtomatski backup - ustvarjeno $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
$scriptLines += "# Streznik: ${remoteUser}@${remoteIP} ($remoteHostname)"
$scriptLines += "# Protokol: $protocol"
$scriptLines += "# Urnik: $scheduleDesc"
$scriptLines += "# Rotacija: $retention dni"
$scriptLines += ""
$scriptLines += '$backupDir = "' + $backupDir + '"'
$scriptLines += '$retention = ' + $retention
$scriptLines += '$logFile = "' + $logPath + '"'
$scriptLines += '$date = Get-Date -Format "yyyyMMdd_HHmm"'
$scriptLines += ""
$scriptLines += 'function Log($msg) { "$(Get-Date -Format ''yyyy-MM-dd HH:mm:ss'') | $msg" | Add-Content $logFile }'
$scriptLines += ""
$scriptLines += 'Log "=== Backup started (' + $protocol + ') ==="'

if ($protocol -eq "sftp") {
    $scriptLines += ""
    $scriptLines += '$sshKey = "' + $sshKeyPath + '"'
    $scriptLines += '$remoteUser = "' + $remoteUser + '"'
    $scriptLines += '$remoteIP = "' + $remoteIP + '"'
    $scriptLines += '$remotePort = "' + $remotePort + '"'

    foreach ($p in $paths) {
        $dirName = Split-Path $p -Leaf
        $scriptLines += ""
        $scriptLines += "# --- SFTP: $p ---"
        $scriptLines += '$syncDir = Join-Path $backupDir "' + $dirName + '"'
        $scriptLines += 'if (-not (Test-Path $syncDir)) { New-Item -ItemType Directory -Path $syncDir -Force | Out-Null }'
        $scriptLines += 'Log "SFTP prenos ' + $p + '..."'
        $scriptLines += '$batchFile = [System.IO.Path]::GetTempFileName()'
        $scriptLines += '@"'
        $scriptLines += "cd $p"
        $scriptLines += 'lcd $syncDir'
        $scriptLines += 'get -r *'
        $scriptLines += 'bye'
        $scriptLines += '"@ | Set-Content $batchFile'
        $scriptLines += '& sftp.exe -i $sshKey -P $remotePort -o StrictHostKeyChecking=no -b $batchFile "${remoteUser}@${remoteIP}" 2>&1 | Add-Content $logFile'
        $scriptLines += 'if ($LASTEXITCODE -eq 0) {'
        $scriptLines += '    $size = (Get-ChildItem $syncDir -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB'
        $scriptLines += '    Log "  SFTP OK: $([math]::Round($size, 1)) MB"'
        $scriptLines += '} else {'
        $scriptLines += '    Log "  SFTP NAPAKA"'
        $scriptLines += '}'
        $scriptLines += 'Remove-Item $batchFile -ErrorAction SilentlyContinue'
    }
} else {
    # FTP
    $scriptLines += ""
    $scriptLines += '$ftpUser = "' + $remoteUser + '"'
    $scriptLines += '$ftpPass = "' + $remotePass + '"'
    $scriptLines += '$ftpHost = "' + $remoteIP + '"'
    $scriptLines += '$ftpPort = "' + $remotePort + '"'
    $scriptLines += ""
    # Vgradi FTP download funkcijo
    $scriptLines += @'
function Download-FtpDir($url, $localPath, $user, $pass) {
    if (-not (Test-Path $localPath)) { New-Item -ItemType Directory -Path $localPath -Force | Out-Null }
    try {
        $request = [System.Net.FtpWebRequest]::Create($url)
        $request.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectoryDetails
        $request.Credentials = New-Object System.Net.NetworkCredential($user, $pass)
        $request.UseBinary = $true; $request.UsePassive = $true
        $response = $request.GetResponse()
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        $listing = $reader.ReadToEnd(); $reader.Close(); $response.Close()
    } catch { Log "    FTP napaka: $_"; return }
    foreach ($line in $listing.Split("`n", [StringSplitOptions]::RemoveEmptyEntries)) {
        $line = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $isDir = $line.StartsWith("d")
        $parts = $line -split "\s+", 9
        if ($parts.Count -lt 9) { continue }
        $name = $parts[8]
        if ($name -eq "." -or $name -eq "..") { continue }
        $itemUrl = "$url/$name"; $itemLocal = Join-Path $localPath $name
        if ($isDir) { Download-FtpDir $itemUrl $itemLocal $user $pass }
        else {
            try {
                $fr = [System.Net.FtpWebRequest]::Create($itemUrl)
                $fr.Method = [System.Net.WebRequestMethods+Ftp]::DownloadFile
                $fr.Credentials = New-Object System.Net.NetworkCredential($user, $pass)
                $fr.UseBinary = $true; $fr.UsePassive = $true
                $resp = $fr.GetResponse(); $stream = $resp.GetResponseStream()
                $fs = [System.IO.File]::Create($itemLocal)
                $stream.CopyTo($fs); $fs.Close(); $stream.Close(); $resp.Close()
            } catch { Log "    Napaka: $name - $_" }
        }
    }
}
'@

    foreach ($p in $paths) {
        $dirName = Split-Path $p -Leaf
        $scriptLines += ""
        $scriptLines += "# --- FTP: $p ---"
        $scriptLines += '$syncDir = Join-Path $backupDir "' + $dirName + '"'
        $scriptLines += 'if (-not (Test-Path $syncDir)) { New-Item -ItemType Directory -Path $syncDir -Force | Out-Null }'
        $scriptLines += 'Log "FTP prenos ' + $p + '..."'
        $scriptLines += 'try {'
        $scriptLines += '    Download-FtpDir "ftp://${ftpHost}:${ftpPort}' + $p + '" $syncDir $ftpUser $ftpPass'
        $scriptLines += '    $size = (Get-ChildItem $syncDir -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB'
        $scriptLines += '    Log "  FTP OK: $([math]::Round($size, 1)) MB"'
        $scriptLines += '} catch {'
        $scriptLines += '    Log "  FTP NAPAKA: $_"'
        $scriptLines += '}'
    }
}

# Rotacija + footer
$scriptLines += ""
$scriptLines += '# --- Rotacija starih backupov ---'
$scriptLines += '$cutoff = (Get-Date).AddDays(-$retention)'
$scriptLines += 'Get-ChildItem $backupDir -Recurse -File | Where-Object { $_.LastWriteTime -lt $cutoff -and $_.Name -match "\d{8}_\d{4}" } | Remove-Item -Force -ErrorAction SilentlyContinue'
$scriptLines += ""
$scriptLines += '# --- Disk space ---'
$scriptLines += '$drive = (Get-Item $backupDir).PSDrive'
$scriptLines += '$freeGB = [math]::Round((Get-PSDrive $drive.Name).Free / 1GB, 1)'
$scriptLines += 'Log "Disk: ${freeGB} GB free"'
$scriptLines += 'Log "=== Backup done ==="'

$scriptContent = $scriptLines -join "`r`n"
Set-Content -Path $scriptPath -Value $scriptContent -Encoding UTF8
Print-Ok "Skripta ustvarjena: $scriptPath"

# ---- Task Scheduler ----
$taskName = "Backup-$remoteHostname"

try {
    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -Daily -At $scheduleTime

    if ($scheduleRepeat) {
        $trigger.Repetition = (New-ScheduledTaskTrigger -Once -At "00:00" -RepetitionInterval (New-TimeSpan -Hours ([int]($scheduleRepeat.Split(":")[0])))).Repetition
    }

    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries

    # Odstrani star task ce obstaja
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "Avtomatski backup $remoteHostname" | Out-Null
    Print-Ok "Task Scheduler nastavljen: $scheduleDesc"
} catch {
    Print-Warn "Task Scheduler ni uspel (morda potrebujete Administrator pravice)."
    Print-Warn "Rocno dodajte task ali uporabite: schtasks /create /tn `"$taskName`" /tr `"PowerShell -File '$scriptPath'`" /sc daily /st $scheduleTime"
}

# ============================================================================
# PRVI BACKUP
# ============================================================================
Write-Host ""
Write-Host "  Vse je nastavljeno! Pozenem prvi backup..." -ForegroundColor White
Write-Host ""

try {
    & PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath
    Print-Ok "Prvi backup koncen!"
} catch {
    Print-Warn "Prvi backup ni uspel: $_"
    Print-Warn "Preverite povezavo in pozenite rocno: $scriptPath"
}

# ---- Rezultat ----
Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Blue
Write-Host "  SETUP KONCAN" -ForegroundColor White
Write-Host ("=" * 60) -ForegroundColor Blue
Write-Host ""
Write-Host "  Streznik:      ${remoteUser}@${remoteIP} ($remoteHostname)" -ForegroundColor White
Write-Host "  Protokol:      $protocol" -ForegroundColor White
Write-Host "  Backupi v:     $backupDir" -ForegroundColor White
Write-Host "  Urnik:         $scheduleDesc" -ForegroundColor White
Write-Host "  Rotacija:      $retention dni" -ForegroundColor White
if ($sshKeyPath) {
    Write-Host "  SSH kljuc:     $sshKeyPath" -ForegroundColor White
}
Write-Host "  Skripta:       $scriptPath" -ForegroundColor White
Write-Host "  Log:           $logPath" -ForegroundColor White
Write-Host "  Task:          $taskName" -ForegroundColor White
Write-Host ""
Write-Host "  Uporabni ukazi:" -ForegroundColor White
Write-Host "    Rocni backup:    & '$scriptPath'" -ForegroundColor Cyan
Write-Host "    Poglej log:      Get-Content '$logPath'" -ForegroundColor Cyan
Write-Host "    Poglej backupe:  Get-ChildItem '$backupDir'" -ForegroundColor Cyan
Write-Host "    Uredi task:      taskschd.msc" -ForegroundColor Cyan
Write-Host "    Odstrani task:   Unregister-ScheduledTask -TaskName '$taskName'" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Backup se bo avtomatsko izvajal $scheduleDesc." -ForegroundColor Green
Write-Host ""
