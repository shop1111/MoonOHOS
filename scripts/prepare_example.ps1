param([string]$Package = "$PSScriptRoot\..\_build\moonohos\dist")
$ErrorActionPreference = 'Stop'
$taskPackage = (Resolve-Path -LiteralPath $Package).Path
$taskExample = [IO.Path]::GetFullPath("$PSScriptRoot\..\examples\harmony\entry")
$taskManifest = Get-Content -Raw -Encoding UTF8 -LiteralPath "$taskPackage\manifest.json" | ConvertFrom-Json
if ($taskManifest.module -ne 'moonohos') { throw 'The example requires nativeModule=moonohos' }
foreach ($taskAbi in @('arm64-v8a','x86_64')) {
    $taskDest = "$taskExample\libs\$taskAbi"
    New-Item -ItemType Directory -Path $taskDest -Force | Out-Null
    Copy-Item -LiteralPath "$taskPackage\libs\$taskAbi\libmoonohos.so" -Destination $taskDest -Force
}
$taskTypes = "$taskExample\src\main\cpp\types\libmoonohos"
New-Item -ItemType Directory -Path $taskTypes -Force | Out-Null
Copy-Item -LiteralPath "$taskPackage\types\libmoonohos\index.d.ts" -Destination $taskTypes -Force
Copy-Item -LiteralPath "$taskPackage\types\libmoonohos\oh-package.json5" -Destination $taskTypes -Force
Write-Output "Prepared $taskExample"
