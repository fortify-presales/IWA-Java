#
# Example script to perform Fortify Static Code Analysis
#

# Parameters
param (
    [Parameter(Mandatory=$false)]
    [ValidateSet('classic','security','devops')]
    [string]$ScanPolicy = "classic",
    [Parameter(Mandatory=$false)]
    [switch]$SkipPDF,
    [Parameter(Mandatory=$false)]
    [switch]$SkipSSC
)

# Import some supporting functions
Import-Module $PSScriptRoot\modules\FortifyFunctions.psm1

# Import local environment specific settings
$EnvSettings = $(ConvertFrom-StringData -StringData (Get-Content ".\.env" | Where-Object {-not ($_.StartsWith('#'))} | Out-String))
$AppName = $EnvSettings['SSC_APP_NAME']
$AppVersion = $EnvSettings['SSC_APP_VER_NAME']
$SSCUrl = $EnvSettings['SSC_URL']
$SSCAuthToken = $EnvSettings['SSC_AUTH_TOKEN'] # CIToken
$JVMArgs = "-Xss256M"
#$ScanSwitches = "-Dcom.fortify.sca.rules.enable_wi_correlation=true"
$ScanSwitches = "-Dcom.fortify.sca.ProjectRoot=.fortify"

# Test we have Fortify installed successfully
Test-Environment
if ([string]::IsNullOrEmpty($AppName)) { throw "Application Name has not been set" }

# Run the translation and scan

Write-Host Running translation...
& sourceanalyzer $JVMArgs $ScanSwitches -b "$AppName" `
    -gradle -verbose ./gradlew clean build

Write-Host Running scan...
# this example uses Scan Policy, Custom Rules and Filters
& sourceanalyzer '-Dcom.fortify.sca.ProjectRoot=.fortify' $JVMArgs $ScanSwitches -b "$AppName" `
    -verbose -scan-policy $ScanPolicy `
    -rules etc/sast-custom-rules/example-custom-rules.xml -filter etc/sast-filters/example-filter.txt `
    -build-project "$AppName" -build-version "$AppVersion" -build-label "SNAPSHOT" `
    -scan -f "$($AppName).fpr"

# summarise issue count by analyzer
& FPRUtility -information -analyzerIssueCounts -project "$($AppName).fpr"

if (-not $SkipPDF) {
    Write-Host Generating PDF report...
    & ReportGenerator '-Dcom.fortify.sca.ProjectRoot=.fortify' -user "Demo User" -format pdf -f "$($AppName).pdf" -source "$($AppName).fpr"
}

if (-not $SkipSSC) {
    Write-Host Uploading results to SSC...
    & fortifyclient uploadFPR -file "$($AppName).fpr" -url $SSCUrl -authtoken $SSCAuthToken -application $AppName -applicationVersion $AppVersion
}

Write-Host Done.
