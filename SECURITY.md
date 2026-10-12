# Security policy

## Supported versions

Security fixes are provided for the latest release.

## Data handling

The installer and runtime operate only on local Clash Verge configuration, browser policy registry values, and Windows Firewall rules. They do not transmit configuration, browsing data, subscription URLs, node addresses, or credentials.

The runtime reads Mihomo's local controller secret only to authenticate over the local named pipe. It does not write, log, or transmit that secret.

## Reporting a vulnerability

Open a GitHub issue with a minimal reproduction that contains no subscription data, credentials, public IP addresses, or other personal information. For a report that cannot be safely public, contact the repository owner through their GitHub profile before sharing details.
