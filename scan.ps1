#!/usr/bin/env pwsh
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
    6. Optionally audit results using Fortify Aviator
    The script supports reading additional options from a fortify.config file.
    This file can contain [translation], [scan], [ssc], and [aviator] sections for respective options.

.PARAMETER BuildId
    The build ID for OpenText SAST (default: current directory name)

.PARAMETER ProjectRoot
    The project root directory for OpenText SAST (default: .fortify)

.PARAMETER VerboseOutput
    Enable verbose output for OpenText SAST

.PARAMETER DebugOutput
    Enable debug output for OpenText SAST

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

.PARAMETER AuditWithAviator
    Audit the results using Fortify Aviator

.PARAMETER AviatorUrl
    Fortify Aviator URL (can also be set via AVIATOR_URL environment variable or config file)

.PARAMETER AviatorToken
    Aviator Authentication Token (can also be set via AVIATOR_TOKEN environment variable or config file)

.PARAMETER AviatorAppName
    Aviator Application Name (can also be set via AVIATOR_APP_NAME environment variable or config file)

.PARAMETER AviatorAuditOnly
    Skip all scan steps and only run Aviator audit (requires existing SSC results)

.PARAMETER SSCUploadOnly
    Skip all scan steps and only upload existing FPR to SSC

.EXAMPLE
    .\scan.ps1
    
.EXAMPLE
    .\scan.ps1 -BuildId "my-build" -VerboseOutput -DebugOutput
    
.EXAMPLE
    .\scan.ps1 -UploadToSSC
    
.EXAMPLE
    .\scan.ps1 -UploadToSSC -SSCUrl "https://ssc.company.com/ssc" -SSCAuthToken "token123" -SSCAppName "MyApp" -SSCAppVersionName "1.0"
    
.EXAMPLE
    .\scan.ps1 -UploadToSSC -AuditWithAviator
    
.EXAMPLE
    .\scan.ps1 -AviatorAuditOnly
    
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
    [switch]$VerboseOutput,
    
    [Parameter(Mandatory=$false)]
    [switch]$DebugOutput,
    
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
    [switch]$AuditWithAviator,
    
    [Parameter(Mandatory=$false)]
    [string]$AviatorUrl = "",
    
    [Parameter(Mandatory=$false)]
    [string]$AviatorToken = "",
    
    [Parameter(Mandatory=$false)]
    [string]$AviatorAppName = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$AviatorAuditOnly,
    
    [Parameter(Mandatory=$false)]
    [switch]$SSCUploadOnly
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
$verboseArg = if ($VerboseOutput) { "-verbose" } else { "" }
$debugArg = if ($DebugOutput) { "-debug" } else { "" }

# Read options from fortify.config if it exists
$optsFile = "fortify.config"
$transOptions = ""
$scanOptions = ""
$configSSCUrl = ""
$configSSCAuthToken = ""
$configAppName = ""
$configAppVersion = ""
$configAviatorUrl = ""
$configAviatorToken = ""
$configAviatorAppName = ""

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
        elseif ($currentSection -eq "aviator") {
            # Parse Aviator configuration options
            if ($line -match '^AviatorUrl\s*=\s*(.+)$') {
                $configAviatorUrl = $matches[1].Trim('"')
            }
            elseif ($line -match '^AviatorToken\s*=\s*(.+)$') {
                $configAviatorToken = $matches[1].Trim('"')
            }
            elseif ($line -match '^AviatorAppName\s*=\s*(.+)$') {
                $configAviatorAppName = $matches[1].Trim('"')
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

# Resolve SSC configuration with precedence: Environment Variables > Config File > Parameters
# SSC URL
if (-not [string]::IsNullOrEmpty($env:SSC_URL)) {
    $SSCUrl = $env:SSC_URL
    Write-Host "Using SSC URL from environment variable" -ForegroundColor Yellow
} elseif (-not [string]::IsNullOrEmpty($configSSCUrl)) {
    $SSCUrl = $configSSCUrl
    Write-Host "Using SSC URL from config file" -ForegroundColor Yellow
} elseif (-not [string]::IsNullOrEmpty($SSCUrl)) {
    Write-Host "Using SSC URL from parameter" -ForegroundColor Yellow
}

# SSC Auth Token
if (-not [string]::IsNullOrEmpty($env:SSC_AUTH_TOKEN)) {
    $SSCAuthToken = $env:SSC_AUTH_TOKEN
    Write-Host "Using SSC Auth Token from environment variable" -ForegroundColor Yellow
} elseif (-not [string]::IsNullOrEmpty($configSSCAuthToken)) {
    $SSCAuthToken = $configSSCAuthToken
    Write-Host "Using SSC Auth Token from config file" -ForegroundColor Yellow
} elseif (-not [string]::IsNullOrEmpty($SSCAuthToken)) {
    Write-Host "Using SSC Auth Token from parameter" -ForegroundColor Yellow
}

# SSC App Name
if (-not [string]::IsNullOrEmpty($env:SSC_APP_NAME)) {
    $AppName = $env:SSC_APP_NAME
    Write-Host "Using SSC App Name from environment variable" -ForegroundColor Yellow
} elseif (-not [string]::IsNullOrEmpty($configAppName)) {
    $AppName = $configAppName
    Write-Host "Using SSC App Name from config file" -ForegroundColor Yellow
} elseif (-not [string]::IsNullOrEmpty($SSCAppName)) {
    $AppName = $SSCAppName
    Write-Host "Using SSC App Name from parameter" -ForegroundColor Yellow
}

# SSC App Version
if (-not [string]::IsNullOrEmpty($env:SSC_APP_VERSION_NAME)) {
    $AppVersion = $env:SSC_APP_VERSION_NAME
    Write-Host "Using SSC App Version from environment variable" -ForegroundColor Yellow
} elseif (-not [string]::IsNullOrEmpty($configAppVersion)) {
    $AppVersion = $configAppVersion
    Write-Host "Using SSC App Version from config file" -ForegroundColor Yellow
} elseif (-not [string]::IsNullOrEmpty($SSCAppVersionName)) {
    $AppVersion = $SSCAppVersionName
    Write-Host "Using SSC App Version from parameter" -ForegroundColor Yellow
}

# Resolve Aviator configuration with precedence: Environment Variables > Config File > Parameters
# Aviator URL
if (-not [string]::IsNullOrEmpty($env:AVIATOR_URL)) {
    $AviatorUrl = $env:AVIATOR_URL
    Write-Host "Using Aviator URL from environment variable" -ForegroundColor Yellow
} elseif (-not [string]::IsNullOrEmpty($configAviatorUrl)) {
    $AviatorUrl = $configAviatorUrl
    Write-Host "Using Aviator URL from config file" -ForegroundColor Yellow
} elseif (-not [string]::IsNullOrEmpty($AviatorUrl)) {
    Write-Host "Using Aviator URL from parameter" -ForegroundColor Yellow
}

# Aviator Token
if (-not [string]::IsNullOrEmpty($env:AVIATOR_TOKEN)) {
    $AviatorToken = $env:AVIATOR_TOKEN
    Write-Host "Using Aviator Token from environment variable" -ForegroundColor Yellow
} elseif (-not [string]::IsNullOrEmpty($configAviatorToken)) {
    $AviatorToken = $configAviatorToken
    Write-Host "Using Aviator Token from config file" -ForegroundColor Yellow
} elseif (-not [string]::IsNullOrEmpty($AviatorToken)) {
    Write-Host "Using Aviator Token from parameter" -ForegroundColor Yellow
}

# Aviator App Name
if (-not [string]::IsNullOrEmpty($env:AVIATOR_APP_NAME)) {
    $AviatorAppName = $env:AVIATOR_APP_NAME
    Write-Host "Using Aviator App Name from environment variable" -ForegroundColor Yellow
} elseif (-not [string]::IsNullOrEmpty($configAviatorAppName)) {
    $AviatorAppName = $configAviatorAppName
    Write-Host "Using Aviator App Name from config file" -ForegroundColor Yellow
} elseif (-not [string]::IsNullOrEmpty($AviatorAppName)) {
    Write-Host "Using Aviator App Name from parameter" -ForegroundColor Yellow
}

# Display resolved SSC configuration if uploading
if ($UploadToSSC) {
    if (-not [string]::IsNullOrEmpty($SSCUrl)) {
        Write-Host "SSC Upload URL: $SSCUrl" -ForegroundColor Cyan
    }
    if (-not [string]::IsNullOrEmpty($AppName)) {
        Write-Host "SSC Application: $AppName" -ForegroundColor Cyan
    }
    if (-not [string]::IsNullOrEmpty($AppVersion)) {
        Write-Host "SSC Application Version: $AppVersion" -ForegroundColor Cyan
    }
}

# Display resolved Aviator configuration if auditing
if ($AuditWithAviator) {
    if (-not [string]::IsNullOrEmpty($AviatorUrl)) {
        Write-Host "Aviator URL: $AviatorUrl" -ForegroundColor Cyan
    }
    if (-not [string]::IsNullOrEmpty($AviatorAppName)) {
        Write-Host "Aviator Application: $AviatorAppName" -ForegroundColor Cyan
    }
}

# Check if we should skip scan steps and only run specific operations
if ($AviatorAuditOnly) {
    Write-Host "`n=== Aviator Audit Only Mode ===" -ForegroundColor Yellow
    Write-Host "Skipping scan steps, proceeding directly to Aviator audit..." -ForegroundColor Cyan
    $fprFile = "$BuildId.fpr"  # Set expected FPR file name for reference
} elseif ($SSCUploadOnly) {
    Write-Host "`n=== SSC Upload Only Mode ===" -ForegroundColor Yellow
    Write-Host "Skipping scan steps, proceeding directly to SSC upload..." -ForegroundColor Cyan
    $fprFile = "$BuildId.fpr"  # Set expected FPR file name for reference
} else {
    Write-Host "`n=== Starting OpenText SAST Scan ===" -ForegroundColor Yellow
    Write-Host "Build ID: $BuildId" -ForegroundColor Cyan
    Write-Host "Project Root: $ProjectRoot" -ForegroundColor Cyan
    Write-Host ""

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
if (($UploadToSSC -and -not $AviatorAuditOnly) -or $SSCUploadOnly) {
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

# Step 6: Audit with Aviator (optional or audit-only mode, skip if SSCUploadOnly)
if (($AuditWithAviator -or $AviatorAuditOnly) -and -not $SSCUploadOnly) {
    Write-Host "[6/6] Auditing results with Fortify Aviator..." -ForegroundColor Yellow
    
    # Validate Aviator configuration
    if ([string]::IsNullOrEmpty($SSCUrl) -or [string]::IsNullOrEmpty($SSCAuthToken) -or 
        [string]::IsNullOrEmpty($AviatorUrl) -or [string]::IsNullOrEmpty($AviatorToken) -or 
        [string]::IsNullOrEmpty($AviatorAppName) -or [string]::IsNullOrEmpty($AppName) -or [string]::IsNullOrEmpty($AppVersion)) {
        Write-Error "Aviator audit configuration incomplete. Please ensure SSCUrl, SSCAuthToken, AviatorUrl, AviatorToken, AviatorAppName, AppName, and AppVersion are all configured via parameters, environment variables, or fortify.config file"
        exit 1
    }
    
    # Check if fcli is available
    try {
        $null = Get-Command fcli -ErrorAction Stop
        Write-Host "fcli found." -ForegroundColor Green
    }
    catch {
        Write-Error "fcli command not found. Please ensure Fortify CLI is installed and in your PATH."
        exit 1
    }
    
    try {
        # Login to SSC
        Write-Host "Logging into SSC..." -ForegroundColor Cyan
        $process = Start-Process -FilePath "fcli" `
                                  -ArgumentList "ssc session login --url $SSCUrl -t $SSCAuthToken" `
                                  -NoNewWindow `
                                  -Wait `
                                  -PassThru
        
        if ($process.ExitCode -ne 0) {
            Write-Error "Failed to login to SSC with exit code: $($process.ExitCode)"
            exit $process.ExitCode
        }
        
        # Login to Aviator
        Write-Host "Logging into Aviator..." -ForegroundColor Cyan
        $process = Start-Process -FilePath "fcli" `
                                  -ArgumentList "aviator session login --url $AviatorUrl -t string:$AviatorToken" `
                                  -NoNewWindow `
                                  -Wait `
                                  -PassThru
        
        if ($process.ExitCode -ne 0) {
            Write-Error "Failed to login to Aviator with exit code: $($process.ExitCode)"
            exit $process.ExitCode
        }
        
        # Run Aviator audit
        Write-Host "Running Aviator audit..." -ForegroundColor Cyan
        $appVersionArg = "$AppName`:$AppVersion"
        Write-Host "Executing: fcli aviator ssc audit --app `"$AviatorAppName`" --appversion `"$appVersionArg`"" -ForegroundColor Cyan
        
        # Use Invoke-Expression with proper quoting to handle spaces and special characters
        $fcliCommand = "fcli aviator ssc audit --app `"$AviatorAppName`" --appversion `"$appVersionArg`""
        Write-Host "Full command: $fcliCommand" -ForegroundColor Gray
        
        try {
            $result = Invoke-Expression $fcliCommand
            $exitCode = $LASTEXITCODE
            
            if ($exitCode -eq 0) {
                Write-Host "Aviator audit completed successfully.`n" -ForegroundColor Green
            } else {
                Write-Warning "Aviator audit completed with exit code: $exitCode"
            }
        }
        catch {
            Write-Error "Failed to execute Aviator audit command: $_"
            exit 1
        }
        
        if ($process.ExitCode -eq 0) {
            Write-Host "Aviator audit completed successfully.`n" -ForegroundColor Green
        } else {
            Write-Warning "Aviator audit completed with exit code: $($process.ExitCode)"
        }
    }
    catch {
        Write-Error "Failed to execute Aviator audit: $_"
        exit 1
    }
}

if ($AviatorAuditOnly) {
    Write-Host "=== Aviator Audit Complete ===" -ForegroundColor Green
} elseif ($SSCUploadOnly) {
    Write-Host "=== SSC Upload Complete ===" -ForegroundColor Green
} else {
    Write-Host "=== OpenText SAST Scan Complete ===" -ForegroundColor Green
    Write-Host "Results available in: $fprFile" -ForegroundColor Cyan
}
if ((($UploadToSSC -and -not $AviatorAuditOnly) -or $SSCUploadOnly) -and $SSCUrl) {
    Write-Host "Results uploaded to SSC: $SSCUrl" -ForegroundColor Cyan
}
if (($AuditWithAviator -or $AviatorAuditOnly) -and -not $SSCUploadOnly -and $AviatorUrl) {
    Write-Host "Results audited with Aviator: $AviatorUrl" -ForegroundColor Cyan
}