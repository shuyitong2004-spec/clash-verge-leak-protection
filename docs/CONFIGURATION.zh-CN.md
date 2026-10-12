# 配置与验证

简体中文 | [English](CONFIGURATION.md)

## 安装位置

安装程序会把运行文件复制到：

```text
%LOCALAPPDATA%\ClashVergeLeakProtection
```

Clash Verge 通过自身的 `startup_script` 调用 `LeakProtection.ps1`。项目不会创建计划任务、系统服务或启动文件夹快捷方式。

## DNS 解析器配置

编辑安装目录中的 `config\dns_config.yaml`，然后重启 Clash Verge。默认配置为：

```yaml
nameserver:
  - https://1.1.1.1/dns-query#GLOBAL
  - https://8.8.8.8/dns-query#GLOBAL
```

`#GLOBAL` 会强制 DoH 连接经过 Mihomo 内置 `GLOBAL` 组当前选择的代理。`proxy-server-nameserver` 至少需要保留一个无需代理即可访问的解析器，因为隧道建立前，Mihomo 必须先解析代理服务器域名。

## 添加其他浏览器

1.0.0 默认配置 Google Chrome 和 Microsoft Edge。若要添加其他 Chromium 浏览器，可复制 `Install.ps1` 中的浏览器条目，填写程序路径并使用不重复的规则名前缀。浏览器本身需要支持 Chromium WebRTC IP 处理策略。

## 添加其他网卡类型

默认防火墙规则覆盖 `Wired` 和 `Wireless`。移动宽带、USB 网络共享或特殊 VPN 网卡可能使用其他 Windows 接口类型。添加规则前应先检查实际路由与网卡类型；如果希望 TUN 中的 WebRTC 正常使用 UDP，不要创建不区分网卡的浏览器 UDP 全局阻止规则。

## 验证步骤

重启 Clash Verge 和浏览器后：

1. 在 TUN 模式下运行 `Get-NetAdapter`，确认 Meta/Mihomo 网卡已经启动。
2. 运行 `Resolve-DnsName example.com`，Fake-IP 模式应返回 `198.18.0.0/16` 内的地址。
3. 严格路由生效时，显式向局域网路由器发出的 DNS 查询应超时。
4. 在 `chrome://policy` 和 `edge://policy` 中检查 WebRTC 策略。
5. 使用无痕窗口打开浏览器泄露测试。WebRTC 不能显示运营商真实地址，DNS 解析器也不应属于本地运营商。

本地检查命令：

```powershell
Get-NetFirewallRule -Name 'CVLP-WebRTC-*'
Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Google\Chrome'
Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
```

## 故障排查

- TUN 无法启动时，确认 Clash Verge 服务模式已经安装，然后重启 Clash Verge。
- 订阅更新后 DNS 覆写被关闭时，请升级到 Clash Verge Rev 2.5.7 或更高版本。
- 系统代理模式中的 WebRTC 通话失败时，该服务可能要求直连 UDP。可在通话期间使用 TUN，或卸载 WebRTC 防火墙组件。
- 虚拟机断网时，可暂时关闭严格路由并检查虚拟机网卡路由。
