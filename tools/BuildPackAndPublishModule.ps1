# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.
<#
.DESCRIPTION
Builds and packs generated module into nuget packages for distribution. The generated packages are moved to '{repo}\bin' by default for easy access.

.PARAMETER Module
The name of the module to build and pack.

.PARAMETER OutputFolder
The output folder to move the generated nuget packages to. This defaults to '{repo}\artifacts'.
#>
Param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $Module,
    [ValidateNotNullOrEmpty()]
    [string] $RepositoryFeedUrl,
    [ValidateNotNullOrEmpty()]
    [string] $RepositoryApiKey,
    [string] $RollUpModule,
    [string[]] $RequiredModules,
    [string] $OutputFolder
)
$ErrorActionPreference = "Stop"
if($PSEdition -ne "Core") {
  Write-Error "This script requires PowerShell Core to execute. [Note] Generated cmdlets will work in both PowerShell Core or Windows PowerShell."
}

$ModuleProjDir = "./src/$Module/$Module"
$BuildModulePS1 = Join-Path $ModuleProjDir "/build-module.ps1"
$PackModulePS1 = Join-Path $ModuleProjDir "/pack-module.ps1"

if([string]::IsNullOrEmpty($OutputFolder)) {
    $OutputFolder = "./artifacts/"
}

if (-not (Test-Path -Path $BuildModulePS1)){
    Write-Error "Build script file '$BuildModulePS1' not found for $Module module."
    return
}

# Build module
Write-Host -ForegroundColor Green "Building '$Module' module..."
& $BuildModulePS1 -Test -Docs -Release
if($LastExitCode -ne 0) {
    # Build failed, don't pack the module.
    Write-Error "Failed to build '$Module' module."
}

if($RequiredModules.Count -gt 0) {
    # Add required modules.
    try{
        Write-Host -ForegroundColor Green "Updating '$Module' module manifest..."
        Update-ModuleManifest -Path (Join-Path $ModuleProjDir "$RollUpModule.$Module.psd1") -FunctionsToExport "*" -RequiredModules $RequiredModules
    } catch {
        Write-Error $_.Exception
    }
}

# Pack module
Write-Host -ForegroundColor Green "Packaging '$Module' module..."
& $PackModulePS1
if($LastExitCode -ne 0) {
    # Pack failed, don't attempt to move nuget package.
    Write-Error "Failed to pack $Module."
    return
}

# Get generated .nupkg
$NugetPackage = (Get-ChildItem (Join-Path $ModuleProjDir "./bin") | Where-Object Name -Match ".nupkg").FullName

if(-not (Test-Path $OutputFolder)) {
    # Create artifacts folder.
    New-Item -Path $OutputFolder -Type Directory
}

# Copy package to feed.
Write-Host -ForegroundColor Green "Publishing '$Module' module to feed..."
nuget push $NugetPackage -Source $RepositoryFeedUrl -apikey $RepositoryApiKey
if($LastExitCode -ne 0) {
    # nuget push failed. Check package version number.
    # Write-Error "Failed to push '$Module' package. A module name with the same version number already exists."
}

# Copy package to artifacts folder.
Write-Host -ForegroundColor Green "Copying '$Module' module to $OutputFolder..."
Copy-Item -Path $NugetPackage -Destination $OutputFolder -Force
Write-Host -ForegroundColor Green "-------------Done-------------"