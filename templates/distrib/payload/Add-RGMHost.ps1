[cmdletbinding()]
param (
    [String]$username,
    [String]$password,
   # [String]$token,
    [String]$RGMServer="{{ ansible_default_ipv4.address }}",
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

$Header = @{
    "Content-Type" = "application/json"
}

function Get-RGMApiToken {
#    param (
#        [String]$username,
#        [String]$password,
#        [String]$RGMServer
#    )
       
    $UriAuthent = "https://$RGMServer/rgmapi/getAuthToken?&username=$username&password=$password"

    $TokenReturn = Invoke-RestMethod -Uri $UriAuthent -Method GET -Headers $Header
    $script:token = $TokenReturn.RGMAPI_TOKEN
#    return $token
}


function Test-RGMApiToken {
#   param (
#    [String]$token,
 #   [String]$RGMServer
  #  )

    $UriTokenCheck = "https://$RGMServer/rgmapi/checkAuthToken?token=$token"
    try{
    $null = Invoke-RestMethod -Uri $UriTokenCheck -Method GET -Headers $Header
    }
    catch{
        return $false
    }
    return $true
}

function Invoke-RGMRestMethod {
    param (
#        [String]$token,
 #       [String]$RGMServer,
        [String]$Uri,
        [String]$Methode,
        [String]$Body
    )
    if (!(Test-RGMApiToken)) {
        Get-RGMApiToken
    }

    $UriWithAuth = $Uri + "?&username=$username&token=$token"
    if ($Methode -eq "Get") {
        return (Invoke-RestMethod -Uri $UriWithAuth -Method Get -Headers $Header)
    }
    else {
        $token
        return (Invoke-RestMethod -Uri $UriWithAuth -Method $Methode -Body $Body -Headers $Header)
    }
}


function New-RGMHost {
    param (
#        [String]$username,
#        [String]$token,
#        [String]$RGMServer,
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


#if($token){}else{
# Request the API Key
#$token = get-RGMApiToken # -username $username -password $password -RGMServer $RGMServer
#}
# Create the object on the RGM server
$NewHost = New-RGMHost -hostName $Hostname -hostIp $PrincipaleIP #-username $username -token $FreshToken -RGMServer $RGMServer 
$NewHost.result

# Call MetricBeat Install
if($NoMetricBeat){}else{
    powershell.exe -executionpolicy bypass -Command $([Scriptblock]::Create((New-Object System.Net.WebClient).DownloadString("https://$RGMServer/distrib/install/Install-MetricBeat.ps1")))
}

# Ready to add other install options
if($AuditBeat){
    powershell.exe -executionpolicy bypass -Command $([Scriptblock]::Create((New-Object System.Net.WebClient).DownloadString("https://$RGMServer/distrib/install/Install-AuditBeat.ps1")))

}
# Ready to add other install options
if($InstallSomething){


}