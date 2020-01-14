# OneLiner Launch

The principal script is dedicated to register the host in the RGM console and launch the metricbeat agent installation. Like linux, it is possible to launch the installation in oneliner, but... 
Because the SSL check is, now, more important, if you do not use an entreprise certificate for RGM, you should pass some lignes to avoid SSL issues

## Powershell

Run the Powershell command line as __Administrator__

To avoid SSL issues in case of self-signed certificate, it is necessary to bypass the SSL check

If the Powershell client is Equal or lowest than 5.1 :

```
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
```

There is some variable available to be able to register the Host in RGM.

| name | defaults | description |
|--|--|--|
| `Username`  |  | _mandatory_. enter an RGM internal account |
| `Password`  |  | _mandatory_. enter the associate password |
| `OneTimeToken`  |  | _mandatory_. If you already know the token, it can bu used instead of the password |
| `RGMServer`  | rgm server ip | _optionnal_. By default the IP of the RGM server is used, you can provide another IP |
| `RGMTemplate`  | GENERIC_HOST | _optionnal_.RGM template model to use when the computer is registered in RGM |
| `HostAlias`  |  | _optionnal_. Alias Name for the server in RGM |
| `NoMetricBeat`  | false | _optionnal_. Use this option to **not** install metric beat |
| `AuditBeat`  | false | _optionnal_. Use this option to install audit beat |
| `Verbose`  | false | _optionnal_. Common Commandlets are available. Use Verbose to have more details |


Launch the installation with this command :

```
& $([Scriptblock]::Create((New-Object System.Net.WebClient).DownloadString("https://{{ ansible_default_ipv4.address }}/distrib/install/Add-RGMHost.ps1"))) -username admin -password ******

```

<s>If Powershell is 6.0

```
Invoke-Expression ([System.Text.Encoding]::ASCII.GetString((Invoke-WebRequest https://{{ ansible_default_ipv4.address }}/distrib/install/install-beats.ps1 -SkipCertificateCheck).Content))

```
</s>
 
 __PowerShell Core 6 is not yet supported__

<s>

## Command DOS
AS the Powershell method, it is higly recommanded to use a trusted certificate (public authority or company auhtority) for the RGM server to avoid SSL issus during the setup of Metricbeats agents

```
Powershell -executionPolicy bypass -command "& {Invoke-Expression ([System.Text.Encoding]::ASCII.GetString((Invoke-WebRequest https://{{ ansible_default_ipv4.address }}/distrib/install/install-beats.ps1).Content))}"
```
</s>

 __Better to use PowerShell__
