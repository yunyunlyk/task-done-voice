# 变更记录

版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)，git tag 即版本事实来源。每一版在 GitHub Releases 上都有对应发行版。

## [1.0.0] - 2026-11-07

首个正式发行版。

### 新增

- `SKILL.md`：三档事件（完成 / 待确认 / 出错）的触发规则、按平台的调用命令、五条硬规则、`--dry-run` 自检、指向各 harness 接线文档。
- `scripts/notify.ps1`：Windows 发声。存成 UTF-8 with BOM（PowerShell 5.1 兼容）；分离隐藏进程，调用方 < 1 秒返回；恒 `exit 0`；默认 10 秒节流；中文优先匹配 `zh-*` 系统语音；用 `ValueFromRemainingArguments` 吞掉 harness 追加的事件参数（兼容 Codex）；文本用 base64 传给 worker，避开命令行转义。
- `scripts/notify.sh`：macOS / Linux 发声，`say` → `spd-say` → `espeak-ng` → `espeak` 回退链，`nohup` 分离，无 BOM、LF 换行。
- `references/harness-hooks.md`：Claude Code（`settings.json` 钩子 + 技能 frontmatter 自注册）、Codex `notify`、Cursor 规则、DSH 常驻与自动更新、通用兜底，以及「没声音」五步排障。
- `tests/smoke.ps1`：六条冒烟断言（中英文文案、静音开关、节流只响一次、耗时上限、退出码）。
- `README.md`：五种安装方式、参数与环境变量表、更新与计划任务、已知限制。
- `LICENSE`：MIT。

### 说明

- Windows 已在本机实测（含中文语音）；macOS / Linux 分支未在本机验证，README 已标注。
- 技能 frontmatter 保持最小（只有 `name` + `description`），Claude Code 的自注册钩子放在 references 里按需加，避免额外键影响其他 harness 的加载器。
