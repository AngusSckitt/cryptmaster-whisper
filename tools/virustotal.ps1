# Scans release files with VirusTotal before publishing (PowerShell 7). Files VirusTotal already knows (same
# SHA-256) aren't uploaded again. Uploaded files become available to VirusTotal's partners: only scan what
# is going to be published anyway.
# Usage:
#   pwsh tools\virustotal.ps1 -SetKey                 stores the API key (typed in, never shown), once
#   pwsh tools\virustotal.ps1 [-Version 0.9.1]        scans dist\CryptmasterWhisper-Setup-<v>.exe and the zip
#   pwsh tools\virustotal.ps1 -Files a.exe,b.zip      scans these instead
# The key is stored encrypted with Windows DPAPI in %APPDATA%\CryptmasterWhisper\virustotal.key: only this
# Windows account on this PC can read it. It is never written to the repository or printed.
# Keep this script ASCII-only.
#Requires -Version 7
param([switch]$SetKey, [string]$Version = '0.9.1', [string[]]$Files)
$ErrorActionPreference = 'Stop'
$keyFile = Join-Path $env:APPDATA 'CryptmasterWhisper\virustotal.key'

if ($SetKey) {
    New-Item -ItemType Directory -Force (Split-Path $keyFile) | Out-Null
    Read-Host 'VirusTotal API key' -AsSecureString | ConvertFrom-SecureString | Set-Content $keyFile
    "Stored (encrypted for this Windows account) in $keyFile."
    return
}
if (-not (Test-Path $keyFile)) { throw "No API key yet: run 'pwsh tools\virustotal.ps1 -SetKey' first." }
$secure = Get-Content $keyFile | ConvertTo-SecureString
$headers = @{ 'x-apikey' = (New-Object System.Net.NetworkCredential('', $secure)).Password }

$root = Split-Path -Parent $PSScriptRoot
if (-not $Files) {
    $Files = "$root\dist\CryptmasterWhisper-Setup-$Version.exe", "$root\dist\CryptmasterWhisper-$Version.zip"
}
# The free API allows 4 requests a minute: every call waits its turn.
$script:last = [datetime]::MinValue
function Call([string]$Method, [string]$Uri, $Form) {
    $wait = 16 - ((Get-Date) - $script:last).TotalSeconds
    if ($wait -gt 0) { Start-Sleep -Seconds ([math]::Ceiling($wait)) }
    $script:last = Get-Date
    if ($Form) { return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -Form $Form }
    $result = Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -SkipHttpErrorCheck -StatusCodeVariable code
    $script:status = $code
    return $result
}

$report = @()
foreach ($file in $Files) {
    $name = Split-Path $file -Leaf
    $sha = (Get-FileHash $file -Algorithm SHA256).Hash.ToLower()
    $known = Call 'GET' "https://www.virustotal.com/api/v3/files/$sha"
    if ($script:status -eq 404) {
        if ((Get-Item $file).Length -gt 32MB) { throw "$name is over 32 MB: the upload_url endpoint would be needed." }
        "$name : uploading..."
        $upload = Call 'POST' 'https://www.virustotal.com/api/v3/files' @{ file = Get-Item $file }
        do {
            $analysis = Call 'GET' "https://www.virustotal.com/api/v3/analyses/$($upload.data.id)"
            "$name : $($analysis.data.attributes.status)"
        } while ($analysis.data.attributes.status -ne 'completed')
        $stats = $analysis.data.attributes.stats
        $results = $analysis.data.attributes.results
    }
    elseif ($script:status -eq 200) {
        "$name : already known to VirusTotal, using its last analysis"
        $stats = $known.data.attributes.last_analysis_stats
        $results = $known.data.attributes.last_analysis_results
    }
    else { throw "VirusTotal answered $($script:status) for $name." }
    $flagged = $results.PSObject.Properties | Where-Object { $_.Value.category -in 'malicious', 'suspicious' } |
        ForEach-Object { "$($_.Name): $($_.Value.result)" }
    $report += [pscustomobject]@{
        File = $name; Malicious = $stats.malicious; Suspicious = $stats.suspicious; Undetected = $stats.undetected
        Flagged = ($flagged -join '; '); Link = "https://www.virustotal.com/gui/file/$sha"
    }
}
$report | Format-List
