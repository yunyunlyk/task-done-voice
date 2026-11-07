<#
  任务完成语音提示 — Windows / PowerShell 5.1+。
  设计要点：调用方拿到返回立刻走人；真正发声在分离的隐藏进程里做；任何失败都 exit 0。
  注意：本文件必须存成 UTF-8 with BOM，否则 PowerShell 5.1 按 ANSI 解码，中文文案变乱码。
#>
[CmdletBinding()]
param(
    [ValidateSet('done', 'ask', 'error')][string]$Event = 'done',
    [string]$Text = '',
    [string]$Text64 = '',                                   # worker 内部用：base64(UTF-8)，避开命令行转义
    [ValidateSet('zh', 'en', '')][string]$Lang = '',
    [string]$Voice = '',
    [int]$Rate = 0,
    [switch]$DryRun,
    [switch]$Worker,
    [Parameter(ValueFromRemainingArguments = $true)][object[]]$Rest   # 吞掉 harness 追加的事件参数（如 Codex 的 JSON）
)

$ErrorActionPreference = 'Stop'

function Get-TempPath([string]$Name) {
    $root = if ($env:TEMP) { $env:TEMP } else { [IO.Path]::GetTempPath() }
    Join-Path $root $Name
}

function Write-DebugLog([string]$Mode, [string]$Say) {
    if ($env:VOICE_NOTIFY_DEBUG -ne '1') { return }
    try {
        $line = '{0} | {1} | {2} | {3} | {4} | {5}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Event, $Lang, $Voice, $Mode, $Say
        Add-Content -LiteralPath (Get-TempPath 'voice-notify.log') -Value $line -Encoding UTF8
    } catch { }
}

if ($env:VOICE_NOTIFY_OFF -eq '1') { Write-DebugLog 'OFF' ''; exit 0 }

if (-not $Lang) {
    if ($env:VOICE_NOTIFY_LANG -in @('zh', 'en')) { $Lang = $env:VOICE_NOTIFY_LANG } else { $Lang = 'zh' }
}

# Worker：真正发声，同步播完即退。
if ($Worker) {
    try {
        if ($Text64) { $Text = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Text64)) }
        Add-Type -AssemblyName System.Speech
        $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $prefix = if ($Lang -eq 'en') { 'en' } else { 'zh' }
        $picked = ''
        try {
            if ($Voice) { $synth.SelectVoice($Voice); $picked = $Voice }
            else {
                $installed = @($synth.GetInstalledVoices() | Where-Object { $_.Enabled -and $_.VoiceInfo.Culture.Name -like "$prefix*" })
                if ($installed.Count -gt 0) { $synth.SelectVoice($installed[0].VoiceInfo.Name); $picked = $installed[0].VoiceInfo.Name }
                else { $picked = $synth.Voice.Name }
            }
        } catch { $picked = $synth.Voice.Name }
        try { $synth.Rate = [Math]::Max(-10, [Math]::Min(10, $Rate)) } catch { }
        Write-DebugLog 'SPEAKING' ("$picked :: $Text")
        $synth.Speak($Text)
    } catch { Write-DebugLog 'WORKER-ERR' $_.Exception.Message }
    exit 0
}

# 默认文案
if (-not $Text) {
    $zh = @{ done = '任务完成了'; ask = '需要你确认一下'; error = '出错了，需要看一下' }
    $en = @{ done = 'Task complete'; ask = 'Waiting for your input'; error = 'Something went wrong' }
    $Text = if ($Lang -eq 'en') { $en[$Event] } else { $zh[$Event] }
}

if ($DryRun) {
    $shownVoice = if ($Voice) { $Voice } elseif ($Lang -eq 'en') { 'auto(en)' } else { 'auto(zh)' }
    Write-Output ('WOULD SAY: {0} | lang={1} voice={2} event={3}' -f $Text, $Lang, $shownVoice, $Event)
    exit 0
}

# 节流：窗口内的第二次只记日志，不重复出声。
$gap = 10
if ($env:VOICE_NOTIFY_MIN_GAP) { $parsed = 0; if ([int]::TryParse($env:VOICE_NOTIFY_MIN_GAP, [ref]$parsed)) { $gap = $parsed } }
$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$stamp = Get-TempPath 'voice-notify.last'
$last = 0
if (Test-Path -LiteralPath $stamp) { try { $last = [int]((Get-Content -LiteralPath $stamp -Raw).Trim()) } catch { $last = 0 } }
if ($gap -gt 0 -and $last -gt 0 -and ($now - $last) -lt $gap) { Write-DebugLog 'SKIP' $Text; exit 0 }
try { [IO.File]::WriteAllText($stamp, [string]$now) } catch { }

# 分离到隐藏进程发声，父进程立即返回。
try {
    $exe = (Get-Process -Id $PID).Path
    if (-not $exe) { $exe = 'powershell.exe' }
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text))
    # Start-Process 把数组按空格拼成命令行，路径带空格必须自己加引号，否则 worker 静默起不来。
    $quotedScript = '"{0}"' -f $PSCommandPath
    $argList = @('-NoProfile', '-File', $quotedScript, '-Worker', '-Event', $Event, '-Lang', $Lang, '-Rate', "$Rate", '-Text64', $b64)
    if ((Split-Path -Leaf $exe) -like 'powershell*') {
        $argList = @('-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', $quotedScript,
            '-Worker', '-Event', $Event, '-Lang', $Lang, '-Rate', "$Rate", '-Text64', $b64)
    }
    if ($Voice) { $argList += @('-Voice', $Voice) }
    Start-Process -FilePath $exe -ArgumentList $argList -WindowStyle Hidden | Out-Null
    Write-DebugLog 'DISPATCHED' $Text
} catch { Write-DebugLog 'DISPATCH-ERR' $_.Exception.Message }
exit 0
