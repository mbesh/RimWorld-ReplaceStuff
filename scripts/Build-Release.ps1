[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$RimWorldDir = $env:RimWorldDir,
    [switch]$RemoveDevBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RimWorldDir)) {
    $RimWorldDir = [Environment]::GetEnvironmentVariable('RimWorldDir', 'User')
}
if ([string]::IsNullOrWhiteSpace($RimWorldDir)) {
    throw 'Set RimWorldDir or pass -RimWorldDir <game installation directory>.'
}
$gameRoot = (Resolve-Path -LiteralPath $RimWorldDir).ProviderPath
if (-not ((Test-Path -LiteralPath (Join-Path $gameRoot 'RimWorld.exe') -PathType Leaf) -or
          (Test-Path -LiteralPath (Join-Path $gameRoot 'RimWorldWin64.exe') -PathType Leaf))) {
    throw "No RimWorld executable found in '$gameRoot'."
}
if (Get-Process -Name RimWorld, RimWorldWin64 -ErrorAction SilentlyContinue) {
    throw 'Close RimWorld before building and installing the release.'
}

$sourceRoot = Split-Path -Parent $PSScriptRoot
$packageRoot = Join-Path (Split-Path -Parent $sourceRoot) 'Replace Stuff - Release'
$modsRoot = Join-Path $gameRoot 'Mods'
$destination = Join-Path $modsRoot 'ReplaceStuff-Release'
$devDirectory = Join-Path $modsRoot 'ReplaceStuff-Dev'
[xml]$releaseMetadata = Get-Content -LiteralPath (Join-Path $sourceRoot 'About\About-Release.xml') -Raw
if (Test-Path -LiteralPath $destination) {
    [xml]$existing = Get-Content -LiteralPath (Join-Path $destination 'About\About.xml') -Raw
    if ($existing.ModMetaData.packageId -ne $releaseMetadata.ModMetaData.packageId) {
        throw "Refusing to overwrite a different mod in '$destination'."
    }
}

function Assert-DevDirectory {
    # Check the resolved absolute path and identity before any recursive removal.
    $resolvedMods = (Resolve-Path -LiteralPath $modsRoot).ProviderPath.TrimEnd('\')
    $resolvedDev = (Resolve-Path -LiteralPath $devDirectory).ProviderPath.TrimEnd('\')
    if ($resolvedDev -ne (Join-Path $resolvedMods 'ReplaceStuff-Dev')) {
        throw "Unexpected development mod path: '$resolvedDev'."
    }
    $entries = @((Get-Item -LiteralPath $resolvedDev)) + @(Get-ChildItem -LiteralPath $resolvedDev -Recurse -Force)
    if ($entries | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) {
        throw 'Refusing to recursively remove a development mod containing links or junctions.'
    }
    [xml]$devMetadata = Get-Content -LiteralPath (Join-Path $resolvedDev 'About\About.xml') -Raw
    if ($devMetadata.ModMetaData.packageId -ne 'DEBUuugggg.ReplaceStuff') {
        throw 'Refusing to remove a directory that is not the Replace Stuff development build.'
    }
}

if ($RemoveDevBuild -and (Test-Path -LiteralPath $devDirectory)) {
    Assert-DevDirectory
}

$msbuild = Get-Command msbuild -ErrorAction SilentlyContinue
if ($msbuild) {
    $msbuildPath = $msbuild.Source
} else {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) {
        throw 'MSBuild was not found. Install Visual Studio .NET desktop build tools.'
    }
    $msbuildPath = & $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' |
        Select-Object -First 1
    if (-not $msbuildPath) { throw 'No Visual Studio installation with MSBuild was found.' }
}

if (-not $PSCmdlet.ShouldProcess($destination, 'Build Release, install and verify runtime files')) { return }
& $msbuildPath (Join-Path $sourceRoot 'Replace Stuff.sln') /restore /p:Configuration=Release "/p:RimWorldDir=$gameRoot" /verbosity:minimal /nologo
if ($LASTEXITCODE -ne 0) { throw "Release build failed with exit code $LASTEXITCODE." }

# Select runtime assets from the repository, avoiding stale files in the build folder.
$relativePaths = @(
    'About\About.xml'
    'Assemblies\Replace_Stuff.dll'
    'LoadFolders.xml'
    foreach ($folder in @('About', 'Defs', 'Patches', 'Languages', 'Textures', 'Sounds', 'News')) {
        $folderPath = Join-Path $sourceRoot $folder
        if (Test-Path -LiteralPath $folderPath -PathType Container) {
            Get-ChildItem -LiteralPath $folderPath -File -Recurse | ForEach-Object {
                $relative = $_.FullName.Substring($sourceRoot.Length).TrimStart('\')
                if ($relative -notin @('About\About.xml', 'About\About-Release.xml', 'About\PublishedFileId.txt')) {
                    $relative
                }
            }
        }
    }
)
foreach ($relative in $relativePaths) {
    if (-not (Test-Path -LiteralPath (Join-Path $packageRoot $relative) -PathType Leaf)) {
        throw "Release package is missing '$relative'."
    }
}
foreach ($relative in $relativePaths) {
    $source = Join-Path $packageRoot $relative
    $target = Join-Path $destination $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $target -Force
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash) {
        throw "Release copy verification failed for '$relative'."
    }
}
[xml]$installed = Get-Content -LiteralPath (Join-Path $destination 'About\About.xml') -Raw
if ($installed.ModMetaData.packageId -ne $releaseMetadata.ModMetaData.packageId) {
    throw 'Installed package ID does not match the release metadata.'
}
Write-Output "Installed and SHA256-verified $($relativePaths.Count) release files in $destination"

# Preserve an existing release About/PublishedFileId.txt so future uploads update it.
if ($RemoveDevBuild -and (Test-Path -LiteralPath $devDirectory) -and
    $PSCmdlet.ShouldProcess($devDirectory, 'Remove the verified development mod')) {
    Assert-DevDirectory
    Remove-Item -LiteralPath $devDirectory -Recurse -Force
    Write-Output "Removed development mod: $devDirectory"
}
Write-Output "Package ID: $($installed.ModMetaData.packageId). Enable the release after Harmony in RimWorld."
