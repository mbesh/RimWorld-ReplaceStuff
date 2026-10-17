[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$RimWorldDir = $env:RimWorldDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# A recently configured user variable may not yet be in the current shell.
if ([string]::IsNullOrWhiteSpace($RimWorldDir)) {
    $RimWorldDir = [Environment]::GetEnvironmentVariable('RimWorldDir', 'User')
}
if ([string]::IsNullOrWhiteSpace($RimWorldDir)) {
    throw 'Set the RimWorldDir environment variable or pass -RimWorldDir <game installation directory>.'
}

$gameRoot = (Resolve-Path -LiteralPath $RimWorldDir).ProviderPath
if (-not ((Test-Path -LiteralPath (Join-Path $gameRoot 'RimWorld.exe') -PathType Leaf) -or
          (Test-Path -LiteralPath (Join-Path $gameRoot 'RimWorldWin64.exe') -PathType Leaf))) {
    throw "No RimWorld executable found in '$gameRoot'."
}

$sourceRoot = Split-Path -Parent $PSScriptRoot
$destination = Join-Path $gameRoot 'Mods\ReplaceStuff-Dev'
if ([IO.Path]::GetFullPath($destination).TrimEnd('\') -eq $sourceRoot.TrimEnd('\')) {
    throw 'The source and deployment directories must be different.'
}

$assembly = Join-Path $sourceRoot 'Assemblies\Replace_Stuff.dll'
if (-not (Test-Path -LiteralPath $assembly -PathType Leaf)) {
    throw 'Build the Debug configuration first; Assemblies\Replace_Stuff.dll is missing.'
}

$sourceMetadata = Join-Path $sourceRoot 'About\About.xml'
[xml]$metadata = Get-Content -LiteralPath $sourceMetadata -Raw
$installedMetadata = Join-Path $destination 'About\About.xml'
if (Test-Path -LiteralPath $installedMetadata -PathType Leaf) {
    [xml]$existing = Get-Content -LiteralPath $installedMetadata -Raw
    if ($existing.ModMetaData.packageId -ne $metadata.ModMetaData.packageId) {
        throw "Refusing to overwrite a different mod in '$destination'."
    }
}

# Copy only runtime content, never source, build intermediates, or game DLLs.
$files = @(
    foreach ($folder in @('About', 'Defs', 'Patches', 'Languages', 'Textures', 'Sounds', 'News')) {
        $folderPath = Join-Path $sourceRoot $folder
        if (Test-Path -LiteralPath $folderPath -PathType Container) {
            Get-ChildItem -LiteralPath $folderPath -File -Recurse |
                Where-Object { $_.FullName -ne (Join-Path $sourceRoot 'About\About-Release.xml') }
        }
    }
    Get-Item -LiteralPath $assembly
    $symbols = Join-Path $sourceRoot 'Assemblies\Replace_Stuff.pdb'
    if (Test-Path -LiteralPath $symbols -PathType Leaf) {
        Get-Item -LiteralPath $symbols
    }
    Get-Item -LiteralPath (Join-Path $sourceRoot 'LoadFolders.xml')
)

if (-not $PSCmdlet.ShouldProcess($destination, "Copy and verify $($files.Count) development mod files")) {
    return
}

foreach ($file in $files) {
    $relativePath = $file.FullName.Substring($sourceRoot.Length).TrimStart('\')
    $target = Join-Path $destination $relativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $target -Force
    if ((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash) {
        throw "Copy verification failed for '$relativePath'."
    }
}

Write-Output "Deployed and SHA256-verified $($files.Count) files to $destination"
Write-Output "Enable '$($metadata.ModMetaData.name)' after Harmony in RimWorld's Mods menu."
