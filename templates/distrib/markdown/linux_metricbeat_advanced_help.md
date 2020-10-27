
# OneLiner Launch

The _bash_ script download metricbeat package from RGM distrib host, installs and configure the daemon,
then finally register the host on RGM and triggers a Lilac configuration export.

The **one-liner** supports the following arguments:

| name                     | default       | description |
|--------------------------|---------------|--|
| `-u <user>`              |               | RGM API user with admin privileges |
| `-p <password>`          |               | RGM API password |
| `-o <one-time token>`    |               | one-time usage token |
| `-s <RGM host>`          | RGM server IP | Optional RGM host IP or FQDN (default to RGM server used to download this script) |
| `-t <RGM host template>` | RGM_LINUX_ES  | Optional RGM Host Template to apply to this host. default to '' |
| `-a <RGM host alias>`    | `hostname -s` | Optional RGM Host Alias. Defaults to $(hostname -s) |
| `-d`                     | enabled       | Disables automatic Lilac configuration export |

## RGM API authentication

Authentication over RGM API with _admin role_ is mandatory. The user can pass either a user/password **or** a _one-time token_.

The **one-time token** is a single usage token, generated on-the-fly by administrator and and avoid to type on the shell the clear text user/password.