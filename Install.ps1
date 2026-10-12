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

$productName = 'Clash Verge Leak Protection'
$installRoot = Join-Path $env:LOCALAPPDATA 'ClashVergeLeakProtection'
$configRoot = Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev'
$statePath = Join-Path $installRoot 'install-state.json'
$vergePath = Join-Path $configRoot 'verge.yaml'

function Get-RegistrySnapshot {
    param([string]$Path, [string]$Name)
    if (!(Test-Path -LiteralPath $Path)) { return [pscustomobject]@{ path = $Path; name = $Name; existed = $false; value = $null } }
    $item = Get-ItemProperty -LiteralPath $Path
    $property = $item.PSObject.Properties[$Name]
    return [pscustomobject]@{ path = $Path; name = $Name; existed = ($null -ne $property); value = if ($property) { [string]$property.Value } else { $null } }
}

function Set-VergeStartupScript {
    param([string]$Path, [string]$ScriptPath)
    $text = [System.IO.File]::ReadAllText($Path)
    $yamlValue = "'" + $ScriptPath.Replace("'", "''") + "'"
    if ($text -match '(?m)^startup_script:.*$') {
        $text = [regex]::Replace($text, '(?m)^startup_script:.*$', 'startup_script: ' + $yamlValue, 1)
    } else {
        $text += "`r`nstartup_script: " + $yamlValue + "`r`n"
    }
    [System.IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding($true)))
}

try {
    if (!(Test-Path -LiteralPath $vergePath)) { throw 'Clash Verge Rev configuration was not found.' }
    if (!(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'src\LeakProtection.ps1'))) { throw 'Package files are incomplete.' }

    New-Item -ItemType Directory -Path (Join-Path $installRoot 'config') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'src\LeakProtection.ps1') -Destination (Join-Path $installRoot 'LeakProtection.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'config\dns_config.yaml') -Destination (Join-Path $installRoot 'config\dns_config.yaml') -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Uninstall.ps1') -Destination (Join-Path $installRoot 'Uninstall.ps1') -Force

    $state = $null
    if (Test-Path -LiteralPath $statePath) { $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json }
    if (!$state) {
        $backupRoot = Join-Path $installRoot 'backup'
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        $backupFiles = @()
        foreach ($name in @('config.yaml', 'verge.yaml', 'dns_config.yaml')) {
            $source = Join-Path $configRoot $name
            $existed = Test-Path -LiteralPath $source
            if ($existed) { Copy-Item -LiteralPath $source -Destination (Join-Path $backupRoot $name) -Force }
            $backupFiles += [pscustomobject]@{ name = $name; existed = $existed }
        }
        $vergeText = [System.IO.File]::ReadAllText($vergePath)
        $previousStartup = if ($vergeText -match '(?m)^startup_script:\s*(.*)$') { $Matches[1].Trim() } else { $null }
        $registry = @(
            Get-RegistrySnapshot 'HKLM:\SOFTWARE\Policies\Google\Chrome' 'WebRtcIPHandlingUrl'
            Get-RegistrySnapshot 'HKLM:\SOFTWARE\Policies\Google\Chrome' 'WebRtcIPHandling'
            Get-RegistrySnapshot 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'WebRtcIPHandlingUrl'
            Get-RegistrySnapshot 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'WebRtcLocalhostIpHandling'
        )
        $state = [pscustomobject]@{
            installedVersion = '1.0.0'
            installedAt = [DateTime]::UtcNow.ToString('o')
            previousStartupScript = $previousStartup
            backupFiles = $backupFiles
            registry = $registry
        }
        $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding UTF8
    }

    $policyJson = '[{"handling":"disable_non_proxied_udp","url":"*"}]'
    foreach ($policyPath in @('HKLM:\SOFTWARE\Policies\Google\Chrome', 'HKLM:\SOFTWARE\Policies\Microsoft\Edge')) {
        New-Item -Path $policyPath -Force | Out-Null
        New-ItemProperty -Path $policyPath -Name 'WebRtcIPHandlingUrl' -PropertyType String -Value $policyJson -Force | Out-Null
    }
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Google\Chrome' -Name 'WebRtcIPHandling' -PropertyType String -Value 'disable_non_proxied_udp' -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'WebRtcLocalhostIpHandling' -PropertyType String -Value 'disable_non_proxied_udp' -Force | Out-Null

    $browsers = @(
        @{ Id = 'Chrome'; Path = Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe' },
        @{ Id = 'Edge'; Path = Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe' }
    )
    foreach ($browser in $browsers) {
        if (!(Test-Path -LiteralPath $browser.Path)) { continue }
        foreach ($interfaceType in @('Wireless', 'Wired')) {
            $ruleName = 'CVLP-WebRTC-' + $browser.Id + '-' + $interfaceType
            Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
            New-NetFirewallRule -Name $ruleName -DisplayName ($productName + ' - ' + $browser.Id + ' - ' + $interfaceType) `
                -Group $productName -Direction Outbound -Action Block -Enabled True -Profile Any `
                -Program $browser.Path -Protocol UDP -InterfaceType $interfaceType | Out-Null
        }
    }

    $installedScript = Join-Path $installRoot 'LeakProtection.ps1'
    Set-VergeStartupScript -Path $vergePath -ScriptPath $installedScript
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installedScript -InstallOnly -ConfigRoot $configRoot
    if ($LASTEXITCODE -ne 0) { throw 'Clash Verge configuration could not be updated.' }

    Write-Host ''
    Write-Host 'Clash Verge Leak Protection 1.0.0 installed successfully.' -ForegroundColor Green
    Write-Host 'Restart Clash Verge, Chrome, and Edge to load every setting.'
} catch {
    Write-Host ''
    Write-Host ('Installation failed: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
