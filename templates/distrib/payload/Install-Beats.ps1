#Requires -RunAsAdministrator
[cmdletbinding()]
Param(
	[String]$RGMServer = "{{ ansible_default_ipv4.address }}",
	[String]$BeatsBasePath = "{{ winbeats_base_path }}",
	[String[]]$Agents
)
function Test-Administrator  
{  
	$user = [Security.Principal.WindowsIdentity]::GetCurrent();
	(New-Object Security.Principal.WindowsPrincipal $user).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)  
}

If (($PSVersionTable.PSVersion).Major -le 3){
	If (Test-Administrator -eq $false) {
		Write-Information -MessageData "The script require Administrator privileges" -InformationAction Continue
		exit 1
	}
}

###############  Variables  ###############

$AgentsDetails =
@"
[
    {
		"agent": "metricbeat",
		"servicename": "metricbeat",
		"foldername": "MetricBeat",
		"modules": ["windows_rgm-system-core.yml","windows_rgm-system-fs.yml","windows_rgm-system-uptime.yml"]
    },
    {
        "agent": "winlogbeat",
        "servicename": "winlogbeat",
        "foldername": "WinLogBeat"
    },
    {
        "agent": "auditbeat",
        "servicename": "auditbeat",
        "foldername": "AuditBeat"
    },
    {
        "agent": "filebeat",
        "servicename": "filebeat",
        "foldername": "FileBeat"
    },
    {
        "agent": "heartbeat",
        "servicename": "heartbeat",
        "foldername": "HeartBeat"
    }
]
"@ | ConvertFrom-Json

###############  Script  ###############

# Valide the Agent liste to install
$ValidBeats = $AgentsDetails.agent
$Agents += "metricbeat"
$BeatsListCompare = Compare-Object -ReferenceObject $ValidBeats -DifferenceObject $($Agents | Select-Object -Unique )-IncludeEqual
# Generate list of effective agent to install
$Beatstoinstall = $BeatsListCompare | Where-Object {$_.SideIndicator -eq "=="} | Select-Object -ExpandProperty InputObject
# Generate list of rejected aget names
$BeatsFailed = $BeatsListCompare | Where-Object {$_.SideIndicator -eq "=>"} | Select-Object -ExpandProperty InputObject
foreach ($BeatFailed in $BeatsFailed) {
	Write-Information -MessageData "$BeatFailed is not a valide agent name or not managed yet" -InformationAction Continue
}


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

#  Agent installation Loop
foreach ($Beattoinstall in $Beatstoinstall) {
	# generate agent variables in the loop
	$AgentDetail = $AgentsDetails | Where-Object { $_.agent -eq $Beattoinstall }
	$AgentName = $AgentDetail.agent
	$AgentServiceName = $AgentDetail.servicename
	$AgentfolderPath = $BeatsBasePath + "\" + $AgentDetail.foldername
	Write-Information -MessageData "Installation of the $AgentName agent" -InformationAction Continue

	# generate download links
	$BeatFileDownloadLink = "https://$RGMServer/distrib/packages/$AgentName-oss-latest-windows-x86_64.zip"
	$BeatConfFileLink = "https://$RGMServer/distrib/conf/windows_$AgentName.yml"
	
	# generate files names and local path variables
	$BeatFileName = ($BeatFileDownloadLink -split ("/"))[-1]
	$BeatConfFileName = ($BeatConfFileLink -split ("/"))[-1]
	$BeatFoldername = $BeatFileName.Replace(".zip", "")
	$ConfigurationFilePath = "$AgentfolderPath\$BeatConfFileName" -replace ("windows_")

	# Donwload the zip file agent (New-Object System.Net.WebClient).DownloadFile is very fastest than Invoke-WebRequest
	$DownloadPathName = (Get-Location).Path , $BeatFileName -join "\"
	(New-Object System.Net.WebClient).DownloadFile($BeatFileDownloadLink, $DownloadPathName)

	######  Unzip Part #######

	# Create the Destination zip folder 
	$DestinationUnZIPFolder=(new-item -Name $BeatFoldername -ItemType Directory).FullName

	# UnZIP MetricBeat
	# Manage unzip depending Powershell Version
	If (($PSVersionTable.PSVersion).Major -le 4) {
		# oldest Powershell version (4 and oldest ) use old unzip methode
		$SourceFile = (Get-ChildItem -filter $BeatFileName -File).FullName
		$shell_app=new-object -com shell.application
		$zip_file = $shell_app.namespace($SourceFile)
		$destination = $shell_app.namespace($DestinationUnZIPFolder)
		# Copyhere option 16 (Respond Yes to all) + 4 (do not display progress dialog box)
		$destination.Copyhere($zip_file.items(),20)
	}else{
	# Most recent Powershell version
		Expand-Archive -Path .\$BeatFileName -DestinationPath $DestinationUnZIPFolder -Force
	}

	######  Destination Folder Part #######
	# Create folder $BeatBasePath\MetricBeat if not existe
	if ((Test-Path $AgentfolderPath) -eq $false) {
		try {
			New-Item -Path $AgentfolderPath -Type "directory"
		}
		catch {
			Write-Information - "The folder $AgentfolderPath can't be created"
			#
			exit 1
		}
	}


	######  Service check before copy Part #######
	# If the service MetricBeat already existe, stop to be able to replace all content
	if (get-service $AgentServiceName -ErrorAction SilentlyContinue){
		Write-Verbose -Message "Stop $AgentServiceName service before install / update"
		Stop-Service $AgentServiceName
		Start-Sleep -s 1
	}

	######  Copy Part #######
	# Copie of download/unzipped folder to Program file. Option force used to force remplacement files
	# If other file existe, it is keeped.
	$TempfolderContent = Get-ChildItem $DestinationUnZIPFolder
	Copy-Item -Path "$($TempfolderContent.FullName)\*" -Destination $AgentfolderPath -Recurse -Force
	
	# Download dedicated Agent configuration file from RGM
	(New-Object System.Net.WebClient).DownloadFile($BeatConfFileLink, $ConfigurationFilePath)

	# Part depending of the agent
	switch ($AgentName) {
		metricbeat { 
			# Dedicated part of the metricbeat agent
			Write-Verbose -Message "tunning of metricbeat agent"

			# Collect current IP address
			$IPaddress = Get-WmiObject -class Win32_NetworkAdapterConfiguration -Filter "IpEnabled = 'True' " | Where-Object {$_.DefaultIPGateway -ne $null} | Select-Object -ExpandProperty IPaddress | Select-Object -First 1

			# dynamically insert host IP address as a beat "fields" into config
			$ConfigurationFileContent = Get-Content $ConfigurationFilePath
			$ConfigurationFileContent = $ConfigurationFileContent -replace ("%%IP%%",$IPaddress)
			Set-Content -Path $ConfigurationFilePath -Value $ConfigurationFileContent

			# Rgm module adjustement
			# Loop to download all rgm dedicated module for metricbeat to the module.d folder
			foreach ($module in $AgentDetail.modules) {
				$BeatConfRGMLink = "https://$RGMServer/distrib/conf/modules/$module"
				$BeatDestFileName = $module -replace ("windows_")
				$BeatConfPath = $AgentfolderPath + "\modules.d\" + $BeatDestFileName
				(New-Object System.Net.WebClient).DownloadFile($BeatConfRGMLink, $BeatConfPath)
			}

			# Disable the default system module
			$SystemModulePath = "$AgentfolderPath\modules.d\system.yml"
			if (Test-Path $SystemModulePath){
				# Use Move-item instead of rename-item to bypass if file already exist
				Move-Item  -Path $SystemModulePath -Destination $($SystemModulePath -replace (".yml",".yml.disabled")) -force
			}

		}
		Default {}
	}

	######  Service Creation part #######

	If (($PSVersionTable.PSVersion).Major -le 4) {
		#  # oldest Powershell version (4 and oldest ) use old service management methode
		# delete the service if exist
		if (Get-Service $AgentServiceName -ErrorAction SilentlyContinue) {
			$service = Get-WmiObject -Class Win32_Service -Filter "name=$AgentServiceName"
			$service.StopService()
			Start-Sleep -s 1
			$service.delete()
		}

		# install the new version of the service
		$displayName = $AgentServiceName
		$path = """$AgentfolderPath\$AgentName.exe"" -c ""$AgentfolderPath\$AgentName.yml"" -path.home ""$AgentfolderPath"" -path.data ""C:\ProgramData\$AgentName"" -path.logs ""$AgentfolderPath\logs"""
		$startMode = "Automatic"
		$interactWithDesktop= $false
		$params = $AgentServiceName, $displayName, $path, 16, 1, $startMode, $interactWithDesktop, $null, $null, $null, $null, $null           

		$scope = new-object System.Management.ManagementScope("\\localhost\root\cimv2", (new-object System.Management.ConnectionOptions))
		$scope.Connect()
		$mgt = new-object System.Management.ManagementClass($scope, (new-object System.Management.ManagementPath("Win32_Service")), (new-object System.Management.ObjectGetOptions))
		$null = $mgt.InvokeMethod("Create", $params)    
		switch ($AgentName) {
			metricbeat {}
			Default {
			# Update startup delay on winlogbeat
				Try {
					Start-Process -FilePath sc.exe -ArgumentList 'config $AgentServiceName start= delayed-auto'
				}
				Catch {
					Write-information -MessageData "An error occured setting the $AgentServiceName service to delayed start." -InformationAction Continue 
				}
			}

		}

	}Else{
		# Powershell V5 and most recent, ability to use the integrated install service script but replace the log folder destination
		$InstallServiceFilePath = "$AgentfolderPath\install-service-$AgentName.ps1"
		$setupfile = Get-Content $InstallServiceFilePath
		$setupfile = $setupfile -replace ("C:\\ProgramData\\$AgentName\\logs",'$workdir\logs')
		set-Content $InstallServiceFilePath -Value $setupfile
		Powershell -executionpolicy bypass -file $InstallServiceFilePath
	}

	# start the service
	start-service $AgentServiceName -PassThru
	# on some case, the PassThru is not displayed. call the get-service to avec the exact service status
	get-service $AgentServiceName

	# Clean installation folder -> (TO DO -> funtion to be able to call it in case of failure)
	Remove-Item .\$BeatFileName
	Remove-Item $DestinationUnZIPFolder -Recurse
	Write-Information -MessageData "Agent $AgentName installed" -InformationAction Continue
}

exit