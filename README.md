# Clash Verge Leak Protection

[简体中文](README.zh-CN.md) | English

A small Windows hardening package for two leak paths commonly seen with Clash Verge Rev:

Configured a clean proxy IP but websites still keep blocking you? Your real IP or DNS traffic may be escaping through WebRTC or an IPv4 DNS path. This package applies a one-click fix for WebRTC leaks in System Proxy mode and IPv4 DNS leaks in TUN mode.

- **WebRTC leaks in System Proxy mode**: Chrome or Edge can send direct UDP outside an HTTP system proxy.
- **IPv4 DNS leaks in TUN mode**: Windows multi-homed DNS can use the physical adapter when Mihomo TUN is not using strict routing.

The package contains no proxy nodes, subscription URLs, credentials, telemetry, or remote update code.

## Requirements

- Windows 10 or Windows 11
- Clash Verge Rev **2.5.7 or newer**
- Mihomo core and Service Mode for TUN
- Windows PowerShell 5.1 or PowerShell 7
- Administrator approval during installation

## Install

1. Download and extract `clash-verge-leak-protection-v1.0.0.zip`.
2. Right-click `Install.ps1` and choose **Run with PowerShell**.
3. Approve the Windows administrator prompt.
4. Restart Clash Verge, Chrome, and Edge.

If Windows marks the downloaded script as blocked, open file properties and select **Unblock**, or run:

```powershell
Unblock-File .\Install.ps1, .\Uninstall.ps1, .\src\LeakProtection.ps1
.\Install.ps1
```

## What it changes

### System Proxy / WebRTC

- Applies the Chrome and Edge `disable_non_proxied_udp` enterprise policies.
- Blocks outbound UDP from Chrome and Edge on Windows **Wired** and **Wireless** interfaces.
- Does not block the browser on the Mihomo/Meta TUN interface. The Mihomo process can still carry proxied UDP over the physical adapter.

### TUN / DNS

- Enables `strict-route` and automatic routing.
- Hijacks both UDP and TCP port 53.
- Disables proxy-side IPv6 to avoid an unprotected parallel path.
- Enables Clash Verge DNS Override for every profile present at startup.
- Sends normal DNS through Cloudflare or Google DoH using the current `GLOBAL` proxy selection.
- Uses direct DoT only to bootstrap proxy and DoH server hostnames.

The background watcher is launched by Clash Verge's own `startup_script`. It is not a Windows logon task or independent startup application, and it exits after Clash Verge closes.

## Side effects

- Chrome and Edge cannot use direct QUIC on physical interfaces while System Proxy mode is in use; normal web traffic falls back to TCP.
- WebRTC calls may use TCP/TURN, and a service without a TCP relay can fail in System Proxy mode.
- Strict routing can conflict with some virtual-machine or third-party VPN adapters.
- DNS answers use the proxy exit's resolver location, which may reduce local CDN accuracy for directly routed domains.

See [Configuration](docs/CONFIGURATION.md) for customization and validation.

## Uninstall

Run `Uninstall.ps1` as administrator. It removes only rules created by this project, restores browser policy values, restores the previous Clash Verge startup script, restores `config.yaml`, `verge.yaml`, and `dns_config.yaml` from the first-install backup, and removes the installed files. Changes made to those three files after installation are therefore rolled back during uninstall.

## Security

See [SECURITY.md](SECURITY.md). Please do not attach subscription files or credentials to public issues.

## License

[MIT](LICENSE)

