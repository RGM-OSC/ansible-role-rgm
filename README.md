Role Name
=========

This role install and configure [RGM](http://rgm.cloud/) and all its rependencies.

Requirements
------------

RGM currently excusively supports RHEL 7 and CentOS 7 operating systems. That means that the installation will mostly fail on anything else. RGM installer excpects a fresh, **minimal** install, with at least **git** and **ansible** installed on the system.

For commodity, we provide a *bash shell script* that automatically set-up the system for RGM installation : [rgm-installer.sh](https://installer.rgm-cloud.io/rgm-installer.sh). The script require **root** privileges, and do the following:
  * adds EPEL repository
  * adds RGM official repository
  * adds RGM repo GPG key
  * install some prerequisites (git, ansible)

It supports many command-line parameters, see its inline help for details. Below an example:

    bash <(curl -k -s https://installer.rgm-cloud.io/rgm-installer.sh) -y

Role Variables
--------------

For a typical setup, RGM comes with defaults values pre-defined.

### system related defaults values

| variable name | default |description |
|---------------|---------|------------|
| ```rgm_admin_user``` | admin | username to access RGM web interface |
| ```rgm_user``` | rgm | system user for RGM |
| ```rgm_user_password``` | changeme | system user's password for RGM |
| ```rgma_user``` | rgm | system user for RGMA. See [RGMA](./README_RGMA.md) for details |
| ```rgma_user_password``` | changeme | system user's password for RGMA |
| ```mariadb_user``` | rgminternal | MariaDB user for RGM internal purpose |
| ```mariadb_pwd``` | 0rd0-c0m1735-b47h0n143 | MariaDB password for RGM internal purpose |
| ```mariadb_ro_user``` | rgmro | MariaDB user for RO operations |
| ```mariadb_ro_pwd``` | XgfLlyTmMeNntE9WrTE3ToQhy7ATZmDC | MariaDB password for RO operations |
| ```ntp_servers``` | ['0.pool.ntp.org', '1.pool.ntp.org', '2.pool.ntp.org', '3.pool.ntp.org'] | a list of NTP servers to use for time syncrhonization |

### Grafana related defaults

| variable name | default |description |
|---------------|---------|------------|
| ```grafana_http_addr``` | 127.0.0.1 | grafana's binding address. Defaults only listen on localhost as Apache provides reverse-proxying |
| ```grafana_http_port``` | 3000 | grafana's binding port |
| ```grafana_rgm_dashboards``` | ```{{ rgm_root_path }}/grafana/dashboards``` | location where dashboard are stored |
| ```grafana_install_plugins_core``` | *True* | install a list of *core* plugins (ie. maintained by Grafana team) |
| ```grafana_install_plugins_contrib``` | *False* | install a list of *contrib* plugins, provided by 3rd parties |
| ```grafana_apply_patches``` | *True* | apply some RGM patches on grafana to algin UI with RGM |

List of *core* grafana plugins:
  - grafana-simple-json-datasource
  - grafana-worldmap-panel
  - grafana-clock-panel
  - grafana-piechart-panel
  - grafana-polystat-panel

List of *contrib* grafana plugins:
  - fetzerch-sunandmoon-datasource
  - satellogic-3d-globe-panel
  - ryantxu-ajax-panel
  - michaeldmoore-annunciator-panel
  - farski-blendstat-panel
  - yesoreyeram-boomtable-panel
  - briangann-gauge-panel
  - briangann-datatable-panel
  - jdbranham-diagram-panel
  - natel-discrete-panel
  - larona-epict-panel
  - agenty-flowcharting-panel
  - mtanda-histogram-panel
  - natel-influx-admin-panel
  - michaeldmoore-multistat-panel
  - digiapulssi-organisations-panel
  - bessler-pictureit-panel
  - natel-plotly-panel
  - corpglory-progresslist-panel
  - snuids-radar-panel
  - scadavis-synoptic-panel
  - marcuscalidus-svg-panel
  - gretamosa-topology-panel

Dependencies
------------

| name | link |
|------|------|
| ```ansible-role-lvm-mount``` | https://git.rgm-cloud.io/ansible-role-lvm-mount.git |
| ```ansible-role-snmp``` | https://git.rgm-cloud.io/ansible-role-snmp.git |

Example Playbook
----------------

This role is intended to be executed by [ansible-rgm](https://git.rgm-cloud.io/ansible-rgm.git) playbook

License
-------

GPLv3

Author Information
------------------

RGM stands for *Rigby Group Monitoring*. RGM is Copyrighted by **SCC France S.A.**, 2019
