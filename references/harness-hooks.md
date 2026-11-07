# 接到各 harness

三种接线强度，按你的 harness 支持哪档来选：

| 强度 | 手段 | 谁会真的响 |
| --- | --- | --- |
| 最强 | harness 的「完成」事件钩子 | Claude Code（`Stop`）、Codex（`notify`） |
| 中 | 常驻规则文件（`AGENTS.md` / 规则文件） | DSH、Cursor、任何读 AGENTS.md 的 agent |
| 弱 | 技能按名加载，模型自己决定什么时候调 | 全部 harness |

最强那档不依赖模型记性，值得优先接。

---

## Claude Code

### 用 settings.json 钩子（推荐）

`~/.claude/settings.json`（项目级放 `.claude/settings.json`）：

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:\\Users\\<你>\\skills\\task-done-voice\\scripts\\notify.ps1\" -Event done",
            "async": true
          }
        ]
      }
    ],
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:\\Users\\<你>\\skills\\task-done-voice\\scripts\\notify.ps1\" -Event ask",
            "async": true
          }
        ]
      }
    ]
  }
}
```

macOS / Linux 把命令换成：

```json
"command": "bash \"$HOME/.claude/skills/task-done-voice/scripts/notify.sh\" --event done"
```

要点：

- `Stop` 是 Claude 结束一次回答时触发，`Notification` 是它需要权限或等你输入时触发，用 `ask` 文案。
- 子代理完成走 `SubagentStop`，想让它也响就照样加一条。
- **`"async": true` 别省**：不加的话 Claude Code 会等钩子跑完才继续；脚本虽然自己分离了进程，但仍白等一次启动开销。
- 事件名与字段以官方 [Hooks 参考](https://code.claude.com/docs/en/hooks) 为准（本仓库核对时该文档列出了 `Stop` / `SubagentStop` / `SessionEnd` / `Notification`）。

### 用技能 frontmatter 自注册

Claude Code 的技能可以在 frontmatter 里带 `hooks:`，技能被调用后这些钩子会在本会话后续回合里一直生效：

```yaml
hooks:
  Stop:
    - hooks:
        - type: command
          command: "powershell -NoProfile -ExecutionPolicy Bypass -File <绝对路径>\\scripts\\notify.ps1 -Event done"
          async: true
```

本仓库的 `SKILL.md` **没有**默认写这段：DSH 的技能加载器只要求 `name` + `description`，塞额外键有风险，所以放在这里让你按需加。用相对路径请确认 harness 的解析基准，稳妥起见用绝对路径。

---

## Codex CLI

`~/.codex/config.toml`：

```toml
notify = [
  "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
  "-File", "C:\\Users\\<你>\\skills\\task-done-voice\\scripts\\notify.ps1",
  "-Event", "done"
]
```

- `notify` 的数组就是「程序 + 参数」，Codex 在事件发生时执行它。
- Codex 会在参数末尾追加一个事件对象（JSON）。本仓库脚本用 `ValueFromRemainingArguments` 吞掉多余参数、`notify.sh` 也会忽略未知参数，所以**不需要**为它改脚本。
- 本机核对过这个字段的真实写法：现有配置里就是 `notify = ["<exe>", "turn-ended"]` 这种形式。
- 想确认实际传了什么，在脚本外面套一层记录参数的包装脚本，或看 `VOICE_NOTIFY_DEBUG=1` 的日志。

---

## Cursor / 其他读 AGENTS.md 的 harness

`.cursor/rules/task-done-voice.mdc`：

```markdown
---
description: 任务完成后语音提示
alwaysApply: true
---

每次给出最终答复前，执行一次（脚本自己分离进程、恒 exit 0，不要重试）：

powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\<你>\skills\task-done-voice\scripts\notify.ps1" -Event done

需要用户拍板时用 -Event ask，任务失败收尾用 -Event error。
```

`CLAUDE.md`、`GEMINI.md`、`AGENTS.md` 同理：一句话规则 + 命令。

---

## DSH

1. 技能装成 git 克隆（才能自动更新）：

```powershell
git clone https://github.com/yunyunlyk/task-done-voice.git "$env:DSH_HOME\skills\task-done-voice"
```

2. 常驻（写进 `$env:DSH_HOME\AGENTS.md`，每次会话都会带上）：

```markdown
## 任务完成语音提示（task-done-voice）

<!-- 来源: github.com/yunyunlyk/task-done-voice；技能: $DSH_HOME\skills\task-done-voice；更新: 计划任务 task-done-voice-sync 每 6 小时 git pull --ff-only；回滚: 删本节 + 注销计划任务 + 删技能目录 -->

每次给出最终答复前执行一次；需要用户拍板用 `-Event ask`，任务失败收尾用 `-Event error`：

powershell -NoProfile -ExecutionPolicy Bypass -File "D:\...\dsh-home\skills\task-done-voice\scripts\notify.ps1" -Event done
```

路径写**本机绝对路径**，别指望模型每次正确展开 `$env:DSH_HOME`。

3. 自动更新脚本 `$env:DSH_HOME\scripts\task-done-voice-update.ps1`（脚本里不写中文，PowerShell 5.1 读无 BOM UTF-8 会解析失败）：

```powershell
$repo = Join-Path $env:DSH_HOME 'skills\task-done-voice'
$log = Join-Path $env:DSH_HOME 'logs\task-done-voice-update.log'
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
if (-not (Test-Path (Join-Path $repo '.git'))) { 'SKIP: not a git repo' | Add-Content $log; exit 1 }
Push-Location $repo
try {
    $before = (git rev-parse --short HEAD).Trim()
    git fetch --tags --prune --quiet 2>&1 | Out-Null
    $out = git pull --ff-only 2>&1 | Out-String
    $code = $LASTEXITCODE
    $after = (git rev-parse --short HEAD).Trim()
    $tag = (git describe --tags --abbrev=0 2>$null)
    if ($code -ne 0) { "ERROR: $($out.Trim()) ($before -> $after)" | Add-Content $log }
    elseif ($before -ne $after) { "UPDATED: $before -> $after ($tag)" | Add-Content $log }
    else { "OK: up to date ($before, $tag)" | Add-Content $log }
} finally { Pop-Location }
```

注册计划任务（登录时 + 每 6 小时）：

```powershell
$script = Join-Path $env:DSH_HOME 'scripts\task-done-voice-update.ps1'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $script)
$t1 = New-ScheduledTaskTrigger -AtLogOn
$t2 = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) -RepetitionInterval (New-TimeSpan -Hours 6) -RepetitionDuration (New-TimeSpan -Days 3650)
Register-ScheduledTask -TaskName 'task-done-voice-sync' -Action $action -Trigger @($t1,$t2) -Force
```

---

## 没声音时的五步排查

1. `VOICE_NOTIFY_OFF` 是不是被设成 `1` 了。
2. 距上一次提示不到 `VOICE_NOTIFY_MIN_GAP`（默认 10 秒）→ 日志里是 `SKIP`，这是设计行为。
3. `VOICE_NOTIFY_DEBUG=1` 跑一次，看日志最后一行：`DISPATCHED` 说明进程拉起来了，`NO-TTS` / `WORKER-ERR` 说明本机缺语音。
4. 系统输出设备：Windows 看 `Get-PnpDevice -Class AudioEndpoint`，macOS 看「声音」输出，Linux 看 `pactl list short sinks`。
5. 语言不匹配：中文文本配了英文语音会读成乱码。`-Lang zh`（默认）会挑 `zh-*` 语音，机器上没装中文语音就会退回默认语音并在日志里标出来。
