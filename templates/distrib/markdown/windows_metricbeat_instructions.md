## Open a Powershell command line as __Administrator__

From Windows *Start* menu, search for *Windows PowerShell* application, then right-click and select *Run as Administrator* menu item.

## Execute the one-liner

Copy/paste the following line into the PowerShell. Don't forget to adapt _-username_ and _-password_ fields to your needs:

```
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
& $([Scriptblock]::Create((New-Object System.Net.WebClient).DownloadString("https://{{ ansible_default_ipv4.address }}/distrib/install/Add-RGMHost.ps1"))) -username admin -password ******
```

This will download and execute a PowerShell script from RGM server that will download, install, configure, then start metricbeat agent on the target host.