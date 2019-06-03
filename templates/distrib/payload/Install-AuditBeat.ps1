#Requires -RunAsAdministrator
[cmdletbinding()]
Param()

function Test-Administrator  
{  
	$user = [Security.Principal.WindowsIdentity]::GetCurrent();
	(New-Object Security.Principal.WindowsPrincipal $user).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)  
}

If (($PSVersionTable.PSVersion).Major -le 3){
	If (Test-Administrator -eq $false) {
		Write-Host "The script require Administrator privileges"
		exit 1
	}
}

$AuditBeatFileDownloadLink = "https://{{ ansible_default_ipv4.address }}/distrib/packages/auditbeat-oss-latest-windows-x86_64.zip"
$AuditBeatConfFileLink = "https://{{ ansible_default_ipv4.address }}/distrib/conf/windows_auditbeat.yml"
$AuditBeatBasePath="{{ winbeats_base_path }}"
# {{ ansible_default_ipv4.address }}
######  Download Part #######

$AuditBeatFileName = ($AuditBeatFileDownloadLink -split ("/"))[-1]
$AuditBeatFoldername = $AuditBeatFileName.Replace(".zip", "")

### SSL Bypass process
if ("TrustAllCertsPolicy" -as [type]) {} else{
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

#Donwload AuditBeat zip file mode (New-Object System.Net.WebClient).DownloadFile is very fastest than Invoke-WebRequest
$DownloadPathName = (Get-Location).Path , $AuditBeatFileName -join "\"
(New-Object System.Net.WebClient).DownloadFile($AuditBeatFileDownloadLink, $DownloadPathName)

######  Unzip Part #######

# Creation of the Destination zip folder 
$DestinationUnZIPFolder=(new-item -Name $AuditBeatFoldername -ItemType Directory).FullName

# UnZIP AuditBeat
If (($PSVersionTable.PSVersion).Major -le 4) {
	# oldest Powershell version (4 and oldest ) use old unzip methode
	$SourceFile = (Get-ChildItem -filter $AuditBeatFileName -File).FullName
	$shell_app=new-object -com shell.application
	$zip_file = $shell_app.namespace($SourceFile)
	$destination = $shell_app.namespace($DestinationUnZIPFolder)
	# Copyhere option 16 (Respond Yes to all) + 4 (do not display progress dialog box)
	$destination.Copyhere($zip_file.items(),20)
}else{
# Most recent Powershell version
	Expand-Archive -Path .\$AuditBeatFileName -DestinationPath $DestinationUnZIPFolder -Force
}


######  Destination Folder Part #######
# Create folder $AuditBeatBasePath\AuditBeat if not existe
if ((Test-Path "$AuditBeatBasePath\AuditBeat") -eq $false) {
	try {
		New-Item -Path "$AuditBeatBasePath\AuditBeat" -Type "directory"
	}
	catch {
		Write-Host "The folder $AuditBeatBasePath\AuditBeat can't be created"
		# Add cleaning steps or test before download
		exit 1
	}
}

######  Service check before copy Part #######
# If the service AuditBeat already existe, stop to be able to replace all content
if (get-service auditbeat -ErrorAction SilentlyContinue){Stop-Service auditbeat}

######  Copy Part #######
# Copie of download/unzipped folder to Program file. Option force used to force remplacement files
$TempfolderContent = Get-ChildItem $DestinationUnZIPFolder
# TO DO  -> Check if force option not to much and could replace conffiles...
Copy-Item -Path "$($TempfolderContent.FullName)\*" -Destination "$AuditBeatBasePath\AuditBeat" -Recurse -Force

######  AuditBeat configuration part #######

# Collect current IP address
$IPaddress = Get-WmiObject -class Win32_NetworkAdapterConfiguration -Filter "IpEnabled = 'True' " | Where-Object {$_.DefaultIPGateway -ne $null} | Select-Object -ExpandProperty IPaddress | Select-Object -First 1

# Get RGM-ready config file from RGM server distrib repository 
$ConfigurationFilePath = "$AuditBeatBasePath\AuditBeat\auditbeat.yml"

# dynamically insert host IP address as a beat "fields" into config
(New-Object System.Net.WebClient).DownloadFile($AuditBeatConfFileLink, $ConfigurationFilePath)
$ConfigurationFileContent = Get-Content $ConfigurationFilePath
$ConfigurationFileContent = $ConfigurationFileContent -replace ("%%IP%%",$IPaddress)
Set-Content -Path $ConfigurationFilePath -Value $ConfigurationFileContent

######  Service Creation part #######

If (($PSVersionTable.PSVersion).Major -le 4) {
	#  # oldest Powershell version (4 and oldest ) use old service management methode
	# delete the service if exist
	if (Get-Service auditbeat -ErrorAction SilentlyContinue) {
		$service = Get-WmiObject -Class Win32_Service -Filter "name='auditbeat'"
		$service.StopService()
		Start-Sleep -s 1
		$service.delete()
	}
	
	# install the new version of the service
	$serviceName="auditbeat"
	$displayName="auditbeat"
	$path = """$AuditBeatBasePath\AuditBeat\auditbeat.exe"" -c ""$AuditBeatBasePath\AuditBeat\auditbeat.yml"" -path.home ""$AuditBeatBasePath\AuditBeat"" -path.data ""C:\ProgramData\auditbeat"" -path.logs ""C:\ProgramData\auditbeat\logs"""
	$startMode = "Automatic"
	$interactWithDesktop= $false
	$params = $serviceName, $displayName, $path, 16, 1, $startMode, $interactWithDesktop, $null, $null, $null, $null, $null           
	
	$scope = new-object System.Management.ManagementScope("\\localhost\root\cimv2", (new-object System.Management.ConnectionOptions))
	$scope.Connect()
	$mgt = new-object System.Management.ManagementClass($scope, (new-object System.Management.ManagementPath("Win32_Service")), (new-object System.Management.ObjectGetOptions))
	$null = $mgt.InvokeMethod("Create", $params)    

}Else{
	# Powershell V5 and most recent, ability to use the integrated install service script
	Powershell -executionpolicy bypass -file "$AuditBeatBasePath\AuditBeat\install-service-auditbeat.ps1"
}

# start the service
start-service auditbeat -PassThru
# on some case, the PassThru is not displayed. call the get-service to avec the exact service status
get-service auditbeat

# Clean installation folder -> (TO DO -> funtion to be able to call it in case of failure)
Remove-Item .\$AuditBeatFileName
Remove-Item $DestinationUnZIPFolder -Recurse
exit