#
# Example script to perform Fortify WebInspect dynamic analysis
#

# Import some supporting functions
Import-Module $PSScriptRoot\modules\FortifyFunctions.psm1

# Import local environment specific settings
$EnvSettings = $(ConvertFrom-StringData -StringData (Get-Content ".\.env" | Where-Object {-not ($_.StartsWith('#'))} | Out-String))
$AppName = $EnvSettings['SSC_APP_NAME']
$AppVersion = $EnvSettings['SSC_APP_VER_NAME']
$AppUrl = $EnvSettings['APP_URL']
$SSCUrl = $EnvSettings['SSC_URL']
$SSCAuthToken = $EnvSettings['SSC_AUTH_TOKEN'] # CIToken
$ScanSwitches = "-Dcom.fortify.sca.Phase0HigherOrder.Languages=javascript,typescript -Dcom.fortify.sca.EnableDOMModeling=true -Dcom.fortify.sca.follow.imports=true -Dcom.fortify.sca.exclude.unimported.node.modules=true"

# Test we have Fortify installed successfully
Test-Environment
if ([string]::IsNullOrEmpty($AppName)) { throw "Application Name has not been set" }

# WebInspect policy to use - 1008 = Crtical and High only
$WIPolicyId = 1008
# WebInspect custom policy file to use
$WIPolicyPath = ".\etc\Critical-and-Highs-Custom.policy"

# example path for WebInspect
$env:Path += ";C:\Program Files\Fortify\Fortify WebInspect\"

# Check Maven is on the path
if ((Get-Command "WI.exe" -ErrorAction SilentlyContinue) -eq $null)
{
    Write-Error "Unable to find WI.exe in your PATH"
    Break
}

Write-Host Executing dynamic scan...
& wi -s ".\etc\IWA-UI-Dev-Settings.xml" -macro ".\etc\IWA-UI-Dev-Login.webmacro" -u $AppUrl `
    -ep ".\IWA-DAST.fpr" -pc $WIPolicyPath # -ps $WIPolicyId

Write-Host Generating PDF report...
& ReportGenerator '-Dcom.fortify.sca.ProjectRoot=.fortify' -user "Demo User" -format pdf -f "$($AppName).pdf" -source "$($AppName).fpr"

if (![string]::IsNullOrEmpty($SSCUrl)) {
    Write-Host Uploading results to SSC...
    & fortifyclient uploadFPR -file ".\IWA-DAST.fpr" -url $SSCUrl -authtoken $SSCAuthToken -application $AppName -applicationVersion $AppVersion
}

Write-Host Done.
