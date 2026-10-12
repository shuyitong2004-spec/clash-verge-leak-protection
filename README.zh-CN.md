# Clash Verge 防泄露补丁

简体中文 | [English](README.md)

这是一个用于 Windows 与 Clash Verge Rev 的轻量补丁，处理两种常见泄露：

明明配置了纯净代理 IP，网站却仍频繁封禁？真实 IP 或 DNS 可能正通过 WebRTC 或 IPv4 DNS 旁路泄露。本项目可一键修复 Clash Verge Rev 在系统代理模式下的 WebRTC 泄露和 TUN 模式下的 IPv4 DNS 泄露。

- **系统代理模式的 WebRTC 泄露**：Chrome 或 Edge 可以绕过 HTTP 系统代理直接发送 UDP。
- **TUN 模式的 IPv4 DNS 泄露**：Mihomo 没有启用严格路由时，Windows 多网卡 DNS 可能从实体网卡直接发出。

项目不包含代理节点、订阅地址、账号密码、遥测或联网更新代码。

## 使用条件

- Windows 10 或 Windows 11
- Clash Verge Rev **2.5.7 或更高版本**
- TUN 使用 Mihomo 内核与服务模式
- Windows PowerShell 5.1 或 PowerShell 7
- 安装时允许一次管理员权限

## 安装

1. 下载并解压 `clash-verge-leak-protection-v1.0.0.zip`。
2. 右键点击 `Install.ps1`，选择**使用 PowerShell 运行**。
3. 在 Windows 管理员提示中点击“是”。
4. 完整重启 Clash Verge、Chrome 和 Edge。

如果 Windows 将下载的脚本标记为阻止，可在文件属性中选择“解除锁定”，也可以运行：

```powershell
Unblock-File .\Install.ps1, .\Uninstall.ps1, .\src\LeakProtection.ps1
.\Install.ps1
```

## 修改内容

### 系统代理与 WebRTC

- 为 Chrome、Edge 配置 `disable_non_proxied_udp` 强制策略。
- 阻止 Chrome、Edge 在 Windows **有线**和**无线**实体网卡上直接发送 UDP。
- 不阻止浏览器通过 Mihomo/Meta TUN 虚拟网卡发送 UDP；Mihomo 内核仍能在实体网卡上承载代理后的 UDP。

### TUN 与 DNS

- 开启严格路由与自动路由。
- 同时劫持 UDP 53 和 TCP 53。
- 关闭代理侧 IPv6，避免出现未保护的并行出口。
- 对启动时已经存在的全部配置启用 Clash Verge DNS 覆写。
- 普通 DNS 通过当前 `GLOBAL` 代理选择发送到 Cloudflare 或 Google DoH。
- 只有代理服务器和 DoH 服务器域名的引导解析使用直连 DoT。

后台检查由 Clash Verge 自带的 `startup_script` 启动，不创建 Windows 登录启动项。退出 Clash Verge 后，后台检查也会自动结束。

## 可能影响

- 系统代理模式下，Chrome、Edge 不能通过实体网卡直连 QUIC，普通网页会自动回退到 TCP。
- WebRTC 通话可能回退到 TCP/TURN；如果服务不提供 TCP 中继，系统代理模式下的通话可能失败。
- 严格路由可能与部分虚拟机或第三方 VPN 网卡冲突。
- DNS 使用代理出口附近的解析器，国内直连网站的本地 CDN 命中率可能降低。

自定义方法和验证步骤见[配置说明](docs/CONFIGURATION.zh-CN.md)。

## 卸载

以管理员权限运行 `Uninstall.ps1`。卸载程序只删除本项目创建的规则，恢复安装前记录的浏览器策略与 Clash Verge 启动脚本，恢复首次安装时备份的 `config.yaml`、`verge.yaml` 和 `dns_config.yaml`，然后删除安装目录。因此，安装后对这三个文件的修改也会在卸载时回退。

## 安全说明

请阅读 [SECURITY.md](SECURITY.md)。提交公开 Issue 时不要上传订阅文件或账号密码。

## 许可证

[MIT](LICENSE)
