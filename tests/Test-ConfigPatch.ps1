$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $PSScriptRoot '.test-work'

function Assert-Match {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -notmatch $Pattern) { throw $Message }
}

$resolvedTests = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'
$resolvedWork = [System.IO.Path]::GetFullPath($testRoot)
if (!$resolvedWork.StartsWith($resolvedTests, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test path.' }
if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
try {
    @'
mixed-port: 7897
ipv6: true
tun:
  enable: false
  auto-route: false
  strict-route: false
  dns-hijack:
    - any:53
secret: test-only
'@ | Set-Content -LiteralPath (Join-Path $testRoot 'config.yaml') -Encoding UTF8

    @'
startup_script: null
enable_tun_mode: true
enable_dns_settings: false
profile_dns_settings:
  old:
    enabled: false
'@ | Set-Content -LiteralPath (Join-Path $testRoot 'verge.yaml') -Encoding UTF8

    @'
current: alpha
items:
  - uid: alpha
    type: remote
    name: First
  - uid: beta
    type: local
    name: Second
'@ | Set-Content -LiteralPath (Join-Path $testRoot 'profiles.yaml') -Encoding UTF8

    New-Item -ItemType Directory -Path (Join-Path $PSScriptRoot 'config') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'config\dns_config.yaml') -Destination (Join-Path $PSScriptRoot 'config\dns_config.yaml') -Force
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'src\LeakProtection.ps1') -InstallOnly -ConfigRoot $testRoot
    if ($LASTEXITCODE -ne 0) { throw 'Configuration patch process failed.' }

    $config = Get-Content -LiteralPath (Join-Path $testRoot 'config.yaml') -Raw
    $verge = Get-Content -LiteralPath (Join-Path $testRoot 'verge.yaml') -Raw
    $dns = Get-Content -LiteralPath (Join-Path $testRoot 'dns_config.yaml') -Raw
    Assert-Match $config '(?m)^ipv6: false\r?$' 'IPv6 was not disabled.'
    Assert-Match $config '(?m)^  strict-route: true\r?$' 'Strict routing was not enabled.'
    Assert-Match $config '(?m)^    - tcp://any:53\r?$' 'TCP DNS hijacking was not added.'
    Assert-Match $verge '(?m)^enable_dns_settings: true\r?$' 'DNS Override was not enabled.'
    Assert-Match $verge '(?m)^  alpha:\r?\n    enabled: true\r?$' 'First profile was not enabled.'
    Assert-Match $verge '(?m)^  beta:\r?\n    enabled: true\r?$' 'Second profile was not enabled.'
    Assert-Match $dns 'https://1\.1\.1\.1/dns-query#GLOBAL' 'Protected DNS template was not installed.'
    Write-Host 'All configuration tests passed.' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
    $testConfig = Join-Path $PSScriptRoot 'config'
    if (Test-Path -LiteralPath $testConfig) { Remove-Item -LiteralPath $testConfig -Recurse -Force }
}
