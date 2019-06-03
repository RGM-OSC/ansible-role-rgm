[cmdletbinding()]
param (
    [String]$username,
    [String]$password,
    [String]$token,
    [String]$RGMServer="{{ ansible_default_ipv4.address }}",
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

function get-RGMApiToken {
    param (
        [String]$username,
        [String]$password,
        [String]$RGMServer
    )
       
    $UriAuthent = "https://$RGMServer/rgmapi/getAuthToken?&username=$username&password=$password"

    $TokenReturn = Invoke-RestMethod -Uri $UriAuthent -Method GET  -Headers $Header
    $token = $TokenReturn.RGMAPI_TOKEN
    return $token
}


function new-RGMHost {
    param (
        [String]$username,
        [String]$token,
        [String]$RGMServer,
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

    $UriCreateHost = "https://$RGMServer/rgmapi/createHost?&username=$username&token=$token"

    $NewHost = Invoke-RestMethod -Uri $UriCreateHost -Method Post -Body $CreateHostBody -Headers $Header
    return $NewHost
}


# found active IP address
$interfaces = Get-NetRoute -DestinationPrefix 0.0.0.0/0 # Search Interfaces with gateway to go out
$ActiveInterface = $interfaces | Get-NetIPInterface | where-object { $_.ConnectionState -eq "Connected" } # filter to keep active interface
$PrincipaleIP = Get-NetIPAddress -InterfaceIndex $ActiveInterface.InterfaceIndex -AddressFamily IPV4 | Select-Object -ExpandProperty IPaddress
# Collect current computername
$Hostname = $env:COMPUTERNAME


if($token){}else{
# Request the API Key
$token = get-RGMApiToken -username $username -password $password -RGMServer $RGMServer
}
# Create the object on the RGM server
$NewHost = new-RGMHost -username $username -token $token -RGMServer $RGMServer -hostName $Hostname -hostIp $PrincipaleIP
$NewHost.result

# Call MetricBeat Install
powershell.exe -executionpolicy bypass -Command $([Scriptblock]::Create((New-Object System.Net.WebClient).DownloadString("https://$RGMServer/distrib/install/Install-MetricBeat.ps1")))

# Ready to add other install options
if($AuditBeat){
    powershell.exe -executionpolicy bypass -Command $([Scriptblock]::Create((New-Object System.Net.WebClient).DownloadString("https://$RGMServer/distrib/install/Install-AuditBeat.ps1")))

}
# Ready to add other install options
if($InstallSomething){


}