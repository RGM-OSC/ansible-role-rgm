[cmdletbinding()]
param (
    [Parameter(Mandatory=$true,ParameterSetName="Username")]
    [String]$Username,
    [Parameter(Mandatory=$true,ParameterSetName="Username")]
    [String]$Password,
    [Parameter(Mandatory=$true,ParameterSetName="OneTimeToken")]
    [String]$OneTimeToken,
    [String]$RGMServer = "{{ ansible_default_ipv4.address }}",
    [Switch]$NoMetricBeat,
    [Switch]$AuditBeat,
    [Switch]$InstallSomething
)


if ("TrustAllCertsPolicy" -as [type]) { } else {
    add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Create header with token value if the token is passed in variable
If ($OneTimeToken) {
    $Header = @{
        "Content-Type" = "application/json"
        "token"        = $OneTimeToken
    }
}
Else {
    $Header = @{
        "Content-Type" = "application/json"
    }
}

function Get-RGMApiToken {

    $UriAuthent = "https://$RGMServer/rgmapi/getAuthToken?&username=$Username&password=$Password"

    $TokenReturn = Invoke-RestMethod -Uri $UriAuthent -Method GET -Headers $Header

    # Update the current header with the current active token
    $script:Header = @{
        "Content-Type" = "application/json"
        "token"        = $TokenReturn.RGMAPI_TOKEN
    }
}


function Test-RGMApiToken {

    $UriTokenCheck = "https://$RGMServer/rgmapi/checkAuthToken"
    try {
        $null = Invoke-RestMethod -Uri $UriTokenCheck -Method GET -Headers $Header
    }
    catch {
        return $false
    }
    return $true
}

function Invoke-RGMRestMethod {
    param (
        [String]$Uri,
        [String]$Methode,
        [String]$Body
    )
    if (!(Test-RGMApiToken)) {
        if ($password) {
            Get-RGMApiToken
        }
        elseif ($OneTimeToken) {
            Write-Host "The OnTimeToken is not valid`nEnd of script"
            exit
        }else{
            Write-Host "There is an unexpected error (no password or no OneTimeToken provided)`nEnd of script"
            exit
        }
    }

    if ($Methode -eq "Get") {
        return (Invoke-RestMethod -Uri $Uri -Method Get -Headers $Header)
    }
    else {
        return (Invoke-RestMethod -Uri $Uri -Method $Methode -Body $Body -Headers $Header)
    }
}


function New-RGMHost {
    param (
        [String]$templateHostName = "GENERIC_HOST",
        [String]$hostName, 
        [String]$hostIp, 
        [String]$hostAlias = ""#, 
        #   [String]$contactName, 
        #   [String]$contactGroupName, 
        #   [bool]$exportConfiguration=$false
    )

    $CreateHostBody = @{
        "templateHostName" = $templateHostName
        "hostName"         = $hostName
        "hostIp"           = $hostIp
        "hostAlias"        = $hostAlias
    } | ConvertTo-Json

    $UriCreateHost = "https://$RGMServer/rgmapi/createHost"

    $NewHost = Invoke-RGMRestMethod -Uri $UriCreateHost -Method Post -Body $CreateHostBody
    return $NewHost
}


# found active IP address
$interfaces = Get-NetRoute -DestinationPrefix 0.0.0.0/0 # Search Interfaces with gateway to go out
$ActiveInterface = $interfaces | Get-NetIPInterface | where-object { $_.ConnectionState -eq "Connected" } # filter to keep active interface
$PrincipaleIP = Get-NetIPAddress -InterfaceIndex $ActiveInterface.InterfaceIndex -AddressFamily IPV4 | Select-Object -ExpandProperty IPaddress
# Collect current computername
$Hostname = $env:COMPUTERNAME


# Create the object on the RGM server
$NewHost = New-RGMHost -hostName $Hostname -hostIp $PrincipaleIP
$NewHost.result

# Call MetricBeat Install
if ($NoMetricBeat) { }else {
    powershell.exe -executionpolicy bypass -Command $([Scriptblock]::Create((New-Object System.Net.WebClient).DownloadString("https://$RGMServer/distrib/install/Install-MetricBeat.ps1")))
}

# Ready to add other install options
if ($AuditBeat) {
    powershell.exe -executionpolicy bypass -Command $([Scriptblock]::Create((New-Object System.Net.WebClient).DownloadString("https://$RGMServer/distrib/install/Install-AuditBeat.ps1")))

}
# Ready to add other install options
if ($InstallSomething) {


}