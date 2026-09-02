# VPS Traffic (VPS 流量监控插件)

**[English](README.md)** | **[简体中文](README_zh.md)**

专为 [Omarchy](https://omarchy.org/) 桌面环境打造的原生顶栏（Bar）小部件，用于实时显示 VPS 供应商的**官方计费流量使用情况** —— 已用 / 总量、百分比进度以及重置倒计时。

首发针对 [BandwagonHost (搬瓦工)](https://bandwagonhost.com/) KiwiVM 进行实测，并内置对 [Vultr](https://www.vultr.com/) 的参考扩展支持。

## 功能特性

- **官方计费数据**：已用 / 总量 / 百分比，与服务商后台控制面板完全一致
- **重置倒计时**：直观展示距离下个计费周期重置的时间（例如 `17d 2h left`）及具体重置日期
- **状态指示色**：常态保持主题色平静显示 → 超过 80% 变为黄色警告 → 超过 95% 或实例被暂停时变为红色紧急
- **快捷详情面板**：点击弹出原生面板，包含流量仪表盘条、套餐名称、机房位置、操作系统及 IP
- **自定义刷新周期**：支持自定义轮询间隔；支持**鼠标中键**一键切换供应商
- **零外部依赖**：单文件自包含 CLI 脚本，纯原生 JavaScript 数据模型，无需庞大依赖库

## 安装方法

运行环境需具备 `curl` 与 `python3`（Omarchy 系统均已标配）。

```bash
omarchy plugin add https://github.com/kylesean/vps-traffic --enable
```

或者手动安装：将本项目克隆或复制至 `~/.config/omarchy/plugins/kylesean.vps-traffic/`，
执行 `omarchy-shell shell rescanPlugins`，然后运行 `omarchy plugin enable kylesean.vps-traffic`。

将其固定到顶栏：
```bash
omarchy bar put kylesean.vps-traffic --after omarchy.clock
```

## 配置指南

右键点击顶栏小部件 → **Settings (设置)** → 粘贴凭据：
* KiwiVM: 填写 `VEID` + `API key`
* Vultr: 填写 `Instance ID` + `API key`

凭据将自动以 `0600` 安全权限保存到本地 `~/.config/vps-traffic/<provider>/env`，绝不随 Git 提交或泄露。

也可以手动写入配置文件：

```bash
mkdir -p ~/.config/vps-traffic/kiwivm && chmod 700 ~/.config/vps-traffic ~/.config/vps-traffic/kiwivm
cat > ~/.config/vps-traffic/kiwivm/env <<'EOF'
KIWIVM_VEID=你的VEID
KIWIVM_API_KEY=private_xxxxxxxx
EOF
chmod 600 ~/.config/vps-traffic/kiwivm/env
```

| 配置键名 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `provider` | enum | `kiwivm` | 指定抓取的数据源 (`kiwivm`, `vultr`) |
| `refreshIntervalSec` | int | 300 | 自动刷新间隔秒数 (30–3600) |
| `warnPercent` | int | 80 | 黄色警告阈值百分比 |
| `criticalPercent` | int | 95 | 红色告警阈值百分比 |
| `showPercent` | bool | true | 是否在顶栏图标旁显示百分比数字 |
| `showHost` | bool | false | 是否在百分比前显示 VPS 主机名 |

配置内联存储在 `~/.config/omarchy/shell.json` 中；也可以使用命令行修改：
`omarchy bar set kylesean.vps-traffic <key> <value>`。

## 交互与快捷键

- **鼠标左键 / Esc** — 展开 / 收起详情面板
- **鼠标右键** — 打开设置表单
- **鼠标滚轮** — 立即刷新；**鼠标中键** — 循环切换已配置的供应商
- **R 键 / F5** — 刷新数据
- **S 键** — 打开设置

## 供应商支持说明

- **BandwagonHost (KiwiVM)**：**已实测**。直接调用 `getServiceInfo` API 读取实时计数器；官方双向统计流量，数据通常有约 15 分钟的统计延迟。
- **Vultr**：**暂未实测（参考实现）**。保留该后端主要是为了验证并保持多 Provider 的良好扩展性。其逻辑是通过 `/instances/{id}/bandwidth` 汇总当月出站流量并与 `allowed_bandwidth` 比对。（欢迎使用 Vultr 的用户测试并提交 PR 完善！）
- **安全与凭据管理**：KiwiVM API 采用 URL 参数鉴权，Vultr 采用 `Authorization: Bearer` 请求头鉴权。设置助手在保存密钥时使用标准输入 `stdin` 管道写入独立文件，权限严格设为 `mode 600`，绝不会将 API 密钥作为进程参数传递，保障在 `ps aux` 中绝不泄密。

## 后续计划与贡献鼓励

- **提交官方插件市场**：在作者日常实测稳定、进一步打磨完善之后，本项目将正式提交至 [Omarchy 官方插件市场 (Plugin Marketplace)](https://github.com/omacom/omarchy-plugin-marketplace)。
- **欢迎 Fork 与个性化定制**：本插件的代码逻辑与架构非常轻巧精简，前后端解耦彻底。非常鼓励大家自由 **Fork** 修改、打造成适合你自己的专属版本，或为其他 VPS 供应商（如 Hetzner、DigitalOcean、Linode、腾讯云、阿里云等）贡献适配后端！

## 开发与本地测试

```bash
node omarchy/model.test.mjs   # 运行纯 JS 合约测试（零外部 node_modules）
omarchy plugin validate .     # 校验 manifest 与入口点合法性
```

添加新供应商只需三步：在 `omarchy/Model.js` 注册供应商与所需字段，在 `bin/vps-traffic` 添加一个 `case` 分支，并在 `manifest.json` 的 enum 中增加选项 —— 前端 UI 与设置界面会自动动态生成。

## 开源协议

[MIT License](LICENSE)。与 BandwagonHost 或 Vultr 官方无关。
