# Configuration and validation

[简体中文](CONFIGURATION.zh-CN.md) | English

## Installed location

The installer copies the runtime to:

```text
%LOCALAPPDATA%\ClashVergeLeakProtection
```

Clash Verge is configured to call `LeakProtection.ps1` through its `startup_script` setting. No Scheduled Task, service, or Startup-folder shortcut is created.

## DNS resolver configuration

Edit the installed `config\dns_config.yaml`, then restart Clash Verge. The default uses:

```yaml
nameserver:
  - https://1.1.1.1/dns-query#GLOBAL
  - https://8.8.8.8/dns-query#GLOBAL
```

`#GLOBAL` forces the DoH transport through the proxy selected by Mihomo's built-in `GLOBAL` group. Keep at least one `proxy-server-nameserver` entry reachable without the proxy; Mihomo needs it to resolve proxy server hostnames before the tunnel exists.

## Additional browsers

Version 1.0.0 configures Google Chrome and Microsoft Edge. To add another Chromium browser, duplicate one browser entry in `Install.ps1`, provide its executable path, and use a unique rule prefix. The browser must support the Chromium WebRTC IP handling policy.

## Additional interface types

The default firewall rules cover `Wired` and `Wireless`. Mobile broadband, USB tethering, or unusual VPN adapters may use another Windows interface type. Inspect the route and interface before adding a rule; do not use an unrestricted all-interface UDP block if you want WebRTC to work through TUN.

## Verification

After restarting Clash Verge and the browsers:

1. In TUN mode, run `Get-NetAdapter` and confirm the Meta/Mihomo adapter is up.
2. Run `Resolve-DnsName example.com`. Fake-IP mode should return an address in `198.18.0.0/16`.
3. Explicit DNS to the LAN router should time out while strict routing is active.
4. Check `chrome://policy` and `edge://policy` for the WebRTC policies.
5. Use a browser leak test in a fresh private window. The WebRTC address must not be the ISP address, and DNS resolver addresses must not belong to the local ISP.

Useful local checks:

```powershell
Get-NetFirewallRule -Name 'CVLP-WebRTC-*'
Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Google\Chrome'
Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
```

## Troubleshooting

- If TUN cannot start, confirm Clash Verge Service Mode is installed and restart Clash Verge.
- If a profile update disables DNS Override, update Clash Verge Rev to 2.5.7 or newer.
- If a WebRTC call fails in System Proxy mode, the service may require direct UDP. Use TUN mode for that call, or uninstall the WebRTC firewall component.
- If a VM loses connectivity, disable strict routing temporarily and review the VM adapter routes.
