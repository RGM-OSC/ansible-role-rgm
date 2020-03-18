#Requires -RunAsAdministrator
[cmdletbinding()]
Param(
	[String]$RGMServer = "{{ ansible_default_ipv4.address }}"
)

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

$WinLogBeatFileDownloadLink = "https://$RGMServer/distrib/packages/winlogbeat-oss-latest-windows-x86_64.zip"
# $WinLogBeatConfFileLink = "https://$RGMServer/distrib/conf/windows_winlogbeat.yml"
# $WinLogBeatConfRGMsystemcoreLink = "https://$RGMServer/distrib/conf/modules/windows_rgm-system-core.yml"
# $WinLogBeatConfRGMsystemfsLink = "https://$RGMServer/distrib/conf/modules/windows_rgm-system-fs.yml"
# $WinLogBeatConfRGMsystemuptimeLink = "https://$RGMServer/distrib/conf/modules/windows_rgm-system-uptime.yml"

$WinLogBeatBasePath="{{ winbeats_base_path }}"
# $RGMServer
######  Download Part #######

$WinLogBeatFileName = ($WinLogBeatFileDownloadLink -split ("/"))[-1]
$WinLogBeatFoldername = $WinLogBeatFileName.Replace(".zip", "")

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

#Donwload WinLogBeat zip file mode (New-Object System.Net.WebClient).DownloadFile is very fastest than Invoke-WebRequest
$DownloadPathName = (Get-Location).Path , $WinLogBeatFileName -join "\"
(New-Object System.Net.WebClient).DownloadFile($WinLogBeatFileDownloadLink, $DownloadPathName)

######  Unzip Part #######

# Creation of the Destination zip folder 
$DestinationUnZIPFolder=(new-item -Name $WinLogBeatFoldername -ItemType Directory).FullName

# UnZIP WinLogBeat
If (($PSVersionTable.PSVersion).Major -le 4) {
	# oldest Powershell version (4 and oldest ) use old unzip methode
	$SourceFile = (Get-ChildItem -filter $WinLogBeatFileName -File).FullName
	$shell_app=new-object -com shell.application
	$zip_file = $shell_app.namespace($SourceFile)
	$destination = $shell_app.namespace($DestinationUnZIPFolder)
	# Copyhere option 16 (Respond Yes to all) + 4 (do not display progress dialog box)
	$destination.Copyhere($zip_file.items(),20)
}else{
# Most recent Powershell version
	Expand-Archive -Path .\$WinLogBeatFileName -DestinationPath $DestinationUnZIPFolder -Force
}


######  Destination Folder Part #######
# Create folder $WinLogBeatBasePath\WinLogBeat if not existe
if ((Test-Path "$WinLogBeatBasePath\WinLogBeat") -eq $false) {
	try {
		New-Item -Path "$WinLogBeatBasePath\WinLogBeat" -Type "directory"
	}
	catch {
		Write-Host "The folder $WinLogBeatBasePath\WinLogBeat can't be created"
		# Add cleaning steps or test before download
		exit 1
	}
}

######  Service check before copy Part #######
# If the service WinLogBeat already existe, stop to be able to replace all content
if (get-service winlogbeat -ErrorAction SilentlyContinue){Stop-Service WinLogBeat}

######  Copy Part #######
# Copie of download/unzipped folder to Program file. Option force used to force remplacement files
$TempfolderContent = Get-ChildItem $DestinationUnZIPFolder
# TO DO  -> Check if force option not to much and could replace conffiles...
Copy-Item -Path "$($TempfolderContent.FullName)\*" -Destination "$WinLogBeatBasePath\WinLogBeat" -Recurse -Force

######  WinLogBeat configuration part #######


# # Get RGM-ready config file from RGM server distrib repository 
$ConfigurationFilePath = "$WinLogBeatBasePath\WinLogBeat\winlogbeat.yml"

# # dynamically insert host IP address as a beat "fields" into config
(New-Object System.Net.WebClient).DownloadFile($WinLogBeatConfFileLink, $ConfigurationFilePath)
# $ConfigurationFileContent = Get-Content $ConfigurationFilePath
# $ConfigurationFileContent = $ConfigurationFileContent -replace ("%%IP%%",$IPaddress)
# Set-Content -Path $ConfigurationFilePath -Value $ConfigurationFileContent

# # Disable the default system module
# $SystemModulePath = "$WinLogBeatBasePath\WinLogBeat\modules.d\system.yml"
# if (Test-Path $SystemModulePath){
# 	Rename-Item -Path $SystemModulePath -NewName "system.yml.disabled"
# }

######  Service Creation part #######

If (($PSVersionTable.PSVersion).Major -le 4) {
	#  # oldest Powershell version (4 and oldest ) use old service management methode
	# delete the service if exist
	if (Get-Service WinLogBeat -ErrorAction SilentlyContinue) {
		$service = Get-WmiObject -Class Win32_Service -Filter "name='winlogbeat'"
		$service.StopService()
		Start-Sleep -s 1
		$service.delete()
	}
	
	# install the new version of the service
	$serviceName="winlogbeat"
	$displayName="winlogbeat"
	$path = """$WinLogBeatBasePath\WinLogBeat\WinLogBeat.exe"" -c ""$WinLogBeatBasePath\WinLogBeat\WinLogBeat.yml"" -path.home ""$WinLogBeatBasePath\WinLogBeat"" -path.data ""C:\ProgramData\WinLogBeat"" -path.logs ""$WinLogBeatBasePath\WinLogBeat\logs"""
	$startMode = "Automatic"
	$interactWithDesktop= $false
	$params = $serviceName, $displayName, $path, 16, 1, $startMode, $interactWithDesktop, $null, $null, $null, $null, $null           
	
	$scope = new-object System.Management.ManagementScope("\\localhost\root\cimv2", (new-object System.Management.ConnectionOptions))
	$scope.Connect()
	$mgt = new-object System.Management.ManagementClass($scope, (new-object System.Management.ManagementPath("Win32_Service")), (new-object System.Management.ObjectGetOptions))
	$null = $mgt.InvokeMethod("Create", $params)
	Try {
		Start-Process -FilePath sc.exe -ArgumentList 'config winlogbeat start= delayed-auto'
	}
	Catch { Write-Host -f red "An error occured setting the service to delayed start."
	}

}Else{
	# Powershell V5 and most recent, ability to use the integrated install service script but replace the log folder destination
	$InstallServiceFilePath = "$WinLogBeatBasePath\WinLogBeat\install-service-WinLogBeat.ps1"
	$setupfile = Get-Content $InstallServiceFilePath
	$setupfile = $setupfile -replace ("C:\\ProgramData\\winlogbeat\\logs",'$workdir\WinLogBeat\logs')
	set-Content $InstallServiceFilePath -Value $setupfile
	Powershell -executionpolicy bypass -file $InstallServiceFilePath
}

# start the service
start-service winlogbeat -PassThru
# on some case, the PassThru is not displayed. call the get-service to avec the exact service status
get-service winlogbeat

# Clean installation folder -> (TO DO -> funtion to be able to call it in case of failure)
Remove-Item .\$WinLogBeatFileName
Remove-Item $DestinationUnZIPFolder -Recurse
exit