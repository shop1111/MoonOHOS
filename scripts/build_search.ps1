param(
  [string]$DevEco = 'D:\apps\DevEco Studio',
  [int]$Docs = 2000,
  [switch]$AppOnly
)
# Builds the offline search example end to end with the MoonOHOS CLI:
# MoonBit -> dual-ABI native package -> HAR -> independent Stage application.
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $root '_build\native\release\build\cmd\moonohos\moonohos.exe'
if (-not (Test-Path $cli)) { throw 'Build the CLI first: moon build --target native --release cmd/moonohos' }
$evidence = Join-Path $root '_build\search-v0.4'
New-Item -ItemType Directory -Force $evidence | Out-Null

function Run([string]$Name, [scriptblock]$Block) {
  $output = & $Block 2>&1
  $output | Out-File -FilePath (Join-Path $evidence "$Name.log") -Encoding utf8
  if ($LASTEXITCODE -ne 0) { $output | Select-Object -Last 30 | Write-Host; throw "$Name failed" }
  $output
}

$dist = Join-Path $root 'examples\search\_build\dist'
if (-not $AppOnly) {
  if (Test-Path $dist) { Remove-Item -Recurse -Force $dist }
  Run 'cli-build' { & $cli build --config (Join-Path $root 'examples\search\moonohos.json') --sdk "$DevEco\sdk" --out $dist --json } | Out-Null
  Run 'cli-har' { & $cli har --dist $dist --module (Join-Path $root 'examples\search\harmony\search') --assemble --deveco $DevEco --json } | Out-Null
}
$harPath = Join-Path $root 'examples\search\harmony\search\build\default\outputs\default\search.har'

$app = Join-Path $root 'examples\search-app'
$raw = Join-Path $app 'entry\src\main\resources\rawfile'
New-Item -ItemType Directory -Force (Join-Path $raw 'docs') | Out-Null
Copy-Item -Force (Join-Path $root 'examples\search\core\testdata\docs\*.md') (Join-Path $raw 'docs')
$corpus = Run 'corpus' { python (Join-Path $root 'scripts\make_corpus.py') (Join-Path $raw 'docs_large') --docs $Docs }

$saved = @{}
foreach ($pair in @{ DEVECO_SDK_HOME = "$DevEco\sdk"; NODE_HOME = "$DevEco\tools\node"; OHPM_HOME = "$DevEco\tools\ohpm"; JAVA_HOME = "$DevEco\jbr" }.GetEnumerator()) {
  $saved[$pair.Key] = [Environment]::GetEnvironmentVariable($pair.Key, 'Process')
  [Environment]::SetEnvironmentVariable($pair.Key, $pair.Value, 'Process')
}
Push-Location $app
try {
  # The HAR is consumed by file dependency only; refresh the installed copy.
  foreach ($stale in @('oh_modules', 'entry\oh_modules', 'oh-package-lock.json5', 'entry\oh-package-lock.json5')) {
    if (Test-Path $stale) { Remove-Item -Recurse -Force $stale }
  }
  Run 'ohpm-install' { & "$DevEco\tools\node\node.exe" "$DevEco\tools\ohpm\bin\pm-cli.js" install } | Out-Null
  Run 'assemble-hap' { & "$DevEco\tools\node\node.exe" "$DevEco\tools\hvigor\bin\hvigorw.js" --mode module -p 'module=entry@default' -p 'product=default' -p 'buildMode=debug' --no-daemon assembleHap } | Out-Null
} finally {
  Pop-Location
  foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
}
$hap = Join-Path $app 'entry\build\default\outputs\default\entry-default-unsigned.hap'
$summary = [ordered]@{
  har = $harPath
  harSha256 = (Get-FileHash $harPath -Algorithm SHA256).Hash
  harEntries = @(tar -tzf $harPath)
  hap = $hap
  hapSha256 = (Get-FileHash $hap -Algorithm SHA256).Hash
  hapNative = @(tar -tf $hap | Where-Object { $_ -like 'libs/*' })
  corpus = ($corpus | Select-Object -Last 1).ToString()
}
$summary | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $evidence 'artifacts.json') -Encoding utf8
"SEARCH_BUILD_PASS hap=$hap"
