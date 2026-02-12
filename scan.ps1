<#
.SYNOPSIS
    OpenText SAST (Fortify Static Code Analyzer) local scan script

.DESCRIPTION
    This script performs an OpenText SAST scan with the following steps:
    1. Clean the build
    2. Translate/analyze the source code
    3. Perform the scan
    4. Summarize issues using FPRUtility
    5. Optionally upload FPR to Fortify Software Security Center
    The script supports reading additional options from a fortify.config file.
    This file can contain [translation], [scan] and [ssc] sections for respective options.

.PARAMETER BuildId
    The build ID for OpenText SAST (default: current directory name)

.PARAMETER ProjectRoot
    The project root directory for OpenText SAST (default: .fortify)

.PARAMETER UploadToSSC
    Upload the generated FPR file to Fortify Software Security Center

.PARAMETER SSCUrl
    Fortify Software Security Center URL (can also be set via SSC_URL environment variable or config file)

.PARAMETER SSCAuthToken
    SSC Authentication Token (can also be set via SSC_AUTH_TOKEN environment variable or config file)

.PARAMETER SSCAppName
    SSC Application Name (can also be set via SSC_APP_NAME environment variable or config file)

.PARAMETER SSCAppVersionName
    SSC Application Version Name (can also be set via SSC_APP_VERSION_NAME environment variable or config file)

.PARAMETER SSCUploadOnly
    Skip all scan steps and only upload existing FPR to SSC

.NOTES
    This script uses PowerShell common parameters -Verbose and -Debug. To enable verbose/debug output use the built-in switches (e.g. -Verbose -Debug).

.EXAMPLE
    .\scan.ps1

.EXAMPLE
    .\scan.ps1 -BuildId "my-build" -Verbose -Debug

.EXAMPLE
    .\scan.ps1 -UploadToSSC

.EXAMPLE
    .\scan.ps1 -UploadToSSC -SSCUrl "https://ssc.company.com/ssc" -SSCAuthToken "token123" -SSCAppName "MyApp" -SSCAppVersionName "1.0"

.EXAMPLE
    .\scan.ps1 -SSCUploadOnly
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$BuildId = "",
    
    [Parameter(Mandatory=$false)]
    [string]$ProjectRoot = ".fortify",
    
    [Parameter(Mandatory=$false)]
    [switch]$UploadToSSC,
    
    [Parameter(Mandatory=$false)]
    [string]$SSCUrl = "",
    
    [Parameter(Mandatory=$false)]
    [string]$SSCAuthToken = "",
    
    [Parameter(Mandatory=$false)]
    [string]$SSCAppName = "",
    
    [Parameter(Mandatory=$false)]
    [string]$SSCAppVersionName = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$SSCUploadOnly,

    [Parameter(Mandatory=$false)]
    [switch]$WhatIfConfig
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Set default BuildId to current directory name if not specified
if ([string]::IsNullOrEmpty($BuildId)) {
    $BuildId = Split-Path -Leaf (Get-Location)
    Write-Host "Using current directory name as BuildId: $BuildId" -ForegroundColor Cyan
}

# Function to execute sourceanalyzer command
function Invoke-SourceAnalyzer {
    param(
        [string]$Arguments
    )
    
    Write-Host "Executing: sourceanalyzer $Arguments" -ForegroundColor Cyan
    
    try {
        $process = Start-Process -FilePath "sourceanalyzer" `
                                  -ArgumentList $Arguments `
                                  -NoNewWindow `
                                  -Wait `
                                  -PassThru
        
        if ($process.ExitCode -ne 0) {
            Write-Error "sourceanalyzer failed with exit code: $($process.ExitCode)"
            exit $process.ExitCode
        }
    }
    catch {
        Write-Error "Failed to execute sourceanalyzer: $_"
        exit 1
    }
}

# Check if sourceanalyzer is available
Write-Host "Checking for sourceanalyzer..." -ForegroundColor Yellow
try {
    $null = Get-Command sourceanalyzer -ErrorAction Stop
    Write-Host "sourceanalyzer found." -ForegroundColor Green
}
catch {
    Write-Error "sourceanalyzer command not found. Please ensure OpenText SAST is installed and in your PATH."
    exit 1
}

# Build command arguments
$baseArgs = "`"-Dcom.fortify.sca.ProjectRoot=$ProjectRoot`" -b $BuildId"
# Use PowerShell built-in common parameters -Verbose and -Debug to control extra analyzer flags
$verboseArg = if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') { "-verbose" } else { "" }
$debugArg = if ($PSBoundParameters.ContainsKey('Debug') -or $DebugPreference -eq 'Continue') { "-debug" } else { "" }

# Read options from fortify.config if it exists
$optsFile = "fortify.config"
$transOptions = ""
$scanOptions = ""
$configSSCUrl = ""
$configSSCAuthToken = ""
$configAppName = ""
$configAppVersion = ""

if (Test-Path $optsFile) {
    Write-Host "Reading options from $optsFile..." -ForegroundColor Yellow
    $currentSection = ""
    $transOptionsList = @()
    $scanOptionsList = @()
    
    Get-Content $optsFile | ForEach-Object {
        $line = $_.Trim()
        
        # Skip empty lines and comments
        if ($line -eq "" -or $line.StartsWith("#")) {
            return
        }
        
        # Check for section headers
        if ($line -match '^\[(.+)\]$') {
            $currentSection = $matches[1].ToLower()
            return
        }
        
        # Process option based on current section
        if ($currentSection -eq "translation") {
            # Quote -D options
            if ($line.StartsWith("-D")) {
                $transOptionsList += "`"$line`""
            } else {
                $transOptionsList += $line
            }
        }
        elseif ($currentSection -eq "scan") {
            # Quote -D options
            if ($line.StartsWith("-D")) {
                $scanOptionsList += "`"$line`""
            } else {
                $scanOptionsList += $line
            }
        }
        elseif ($currentSection -eq "ssc") {
            # Parse SSC configuration options
            if ($line -match '^SSCUrl\s*=\s*(.+)$') {
                $configSSCUrl = $matches[1].Trim('"')
            }
            elseif ($line -match '^SSCAuthToken\s*=\s*(.+)$') {
                $configSSCAuthToken = $matches[1].Trim('"')
            }
            elseif ($line -match '^AppName\s*=\s*(.+)$') {
                $configAppName = $matches[1].Trim('"')
            }
            elseif ($line -match '^AppVersion\s*=\s*(.+)$') {
                $configAppVersion = $matches[1].Trim('"')
            }
        }
    }
    
    $transOptions = $transOptionsList -join " "
    $scanOptions = $scanOptionsList -join " "
    
    if ($transOptions) {
        Write-Host "Translation options: $transOptions" -ForegroundColor Cyan
    }
    if ($scanOptions) {
        Write-Host "Scan options: $scanOptions" -ForegroundColor Cyan
    }
} else {
    Write-Host "No options file found ($optsFile)" -ForegroundColor Gray
}

# Add a helper to resolve configuration values with precedence: Parameters > Environment Variables > Config file
function Resolve-ConfigValue {
    param(
        [string]$Name,
        [string]$ParamValue,
        [string[]]$EnvNames,
        [string]$ConfigValue
    )

    # 1) Parameter (highest precedence)
    if (-not [string]::IsNullOrEmpty($ParamValue)) {
        return @{ Value = $ParamValue; Source = 'parameter' }
    }

    # 2) Environment variables (check in order)
    foreach ($envName in $EnvNames) {
        if ($envName) {
            $v = (Get-Item -Path "Env:\$envName" -ErrorAction SilentlyContinue).Value
            if (-not [string]::IsNullOrEmpty($v)) {
                return @{ Value = $v; Source = "env:$envName" }
            }
        }
    }

    # 3) Config file
    if (-not [string]::IsNullOrEmpty($ConfigValue)) {
        return @{ Value = $ConfigValue; Source = 'config' }
    }

    return @{ Value = $null; Source = '<unset>' }
}

# Use Resolve-ConfigValue for SSC settings
$resolvedSources = @{}
$resolvedValues = @{}

$rc = Resolve-ConfigValue -Name 'SSCUrl' -ParamValue $SSCUrl -EnvNames @('SSC_URL') -ConfigValue $configSSCUrl
$SSCUrl = $rc.Value
$resolvedSources['SSCUrl'] = $rc.Source
$resolvedValues['SSCUrl'] = $rc.Value

$rc = Resolve-ConfigValue -Name 'SSCAuthToken' -ParamValue $SSCAuthToken -EnvNames @('SSC_AUTH_TOKEN') -ConfigValue $configSSCAuthToken
$SSCAuthToken = $rc.Value
$resolvedSources['SSCAuthToken'] = $rc.Source
$resolvedValues['SSCAuthToken'] = $rc.Value

$rc = Resolve-ConfigValue -Name 'SSCAppName' -ParamValue $SSCAppName -EnvNames @('SSC_APP_NAME') -ConfigValue $configAppName
$AppName = $rc.Value
$resolvedSources['SSCAppName'] = $rc.Source
$resolvedValues['SSCAppName'] = $rc.Value

$rc = Resolve-ConfigValue -Name 'SSCAppVersion' -ParamValue $SSCAppVersionName -EnvNames @('SSC_APP_VERSION_NAME') -ConfigValue $configAppVersion
$AppVersion = $rc.Value
$resolvedSources['SSCAppVersion'] = $rc.Source
$resolvedValues['SSCAppVersion'] = $rc.Value

# Centralized list of environment variable candidates checked for each logical key (used by the WhatIf preview)
$envCandidates = @{
    'SSCUrl'            = @('SSC_URL')
    'SSCAuthToken'      = @('SSC_AUTH_TOKEN')
    'SSCAppName'        = @('SSC_APP_NAME')
    'SSCAppVersion'     = @('SSC_APP_VERSION_NAME')
}

# Helper to print environment variable checks (present/absent) for a given key
function Print-EnvChecks {
    param(
        [string]$Key,
        [string[]]$Candidates
    )
    foreach ($envName in $Candidates) {
        if (-not $envName) { continue }
        $e = Get-Item -Path "Env:\$envName" -ErrorAction SilentlyContinue
        if ($e -and $e.Value -ne '') {
            if ($PSBoundParameters.ContainsKey('Debug')) { $valShown = $e.Value } else { $valShown = '****(masked)' }
            Write-Host ('    {0,-35} -> {1, -20} (present)' -f $envName, $valShown) -ForegroundColor DarkGreen
        } else {
            Write-Host ('    {0,-35} -> {1, -20} (absent)' -f $envName, '<not set>') -ForegroundColor DarkGray
        }
    }
}

# If user requested a WhatIf preview, print a table of resolved values and exit
if ($WhatIfConfig) {
    function MaskVal([string]$key, [string]$val) {
        if (-not $val) { return '<not set>' }
        if ($PSBoundParameters.ContainsKey('Debug')) { return $val }
        $lk = $key.ToLower()
        if ($lk -like '*token*' -or $lk -like '*auth*' -or $lk -like '*pass*' -or $lk -like '*secret*') { return '****(masked)' }
        return $val
    }

    Write-Host "=== scan.ps1 Effective Configuration (WhatIf) ===" -ForegroundColor Yellow
    $report = @()
    # Core SSC values
    $report += [PSCustomObject]@{ Key = 'SSCUrl'; Value = MaskVal 'SSCUrl' $resolvedValues['SSCUrl']; Source = $resolvedSources['SSCUrl'] }
    $report += [PSCustomObject]@{ Key = 'SSCAuthToken'; Value = MaskVal 'SSCAuthToken' $resolvedValues['SSCAuthToken']; Source = $resolvedSources['SSCAuthToken'] }
    $report += [PSCustomObject]@{ Key = 'SSCAppName'; Value = MaskVal 'SSCAppName' $resolvedValues['SSCAppName']; Source = $resolvedSources['SSCAppName'] }
    $report += [PSCustomObject]@{ Key = 'SSCAppVersion'; Value = MaskVal 'SSCAppVersion' $resolvedValues['SSCAppVersion']; Source = $resolvedSources['SSCAppVersion'] }

    # Additional useful keys for preview
    $report += [PSCustomObject]@{ Key = 'BuildId'; Value = MaskVal 'BuildId' $BuildId; Source = if ([string]::IsNullOrEmpty($BuildId)) { '<unset>' } else { 'parameter' } }
    $report += [PSCustomObject]@{ Key = 'ProjectRoot'; Value = MaskVal 'ProjectRoot' $ProjectRoot; Source = 'parameter' }
    $report += [PSCustomObject]@{ Key = 'Verbose'; Value = if ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue') { 'True' } else { 'False' }; Source = 'common parameter' }
    $report += [PSCustomObject]@{ Key = 'Debug'; Value = if ($PSBoundParameters.ContainsKey('Debug') -or $DebugPreference -eq 'Continue') { 'True' } else { 'False' }; Source = 'common parameter' }
    $report += [PSCustomObject]@{ Key = 'UploadToSSC'; Value = if ($UploadToSSC) { 'True' } else { 'False' }; Source = 'parameter' }
    $report += [PSCustomObject]@{ Key = 'SSCUploadOnly'; Value = if ($SSCUploadOnly) { 'True' } else { 'False' }; Source = 'parameter' }
    $report += [PSCustomObject]@{ Key = 'FPRFile'; Value = ("$BuildId.fpr") ; Source = 'derived' }
    $report += [PSCustomObject]@{ Key = 'TranslationOptions'; Value = if ($transOptions) { $transOptions } else { '<none>' }; Source = if ($transOptions) { 'config' } else { '<none>' } }
    $report += [PSCustomObject]@{ Key = 'ScanOptions'; Value = if ($scanOptions) { $scanOptions } else { '<none>' }; Source = if ($scanOptions) { 'config' } else { '<none>' } }

    $report | Format-Table -Property Key, Value, Source -AutoSize
    Write-Host "Note: values containing 'token', 'auth', 'pass', or 'secret' are masked unless you pass -Debug." -ForegroundColor Yellow

    # If verbose, print which environment variable names were checked for each logical key
    if ($PSBoundParameters.ContainsKey('Verbose')) {
        Write-Host "`nEnvironment variables checked (per key):" -ForegroundColor Yellow
        foreach ($k in $envCandidates.Keys) {
            $cands = $envCandidates[$k]
            Write-Host (("- {0}:" -f $k)) -ForegroundColor Cyan
            Print-EnvChecks -Key $k -Candidates $cands
        }
    }

    exit 0
}

# Resolve SSC configuration with precedence: Parameters > Environment Variables > Config File
# SSC URL
if (-not [string]::IsNullOrEmpty($SSCUrl)) {
    Write-Host "Using SSC URL from parameter" -ForegroundColor Yellow
} elseif (-not [string]::IsNullOrEmpty($env:SSC_URL)) {
    $SSCUrl = $env:SSC_URL
    Write-Host "Using SSC URL from environment variable" -ForegroundColor Yellow
} elseif (-not [string]::IsNullOrEmpty($configSSCUrl)) {
    $SSCUrl = $configSSCUrl
    Write-Host "Using SSC URL from config file" -ForegroundColor Yellow
}

# SSC Auth Token
if (-not [string]::IsNullOrEmpty($SSCAuthToken)) {
    Write-Host "Using SSC Auth Token from parameter" -ForegroundColor Yellow
} elseif (-not [string]::IsNullOrEmpty($env:SSC_AUTH_TOKEN)) {
    $SSCAuthToken = $env:SSC_AUTH_TOKEN
    Write-Host "Using SSC Auth Token from environment variable" -ForegroundColor Yellow
} elseif (-not [string]::IsNullOrEmpty($configSSCAuthToken)) {
    $SSCAuthToken = $configSSCAuthToken
    Write-Host "Using SSC Auth Token from config file" -ForegroundColor Yellow
}

# SSC App Name
if (-not [string]::IsNullOrEmpty($SSCAppName)) {
    $AppName = $SSCAppName
    Write-Host "Using SSC App Name from parameter" -ForegroundColor Yellow
} elseif (-not [string]::IsNullOrEmpty($env:SSC_APP_NAME)) {
    $AppName = $env:SSC_APP_NAME
    Write-Host "Using SSC App Name from environment variable" -ForegroundColor Yellow
} elseif (-not [string]::IsNullOrEmpty($configAppName)) {
    $AppName = $configAppName
    Write-Host "Using SSC App Name from config file" -ForegroundColor Yellow
}

# SSC App Version
if (-not [string]::IsNullOrEmpty($SSCAppVersionName)) {
    $AppVersion = $SSCAppVersionName
    Write-Host "Using SSC App Version from parameter" -ForegroundColor Yellow
} elseif (-not [string]::IsNullOrEmpty($env:SSC_APP_VERSION_NAME)) {
    $AppVersion = $env:SSC_APP_VERSION_NAME
    Write-Host "Using SSC App Version from environment variable" -ForegroundColor Yellow
} elseif (-not [string]::IsNullOrEmpty($configAppVersion)) {
    $AppVersion = $configAppVersion
    Write-Host "Using SSC App Version from config file" -ForegroundColor Yellow
}

# If UploadToSSC is requested, also display the values (masking sensitive values unless Debug is present)
if ($UploadToSSC) {
    if ($resolvedValues['SSCUrl']) { Write-Host "SSC Upload URL: $($resolvedValues['SSCUrl'])" -ForegroundColor Cyan }
    if ($resolvedValues['SSCAppName']) { Write-Host "SSC Application: $($resolvedValues['SSCAppName'])" -ForegroundColor Cyan }
    if ($resolvedValues['SSCAppVersion']) { Write-Host "SSC Application Version: $($resolvedValues['SSCAppVersion'])" -ForegroundColor Cyan }
}

# Check if we should skip scan steps and only run specific operations
if ($SSCUploadOnly) {
    Write-Host "`n=== SSC Upload Only Mode ===" -ForegroundColor Yellow
    Write-Host "Skipping scan steps, proceeding directly to SSC upload..." -ForegroundColor Cyan
    $fprFile = "$BuildId.fpr"  # Set expected FPR file name for reference
} else {
    Write-Host "`n=== Starting OpenText SAST Scan ===" -ForegroundColor Yellow
    Write-Host "Build ID: $BuildId" -ForegroundColor Cyan
    Write-Host "Project Root: $ProjectRoot" -ForegroundColor Cyan
    Write-Host ""

    # Before running any SourceAnalyzer/scan commands ensure the binary is available
    Write-Host "Checking for sourceanalyzer..." -ForegroundColor Yellow
    try {
        $null = Get-Command sourceanalyzer -ErrorAction Stop
        Write-Host "sourceanalyzer found." -ForegroundColor Green
    }
    catch {
        Write-Error "sourceanalyzer command not found. Please ensure OpenText SAST is installed and in your PATH."
        exit 1
    }

    # Step 1: Clean the build
    Write-Host "[1/4] Cleaning build..." -ForegroundColor Yellow
    Invoke-SourceAnalyzer "$baseArgs -clean"
    Write-Host "Clean completed successfully.`n" -ForegroundColor Green

    # Step 2: Translation phase
    Write-Host "[2/4] Translating source code..." -ForegroundColor Yellow

    # Ensure we have a translation options list variable (may be undefined when no config file)
    $transList = if ($null -eq $transOptionsList) { @() } else { $transOptionsList }

    # Determine if there are any translation options other than "-exclude"
    $hasNonExclude = $false
    foreach ($opt in $transList) {
        $optNorm = $opt.Trim('"').Trim()
        if (-not ($optNorm -match '^\s*-exclude\b')) {
            $hasNonExclude = $true
            break
        }
    }

    # If there are non-exclude options, do NOT append "." (assume options include paths/targets).
    if ($hasNonExclude) {
        $translateArgs = "$baseArgs $transOptions $verboseArg $debugArg"
    } else {
        # No non-exclude options -> translate current directory (append ".")
        $translateArgs = "$baseArgs $transOptions $verboseArg $debugArg ."
    }
    $translateArgs = $translateArgs -replace '\s+', ' '  # Remove extra spaces
    Invoke-SourceAnalyzer $translateArgs.Trim()

    Write-Host "Translation completed successfully.`n" -ForegroundColor Green

    # Step 3: Scan phase
    Write-Host "[3/4] Scanning..." -ForegroundColor Yellow
    $fprFile = "$BuildId.fpr"
    $scanArgs = "$baseArgs -scan $scanOptions -f `"$fprFile`" $verboseArg $debugArg"
    $scanArgs = $scanArgs -replace '\s+', ' '  # Remove extra spaces
    Invoke-SourceAnalyzer $scanArgs.Trim()
    Write-Host "Scan completed successfully.`n" -ForegroundColor Green
    Write-Host "FPR file created: $fprFile`n" -ForegroundColor Cyan

    # Step 4: Summarize issues using FPRUtility
    Write-Host "[4/4] Summarizing issues in FPR..." -ForegroundColor Yellow
    try {
        $null = Get-Command FPRUtility -ErrorAction Stop
        Write-Host "Executing: FPRUtility -information -analyzerIssueCounts -project `"$fprFile`"" -ForegroundColor Cyan

        $process = Start-Process -FilePath "FPRUtility" `
                                  -ArgumentList "-information -analyzerIssueCounts -project `"$fprFile`"" `
                                  -NoNewWindow `
                                  -Wait `
                                  -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-Host "Issue summary completed successfully.`n" -ForegroundColor Green
        } else {
            Write-Warning "FPRUtility completed with exit code: $($process.ExitCode)"
        }
    }
    catch {
        Write-Warning "FPRUtility command not found. Skipping issue summary."
    }
}

# Step 5: Upload to SSC (optional, or upload-only mode)
if ($UploadToSSC -or $SSCUploadOnly) {
    Write-Host "[5/5] Uploading FPR to Fortify Software Security Center..." -ForegroundColor Yellow
    
    # Validate SSC configuration
    if ([string]::IsNullOrEmpty($SSCUrl) -or [string]::IsNullOrEmpty($SSCAuthToken) -or 
        [string]::IsNullOrEmpty($AppName) -or [string]::IsNullOrEmpty($AppVersion)) {
        Write-Error "SSC configuration incomplete. Please ensure all required values are provided via parameters, environment variables (SSC_URL, SSC_AUTH_TOKEN, SSC_APP_NAME, SSC_APP_VERSION_NAME), or fortify.config file [ssc] section"
        exit 1
    }
    
    # Check if fortifyclient is available
    try {
        $null = Get-Command fortifyclient -ErrorAction Stop
        Write-Host "fortifyclient found." -ForegroundColor Green
    }
    catch {
        Write-Error "fortifyclient command not found. Please ensure Fortify Client is installed and in your PATH."
        exit 1
    }
    
    # Check if FPR file exists
    if (-not (Test-Path $fprFile)) {
        Write-Error "FPR file not found: $fprFile"
        exit 1
    }
    
    # Use AppName from SSC config if available, otherwise use BuildId
    $uploadAppName = if ([string]::IsNullOrEmpty($AppName)) { $BuildId } else { $AppName }
    
    Write-Host "Executing: fortifyclient uploadFPR -file `"$fprFile`" -url $SSCUrl -authtoken [REDACTED] -application `"$uploadAppName`" -applicationVersion `"$AppVersion`"" -ForegroundColor Cyan

    try {
        $process = Start-Process -FilePath "fortifyclient" `
                                  -ArgumentList "uploadFPR -file `"$fprFile`" -url $SSCUrl -authtoken $SSCAuthToken -application `"$uploadAppName`" -applicationVersion `"$AppVersion`"" `
                                  -NoNewWindow `
                                  -Wait `
                                  -PassThru

        if ($process.ExitCode -eq 0) {
            Write-Host "FPR upload completed successfully.`n" -ForegroundColor Green
        } else {
            Write-Warning "fortifyclient uploadFPR completed with exit code: $($process.ExitCode)"
        }
    }
    catch {
        Write-Error "Failed to execute fortifyclient uploadFPR: $_"
        exit 1
    }
}

if ($SSCUploadOnly) {
    Write-Host "=== SSC Upload Complete ===" -ForegroundColor Green
} else {
    Write-Host "=== OpenText SAST Scan Complete ===" -ForegroundColor Green
    Write-Host "Results available in: $fprFile" -ForegroundColor Cyan
}
if (($UploadToSSC -or $SSCUploadOnly) -and $SSCUrl) {
    Write-Host "Results uploaded to SSC: $SSCUrl" -ForegroundColor Cyan
}
