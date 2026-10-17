# RimWorld-ReplaceStuff
RimWorld mod - replace the stuff a thing is made from.

## Building

Use MSBuild from Visual Studio Build Tools with the .NET desktop build tools and
the .NET Framework 4.7.2 SDK and targeting pack installed. VS Code can be used as
the editor.

From Developer PowerShell, run these commands in the repository root, replacing
the example path with your RimWorld installation directory:

```powershell
msbuild "Replace Stuff.sln" /restore /p:Configuration=Debug "/p:RimWorldDir=D:\SteamLibrary\steamapps\common\RimWorld"
```

`RimWorldDir` is the game installation directory. For RimWorld 1.7, references are
resolved directly from this directory using `UnityStubs.dll` and
`Waylith.UnityCompat.dll`. Older installations use `RimWorldWin64_Data\Managed`
and the UnityEngine module DLLs. The layout is detected automatically.
For a different assembly layout, pass the
DLL directory directly using `"/p:RimWorldManagedDir=D:\path\to\Managed"`.
Both properties also accept environment variables; command-line values take
precedence. Use absolute paths for either property.

For Visual Studio builds, set `RimWorldDir` as a Windows user environment variable
(for example, `C:\Steam\steamapps\common\RimWorld`), restart Visual Studio, open
`Replace Stuff.sln`, restore NuGet packages, and choose Build > Build Solution.
`RimWorldManagedDir` is optional when the installation uses either layout above.

If neither property is set, the original layout is preserved: the repository is
expected at `<RimWorldDir>\Mods\<repository>`. The debugger launch path also uses
`RimWorldDir`.

Debug builds write the mod DLL to `Assemblies` in the repository. To build the
release package, run:

```powershell
msbuild "Replace Stuff.sln" /restore /p:Configuration=Release "/p:RimWorldDir=D:\SteamLibrary\steamapps\common\RimWorld"
```

Release builds write the DLL and mod assets to the sibling `Replace Stuff - Release`
directory. Build the whole solution to include the assets and release metadata.

## Installing the development build locally

After a Debug build, close RimWorld and run this from the repository root:

```powershell
.\scripts\Deploy-Mod.ps1
```

The script uses the `RimWorldDir` environment variable (including the Windows user
variable if the current shell has not picked it up yet). You can override it:

```powershell
.\scripts\Deploy-Mod.ps1 -RimWorldDir 'C:\Steam\steamapps\common\RimWorld'
```

It copies runtime content and the compiled mod to `<RimWorldDir>\Mods\ReplaceStuff-Dev`,
then verifies every copied file using SHA256. It omits source, build intermediates,
game DLLs, and release-only metadata. Existing files are updated; unrelated or
obsolete files are not deleted. Use `-WhatIf` to preview the destination.
In RimWorld, enable **Replace Stuff - Dev Build** after **Harmony** and disable
other copies of Replace Stuff. Restart the game after deploying an updated DLL.
