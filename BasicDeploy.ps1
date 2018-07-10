
[cmdletbinding()]
param
(
    # OnDemand ComponentID
    [Parameter(Mandatory)]    
    [string]$ComponentId,

    # OnDemand EnvironmentID
    [Parameter(Mandatory)]    
    [string[]]$EnvironmentId,

    # OnDemand EnvironmentID
    [Parameter()]    
    [string]$EnvironmentId2,

    # Password from TFS Build Variable
    [Parameter(Mandatory)]    
    [string]$Password
)

$url = 'https://ondemand.tfservices.com/api'
$secpasswd = ConvertTo-SecureString $Password -AsPlainText -Force
$creds = New-Object System.Management.Automation.PSCredential ("think.local\s_IIS_OND", $secpasswd)
$dateTime = Get-Date -f G

$component = Invoke-RestMethod -Credential $creds -Method GET -Uri "$url/Components/$ComponentId"

#TFS Copy
$buildPath = $component.BuildPath
$sourceDir = "$Env:BUILD_SOURCESDIRECTORY$buildPath"
$version = $Env:BUILD_BUILDNUMBER
$destinationPath = "\\think.local\DSC\Code\$($component.Name)\$version\Content$($component.BuildPath)"
Write-Verbose "Source Directory: $sourceDir"
Write-Verbose "Version: $version"
Write-Verbose "Destination Path: $destinationPath"

Write-Verbose "Copy-Item: $sourceDir --- $destinationPath"
Copy-Item -Path $sourceDir -Destination $destinationPath -Recurse -Confirm:$false -Force

$build = [PSCustomObject] @{
    ComponentId = $ComponentId
    Version     = $version
}

Write-Verbose "Posting build version: $version to OnDemand for $($component.Name)"
$buildPost = Invoke-RestMethod -Credential $creds -Method Post -Uri "$url/Builds" -Body ($build | ConvertTo-Json) -ContentType 'application/json'

$deploymentStep = [PSCustomObject] @{
    "`$type"      = "OnDemand.Core.Entities.Deployments.ComponentDeploymentStep, OnDemand.Core"
    ComponentId   = $ComponentId
    ComponentName = $component.Name
    BuildId       = $buildPost.Id
    Version       = $version
    DeployOrder   = 0
    Status        = 'PENDING'
}

if ($EnvironmentId2) {$EnvironmentId += $EnvironmentId2}

foreach ($environment in $EnvironmentId)
{
    $deployment = [PSCustomObject] @{
        ServerEnvironmentId = $environment
        DeploymentMethod    = 'AllNodes'
        DeploymentDate      = $dateTime
        DeploymentSteps     = @($deploymentStep)
        IsRejected          = 'false'
    }

    $environmentInfo = Invoke-RestMethod -Credential $creds -Method GET -Uri "$url/Environments/$environment"
    
    Write-Verbose "Kicking off deployment for: $($component.Name) to Environment: $($environmentInfo.Name)"
    
    Invoke-RestMethod -Credential $creds -Method Post -Uri "$url/Deployments" -Body ($deployment | ConvertTo-Json) -ContentType 'application/json'        
}

