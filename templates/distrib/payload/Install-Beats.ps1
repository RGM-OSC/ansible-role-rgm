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

function Write-log {
	param (
		$MessageData
	)
	If (($PSVersionTable.PSVersion).Major -le 4){
		write-host $MessageData
	}Else{
		Write-Information -MessageData $MessageData -InformationAction Continue
	}
}
Write-Verbose -Message "Start Beat agents script installation"

If (($PSVersionTable.PSVersion).Major -le 3){
	If (Test-Administrator -eq $false) {
		Write-log -MessageData "The script require Administrator privileges" -InformationAction Continue
		Write-Verbose -Message "The script require Administrator privileges"
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
		"modules_en": ["windows_rgm-system-core-en.yml","windows_rgm-system-fs.yml","windows_rgm-system-uptime.yml"],
		"modules_fr": ["windows_rgm-system-core-fr.yml","windows_rgm-system-fs.yml","windows_rgm-system-uptime.yml"]
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
	Write-log -MessageData "$BeatFailed is not a valide agent name or not managed yet" -InformationAction Continue
}

# test the $BeatsBasePath value if not good
# Clean any '\' present at the end to avoid issue on next commands
$BeatsBasePath = $BeatsBasePath.TrimEnd("\")
if ((Test-Path $BeatsBasePath) -eq $false) {
	Write-log -MessageData "The folder $BeatsBasePath doesn't exist. Exit" -InformationAction Continue
	Write-Verbose -Message "The folder $BeatsBasePath doesn't exist. Exit"
	exit 1
}

### SSL Bypass process
Write-Verbose -Message "Bypass SSL and set TLS12"

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
	Write-log -MessageData "Installation of the $AgentName agent" -InformationAction Continue
	Write-Verbose -Message "Installation of the $AgentName agent"

	# generate download links
	Write-Verbose -Message "generate download links"
	$BeatFileDownloadLink = "https://$RGMServer/distrib/packages/$AgentName-oss-latest-windows-x86_64.zip"
	$BeatConfFileLink = "https://$RGMServer/distrib/conf/windows_$AgentName.yml"
	
	# generate files names and local path variables
	Write-Verbose -Message "generate files names and local path variables"
	$BeatFileName = ($BeatFileDownloadLink -split ("/"))[-1]
	$BeatConfFileName = ($BeatConfFileLink -split ("/"))[-1]
	$BeatFoldername = $BeatFileName.Replace(".zip", "")
	$ConfigurationFilePath = "$AgentfolderPath\$BeatConfFileName" -replace ("windows_")

	# Donwload the zip file agent (New-Object System.Net.WebClient).DownloadFile is very fastest than Invoke-WebRequest
	$DownloadPathName = (Get-Location).Path , $BeatFileName -join "\"
	write-verbose "Download destination file: $DownloadPathName"
	try {
		Write-log -MessageData "Download $BeatFileDownloadLink file" -InformationAction Continue
		Write-Verbose -Message "Download $BeatFileDownloadLink file"
		(New-Object System.Net.WebClient).DownloadFile($BeatFileDownloadLink, $DownloadPathName)
	}
	catch {
		Write-log -MessageData "unable to donwload the $BeatFileDownloadLink file" -InformationAction Continue
		Write-Verbose -Message "unable to donwload the $BeatFileDownloadLink file"
		exit 1
	}
	######  Unzip Part #######

	# Create the Destination zip folder 
	
	if (Test-Path $BeatFoldername){
		Remove-Item $BeatFoldername -Recurse -ErrorAction Stop
		write-verbose -Message "Clean $BeatFoldername before unzip"
	}
	try {
		$DestinationUnZIPFolder=(new-item -Name $BeatFoldername -ItemType Directory).FullName
		write-verbose -Message "create $DestinationUnZIPFolder folder"

	}
	catch{
		Write-log -MessageData "Issue to create the temporary unzipped folder" -InformationAction Continue
		Write-verbose -Message "Issue to create the temporary unzipped folder"
		exit 1
	}

	# UnZIP MetricBeat
	try {
		# Manage unzip depending Powershell Version
		Write-verbose -Message "unzip"
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
	}
	catch{
		Write-log -MessageData "Issue to unzipped the content" -InformationAction Continue
		write-verbose "Issue to unzipped the content`r`n$_"
		exit 1
	}

	######  Destination Folder Part #######
	# Create folder $BeatBasePath\MetricBeat if not existe
	if ((Test-Path $AgentfolderPath) -eq $false) {
		try {
			New-Item -Path $AgentfolderPath -Type "directory" -ErrorAction Stop
			Write-verbose -Message "Create destination folder $AgentfolderPath"
		}
		catch {
			Write-log -MessageData "The folder $AgentfolderPath can't be created" -InformationAction Continue
			Write-verbose -Message "The folder $AgentfolderPath can't be created"
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
	try{
		$TempfolderContent = Get-ChildItem $DestinationUnZIPFolder
		Write-Verbose -Message "Copy from $($TempfolderContent.FullName) to $AgentfolderPath folder"
		Copy-Item -Path "$($TempfolderContent.FullName)\*" -Destination $AgentfolderPath -Recurse -Force -ErrorAction Stop
	}
	catch{
		Write-log -MessageData "The copy failed from $($TempfolderContent.FullName) to $AgentfolderPath with error`r`n$_" -InformationAction Continue
		Write-verbose -Message "The copy failed from $($TempfolderContent.FullName) to $AgentfolderPath with error`r`n$_"
		exit 1
	}
	
	# Download dedicated Agent configuration file from RGM
	
	try {
		Write-Verbose -Message "Download Agent configuration file"
		Write-log -MessageData "Download Agent configuration file" -InformationAction Continue
		(New-Object System.Net.WebClient).DownloadFile($BeatConfFileLink, $ConfigurationFilePath)
	}
	catch {
		Write-log -MessageData "unable to donwload the $BeatConfFileLink file" -InformationAction Continue
		Write-Verbose -Message "unable to donwload the $BeatConfFileLink file"
		exit 1
	}

	# Part depending of the agent
	switch ($AgentName) {
		"metricbeat" { 
			# Dedicated part of the metricbeat agent
			Write-Verbose -Message "tunning of metricbeat agent"
			Write-log -MessageData "tunning of metricbeat agent" -InformationAction Continue

			# Collect current IP address
			$IPaddress = Get-WmiObject -class Win32_NetworkAdapterConfiguration -Filter "IpEnabled = 'True' " | Where-Object {$_.DefaultIPGateway -ne $null} | Select-Object -ExpandProperty IPaddress | Select-Object -First 1

			# dynamically insert host IP address as a beat "fields" into config
			$ConfigurationFileContent = Get-Content $ConfigurationFilePath
			$ConfigurationFileContent = $ConfigurationFileContent -replace ("%%IP%%",$IPaddress)
			Set-Content -Path $ConfigurationFilePath -Value $ConfigurationFileContent

			# Rgm module adjustement
			# Test language to push the good version
			$OSLanguage = (GET-WinSystemLocale).LCID
			switch ($OSLanguage) {
				1036 { 
					#Case French
					$modules = $AgentDetail.modules_fr
					Write-log -MessageData "Language $OSLanguage" -InformationAction Continue
					Write-Verbose -Message "Language $OSLanguage"
				}
				Default {
					#Default English
					$modules = $AgentDetail.modules_en
					Write-log -MessageData "Language $OSLanguage" -InformationAction Continue
					Write-Verbose -Message "Language $OSLanguage"
				
				}
			}
			# Loop to download all rgm dedicated module for metricbeat to the module.d folder
			Write-Verbose -Message "Inject RGM modules"
			foreach ($module in $modules ) {
				$BeatConfRGMLink = "https://$RGMServer/distrib/conf/modules/$module"
				$BeatDestFileName = $module -replace ("windows_")
				$BeatConfPath = $AgentfolderPath + "\modules.d\" + $BeatDestFileName
				Write-Verbose -Message "Download $BeatConfRGMLink to $BeatConfPath"
				(New-Object System.Net.WebClient).DownloadFile($BeatConfRGMLink, $BeatConfPath)
			}

			# Disable the default system module
			Write-verbose -Message "Disable the default system module"
			$SystemModulePath = "$AgentfolderPath\modules.d\system.yml"
			if (Test-Path $SystemModulePath){
				# Use Move-item instead of rename-item to bypass if file already exist
				Move-Item  -Path $SystemModulePath -Destination $($SystemModulePath -replace (".yml",".yml.disabled")) -force
			}

		}
		Default {}
	}

	######  Service Creation part #######
	Write-verbose -Message "Create the $AgentName service"
	If (($PSVersionTable.PSVersion).Major -le 4) {
		#  # oldest Powershell version (4 and oldest ) use old service management methode
		# delete the service if exist
		if (Get-Service $AgentServiceName -ErrorAction SilentlyContinue) {
			$service = Get-WmiObject -Class Win32_Service | where-object { $_.name -eq $AgentServiceName}
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
					Write-log -MessageData "An error occured setting the $AgentServiceName service to delayed start." -InformationAction Continue 
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
	Write-verbose -Message "start the $AgentServiceName service"
	start-service $AgentServiceName -PassThru
	# on some case, the PassThru is not displayed. call the get-service to avec the exact service status
	get-service $AgentServiceName

	# Clean installation folder -> (TO DO -> funtion to be able to call it in case of failure)
	Write-Verbose -Message "Remove temp files and folders"
	Remove-Item .\$BeatFileName
	Remove-Item $DestinationUnZIPFolder -Recurse
	Write-log -MessageData "Agent $AgentName installed" -InformationAction Continue
	Write-Verbose -Message "Agent $AgentName installed"
}
Write-Verbose -Message "End of Install-Beats Script"