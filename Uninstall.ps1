$ErrorActionPreference = 'Stop'

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (!(Test-Administrator)) {
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments
    exit 0
}

$installRoot = Join-Path $env:LOCALAPPDATA 'ClashVergeLeakProtection'
$configRoot = Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev'
$statePath = Join-Path $installRoot 'install-state.json'
$vergePath = Join-Path $configRoot 'verge.yaml'
$installedScript = Join-Path $installRoot 'LeakProtection.ps1'

function Restore-RegistryValue {
    param([object]$Snapshot)
    if ($Snapshot.existed) {
        New-Item -Path $Snapshot.path -Force | Out-Null
        New-ItemProperty -Path $Snapshot.path -Name $Snapshot.name -PropertyType String -Value ([string]$Snapshot.value) -Force | Out-Null
    } elseif (Test-Path -LiteralPath $Snapshot.path) {
        Remove-ItemProperty -LiteralPath $Snapshot.path -Name $Snapshot.name -ErrorAction SilentlyContinue
    }
}

try {
    foreach ($rule in Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'CVLP-WebRTC-*' }) {
        Remove-NetFirewallRule -Name $rule.Name
    }

    $state = if (Test-Path -LiteralPath $statePath) { Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } else { $null }
    if ($state) {
        foreach ($snapshot in $state.registry) { Restore-RegistryValue -Snapshot $snapshot }
        if (Test-Path -LiteralPath $vergePath) {
            $text = [System.IO.File]::ReadAllText($vergePath)
            if ($text -match '(?m)^startup_script:\s*(.*)$') {
                $current = $Matches[1].Trim().Trim("'").Replace("''", "'")
                if ([string]::Equals($current, $installedScript, [StringComparison]::OrdinalIgnoreCase)) {
                    $previous = if ($null -ne $state.previousStartupScript -and [string]$state.previousStartupScript) { [string]$state.previousStartupScript } else { 'null' }
                    $text = [regex]::Replace($text, '(?m)^startup_script:.*$', 'startup_script: ' + $previous, 1)
                    [System.IO.File]::WriteAllText($vergePath, $text, (New-Object System.Text.UTF8Encoding($true)))
                }
            }
        }
    }

    Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*ClashVergeLeakProtection*LeakProtection.ps1*-Watch*'
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

    if ($state -and $state.backupFiles) {
        $backupRoot = Join-Path $installRoot 'backup'
        foreach ($entry in $state.backupFiles) {
            $target = Join-Path $configRoot ([string]$entry.name)
            $backup = Join-Path $backupRoot ([string]$entry.name)
            if ($entry.existed -and (Test-Path -LiteralPath $backup)) {
                Copy-Item -LiteralPath $backup -Destination $target -Force
            } elseif (!$entry.existed -and (Test-Path -LiteralPath $target)) {
                Remove-Item -LiteralPath $target -Force
            }
        }
    }

    $resolvedRoot = [System.IO.Path]::GetFullPath($installRoot)
    $expectedParent = [System.IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\') + '\'
    if (!$resolvedRoot.StartsWith($expectedParent, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolvedRoot) -ne 'ClashVergeLeakProtection') {
        throw 'Refusing to remove an unexpected path.'
    }
    if (Test-Path -LiteralPath $resolvedRoot) { Remove-Item -LiteralPath $resolvedRoot -Recurse -Force }

    Write-Host ''
    Write-Host 'Clash Verge Leak Protection removed successfully.' -ForegroundColor Green
    Write-Host 'Restart Clash Verge, Chrome, and Edge.'
} catch {
    Write-Host ''
    Write-Host ('Removal failed: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
