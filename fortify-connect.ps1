<#
PowerShell wrapper to run Fortify Connect container

Usage examples:
  pwsh ./fortify-connect.ps1 -FdcAddress 'emea.fodconnect.com:443' -FdcUsername 'user' -FdcPassword 'secret' -FdcProxy '3128'
  or set environment variables FDC_ADDRESS, FDC_UNAME, FDC_UPSWD, FDC_PROXY and run without params
#>

param(
    [Parameter(Mandatory=$false)][string] $FdcAddress,
    [Parameter(Mandatory=$false)][string] $FdcUsername,
    [Parameter(Mandatory=$false)][string] $FdcPassword,
    [Parameter(Mandatory=$false)][string] $FdcProxy,
    [Parameter(Mandatory=$false)][string] $Image = 'fortifydocker/fortify-connect:25.4.alpine.3.18',
    [Parameter(Mandatory=$false)][string] $ContainerName = 'fdc_client',
    [Parameter(Mandatory=$false)][switch] $Start,
    [Parameter(Mandatory=$false)][switch] $Stop,
    [Parameter(Mandatory=$false)][switch] $Status,
    [Parameter(Mandatory=$false)][switch] $Logs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Require-Param([string]$Name, [string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) {
        Write-Error "$Name is required as a parameter or environment variable `$env:$Name` and was not provided."
        exit 1
    }
}

# Resolve values: prefer explicit parameter, then environment variable
$FdcAddress = if ($FdcAddress) { $FdcAddress } elseif ($env:FDC_ADDRESS) { $env:FDC_ADDRESS } else { $null }
$FdcUsername = if ($FdcUsername) { $FdcUsername } elseif ($env:FDC_UNAME) { $env:FDC_UNAME } else { $null }
$FdcPassword = if ($FdcPassword) { $FdcPassword } elseif ($env:FDC_UPSWD) { $env:FDC_UPSWD } else { $null }
$FdcProxy   = if ($FdcProxy)   { $FdcProxy }   elseif ($env:FDC_PROXY)   { $env:FDC_PROXY }   else { $null }

# Provide default for FDC_ADDRESS if not provided
if (-not $FdcAddress) {
    $FdcAddress = 'ams.fodconnect.com:443'
    Write-Host "FDC_ADDRESS not provided; using default: $FdcAddress"
}

# Provide default for FDC_PROXY if not provided
if (-not $FdcProxy) {
    $FdcProxy = '3128'
    Write-Host "FDC_PROXY not provided; using default: $FdcProxy"
}

# Determine which action to run. Ensure only one action is specified.
$actionsSpecified = @()
if ($Start) { $actionsSpecified += 'Start' }
if ($Stop)  { $actionsSpecified += 'Stop' }
if ($Status){ $actionsSpecified += 'Status' }
if ($Logs)  { $actionsSpecified += 'Logs' }

# Allow the Start+Logs combo; otherwise require only one action
if ($actionsSpecified.Count -gt 1 -and -not ($Start -and $Logs -and $actionsSpecified.Count -eq 2)) {
    Write-Error "Only one of -Start, -Stop, -Status, -Logs may be specified at a time (except you may use -Start and -Logs together). You specified: $($actionsSpecified -join ', ')"
    exit 1
}

# If no action specified, default to Start (preserves previous behavior)
if ($actionsSpecified.Count -eq 0) {
    $Start = $true
    Write-Host "No action specified. Defaulting to -Start."
}

# Only require credentials for starting the container (including Start+Logs combo)
if ($Start) {
    Require-Param -Name 'FDC_UNAME' -Value $FdcUsername
    Require-Param -Name 'FDC_UPSWD' -Value $FdcPassword
}

function Ensure-DockerAvailable {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Error "Docker executable not found in PATH. Please install Docker or ensure it's available to this session."
        exit 1
    }
}

function Start-Container {
    Ensure-DockerAvailable

    Write-Host "Pulling image $Image..."
    docker pull $Image | Write-Host

    # If a container with the same name exists, stop and remove it
    $existing = docker ps -a --filter "name=$ContainerName" --format "{{.ID}}" 2>$null
    if ($existing) {
        Write-Host "Found existing container with name '$ContainerName' (id: $existing). Removing..."
        docker rm -f $ContainerName | Write-Host
    }

    Write-Host "Starting container '$ContainerName'..."

    # Determine FDC_TUNNEL_LOGS: set to 1 when the PowerShell -Debug switch is used (or DebugPreference changed), otherwise 0
    $debugFlag = $false
    try {
        if ($PSBoundParameters.ContainsKey('Debug')) { $debugFlag = $true }
    } catch { }
    if ($DebugPreference -ne 'SilentlyContinue') { $debugFlag = $true }
    $FDC_TUNNEL_LOGS = if ($debugFlag) { '1' } else { '0' }

    # Build environment variable arguments safely
    $envArgs = @(
        "-e", "FDC_ADDRESS=$FdcAddress",
        "-e", "FDC_UNAME=$FdcUsername",
        "-e", "FDC_UPSWD=$FdcPassword",
        "-e", "FDC_PROXY=$FdcProxy",
        "-e", "FDC_TUNNEL_LOGS=$FDC_TUNNEL_LOGS"
    )

    $runArgs = @('run', '--name', $ContainerName, '-d') + $envArgs + @('--privileged', $Image)

    # Use Start-Process to run docker so that arguments with special chars are handled correctly
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'docker'
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute = $false
    $psi.Arguments = ($runArgs -join ' ')

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $proc.Start() | Out-Null
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    if ($proc.ExitCode -ne 0) {
        Write-Error "docker run failed with exit code $($proc.ExitCode)."
        if ($stdout) { Write-Host "STDOUT: $stdout" }
        if ($stderr) { Write-Host "STDERR: $stderr" }
        exit $proc.ExitCode
    }

    $containerId = $stdout.Trim()
    if (-not $containerId) {
        # Attempt to find the container id by name
        $containerId = docker ps --filter "name=$ContainerName" --format "{{.ID}}" 2>$null
    }

    Write-Host "Container started successfully (id: $containerId)."
    Write-Host "Fortify Connect connected to $FdcAddress (container: $ContainerName)."
}

function Stop-Container {
    Ensure-DockerAvailable
    $existing = docker ps -a --filter "name=$ContainerName" --format "{{.ID}}" 2>$null
    if (-not $existing) {
        Write-Host "No container named '$ContainerName' found. Nothing to stop."
        return
    }
    Write-Host "Stopping and removing container '$ContainerName'..."
    docker rm -f $ContainerName | Write-Host
    Write-Host "Container removed."
}

function Show-Status {
    Ensure-DockerAvailable
    # Use a custom delimiter-based format so we can reliably detect if any rows were returned.
    $rows = docker ps -a --filter "name=$ContainerName" --format "{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}" 2>$null

    if (-not $rows -or $rows.Trim() -eq '') {
        Write-Host "No container named '$ContainerName' found."
        return
    }

    # Print a simple header and then the parsed rows in tab-separated columns
    Write-Host "CONTAINER ID`tNAMES`tIMAGE`tSTATUS"
    $rows -split "`n" | ForEach-Object {
        $cols = $_ -split '\|'
        # Guard in case docker returns unexpected formatting
        if ($cols.Count -ge 4) {
            Write-Host ($cols[0].Trim() + "`t" + $cols[1].Trim() + "`t" + $cols[2].Trim() + "`t" + $cols[3].Trim())
        } else {
            Write-Host $_
        }
    }
}

function Monitor-Logs {
    Ensure-DockerAvailable
    $existing = docker ps -a --filter "name=$ContainerName" --format "{{.ID}}" 2>$null
    if (-not $existing) {
        Write-Host "No container named '$ContainerName' found. Cannot show logs."
        exit 1
    }
    Write-Host "Tailing logs for container '$ContainerName' (Ctrl+C to exit)..."
    # Use direct invocation so logs stream to console
    docker logs -f $ContainerName
}

# Dispatch action
if ($Start -and $Logs) {
    # Combined action: start then tail logs
    Start-Container
    Monitor-Logs
    exit 0
}
elseif ($Start) {
    Start-Container
    exit 0
}
elseif ($Stop) {
    Stop-Container
    exit 0
}
elseif ($Status) {
    Show-Status
    exit 0
}
elseif ($Logs) {
    Monitor-Logs
    exit 0
}
else {
    Write-Error "Unknown action requested."
    exit 1
}
