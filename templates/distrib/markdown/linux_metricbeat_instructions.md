## Open a *root* shell

Log in as *root* user either by _SSH_ or on local _console_

## Execute the one-liner

```
bash <(curl -k -s https://{{ ansible_default_ipv4.address }}/distrib/install/install-metricbeat.bash)
```
