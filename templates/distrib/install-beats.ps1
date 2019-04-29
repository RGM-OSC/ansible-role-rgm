#Requires -RunAsAdministrator

function Test-Administrator  
{  
    $user = [Security.Principal.WindowsIdentity]::GetCurrent();
    (New-Object Security.Principal.WindowsPrincipal $user).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)  
}

If (($PSVersionTable.PSVersion).Major -le 3){
    If (Test-Administrator -eq $false) {
        Write-Host "The script must launched with Administrator privileges"
        exit 1
    }
}
$MetricBeatFileDownloadLink = "https://{{ ansible_default_ipv4.address }}/distrib/packages/metricbeat-oss-latest-windows-x86_64.zip"
$MetricBeatConfFileLink = "https://{{ ansible_default_ipv4.address }}/distrib/conf/metricbeat/metricbeat.yml"
# {{ ansible_default_ipv4.address }}
######  Download Part #######

$MetricBeatFileName = ($MetricBeatFileDownloadLink -split ("/"))[-1]
$MetricBeatFoldername = $MetricBeatFileName.Replace(".zip", "")

### SSL Bypass process
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

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Invoke-WebRequest -Uri $MetricBeatFileDownloadLink -OutFile .\$MetricBeatFileName -Verbose

######  Unzip Part #######

# Creation of the Destination zipfolder 
$DestinationUnZIPFolder=(new-item -Name $MetricBeatFoldername -ItemType Directory).FullName

# UnZIP MetricBeat
If (($PSVersionTable.PSVersion).Major -le 4) {
    # oldest Powershell version (4 and oldest ) use old unzip methode
    $SourceFile = (Get-ChildItem -filter $MetricBeatFileName -File).FullName
    $shell_app=new-object -com shell.application
    $zip_file = $shell_app.namespace($SourceFile)
    $destination = $shell_app.namespace($DestinationUnZIPFolder)
    # Copyhere option 16 (Respond Yes to all) + 4 (do not display progress dialog box)
    $destination.Copyhere($zip_file.items(),20)
}else{
# Most recent Powershell version
Expand-Archive -Path .\$MetricBeatFileName -DestinationPath $DestinationUnZIPFolder -Force
}


######  Destination Folder Part #######
# Create folder C:\Program Files\MetricBeat if not existe
if ((Test-Path "C:\Program Files\MetricBeat") -eq $false) {
    try {
        New-Item -Path "C:\Program Files\MetricBeat" -Type "directory"
    }
    catch {
        Write-Host "The folder C:\Program Files\MetricBeat can't be created"
        # Add cleaning steps or test before download
        exit 1
    }
}

######  Service check befor copy Part #######
# If the service MetricBeat already existe, stop to be able to replace all content
if (get-service metricbeat -ErrorAction SilentlyContinue){Stop-Service metricbeat}

######  Copy Part #######
# Copie of download/unzipped folder to Program file. Option force used to force remplacement files
$TempfolderContent = Get-ChildItem $DestinationUnZIPFolder
# TO DO  -> Check if force option not to much and could replace conffiles...
Copy-Item -Path "$($TempfolderContent.FullName)\*" -Destination "C:\Program Files\MetricBeat" -Recurse -Force


######  Service Creation part #######

If (($PSVersionTable.PSVersion).Major -le 4) {
    #  # oldest Powershell version (4 and oldest ) use old service management methode
    # delete the service if exist
    if (Get-Service metricbeat -ErrorAction SilentlyContinue) {
        $service = Get-WmiObject -Class Win32_Service -Filter "name='metricbeat'"
        $service.StopService()
        Start-Sleep -s 1
        $service.delete()
      }
    
    # install the new version of the service
    $serviceName="metricbeat"
    $displayName="metricbeat"
    $path='"C:\Program Files\MetricBeat\metricbeat.exe" -c "C:\Program Files\MetricBeat\metricbeat.yml" -path.home "C:\Program Files\MetricBeat" -path.data "C:\ProgramData\metricbeat" -path.logs "C:\ProgramData\metricbeat\logs"'
    $startMode = "Automatic"
    $interactWithDesktop= $false
    $params = $serviceName, $displayName, $path, 16, 1, $startMode, $interactWithDesktop, $null, $null, $null, $null, $null           
    
	$scope = new-object System.Management.ManagementScope("\\localhost\root\cimv2", (new-object System.Management.ConnectionOptions))
    $scope.Connect()
    $mgt = new-object System.Management.ManagementClass($scope, (new-object System.Management.ManagementPath("Win32_Service")), (new-object System.Management.ObjectGetOptions))
    $null = $mgt.InvokeMethod("Create", $params)    

}Else{
    # Powershell V5 and most recent, ability to use the integrated install service script
    . 'C:\Program Files\MetricBeat\install-service-metricbeat.ps1'
}

######  MetricBeat configuration part #######

# Collect current IP address
$IPaddress = (Test-Connection ::1 -Cou 1).IPV4Address.IPAddressToString

# load current Configuration File -> TO DO -> load from RGM
$ConfigurationFilePath = "C:\Program Files\MetricBeat\metricbeat.yml"

Invoke-WebRequest -Uri $MetricBeatConfFileLink -OutFile $ConfigurationFilePath -Verbose
$ConfigurationFileContent = Get-Content $ConfigurationFilePath
$ConfigurationFileContent = $ConfigurationFileContent -replace ("%%IP%%",$IPaddress)
Set-Content -Path $ConfigurationFilePath -Value $ConfigurationFileContent


# start the service
start-service metricbeat

# Clean installation folder -> (TO DO -> funtion to be able to call it in case of failure)
Remove-Item .\$MetricBeatFileName
Remove-Item $DestinationUnZIPFolder -Recurse