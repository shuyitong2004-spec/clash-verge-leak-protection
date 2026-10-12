param(
    [string]$ConfigRoot = (Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev'),
    [switch]$InstallOnly,
    [switch]$Watch,
    [switch]$CheckOnce
)

$ErrorActionPreference = 'Stop'
$script:Utf8Bom = New-Object System.Text.UTF8Encoding($true)

function Read-Lines {
    param([string]$Path)
    if (!(Test-Path -LiteralPath $Path)) { return @() }
    return [System.IO.File]::ReadAllLines($Path)
}

function Write-LinesIfChanged {
    param([string]$Path, [string[]]$Lines)
    $next = ($Lines -join "`r`n") + "`r`n"
    $current = if (Test-Path -LiteralPath $Path) { [System.IO.File]::ReadAllText($Path) } else { '' }
    if ($current.Replace("`r`n", "`n") -eq $next.Replace("`r`n", "`n")) { return $false }
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $next, $script:Utf8Bom)
    return $true
}

function Find-TopLevelBlock {
    param([string[]]$Lines, [string]$Key)
    $start = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match ('^' + [regex]::Escape($Key) + ':')) { $start = $i; break }
    }
    if ($start -lt 0) { return @(-1, -1) }
    $end = $Lines.Count
    for ($i = $start + 1; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^[A-Za-z0-9_.-]+:') { $end = $i; break }
    }
    return @($start, $end)
}

function Set-TopLevelScalar {
    param([string[]]$Lines, [string]$Key, [string]$Value)
    $replacement = $Key + ': ' + $Value
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match ('^' + [regex]::Escape($Key) + ':')) {
            $Lines[$i] = $replacement
            return $Lines
        }
    }
    return @($replacement) + $Lines
}

function Set-TopLevelBlock {
    param([string[]]$Lines, [string]$Key, [string[]]$IndentedBody)
    $range = Find-TopLevelBlock -Lines $Lines -Key $Key
    $block = @($Key + ':') + $IndentedBody
    if ($range[0] -lt 0) { return $Lines + $block }
    $before = if ($range[0] -gt 0) { $Lines[0..($range[0] - 1)] } else { @() }
    $after = if ($range[1] -lt $Lines.Count) { $Lines[$range[1]..($Lines.Count - 1)] } else { @() }
    return @($before) + $block + @($after)
}

function Set-TunProtection {
    param([string]$Path)
    $lines = @(Read-Lines -Path $Path)
    if ($lines.Count -eq 0) { return }
    $lines = @(Set-TopLevelScalar -Lines $lines -Key 'ipv6' -Value 'false')
    $range = Find-TopLevelBlock -Lines $lines -Key 'tun'
    if ($range[0] -lt 0) {
        $lines += @('tun:', '  enable: false', '  auto-route: true', '  strict-route: true', '  auto-detect-interface: true', '  dns-hijack:', '  - any:53', '  - tcp://any:53')
        [void](Write-LinesIfChanged -Path $Path -Lines $lines)
        return
    }

    $block = [System.Collections.Generic.List[string]]::new()
    for ($i = $range[0] + 1; $i -lt $range[1]; $i++) { $block.Add($lines[$i]) }
    foreach ($setting in @(
        @{ Key = 'auto-route'; Value = 'true' },
        @{ Key = 'strict-route'; Value = 'true' },
        @{ Key = 'auto-detect-interface'; Value = 'true' }
    )) {
        $found = $false
        for ($i = 0; $i -lt $block.Count; $i++) {
            if ($block[$i] -match ('^\s{2}' + [regex]::Escape($setting.Key) + ':')) {
                $block[$i] = '  ' + $setting.Key + ': ' + $setting.Value
                $found = $true
                break
            }
        }
        if (!$found) { $block.Add('  ' + $setting.Key + ': ' + $setting.Value) }
    }

    for ($i = $block.Count - 1; $i -ge 0; $i--) {
        if ($block[$i] -match '^\s{2}dns-hijack:') {
            $block.RemoveAt($i)
            while ($i -lt $block.Count -and $block[$i] -match '^\s{4}-') { $block.RemoveAt($i) }
        }
    }
    $block.Add('  dns-hijack:')
    $block.Add('    - any:53')
    $block.Add('    - tcp://any:53')
    $lines = @(Set-TopLevelBlock -Lines $lines -Key 'tun' -IndentedBody $block.ToArray())
    [void](Write-LinesIfChanged -Path $Path -Lines $lines)
}

function Set-DnsOverrides {
    param([string]$Root)
    $profilesPath = Join-Path $Root 'profiles.yaml'
    $vergePath = Join-Path $Root 'verge.yaml'
    $uids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($line in @(Read-Lines -Path $profilesPath)) {
        if ($line -match '^\s*-\s+uid:\s*["'']?([^"''\s#]+)') { [void]$uids.Add($Matches[1]) }
    }

    $verge = @(Read-Lines -Path $vergePath)
    if ($verge.Count -eq 0) { return }
    $verge = @(Set-TopLevelScalar -Lines $verge -Key 'enable_dns_settings' -Value 'true')
    $body = @()
    foreach ($uid in @($uids | Sort-Object)) {
        $body += '  ' + $uid + ':'
        $body += '    enabled: true'
    }
    $verge = @(Set-TopLevelBlock -Lines $verge -Key 'profile_dns_settings' -IndentedBody $body)
    [void](Write-LinesIfChanged -Path $vergePath -Lines $verge)

    $templateCandidates = @(
        (Join-Path $PSScriptRoot 'config\dns_config.yaml'),
        (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\dns_config.yaml')
    )
    $template = $templateCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($template) {
        $content = [System.IO.File]::ReadAllText($template)
        $target = Join-Path $Root 'dns_config.yaml'
        if (!(Test-Path -LiteralPath $target) -or [System.IO.File]::ReadAllText($target).Replace("`r`n", "`n") -ne $content.Replace("`r`n", "`n")) {
            [System.IO.File]::WriteAllText($target, $content, $script:Utf8Bom)
        }
    }
}

function Apply-PersistentProtection {
    param([string]$Root)
    Set-TunProtection -Path (Join-Path $Root 'config.yaml')
    Set-DnsOverrides -Root $Root
}

function Get-PipeSettings {
    param([string]$Root)
    $runtimePath = Join-Path $Root 'clash-verge.yaml'
    if (!(Test-Path -LiteralPath $runtimePath)) { return $null }
    $text = [System.IO.File]::ReadAllText($runtimePath)
    $pipe = $null
    $secret = ''
    if ($text -match '(?m)^external-controller-pipe:\s*["'']?([^\r\n"'']+)') { $pipe = $Matches[1].Trim() }
    if ($text -match '(?m)^secret:\s*["'']?([^\r\n"'']*)') { $secret = $Matches[1].Trim() }
    if (!$pipe) { return $null }
    $name = $pipe -replace '^\\\\\.\\pipe\\', ''
    return [pscustomobject]@{ Name = $name; Secret = $secret }
}

function ConvertFrom-ChunkedBody {
    param([string]$Body)
    $result = New-Object System.Text.StringBuilder
    $position = 0
    while ($position -lt $Body.Length) {
        $lineEnd = $Body.IndexOf("`r`n", $position)
        if ($lineEnd -lt 0) { break }
        $sizeText = $Body.Substring($position, $lineEnd - $position).Split(';')[0]
        $size = [Convert]::ToInt32($sizeText, 16)
        if ($size -eq 0) { break }
        $position = $lineEnd + 2
        [void]$result.Append($Body.Substring($position, $size))
        $position += $size + 2
    }
    return $result.ToString()
}

function Invoke-MihomoPipe {
    param([string]$PipeName, [string]$Secret, [string]$Method, [string]$Route, [object]$Body)
    $pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', $PipeName, [System.IO.Pipes.PipeDirection]::InOut)
    try {
        $pipe.Connect(2000)
        $payload = if ($null -ne $Body) { $Body | ConvertTo-Json -Depth 12 -Compress } else { '' }
        $payloadBytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
        $headers = $Method + ' ' + $Route + " HTTP/1.1`r`nHost: localhost`r`nConnection: close`r`n"
        if ($Secret) { $headers += 'Authorization: Bearer ' + $Secret + "`r`n" }
        if ($payloadBytes.Length -gt 0) { $headers += "Content-Type: application/json`r`nContent-Length: " + $payloadBytes.Length + "`r`n" }
        $headers += "`r`n"
        $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($headers)
        $pipe.Write($headerBytes, 0, $headerBytes.Length)
        if ($payloadBytes.Length -gt 0) { $pipe.Write($payloadBytes, 0, $payloadBytes.Length) }
        $pipe.Flush()

        $memory = New-Object System.IO.MemoryStream
        $buffer = New-Object byte[] 8192
        while (($count = $pipe.Read($buffer, 0, $buffer.Length)) -gt 0) { $memory.Write($buffer, 0, $count) }
        $response = [System.Text.Encoding]::UTF8.GetString($memory.ToArray())
        $split = $response.IndexOf("`r`n`r`n")
        if ($split -lt 0) { throw 'Invalid Mihomo API response.' }
        $head = $response.Substring(0, $split)
        if ($head -notmatch '^HTTP/1\.[01]\s+2\d\d') { throw 'Mihomo API rejected the request.' }
        $content = $response.Substring($split + 4)
        if ($head -match '(?im)^Transfer-Encoding:\s*chunked') { $content = ConvertFrom-ChunkedBody -Body $content }
        if (!$content) { return $null }
        return $content | ConvertFrom-Json
    } finally {
        $pipe.Dispose()
    }
}

function Protect-RunningCore {
    param([string]$Root)
    $vergePath = Join-Path $Root 'verge.yaml'
    if (!(Test-Path -LiteralPath $vergePath)) { return }
    $vergeText = [System.IO.File]::ReadAllText($vergePath)
    if ($vergeText -notmatch '(?m)^enable_tun_mode:\s*true\s*$') { return }
    $settings = Get-PipeSettings -Root $Root
    if (!$settings) { return }
    $current = Invoke-MihomoPipe -PipeName $settings.Name -Secret $settings.Secret -Method 'GET' -Route '/configs' -Body $null
    if (!$current -or !$current.tun) { return }
    $tun = @{}
    foreach ($property in $current.tun.PSObject.Properties) { $tun[$property.Name] = $property.Value }
    $tun['enable'] = $true
    $tun['auto-route'] = $true
    $tun['strict-route'] = $true
    $tun['auto-detect-interface'] = $true
    $tun['dns-hijack'] = @('any:53', 'tcp://any:53')
    [void](Invoke-MihomoPipe -PipeName $settings.Name -Secret $settings.Secret -Method 'PATCH' -Route '/configs' -Body @{ ipv6 = $false; tun = $tun })
}

if ($CheckOnce) {
    Protect-RunningCore -Root $ConfigRoot
    exit 0
}

Apply-PersistentProtection -Root $ConfigRoot
if ($InstallOnly) { exit 0 }

if (!$Watch) {
    $arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $PSCommandPath + '" -Watch -ConfigRoot "' + $ConfigRoot + '"'
    Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden
    exit 0
}

$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\ClashVergeLeakProtectionWatcher', [ref]$created)
if (!$created) { exit 0 }
try {
    $missing = 0
    while ($true) {
        if (Get-Process -Name 'clash-verge' -ErrorAction SilentlyContinue) { $missing = 0 } else { $missing++ }
        if ($missing -ge 3) { break }
        try { Apply-PersistentProtection -Root $ConfigRoot } catch {}
        try { Protect-RunningCore -Root $ConfigRoot } catch {}
        Start-Sleep -Seconds 15
    }
} finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
