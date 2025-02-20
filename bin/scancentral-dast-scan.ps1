#
# Example script to perform Fortify ScanCentral DAST dynamic analysis including status checking and polling
#

    [CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$ApiUri,

    [Parameter(Mandatory)]
    [string]$Username,

    [Parameter(Mandatory)]
    [string]$Password,

    [Parameter(Mandatory)]
    [string]$CiCdToken,

    [Parameter()]
    [string]$ScanName = 'PowerShell initiated scan',

    [Parameter()]
    [int]$PollingInterval = 30,

    [Parameter()]
    [switch]$Raw
)
begin {
    # Remove any training slash from ApiUri
    $ApiUri = $ApiUri.TrimEnd('/')

    # Fortify Security Token
    $FortifyToken = ""

    # Fortify Scan Id
    $ScanId = ""

    # Fortify Scan Status values
    $ScanStatusValues = @{}

    # Default headers
    $Headers = @{
        'Accept' = "application/json"
        'Content-Type' = "application/json"
    }
}
process {
    $Response = $null

    # Authenticate to retrieve FORTIFYTOKEN
    Write-Host "Retrieving Fortify authentication token ..."
    $Body = @{
        username = $Username
        password = $Password
    }
    $Params = @{
        Uri = "$ApiUri/auth"
        ErrorAction = 'Stop'
        Method = 'POST'
        Body = (ConvertTo-Json $Body)
    }
    try  {
        $Response = Invoke-RestMethod -Headers $Headers @Params
        Write-Verbose $Response
        $FortifyToken = $Response.token
        $Headers.Add('Authorization', $FortifyToken)
    } catch {
        Write-Error -Exception $_.Exception -Message "scanCentral DAST API call failed: $_"
    }

    # Get possible scan status values
    Write-Host "Retrieving Fortify scan status values ..."
    $Params = @{
        Uri = "$ApiUri/utilities/lookup-items?type=ScanStatusTypes"
        ErrorAction = 'Stop'
        Method = 'GET'
    }
    try  {
        $Response = Invoke-RestMethod -Headers $Headers @Params
        $ScanStatusValues = $Response
    } catch {
        Write-Error -Exception $_.Exception -Message "scanCentral DAST API call failed: $_"
    }

    # Start the scan
    Write-Host "Starting scan using CiCd Token: $CiCdToken"
    $Body = @{
        name = $ScanName
        cicdToken = $CiCdToken
    }
    $Params = @{
        Uri = "$ApiUri/scans/start-scan-cicd"
        ErrorAction = 'Stop'
        Method = 'POST'
        Body = (ConvertTo-Json $Body)
    }
    try  {
        $Response = Invoke-RestMethod -Headers $Headers @Params
        Write-Verbose $Response
        $ScanId = $Response.id
        Write-Host "Started scan id: $ScanId"
    } catch {
        Write-Error -Exception $_.Exception -Message "scanCentral DAST API call failed: $_"
    }

    # Poll the scan
    Write-Host "Polling status of scan ..."
    $Params = @{
        Uri = "$ApiUri/scans/${ScanId}/scan-summary"
        ErrorAction = 'Stop'
        Method = 'GET'
    }
    do {
        Start-Sleep -s $PollingInterval # sleep for X seconds
        try  {
            $Response = Invoke-RestMethod -Headers $Headers @Params
            Write-Verbose $Response
            $ScanStatusId = ($Response.item.scanStatusType) - 1
            $ScanStatus = $ScanStatusValues.Item($ScanStatusId).text
        } catch {
            Write-Error -Exception $_.Exception -Message "scanCentral DAST API call failed: $_"
        }
        Write-Host "Scan id: '$ScanId' current status: $ScanStatus ($ScanStatusId)"
    } until ($ScanStatusId -in 4..6 -or $ScanStatusId -in 14..16)
}
end {
    if ($Raw) {
        $Response
    } else {
        Write-Host "Scan id: $ScanId final status: $ScanStatus ($ScanStatusId)"
    }
}
