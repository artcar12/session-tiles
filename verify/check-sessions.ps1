<#
Read-only check of Claude Code session files on Windows (PowerShell 5.1 or 7).

  .\check-sessions.ps1               every session file
  .\check-sessions.ps1 -Fields       every field name seen, vs the macOS reference
  .\check-sessions.ps1 -Watch TEXT   print status changes of live sessions whose name, cwd or
                                     hostSessionId contains TEXT (Ctrl+C to stop)
  -Dir PATH                          read another folder
#>
param([string]$Dir = "", [switch]$Fields, [string]$Watch = "")

if (-not $Dir) {
    $base = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE ".claude" }
    $Dir = Join-Path $base "sessions"
}
if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { Write-Host "no such folder: $Dir"; exit 1 }

$Expected = @("pid", "sessionId", "cwd", "startedAt", "procStart", "version", "kind", "entrypoint",
    "hostSessionId", "name", "nameSource", "status", "updatedAt", "statusUpdatedAt",
    "messagingSocketPath", "waitingFor", "nameSince", "pidDomain", "peerProtocol", "peerFeatures")
$Inv = [Globalization.CultureInfo]::InvariantCulture

function Get-Sessions {
    foreach ($f in Get-ChildItem -LiteralPath $Dir -Filter *.json -File | Sort-Object Name) {
        try {
            $d = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            [pscustomobject]@{ File = $f.Name; Data = $d; Err = $null }
        } catch {
            [pscustomobject]@{ File = $f.Name; Data = $null; Err = $_.Exception.Message }
        }
    }
}

function Get-Live($procId) {
    if ($null -eq $procId) { return $null }
    Get-Process -Id ([int]$procId) -ErrorAction SilentlyContinue
}

# procStart vs the real start time of that process ("yes", "NO (...)", or why it couldn't tell).
function Test-Start($p, $procStart) {
    try { $real = $p.StartTime.ToUniversalTime() } catch { return "unknown (no access to start time)" }
    $text = ($procStart -split '\s+' | Where-Object { $_ }) -join ' '
    try { $claimed = [datetime]::ParseExact($text, "ddd MMM d HH:mm:ss yyyy", $Inv) }
    catch { return "unparsed procStart '$procStart' (real $($real.ToString('u')))" }
    if ([math]::Abs(($claimed - $real).TotalSeconds) -lt 2) { "yes" } else { "NO (real $($real.ToString('u')))" }
}

function Format-Age($ms) {
    if ($null -eq $ms) { return "?" }
    $s = [int]([DateTimeOffset]::UtcNow - [DateTimeOffset]::FromUnixTimeMilliseconds([long]$ms)).TotalSeconds
    if ($s -lt 60) { "${s}s" } elseif ($s -lt 3600) { "$([int][math]::Floor($s / 60))m" }
    else { "{0}h{1:00}m" -f [math]::Floor($s / 3600), [math]::Floor(($s % 3600) / 60) }
}

function Show-Table {
    $all = @(Get-Sessions)
    Write-Host "folder: $Dir  ($($all.Count) json files)`n"
    foreach ($s in $all) {
        if ($s.Err) { Write-Host "$($s.File): PARSE ERROR $($s.Err)"; continue }
        $d = $s.Data
        $p = Get-Live $d.pid
        $match = if (-not $p) { "-" } else { Test-Start $p $d.procStart }
        $procName = if ($p) { " process=$($p.ProcessName)" } else { "" }
        Write-Host "$($s.File): live=$([bool]$p) startMatches=$match$procName"
        foreach ($k in "entrypoint", "status", "waitingFor", "name", "cwd", "hostSessionId", "procStart",
                "pidDomain", "messagingSocketPath", "version") {
            if ($d.PSObject.Properties.Name -contains $k) { Write-Host ("    {0,-14} {1}" -f $k, $d.$k) }
        }
        Write-Host ("    {0,-14} {1}" -f "in state for", (Format-Age $d.statusUpdatedAt))
    }
}

function Show-Fields {
    $seen = @{}
    foreach ($s in Get-Sessions) {
        if ($s.Data) { foreach ($k in $s.Data.PSObject.Properties.Name) { $seen[$k] = 1 + [int]$seen[$k] } }
    }
    foreach ($k in $seen.Keys | Sort-Object) {
        $note = if ($Expected -contains $k) { "" } else { "NEW (not seen on macOS)" }
        Write-Host ("{0,-22} {1,3} files  {2}" -f $k, $seen[$k], $note)
    }
    foreach ($k in $Expected | Where-Object { -not $seen.ContainsKey($_) } | Sort-Object) {
        $note = if ($k -eq "waitingFor") { "absent now (only present while waiting)" } else { "MISSING (seen on macOS)" }
        Write-Host ("{0,-22}   0 files  {1}" -f $k, $note)
    }
}

function Watch-Status($text) {
    $last = @{}
    Write-Host "watching $Dir for sessions matching '$text'; Ctrl+C to stop"
    while ($true) {
        foreach ($s in Get-Sessions) {
            if ($s.Err -or -not (Get-Live $s.Data.pid)) { continue }
            $d = $s.Data
            $hay = "$($d.name) $($d.cwd) $($d.hostSessionId)"
            if ($hay.IndexOf($text, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
            $state = "status=$($d.status) waitingFor=$($d.waitingFor)"
            if ($last[$s.File] -ne $state) {
                $last[$s.File] = $state
                $lag = if ($d.statusUpdatedAt) {
                    ([DateTimeOffset]::UtcNow - [DateTimeOffset]::FromUnixTimeMilliseconds([long]$d.statusUpdatedAt)).TotalSeconds
                } else { 0 }
                Write-Host ("{0}  {1}  {2}  (file says changed {3:0.0}s ago)  {4}" -f (Get-Date -Format "HH:mm:ss"),
                    $s.File, $state, $lag, $d.name)
            }
        }
        Start-Sleep -Milliseconds 250
    }
}

if ($Fields) { Show-Fields }
elseif ($PSBoundParameters.ContainsKey("Watch")) { Watch-Status $Watch }
else { Show-Table }
