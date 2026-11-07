# task-done-voice

当前版本：**v1.0.0**（变更记录见 [CHANGELOG.md](CHANGELOG.md)）

任务一结束，本机用系统语音响一句「任务完成了」。

不联网、不装依赖、不生成音频文件：Windows 走 SAPI（`System.Speech`），macOS 走 `say`，Linux 走 `spd-say` / `espeak`。技能本体是一个提示词文件加两个小脚本，任何能读 `SKILL.md` 或 `AGENTS.md` 的 agent 都能用。

## 它解决什么

盯着终端等 agent 跑完是最没意义的时间。这个技能做三件事：

- **响一声**：`done` / `ask` / `error` 三档事件，各有默认中文文案。
- **不拖住 agent**：脚本自己把发声甩进分离进程，调用方 1 秒内拿到返回；恒 `exit 0`，没声卡也不会把主任务搞挂。
- **接得上**：Claude Code 用 `Stop` 钩子、Codex 用 `notify`、DSH / Cursor 用常驻规则，都是复制一段配置的事，见 [`references/harness-hooks.md`](references/harness-hooks.md)。

## 安装

任选一种。装完先跑一次干跑确认：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<技能目录>\scripts\notify.ps1" -DryRun
```

```bash
bash "<技能目录>/scripts/notify.sh" --dry-run
```

### DSH

```powershell
git clone https://github.com/yunyunlyk/task-done-voice.git "$env:DSH_HOME\skills\task-done-voice"
```

克隆而不是复制压缩包，是为了后面能 `git pull` 更新。技能目录被 DSH 监听，装完下一步就能用 `skill` 工具加载。

### Claude Code

```powershell
git clone https://github.com/yunyunlyk/task-done-voice.git "$env:USERPROFILE\.claude\skills\task-done-voice"
```

再按 [`references/harness-hooks.md`](references/harness-hooks.md) 加 `Stop` 钩子，才能做到「一结束就响」。

### Codex CLI

随便放一个目录（下面示例用 `%USERPROFILE%\skills\task-done-voice`），然后在 `~/.codex/config.toml` 加：

```toml
notify = [
  "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
  "-File", "C:\\Users\\<你>\\skills\\task-done-voice\\scripts\\notify.ps1",
  "-Event", "done"
]
```

### Cursor / 其他 harness

把 `SKILL.md` 指给 agent，或在规则文件里加一行命令。`AGENTS.md`、`CLAUDE.md`、`.cursor/rules/*.mdc` 都可以，写法见 references。

### 手动

放到任意路径，自己需要时跑脚本即可，不需要任何 harness 支持。

## 用法

```powershell
# Windows
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\notify.ps1 -Event done
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\notify.ps1 -Event ask -Text "编译好了，要发布吗"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\notify.ps1 -Event done -Lang en

# macOS / Linux
bash scripts/notify.sh --event done
bash scripts/notify.sh --event error --text "测试挂了"
bash scripts/notify.sh --event done --lang en
```

| 参数 | 说明 |
| --- | --- |
| `-Event` / `--event` | `done`（默认）/ `ask` / `error` |
| `-Text` / `--text` | 自定义文案，覆盖默认 |
| `-Lang` / `--lang` | `zh`（默认）/ `en`，决定文案与挑哪个语音 |
| `-Voice` / `--voice` | 指定语音名，例如 `Microsoft Huihui Desktop` |
| `-Rate` / `--rate` | 语速，-10..10 |
| `-DryRun` / `--dry-run` | 只打印 `WOULD SAY: …`，不发声 |

| 环境变量 | 作用 |
| --- | --- |
| `VOICE_NOTIFY_OFF=1` | 完全静音，直接退出 |
| `VOICE_NOTIFY_LANG` | 默认语言 |
| `VOICE_NOTIFY_MIN_GAP` | 节流窗口秒数，默认 10；窗口内第二次只记 `SKIP` |
| `VOICE_NOTIFY_DEBUG=1` | 往 `%TEMP%\voice-notify.log`（POSIX：`${TMPDIR:-/tmp}/voice-notify.log`）写流水：`时间 \| 事件 \| 语言 \| 语音 \| 模式 \| 文本` |

默认文案：

| 事件 | 中文 | 英文 |
| --- | --- | --- |
| `done` | 任务完成了 | Task complete |
| `ask` | 需要你确认一下 | Waiting for your input |
| `error` | 出错了，需要看一下 | Something went wrong |

## 自检

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\smoke.ps1
```

六条断言：中文默认文案、英文 `ask` 文案、`VOICE_NOTIFY_OFF` 静音、节流窗口内只响一次、真实调用耗时 < 2 秒、退出码全为 0。会真的响一声，属正常。

## 更新

仓库是唯一发布源，tag 即版本事实来源。装了克隆副本的：

```powershell
git -C "$env:DSH_HOME\skills\task-done-voice" fetch --tags
git -C "$env:DSH_HOME\skills\task-done-voice" pull --ff-only
```

`--ff-only` 是故意的：本地改过文件它会直接拒绝，不会覆盖你的改动。

想让 DSH 每 6 小时自动拉一次，按 [`references/harness-hooks.md`](references/harness-hooks.md) 的 DSH 一节建 `task-done-voice-sync` 计划任务（附带日志与卸载命令）。

## 限制

- **Windows 走系统 SAPI**：音色取决于系统已安装语音；中文需要 `zh-*` 语音（本机是 `Microsoft Huihui Desktop`）。没装中文语音会退回默认语音，日志里会标出来。
- **macOS / Linux 分支未在作者机器上实测**（该机没有可用 bash 与音频环境），只做了静态审查。Linux 需要 `spd-say`、`espeak-ng` 或 `espeak` 之一，`say` 是 macOS 自带。
- **节流是时间窗不是队列**：连续两次完成只响一次，这是刻意的。
- 脚本能证明「进程起来了、日志写了、退出码 0」，**不能证明你真的听见了**——声音由人验收。
- 有声小说、TTS 音色微调、多语言朗读不是这个技能的目标。
- **改 `notify.ps1` 时记得存成 UTF-8 with BOM**：PowerShell 5.1 读无 BOM 的 UTF-8 会按 ANSI 解码，中文默认文案会变乱码。`tests\smoke.ps1` 的第一条断言就是拿中文原文比对，改坏了会直接 FAIL。

## 许可

[MIT](LICENSE)
