# OneLiner Launch

## Powershell

Run the Powershell command line as Administrator

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
Invoke-Expression $($(Invoke-WebRequest https://{{ ansible_default_ipv4.address }}/distrib/install/install-beats.ps1).Content)
```

If Powershell is 6.0 or higher

```
Invoke-Expression $($(Invoke-WebRequest https://{{ ansible_default_ipv4.address }}/distrib/install/install-beats.ps1).Content -SkipCertificateCheck)
```


## Command DOS
AS the Powershell methode, it is higly recommanded to use a trusted certificat (public authority or company auhtority) for the RGM server to avoid SSL issus during the setup of Metricbeats agents

```
Powershell -executionPolicy bypass -command "& {Invoke-Expression $($(Invoke-WebRequest https://{{ ansible_default_ipv4.address }}/distrib/install/install-beats.ps1).Content)}"
```
