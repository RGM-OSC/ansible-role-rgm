[cmdletbinding()]
param (
    [Parameter(Mandatory = $true, ParameterSetName = "Username")]
    [String]$Username,
    [Parameter(Mandatory = $true, ParameterSetName = "Username")]
    [String]$Password,
    [Parameter(Mandatory = $true, ParameterSetName = "OneTimeToken")]
    [String]$OneTimeToken,
    [String]$RGMServer = "{{ ansible_default_ipv4.address }}",
    [String]$RGMTemplate = "RGM_WINDOWS_ES",
    [String]$HostAlias,
    [String[]]$Agents,
    [String]$BeatsBasePath = "{{ winbeats_base_path }}",
    [Switch]$NoBeat,
    [Switch]$NoExportConfig = $false,
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
    Write-Verbose "Header default Construct with Token"
    $script:Header = @{
        "Content-Type" = "application/json"
        "token"        = $OneTimeToken
    }
}
Else {
    Write-Verbose "Header default Construct without Token"
    $script:Header = @{
        "Content-Type" = "application/json"
    }
}

function Get-RGMApiToken {

    $UriAuthent = "https://$RGMServer/rgmapi/getAuthToken?&username=$Username&password=$Password"

    try {
        $TokenReturn = Invoke-RestMethod -Uri $UriAuthent -Method GET -Headers $script:Header
    }
    catch {
        write-host "Error during API Call`n$($Error[0])`nScript Exit"
        Break;
    }
    Write-Verbose "New Token = $($TokenReturn.RGMAPI_TOKEN)"

    # Update the current header with the current active token
    $script:Header = @{
        "Content-Type" = "application/json"
        "token"        = $TokenReturn.RGMAPI_TOKEN
    }
}


function Test-RGMApiToken {

    $UriTokenCheck = "https://$RGMServer/rgmapi/checkAuthToken"
    try {
        $null = Invoke-RestMethod -Uri $UriTokenCheck -Method GET -Headers $script:Header
    }
    catch {
        Write-Verbose "Token non valide"
        return $false
    }
    Write-Verbose "Token valide"
    return $true
}

function Invoke-RGMRestMethod {
    param (
        [String]$Uri,
        [String]$Methode,
        [String]$Body
    )
    if (!(Test-RGMApiToken)) {
        if ($Password) {
            Write-Verbose $($Header | ConvertTo-Json)
            Write-Verbose "Request token with password"
            Get-RGMApiToken
            Write-Verbose $($Header | ConvertTo-Json)
        }
        elseif ($OneTimeToken) {
            Write-Output "The OnTimeToken is not valid`nEnd of script"
            Break;
        }
        else {
            Write-Output "There is an unexpected error (no password or no OneTimeToken provided)`nEnd of script"
            Break;
        }
    }
    try {
        if ($Methode -eq "Get") {
            return (Invoke-RestMethod -Uri $Uri -Method Get -Headers $script:Header)
        }
        else {
            return (Invoke-RestMethod -Uri $Uri -Method $Methode -Body $Body -Headers $script:Header)
        }
    }
    catch {
        write-host "Error during API Call`n$($Error[0])`nScript Exit"
        Break;

    }
}


function New-RGMHost {
    param (
        [String]$templateHostName = "RGM_WINDOWS_ES",
        [String]$hostName,
        [String]$hostIp,
        [String]$hostAlias = "",
        [Switch]$NoExportConfig#,
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
    Write-Verbose $CreateHostBody

    $UriCreateHost = "https://$RGMServer/rgmapi/createHost"

    $NewHost = Invoke-RGMRestMethod -Uri $UriCreateHost -Method Post -Body $CreateHostBody 
    if ($NoExportConfig) {
        Write-Verbose "no export config!"
    }
    else {
        $ExportConfigBody = @{
            "jobName" = "Nagios Export"
        } | ConvertTo-Json
        Write-Verbose "Launch ExportConfig"

        $UriExportConfig = "https://$RGMServer/rgmapi/exportConfiguration"
        $ExportConfig = Invoke-RGMRestMethod -Uri $UriExportConfig -Method Post -Body $ExportConfigBody
        Write-Verbose $($ExportConfig | Out-String)
    }

    return $NewHost
}


# found active IP address
$interfaces = Get-NetRoute -DestinationPrefix 0.0.0.0/0 | Sort-Object ifIndex | select-object -first 1 # Search Interfaces with gateway to go out and filter on the first lower Index - avoid multi card and a gateway on each card
$ActiveInterface = $interfaces | Get-NetIPInterface | where-object { $_.ConnectionState -eq "Connected" } # filter to keep active interface
$PrincipaleIP = Get-NetIPAddress -InterfaceIndex $ActiveInterface.InterfaceIndex -AddressFamily IPV4 | Select-Object -ExpandProperty IPaddress
# Collect current computername
$Hostname = Get-WmiObject -Class Win32_ComputerSystem -Property DNSHostName | Select-Object -ExpandProperty DNSHostName
Write-Verbose "Hostname: $Hostname, IP: $PrincipaleIP"

# Use Hostname for HostAlias value if HostAlias value notdefined
if ($HostAlias) {
    #Do Nothing
}
else {
    $HostAlias = $Hostname
}
Write-Verbose "HostAlias: $HostAlias"

# Create the object on the RGM server
try {
    $NewHost = New-RGMHost -hostName $Hostname -hostIp $PrincipaleIP -templateHostName $RGMTemplate -hostAlias $HostAlias -NoExportConfig:$NoExportConfig
    $NewHost.result
}
catch {
    Write-host "Error: unable to register the host on EON`n$Error[0]"
    Break;
}

# Call MetricBeat Install
if ($NoBeat) { 
    Write-Verbose "Beat Agents installation bypassed"
}
else {
    Write-Verbose "Beat Agents installation"
    $arguments = @{
        RGMServer = $RGMServer
    }
    if ($BeatsBasePath) {
        $arguments.BeatsBasePath = $BeatsBasePath
    }
    if ($Agents) {
        $arguments.Agents = $Agents
    }
    if ($VerbosePreference -eq "Continue") {
        $arguments.Verbose = $true
    }
    $argumentdisplay = $arguments | Out-String
    Write-Verbose -message "launch Beat Agents installation with arguments : $argumentdisplay"
    try {
        & $([Scriptblock]::Create((New-Object System.Net.WebClient).DownloadString("https://$RGMServer/distrib/install/Install-Beats.ps1"))) @arguments
    }
    catch {
        write-host "Error during Install-Beat launch program`n$($Error[0])`nScript Exit"
        Break;
    }
}

# Ready to add other install options
# Ready to add other install options
if ($InstallSomething) {
    Write-Verbose "Something installation"

}

Write-Verbose "End of add-host script"