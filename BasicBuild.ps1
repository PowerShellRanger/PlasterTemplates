
[cmdletbinding()]
param
(
    [parameter()]    
    [string]$Task = 'Default'
)

$modules = 'Pester' , 'psake' , 'PSScriptAnalyzer'

Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

foreach ($module in $modules) 
{
    if (-not (Get-Module -Name $module -ListAvailable)) 
    { 
        Install-Module -Name $module -Scope CurrentUser -Confirm:$false
        Import-module -Name $module
    }
}

Invoke-PSake -buildFile "$PSScriptRoot\psake.ps1" -taskList $Task -Verbose:$VerbosePreference

if (-not $psake.build_success)
{
    throw "Build failed"
}

