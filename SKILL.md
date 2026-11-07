---
name: task-done-voice
description: "任务完成后用本机系统语音响一句。任何 harness 通用：交付最终答复前、需要用户拍板时、任务失败收尾时，各跑一条命令即可。Use when the user says 语音提示、任务完成响一声、播报一下、notify me when done，或需要提醒离开键盘的用户回来。"
---

# 任务完成语音提示

任务收尾时让本机说一句「任务完成了」。不联网、不装包，走操作系统自带语音。

## 什么时候跑

| 时机 | 事件 |
| --- | --- |
| 交付最终答复前 | `done`（默认） |
| 需要用户拍板 / 阻塞等待 | `ask` |
| 任务失败或工具报错收尾 | `error` |

用户当次说「别响」→ 这次不跑。长期静音 → `VOICE_NOTIFY_OFF=1`。

## 怎么跑

**Windows**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<技能目录>\scripts\notify.ps1" -Event done
```

**macOS / Linux**

```bash
bash "<技能目录>/scripts/notify.sh" --event done
```

`<技能目录>` 就是本 SKILL.md 所在目录。三档事件都有默认中文文案；要自定义加 `-Text "…"` / `--text "…"`；换英文加 `-Lang en` / `--lang en`。

## 硬规则

1. 一次任务完成只跑一次。不要循环、不要重试、不要连跑三次求稳。
2. 脚本自己分离进程并立刻返回，**直接前台调用**即可；别再套 `Start-Job`、`&`、`nohup`。
3. 脚本恒 exit 0。没声音、没语音、没设备都不算错误，不要向用户报故障；要排查就设 `VOICE_NOTIFY_DEBUG=1` 看 `%TEMP%\voice-notify.log`（POSIX 在 `${TMPDIR:-/tmp}/voice-notify.log`）。
4. 不要用别的方式「发出声音」冒充：不带蜂鸣、不播外部音频文件。本机确实没有 TTS 就说明限制，不编造「已提示」。
5. CI、容器、无音频设备的环境不要调用。

## 自检

`-DryRun` / `--dry-run` 只打印 `WOULD SAY: …`，不发声，用来确认文案、语言与语音。

## 接到各 harness

Claude Code 钩子、Codex `notify`、Cursor 规则、DSH 常驻写法，见 [`references/harness-hooks.md`](references/harness-hooks.md)。
