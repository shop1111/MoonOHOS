param(
  [Parameter(Mandatory=$true)][string]$Hdc,
  [string]$Target = '127.0.0.1:5555',
  [string]$Hap = '',
  [string]$Evidence = ''
)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
if (-not $Hap) { $Hap = Join-Path $taskRoot 'examples/harmony/entry/build/default/outputs/default/entry-default-unsigned.hap' }
if (-not $Evidence) { $Evidence = Join-Path $taskRoot '_build/validation-v0.3' }
New-Item -ItemType Directory -Force -Path $Evidence | Out-Null
function Invoke-Device([string[]]$Arguments) {
  $taskStart = [Diagnostics.ProcessStartInfo]::new()
  $taskStart.FileName = $Hdc
  $taskStart.UseShellExecute = $false
  $taskStart.CreateNoWindow = $true
  $taskStart.RedirectStandardOutput = $true
  $taskStart.RedirectStandardError = $true
  $taskStart.StandardOutputEncoding = [Text.Encoding]::UTF8
  $taskStart.StandardErrorEncoding = [Text.Encoding]::UTF8
  foreach ($taskArgument in (@('-t', $Target) + $Arguments)) { $taskStart.ArgumentList.Add($taskArgument) }
  $taskProcess = [Diagnostics.Process]::new()
  $taskProcess.StartInfo = $taskStart
  try {
    [void]$taskProcess.Start()
    $taskStdout = $taskProcess.StandardOutput.ReadToEndAsync()
    $taskStderr = $taskProcess.StandardError.ReadToEndAsync()
    if (-not $taskProcess.WaitForExit(45000)) {
      $taskProcess.Kill()
      throw ('hdc timed out: ' + ($Arguments -join ' '))
    }
    $taskOutput = $taskStdout.GetAwaiter().GetResult() + $taskStderr.GetAwaiter().GetResult()
    if ($taskProcess.ExitCode -ne 0 -or $taskOutput -match '\[Fail\]|Device not found') { throw $taskOutput }
    return $taskOutput
  } finally {
    $taskProcess.Dispose()
  }
}
Invoke-Device @('install', '-r', $Hap)
$taskLogs = Invoke-Device @('shell', 'hilog', '-x', '-T', 'MoonOHOS')
$taskPrevious = @($taskLogs -split "`n" | Where-Object { $_ -match 'MOONOHOS_RUNTIME_PASS' } | Select-Object -Last 1) -join ''
for ($taskRestart = 1; $taskRestart -le 2; $taskRestart++) {
  Invoke-Device @('shell', 'aa', 'force-stop', 'com.moonohos.demo')
  Invoke-Device @('shell', 'aa', 'start', '-a', 'EntryAbility', '-b', 'com.moonohos.demo')
  $taskPassed = $false
  for ($taskAttempt = 0; $taskAttempt -lt 20; $taskAttempt++) {
    Start-Sleep -Seconds 1
    $taskLogs = Invoke-Device @('shell', 'hilog', '-x', '-T', 'MoonOHOS')
    $taskMarkers = @($taskLogs -split "`n" | Where-Object { $_ -match 'MOONOHOS_RUNTIME_PASS version=0.3.0 add=42 scalar_checks=13 reference_checks=14 container_checks=10 repeated_calls=1000' })
    $taskLatest = @($taskMarkers | Select-Object -Last 1) -join ''
    if ($taskLatest -and $taskLatest -ne $taskPrevious) {
      $taskPrevious = $taskLatest
      $taskPassed = $true
      break
    }
  }
  $taskLogs | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $Evidence "restart-$taskRestart.log")
  if (-not $taskPassed) { throw "No new runtime success marker after restart $taskRestart" }
}
$taskLogs | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $Evidence 'runtime.log')
Invoke-Device @('shell', 'snapshot_display', '-f', '/data/local/tmp/moonohos.jpeg')
Invoke-Device @('file', 'recv', '/data/local/tmp/moonohos.jpeg', (Join-Path $Evidence 'page.jpeg'))
Get-FileHash -Algorithm SHA256 -LiteralPath $Hap | Select-Object Algorithm, Hash |
  ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $Evidence 'hap-sha256.json')
Write-Output "DEVICE_RUNTIME_PASS restarts=2 evidence=$Evidence"
