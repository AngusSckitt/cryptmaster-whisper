# Turns the installer's info pages (installer\installer-info*.txt, the files to edit and review) into the
# .rtf files the installer shows, so a line can be bold: a line written as **text** comes out bold.
# Run by tools\package.ps1 before Inno Setup. Keep this script ASCII-only (Windows PowerShell 5.1).
$ErrorActionPreference = 'Stop'
$installer = Join-Path (Split-Path -Parent $PSScriptRoot) 'installer'

function Escape([string]$s) {
    $b = New-Object System.Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        $code = [int]$ch
        if ($ch -eq '\' -or $ch -eq '{' -or $ch -eq '}') { [void]$b.Append('\').Append($ch) }
        elseif ($code -gt 127) { [void]$b.Append('\u').Append([int][int16]$code).Append('?') }  # RTF wants signed 16-bit
        else { [void]$b.Append($ch) }
    }
    $b.ToString()
}

foreach ($txt in Get-ChildItem $installer -Filter 'installer-info*.txt') {
    $lines = [IO.File]::ReadAllText($txt.FullName, [Text.Encoding]::UTF8).Replace("`r`n", "`n").TrimEnd("`n").Split("`n")
    $rtf = New-Object System.Text.StringBuilder
    [void]$rtf.Append('{\rtf1\ansi\ansicpg1252\deff0\uc1{\fonttbl{\f0\fswiss Segoe UI;}}\viewkind4\f0\fs17 ')
    foreach ($line in $lines) {
        if ($line -match '^\*\*(.+)\*\*$') { [void]$rtf.Append('{\b ').Append((Escape $Matches[1])).Append('}') }
        else { [void]$rtf.Append((Escape $line)) }
        [void]$rtf.Append("\par`r`n")
    }
    [void]$rtf.Append('}')
    $out = [IO.Path]::ChangeExtension($txt.FullName, '.rtf')
    [IO.File]::WriteAllText($out, $rtf.ToString(), (New-Object System.Text.ASCIIEncoding))
    "info page: $($txt.Name) -> $(Split-Path $out -Leaf)"
}
