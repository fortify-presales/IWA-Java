param(
    [string]$EnvFile = "$PSScriptRoot/.env",
    [switch]$SkipEnvLoad
)

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Write-Host "[$ts] [$Level] $Message"
}

function Load-DotEnv {
    param([string]$Path)

    # If an explicit path was provided and exists, use it
    if ($Path -and (Test-Path -LiteralPath $Path)) {
        Write-Log "Loading .env from explicit path: $Path" 'DEBUG'
        $resolvedPath = (Get-Item -LiteralPath $Path).FullName
    } else {
        # Candidate locations in order of preference:
        # 1. parent of the script (repo root when script is in bin/)
        # 2. current working directory
        # 3. script directory
        $candidates = @()
        try {
            $scriptParent = (Get-Item -LiteralPath (Join-Path $PSScriptRoot '..')).FullName
            $candidates += (Join-Path $scriptParent '.env')
        } catch { }
        $candidates += (Join-Path (Get-Location).Path '.env')
        $candidates += (Join-Path $PSScriptRoot '.env')

        $resolvedPath = $null
        foreach ($cand in $candidates) {
            if (Test-Path -LiteralPath $cand) { $resolvedPath = (Get-Item -LiteralPath $cand).FullName; break }
        }

        if (-not $resolvedPath) {
            Write-Log "No .env file found in candidates: $($candidates -join ', ') - skipping dotenv load" 'DEBUG'
            return
        }

        Write-Log "Loading .env from $resolvedPath" 'DEBUG'
    }

    Get-Content -LiteralPath $resolvedPath | ForEach-Object {
        $line = $_.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#') -or $line.StartsWith(';')) { return }
        # Support lines like: export KEY=val or KEY="val"
        if ($line -match '^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
            $name = $matches[1]
            $value = $matches[2]
            # Remove surrounding quotes if present
            if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            # Unescape common sequences
            $value = $value -replace '\\n', "`n" -replace '\\r', "`r"

            # Only set if not already present in environment
            if ([string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name))) {
                Write-Log "Setting env $name from .env" 'DEBUG'
                [Environment]::SetEnvironmentVariable($name, $value)
            } else {
                Write-Log "Env $name already set; skipping .env value" 'DEBUG'
            }
        } else {
            Write-Log "Skipping unparsable .env line: $line" 'DEBUG'
        }
    }
}

function Exec-Checked {
    param(
        [Parameter(Mandatory=$true)] [string]$Command,
        [Parameter(Mandatory=$false)] [string[]]$Args
    )
    if (-not $Args) { $Args = @() }

    # Resolve the command first so we can give a clear error if it's not found
    $resolved = Get-Command $Command -ErrorAction SilentlyContinue
    if (-not $resolved) {
        Write-Log "Command '$Command' not found in PATH. Ensure it's installed and accessible." 'ERROR'
        throw "Missing command: $Command"
    }

    $displayArgs = $Args -join ' '
    Write-Log "Running: $Command $displayArgs"

    try {
        # Use the call operator so PowerShell will execute scripts, functions, cmdlets, or external executables correctly
        # Prefer using the resolved path when available (for example, an executable path)
        $invocationTarget = $resolved.Path
        if ([string]::IsNullOrEmpty($invocationTarget)) { $invocationTarget = $Command }

        # Execute and capture combined output (stdout+stderr)
        $output = & $invocationTarget @Args 2>&1
        # For external processes, $LASTEXITCODE will be set; for PowerShell commands it may be null/0
        $exit = $LASTEXITCODE
        if ($null -eq $exit) { $exit = 0 }

        if ($output) {
            if ($output -is [System.Array]) { $output | ForEach-Object { Write-Host $_ } }
            else { Write-Host $output }
        }

        if ($exit -ne 0) {
            throw "Command '$Command' failed with exit code $exit"
        }

        return $exit
    } catch {
        # Re-throw with more context
        throw "Execution of '$Command $displayArgs' failed: $_"
    }
}

# Main
try {
    if (-not $SkipEnvLoad) { Load-DotEnv -Path $EnvFile }

    $required = @('SSC_URL','SSC_CI_TOKEN','SSC_CLIENT_AUTH_TOKEN','SSC_SENSOR_VER','SSC_APP_NAME','SSC_APPVER_NAME')
    $missing = @()
    foreach ($r in $required) {
        if ([string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($r))) { $missing += $r }
    }
    if ($missing.Count -gt 0) {
        Write-Log "Missing required environment variables: $($missing -join ', ')" 'ERROR'
        throw 'Missing required environment variables'
    }

    # Ensure required executables are available
    $needs = @('fcli','scancentral')
    foreach ($n in $needs) {
        if (-not (Get-Command $n -ErrorAction SilentlyContinue)) {
            Write-Log "Required command '$n' not found on PATH. Please install or add it to PATH." 'ERROR'
            throw "Missing command: $n"
        }
    }

    # Login to SSC
    Exec-Checked -Command 'fcli' -Args @('ssc','session','login','--url',$env:SSC_URL,'--token',$env:SSC_CI_TOKEN,'--client-auth-token',$env:SSC_CLIENT_AUTH_TOKEN,'--ssc-session','fcli')

    # Determine repository root (directory containing build.gradle). This lets the script live in bin/ and still find the project.
    $repoRoot = $null
    $starts = @($PSScriptRoot, (Get-Location).Path)
    foreach ($s in $starts) {
        try { $cur = (Resolve-Path -LiteralPath $s).Path } catch { $cur = $s }
        while ($cur) {
            if (Test-Path (Join-Path $cur 'build.gradle')) { $repoRoot = $cur; break }
            $parent = Split-Path $cur -Parent
            if ($parent -and ($parent -ne $cur)) { $cur = $parent } else { $cur = $null }
        }
        if ($repoRoot) { break }
    }

    if (-not $repoRoot) {
        Write-Log 'Could not locate repository root (build.gradle not found). Ensure you run this from the repo or place script inside the repo.' 'ERROR'
        throw 'Repository root not found'
    }

    Write-Log "Using repository root: $repoRoot" 'DEBUG'

    # Change into repo root for packaging and scanning steps
    Push-Location -LiteralPath $repoRoot
    try {
        # Package the project
        if (-not (Test-Path -Path 'build.gradle')) {
            Write-Log 'build.gradle not found in repository root. Ensure repository layout is correct.' 'ERROR'
            throw 'build.gradle missing'
        }

        # Remove existing Package.zip to avoid stale artifacts
        if (Test-Path -Path 'Package.zip') {
            try {
                Remove-Item -LiteralPath 'Package.zip' -Force -ErrorAction Stop
                Write-Log 'Removed existing Package.zip' 'DEBUG'
            } catch {
                Write-Log "Failed to remove existing Package.zip: $_" 'WARNING'
                throw 'Unable to remove existing Package.zip'
            }
        }

        Exec-Checked -Command 'scancentral' -Args @('package','-bt','gradle','-bf','build.gradle','-o','Package.zip')

        # Verify Package.zip was created
        if (-not (Test-Path -Path 'Package.zip')) {
            Write-Log 'Package.zip was not created by scancentral package step.' 'ERROR'
            throw 'Package.zip missing after packaging step'
        } else {
            $pkg = Get-Item -Path 'Package.zip'
            Write-Log "Package.zip created: $($pkg.FullName) (size: $($pkg.Length) bytes)" 'INFO'
        }

        # Start SAST scan
        $publishTo = "$($env:SSC_APP_NAME):$($env:SSC_APPVER_NAME)"
        Exec-Checked -Command 'fcli' -Args @('sc-sast','scan','start','--sensor-version',$env:SSC_SENSOR_VER,'-f','Package.zip','--publish-to',$publishTo,'--store','curScan','--ssc-session','fcli')

        # Wait for scan
        Exec-Checked -Command 'fcli' -Args @('sc-sast','scan','wait-for','::curScan::','--ssc-session','fcli')

        # Run policy check
        Exec-Checked -Command 'fcli' -Args @('ssc','action','run','check-policy','--appversion',$publishTo,'--ssc-session','fcli')
    } finally {
        Pop-Location
    }

    Write-Log 'SAST fcli scan completed successfully' 'INFO'
} catch {
    Write-Log "ERROR: $_" 'ERROR'
    exit 1
}
