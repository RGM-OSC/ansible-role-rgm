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

* __username__ : enter an RGM internal account
* __password__ : enter the associate password
* __token__ : If you already know the token, it can bu used instead of the password
* __RGMServer__ : _optionnal_. By default the IP of the RGM server is used, you can provide another IP.
* InstallSomething : _optionnal - not yet usable_. Use this switch to install Something
* Common commandlets are available like -verbose


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
AS the Powershell methode, it is higly recommanded to use a trusted certificat (public authority or company auhtority) for the RGM server to avoid SSL issus during the setup of Metricbeats agents

```
Powershell -executionPolicy bypass -command "& {Invoke-Expression ([System.Text.Encoding]::ASCII.GetString((Invoke-WebRequest https://{{ ansible_default_ipv4.address }}/distrib/install/install-beats.ps1).Content))}"
```
</s>

 __Better to use PowerShell__
