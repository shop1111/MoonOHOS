param(
  [string]$DevEco = 'D:\apps\DevEco Studio',
  [string]$Target = '127.0.0.1:5555',
  [string]$Evidence = (Join-Path $PSScriptRoot '..\..\_build\probe-v0.4')
)
# One-off P1b/P3 spike: HAR packaging, independent HAP consumption and worker-thread runtime probe.
$ErrorActionPreference = 'Continue'
$hdc = Join-Path $DevEco 'sdk\default\openharmony\toolchains\hdc.exe'
$node = Join-Path $DevEco 'tools\node\node.exe'
$saved = @{}
foreach ($pair in @{ DEVECO_SDK_HOME = "$DevEco\sdk"; NODE_HOME = "$DevEco\tools\node"; OHPM_HOME = "$DevEco\tools\ohpm"; JAVA_HOME = "$DevEco\jbr" }.GetEnumerator()) {
  $saved[$pair.Key] = [Environment]::GetEnvironmentVariable($pair.Key, 'Process')
  [Environment]::SetEnvironmentVariable($pair.Key, $pair.Value, 'Process')
}
function Hvigor([string]$Project, [string[]]$Arguments) {
  Push-Location $Project
  try {
    & $node "$DevEco\tools\ohpm\bin\pm-cli.js" install 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "ohpm install failed in $Project" }
    & $node "$DevEco\tools\hvigor\bin\hvigorw.js" @Arguments 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "hvigor failed in $Project" }
  } finally { Pop-Location }
}
function Device([string[]]$Arguments, [int]$Seconds = 60) {
  $out = [IO.Path]::GetTempFileName(); $err = [IO.Path]::GetTempFileName()
  $process = Start-Process -FilePath $hdc -ArgumentList (@('-t', $Target) + $Arguments) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
  if (-not $process.WaitForExit($Seconds * 1000)) { $process.Kill(); throw "hdc timed out: $Arguments" }
  $text = (Get-Content $out -Raw -Encoding UTF8) + (Get-Content $err -Raw)
  Remove-Item $out, $err
  if ($text -match '\[Fail\]|Device not found') { throw "hdc failed: $text" }
  $text
}
try {
  New-Item -ItemType Directory -Force $Evidence | Out-Null
  Hvigor (Join-Path $PSScriptRoot 'har') @('--mode', 'module', '-p', 'module=asyncprobe@default', '-p', 'product=default', '-p', 'buildMode=release', '--no-daemon', 'assembleHar')
  $har = Join-Path $PSScriptRoot 'har\asyncprobe\build\default\outputs\default\asyncprobe.har'
  Hvigor (Join-Path $PSScriptRoot 'consumer') @('--mode', 'module', '-p', 'module=entry@default', '-p', 'product=default', '-p', 'buildMode=debug', '--no-daemon', 'assembleHap')
  $hap = Join-Path $PSScriptRoot 'consumer\entry\build\default\outputs\default\entry-default-unsigned.hap'
  Device @('install', '-r', $hap) 120 | Out-Null
  Device @('shell', 'hilog', '-r') | Out-Null
  Device @('shell', 'aa', 'force-stop', 'com.moonohos.probe') | Out-Null
  Device @('shell', 'aa', 'start', '-a', 'EntryAbility', '-b', 'com.moonohos.probe') | Out-Null
  $log = ''
  for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Seconds 1
    $log = Device @('shell', 'hilog', '-x', '-T', 'MoonOHOSProbe')
    if ($log -match 'PROBE_DONE|PROBE_FAIL') { break }
  }
  Set-Content -Path (Join-Path $Evidence 'probe-runtime.log') -Value $log -Encoding UTF8
  @{
    har = (Get-FileHash $har -Algorithm SHA256).Hash
    hap = (Get-FileHash $hap -Algorithm SHA256).Hash
    harEntries = (tar -tzf $har)
  } | ConvertTo-Json | Set-Content -Path (Join-Path $Evidence 'probe-artifacts.json') -Encoding UTF8
  $log
  if ($log -notmatch 'PROBE_DONE') { throw 'probe did not finish' }
} finally {
  foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
}
