<#
  冒烟测试：六条断言，全 PASS 才算过。
  会真的响一两声，属正常。跑法：powershell -NoProfile -ExecutionPolicy Bypass -File tests\smoke.ps1
#>
$ErrorActionPreference = 'Stop'

$script = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\notify.ps1'
if (-not (Test-Path -LiteralPath $script)) { Write-Host "FAIL: 找不到脚本 $script"; exit 1 }

$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $psExe)) { $psExe = 'powershell.exe' }

$tempRoot = if ($env:TEMP) { $env:TEMP } else { [IO.Path]::GetTempPath() }
$stamp = Join-Path $tempRoot 'voice-notify.last'
$log = Join-Path $tempRoot 'voice-notify.log'

$fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { Write-Host "PASS  $Name" -ForegroundColor Green }
    else { Write-Host "FAIL  $Name  $Detail" -ForegroundColor Red; $script:fail++ }
}

function Invoke-Notify {
    param([string[]]$Arguments, [hashtable]$Env = @{})
    $saved = @{}
    foreach ($k in $Env.Keys) {
        $saved[$k] = [Environment]::GetEnvironmentVariable($k, 'Process')
        [Environment]::SetEnvironmentVariable($k, $Env[$k], 'Process')
    }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $out = & $psExe -NoProfile -ExecutionPolicy Bypass -File $script @Arguments 2>&1 | Out-String
    $sw.Stop()
    $code = $LASTEXITCODE
    foreach ($k in $Env.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k], 'Process') }
    [pscustomobject]@{ Output = $out.Trim(); Code = $code; Ms = [Math]::Round($sw.Elapsed.TotalMilliseconds) }
}

# 1 中文默认文案
$r = Invoke-Notify -Arguments @('-DryRun', '-Event', 'done') -Env @{ VOICE_NOTIFY_MIN_GAP = '0' }
Check '中文默认文案' ($r.Code -eq 0 -and $r.Output -match '任务完成了' -and $r.Output -match 'lang=zh') "code=$($r.Code) out=$($r.Output)"

# 2 英文 ask 文案
$r = Invoke-Notify -Arguments @('-DryRun', '-Event', 'ask', '-Lang', 'en') -Env @{ VOICE_NOTIFY_MIN_GAP = '0' }
Check '英文 ask 文案' ($r.Code -eq 0 -and $r.Output -match 'Waiting for your input' -and $r.Output -match 'lang=en') "code=$($r.Code) out=$($r.Output)"

# 3 静音开关
$r = Invoke-Notify -Arguments @('-DryRun') -Env @{ VOICE_NOTIFY_OFF = '1'; VOICE_NOTIFY_MIN_GAP = '0' }
Check 'VOICE_NOTIFY_OFF 静音' ($r.Code -eq 0 -and $r.Output -notmatch 'WOULD SAY') "code=$($r.Code) out=$($r.Output)"

# 4 节流：窗口内第二只记 SKIP
if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue }
if (Test-Path -LiteralPath $stamp) { Remove-Item -LiteralPath $stamp -Force -ErrorAction SilentlyContinue }
$envArgs = @{ VOICE_NOTIFY_MIN_GAP = '60'; VOICE_NOTIFY_DEBUG = '1' }
$a = Invoke-Notify -Arguments @('-Event', 'done') -Env $envArgs
$b = Invoke-Notify -Arguments @('-Event', 'done') -Env $envArgs
$logText = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw -Encoding UTF8 } else { '' }
$speaks = ([regex]::Matches($logText, 'DISPATCHED')).Count
$skips = ([regex]::Matches($logText, 'SKIP')).Count
Check '节流只响一次' ($a.Code -eq 0 -and $b.Code -eq 0 -and $speaks -eq 1 -and $skips -eq 1) "dispatched=$speaks skip=$skips"

# 5 真实调用不被阻塞，且 worker 真的把语音送进 TTS
if (Test-Path -LiteralPath $stamp) { Remove-Item -LiteralPath $stamp -Force -ErrorAction SilentlyContinue }
if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue }
$c = Invoke-Notify -Arguments @('-Event', 'done') -Env @{ VOICE_NOTIFY_MIN_GAP = '0'; VOICE_NOTIFY_DEBUG = '1' }
Start-Sleep -Milliseconds 2500
$logText = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw -Encoding UTF8 } else { '' }
$spoke = $logText -match 'SPEAKING'
Check '调用 < 2000ms 返回' ($c.Code -eq 0 -and $c.Ms -lt 2000) "code=$($c.Code) ms=$($c.Ms)"
Check 'worker 真的把语音送进 TTS' $spoke ('log=' + ($logText -replace "`r?`n", ' / '))

# 6 三档事件退出码恒 0
$codes = @()
foreach ($e in @('done', 'ask', 'error')) {
    if (Test-Path -LiteralPath $stamp) { Remove-Item -LiteralPath $stamp -Force -ErrorAction SilentlyContinue }
    $codes += (Invoke-Notify -Arguments @('-Event', $e) -Env @{ VOICE_NOTIFY_MIN_GAP = '0' }).Code
}
Check '三档事件 exit 0' (($codes | Where-Object { $_ -ne 0 }).Count -eq 0) "codes=$($codes -join ',')"

# 清理节流状态，避免影响用户接下来的手动调用
if (Test-Path -LiteralPath $stamp) { Remove-Item -LiteralPath $stamp -Force -ErrorAction SilentlyContinue }

Write-Host ''
if ($fail -eq 0) { Write-Host 'ALL PASS (7/7)' -ForegroundColor Green; exit 0 }
Write-Host "$fail 条失败" -ForegroundColor Red
exit 1
