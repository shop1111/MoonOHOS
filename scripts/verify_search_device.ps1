param(
  [string]$DevEco = 'D:\apps\DevEco Studio',
  [string]$Target = '127.0.0.1:5555',
  [string]$Evidence = (Join-Path (Split-Path -Parent $PSScriptRoot) '_build\search-v0.4'),
  [int]$Runs = 2
)
# Installs the independent search app and runs its scripted scenario on a
# connected emulator/device: small index + async/sync search, cancel a large
# build, full large build while the UI timer runs, leave the page during a
# rebuild, re-enter, and check MoonOHOS diagnostics after both rounds.
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$hdc = Join-Path $DevEco 'sdk\default\openharmony\toolchains\hdc.exe'
$hap = Join-Path $root 'examples\search-app\entry\build\default\outputs\default\entry-default-unsigned.hap'
$bundle = 'com.moonohos.search'
New-Item -ItemType Directory -Force $Evidence | Out-Null

function Device([string[]]$Arguments, [int]$Seconds = 45) {
  $out = [IO.Path]::GetTempFileName(); $err = [IO.Path]::GetTempFileName()
  $process = Start-Process -FilePath $hdc -ArgumentList (@('-t', $Target) + $Arguments) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
  if (-not $process.WaitForExit($Seconds * 1000)) { $process.Kill(); throw "hdc timed out: $Arguments" }
  $text = (Get-Content $out -Raw -Encoding UTF8) + (Get-Content $err -Raw)
  Remove-Item $out, $err
  if ($text -match '\[Fail\]|Device not found') { throw "hdc failed: $text" }
  $text
}

if (-not (Test-Path $hap)) { throw "HAP missing; run scripts\build_search.ps1 first: $hap" }
Device @('install', '-r', $hap) 120 | Out-Null
$required = @(
  'MOONSEARCH_SCENARIO_BEGIN',
  'MOONSEARCH_INDEX_END documents=12',
  'MOONSEARCH_SMALL round=1 documents=12',
  'MOONSEARCH_SYNC_QUERY hits=',
  'MOONSEARCH_INDEX_CANCELLED',
  'MOONSEARCH_CANCELLED round=1 error=AbortError',
  'MOONSEARCH_LARGE round=1',
  'MOONSEARCH_LARGE_QUERY hits=10',
  'MOONSEARCH_PAGE_CLOSED round=1',
  'MOONSEARCH_EXIT_CANCELLED round=1 error=AbortError',
  'MOONSEARCH_RETURNED round=1',
  'MOONSEARCH_SMALL round=2',
  'MOONSEARCH_PAGE_CLOSED round=2',
  'MOONSEARCH_RETURNED round=2',
  'MOONSEARCH_PASS live_handles=0'
)
$results = @()
for ($run = 1; $run -le $Runs; $run++) {
  Device @('shell', 'aa', 'force-stop', $bundle) | Out-Null
  Device @('shell', 'hilog', '-r') | Out-Null
  Device @('shell', 'aa', 'start', '-a', 'EntryAbility', '-b', $bundle, '--ps', 'scenario', 'auto') | Out-Null
  $log = ''; $shot = $false
  for ($i = 0; $i -lt 120; $i++) {
    Start-Sleep -Seconds 1
    $log = (Device @('shell', 'hilog', '-x')) -split "`n" | Where-Object { $_ -match 'MoonSearch' }
    $joined = $log -join "`n"
    if ($run -eq 1 -and -not $shot -and $joined -match 'MOONSEARCH_LARGE_QUERY') {
      Device @('shell', 'snapshot_display', '-f', '/data/local/tmp/moonsearch.jpeg') | Out-Null
      Device @('file', 'recv', '/data/local/tmp/moonsearch.jpeg', (Join-Path $Evidence 'search-page.jpeg')) | Out-Null
      $shot = $true
    }
    if ($joined -match 'MOONSEARCH_PASS|MOONSEARCH_FAIL') { break }
  }
  $joined = $log -join "`n"
  Set-Content -Path (Join-Path $Evidence "device-run-$run.log") -Value $joined -Encoding UTF8
  $position = 0; $missing = @()
  foreach ($marker in $required) {
    $index = $joined.IndexOf($marker, $position)
    if ($index -lt 0) { $missing += $marker } else { $position = $index }
  }
  $results += [ordered]@{ run = $run; missing = $missing; pass = ($missing.Count -eq 0) }
  if ($missing.Count -gt 0) { Write-Host $joined; throw "run $run missing markers: $($missing -join ', ')" }
}
[ordered]@{
  target = $Target
  bundle = $bundle
  hapSha256 = (Get-FileHash $hap -Algorithm SHA256).Hash
  runs = $results
} | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $Evidence 'device-summary.json') -Encoding UTF8
"SEARCH_DEVICE_PASS runs=$Runs"
