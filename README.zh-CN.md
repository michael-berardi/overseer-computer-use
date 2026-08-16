# Overseer Computer Use

[English](./README.md) · [隐私与安全](./SECURITY.md) · [第三方声明](./THIRD_PARTY_NOTICES.md)

Overseer Computer Use 是一个在本机运行的开源 Computer Use runtime。它通过 stdio MCP 为支持 MCP 的 Agent 提供九个桌面工具；不会把屏幕、提示词、坐标或用户内容发送到托管服务，也不需要云端 dashboard。

## 安装（macOS）

需要 macOS 14 或更高版本、已登录的图形桌面，以及支持 MCP/stdio 的 Agent。稳定版安装包是经过 Developer ID 签名和 Apple notarization 的 `Overseer-Computer-Use.pkg`：

```bash
curl -fsSL https://raw.githubusercontent.com/michael-berardi/overseer-computer-use/main/scripts/install-overseer-computer-use.sh | bash
```

脚本从 `michael-berardi/overseer-computer-use` 的最新 stable release 下载包和 SHA-256 清单，校验后才调用系统 `installer`，安装到 `/Applications/Overseer Computer Use.app`。它拒绝 ad-hoc 或错误 Team ID 的包。源码 checkout 可使用：

```bash
./scripts/install-overseer-computer-use.sh --local dist/Overseer-Computer-Use.pkg
```

安装后把 `~/.local/bin` 加入 `PATH`，然后运行：

```bash
overseer computer-use doctor
```


## Agent 配置与工具

通用 MCP 配置示例：

```json
{"mcpServers":{"overseer-computer-use":{"command":"overseer","args":["computer-use","mcp"]}}}
```

首次使用会显示深色权限引导。Accessibility 和 Screen Recording 的状态来自系统 API；打开 System Settings 页面并不等于授权成功。新 bundle ID 需要一次新的授权，之后升级和签名更新会保持同一身份。可用工具包括 `list_apps`、`get_app_state`、`click`、`drag`、`scroll`、`type_text`、`press_key`、`set_value`、`perform_secondary_action`。坐标和状态可能在窗口移动后失效，应重新获取状态。

## 隐私、更新与诊断

首次启动会询问“Share anonymous usage”或“No thanks”。只有明确选择分享后，才会生成随机安装 ID、发送 launch/每日 heartbeat，以及固定工具类别的成功/失败计数。不会发送提示词、截图、坐标、窗口或应用名称、参数、文件路径、用户内容、原始 IP/UA、密钥或硬件标识；标识行最多保留 34 个 UTC 日，无 ID 的日汇总最多保留 360 日。拒绝会保持静默；`overseer computer-use telemetry status|enable|disable` 可随时查看或更改，关闭分享会删除本地 telemetry 状态。

应用启动时检查 GitHub 最新 stable release，最多每日一次。更新提示提供 **Update now**、**Later** 和 **Install updates automatically**；自动安装必须单独选择。候选包需通过 SHA-256、Developer ID Application、bundle/team/designated requirement 和 notarization 校验，然后原子替换；失败会保留旧版本并回滚。

```bash
overseer computer-use doctor
# 诊断（签名、bundle identity、TCC 状态）
overseer computer-use diagnostics
# 卸载应用和命令 shim
overseer computer-use uninstall
```

## 局限与许可

这是本机 macOS 自动化工具，需要用户授予系统权限；辅助功能树和窗口截图会随应用变化，受遮挡、最小化、不同 Space、系统更新及目标应用安全策略影响。实验性的 Linux/Windows runtime 不等同于 macOS release installer。

本项目源自 `iFurySt/open-codex-computer-use`，保留上游 MIT 许可和归属；产品身份、权限引导、匿名 telemetry、签名更新、打包和通用 Agent 安装是本 fork 的有意差异。完整 lineage、维护同步方式和许可证见 [`THIRD_PARTY_NOTICES.md`](./THIRD_PARTY_NOTICES.md)。
