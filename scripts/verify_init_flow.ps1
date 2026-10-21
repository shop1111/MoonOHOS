param(
  [string]$DevEco = 'D:\apps\DevEco Studio',
  [string]$Evidence = (Join-Path (Split-Path -Parent $PSScriptRoot) '_build\init-flow-v0.4')
)
# Clean-room developer flow: moonohos init -> build (both ABIs) -> har --assemble.
# No CMake, type package or library copying is done by hand.
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $root '_build\native\release\build\cmd\moonohos\moonohos.exe'
if (-not (Test-Path $cli)) { throw 'Build the CLI first: moon build --target native --release cmd/moonohos' }
if (Test-Path $Evidence) { Remove-Item -Recurse -Force $Evidence }
New-Item -ItemType Directory -Force $Evidence | Out-Null
$project = Join-Path $Evidence 'textkit'
$steps = @()
function Step([string]$Name, [string[]]$Arguments) {
  $output = & $cli @Arguments 2>&1
  $output | Out-File -FilePath (Join-Path $Evidence "$Name.json") -Encoding utf8
  if ($LASTEXITCODE -ne 0) { $output | Write-Host; throw "$Name failed" }
  $script:steps += $Name
  ($output -join "`n") | ConvertFrom-Json
}
Step 'init' @('init', $project, '--package', 'alice/textkit', '--ohos', (Join-Path $root 'ohos'), '--json') | Out-Null
Push-Location (Join-Path $project 'core')
moon test --target native 2>&1 | Out-File -FilePath (Join-Path $Evidence 'moon-test.log') -Encoding utf8
$tested = $LASTEXITCODE
Pop-Location
if ($tested -ne 0) { throw 'generated library tests failed' }
Step 'build' @('build', '--config', (Join-Path $project 'moonohos.json'), '--sdk', "$DevEco\sdk", '--out', (Join-Path $project '_build\dist'), '--json') | Out-Null
$har = Step 'har' @('har', '--dist', (Join-Path $project '_build\dist'), '--module', (Join-Path $project 'harmony\textkit'), '--assemble', '--deveco', $DevEco, '--json')
$entries = @(tar -tzf $har.result.har | Where-Object { -not $_.EndsWith('/') })
foreach ($required in @('package/libs/arm64-v8a/libtextkit.so', 'package/libs/x86_64/libtextkit.so', 'package/src/main/cpp/types/libtextkit/index.d.ts', 'package/src/main/ets/generated/Native.ets', 'package/moonohos-har.json')) {
  if ($entries -notcontains $required) { throw "HAR misses $required" }
}
[ordered]@{
  steps = $steps
  har = $har.result.har
  sha256 = $har.result.sha256
  size = $har.result.size
  entries = $entries
} | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $Evidence 'summary.json') -Encoding utf8
"INIT_FLOW_PASS har=$($har.result.har)"
