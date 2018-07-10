
Import-Module -Name 'Pester' , 'psake' , 'PSScriptAnalyzer'

function Invoke-TestFailure
{
    param
    (
        [Parameter(Mandatory)]
        [ValidateSet('Unit', 'Integration', 'Acceptance')]
        [string]$TestType,

        [Parameter(Mandatory)]
        $PesterResults
    )

    if ($TestType -eq 'Unit') 
    {
        $errorID = 'UnitTestFailure'
    }
    elseif ($TestType -eq 'Integration')
    {
        $errorID = 'InetegrationTestFailure'
    }
    else
    {
        $errorID = 'AcceptanceTestFailure'
    }

    $errorCategory = [System.Management.Automation.ErrorCategory]::LimitsExceeded
    $errorMessage = "$TestType Test Failed: $($PesterResults.FailedCount) tests failed out of $($PesterResults.TotalCount) total test."
    $exception = New-Object -TypeName System.SystemException -ArgumentList $errorMessage
    $errorRecord = New-Object -TypeName System.Management.Automation.ErrorRecord -ArgumentList $exception, $errorID, $errorCategory, $null

    Write-Output "##vso[task.logissue type=error]Exception: $errorMessage"
    throw $errorRecord    
}

function Import-PsClass
{
    $path = "$PSScriptRoot\$env:BUILD_REPOSITORY_NAME\Classes"
    if (Test-Path -Path $path)
    {
        $classes = Get-ChildItem -Path $path -Filter '*.ps1' 
        if ($classes)
        {
            "Classes are a pain, so we must dot source them first..."
            foreach ($class in $classes)
            {
                "Dot sourcing $($class.FullName)"
                . $($class.FullName)
            }
        }
    }    
}

FormatTaskName "--------------- {0} ---------------"

Properties {
    # psake makes variables declared here available in other scriptblocks    
    $testsPath = "$PSScriptRoot\Tests"
    $testResultsPath = "$TestsPath\Results"        
}

Task Default -Depends ScriptAnalysis, UnitTests, Build, Clean

Task Init {
    "Build System Details:"
    $env:BUILD_REPOSITORY_NAME    
    "`n"
}

Task ScriptAnalysis -Depends Init {        
    . Import-PsClass

    "Starting script analysis..."
    Invoke-ScriptAnalyzer -Path "$PSScriptRoot\$env:BUILD_REPOSITORY_NAME\*\*.ps1"
}

Task UnitTests -Depends ScriptAnalysis {        
    # Make sure Test Result location exists
    New-Item $testResultsPath -ItemType Directory -Force

    . Import-PsClass

    "Starting unit tests..."
    $pesterResults = Invoke-Pester -Path "$testsPath" -OutputFile "$testResultsPath\UnitTest.xml" -OutputFormat NUnitXml -PassThru
    
    if ($pesterResults.FailedCount)
    {
        Invoke-TestFailure -TestType Unit -PesterResults $pesterResults        
    }
}

Task Build -Depends UnitTests {
    "Starting update of module manifest..."
    "BuildID: $env:BUILD_BUILDID"
    "BuildNumber: $env:BUILD_BUILDNUMBER"

    # Get public functions to export
    $functions = Get-ChildItem "$PSScriptRoot\$env:BUILD_REPOSITORY_NAME\Public\*.ps1" | Select-Object -ExpandProperty BaseName
    
    # Update the manifest file
    $splatUpdateModuleManifest = @{
        Path              = "$PSScriptRoot\$env:BUILD_REPOSITORY_NAME\*.psd1"
        ModuleVersion     = $env:BUILD_BUILDNUMBER
        FunctionsToExport = $functions
    }
    Update-ModuleManifest @splatUpdateModuleManifest
}

Task Clean {
    "Starting cleaning environment..."        
    
    # Remove Test Results from previous runs    
    Remove-Item "$TestResultsPath\*.xml"
}