param([Parameter(Mandatory)][string]$DevEco, [string]$Package = "$PSScriptRoot\..\_build\moonohos\dist")
$ErrorActionPreference = 'Stop'
$taskDevEco = (Resolve-Path -LiteralPath $DevEco).Path
$taskExample = [IO.Path]::GetFullPath("$PSScriptRoot\..\examples\harmony")
& "$PSScriptRoot\prepare_example.ps1" -Package $Package
$taskEnv = @{
    DEVECO_SDK_HOME = "$taskDevEco\sdk"
    NODE_HOME = "$taskDevEco\tools\node"
    OHPM_HOME = "$taskDevEco\tools\ohpm"
    JAVA_HOME = "$taskDevEco\jbr"
}
$taskPrevious = @{}
foreach ($taskKey in $taskEnv.Keys) {
    $taskPrevious[$taskKey] = [Environment]::GetEnvironmentVariable($taskKey, 'Process')
    [Environment]::SetEnvironmentVariable($taskKey, $taskEnv[$taskKey], 'Process')
}
Push-Location -LiteralPath $taskExample
try {
    & "$taskDevEco\tools\node\node.exe" "$taskDevEco\tools\ohpm\bin\pm-cli.js" install
    if ($LASTEXITCODE -ne 0) { throw 'ohpm install failed' }
    & "$taskDevEco\tools\node\node.exe" "$taskDevEco\tools\hvigor\bin\hvigorw.js" --mode module -p 'module=entry@default' -p 'product=default' -p 'buildMode=debug' --no-daemon assembleHap
    if ($LASTEXITCODE -ne 0) { throw 'Hvigor assembleHap failed' }
} finally {
    Pop-Location
    foreach ($taskKey in $taskPrevious.Keys) {
        [Environment]::SetEnvironmentVariable($taskKey, $taskPrevious[$taskKey], 'Process')
    }
}
