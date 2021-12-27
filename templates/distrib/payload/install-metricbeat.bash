#!/bin/bash
# {{ ansible_managed }}
# vim: ts=4 expandtab:
#
# RGM deployment script for Linux MetricBeat

RGMSRVR="{{ ansible_default_ipv4.address }}"
RGM_HOST_TMPL='RGM_LINUX_ES'
RGM_HOST_ALIAS="$(hostname -s)"
EXPORTCONFIG=1
RGMAPI_USER=
RGMAPI_PASSWD=
RGMAPI_TOKEN=
PWD="$(pwd)"
RC=1

if [ $UID -ne 0 ]; then
    echo -e "\e[1;31mError :\e[22m This script requires root privileges to execute\e[0m"
    exit 1
fi

api_check_auth() {
    RCHTTP="$(curl -s -k -o /dev/null -w "%{http_code}" \
        -H 'Content-Type: application/json' -H "Authorization: Bearer${1}" \
        "https://${RGMSRVR}/api/v2/token")"
    if [ $? -ne 0 ]; then
        return 0
    else
        return "$RCHTTP"
    fi
}

print_help() {
    cat <<EOF

$(basename "$0") - Install metricbeat & configure for RGM

Usage: $(basename "$0") -u <RGMAPI user> -p <RGMAPI password> | -o <RPMAPI one-time token>
                      [ -s <RGM host> ]
                      [ -t <RGM host template> ]
                      [ -a <RGM host alias> ]
                      [ -d ]

Arguments:
  -u <user>              : RGM API user with admin privileges
  -p <password>          : RGM API password
  -o <token>             : RGM TOKEN if methode used
  -s <RGM host>          : Optional RGM host IP or FQDN (default to RGM server used to download this script)
  -t <RGM host template> : Optional RGM Host Template to apply to this host. default to 'RGM_LINUX_ES'
  -a <RGM host alias>    : Optional RGM Host Alias. Defaults to $(hostname -s)
  -d                     : Disables automatic Lilac configuration export (enabled by default)

EOF
    exit 1
}

while getopts hdu:p:o:s:t:a: arg; do
    case "$arg" in
        h) print_help;;
        d) EXPORTCONFIG=0;;
        u) RGMAPI_USER="$OPTARG";;
        p) RGMAPI_PASSWD="$OPTARG";;
        o) RGMAPI_TOKEN="$OPTARG";;
        s) RGMSRVR="$OPTARG";;
        t) RGM_HOST_TMPL="$OPTARG";;
        a) RGM_HOST_ALIAS="$OPTARG";;
        *) print_help;;
    esac
done

# ensure we can get RGM API Token
RCHTTP=
if [ -n "$RGMAPI_TOKEN" ]; then
    #RCHTTP="$(api_check_auth "$RGMAPI_TOKEN")"
    api_check_auth "$RGMAPI_TOKEN"
    RCHTTP=$?
fi
if [ "$RCHTTP" != '200' ] && [ -n "$RGMAPI_USER" ] && [ -n "$RGMAPI_PASSWD" ]; then
    RGMAPI_TOKEN="$(curl -s -k POST \
        --data-urlencode "username=${RGMAPI_USER}" \
        --data-urlencode "password=${RGMAPI_PASSWD}" \
        "https://${RGMSRVR}/api/v2/token" |
        grep -Po '"token":.*?[^\\]",' | perl -pe 's/"token"://; s/"//; s/",$//')"
    api_check_auth "$RGMAPI_TOKEN"
    RCHTTP=$?
fi
if [ "$RCHTTP" != '200' ]; then
    echo "Fatal: unable to get auth token from RGM API on server $RGMSRVR"
    exit 1
fi

# OS & major release detection
OSTYPE=
OSVERS=
if [ -e /etc/redhat-release ]; then
    if grep -P '^(CentOS|RedHat|Red Hat|Rocky)' /etc/redhat-release &> /dev/null; then
        OSTYPE='redhat'
        OSVERS=$(sed 's/.*release \([0-9]\+\).*/\1/' /etc/redhat-release)
    fi
fi
if [ -e /etc/debian_version ]; then
    OSTYPE=$(lsb_release -a 2>&1 | grep ^Distributor | awk '{print tolower($3)}')
    OSVERS=$(lsb_release -a 2>&1 | grep ^Release | awk '{print $2}' | cut -d '.' -f 1)
fi

if [ -z "$OSTYPE" ]; then
    echo -e "\e[1;31mError :\e[22m Failed to detect OS type\e[0m"
    exit 1
fi

# download files
TMPDIR=$(mktemp -d)
cd "$TMPDIR" || exit 1
DOWNLOADBIN="https://${RGMSRVR}/distrib/packages"
DOWNLOADCFG="https://${RGMSRVR}/distrib/conf/linux_metricbeat.yml"
if [ "$OSTYPE" == 'redhat' ]; then
    BINFILE="metricbeat-oss-latest-x86_64.rpm"
    if rpm -qi metricbeat &> /dev/null; then
        echo "metricbeat package already installed on this host"
    else
        curl -s -O -k "${DOWNLOADBIN}/${BINFILE}"
        yum localinstall -y $BINFILE
    fi
    curl -s -O -k "${DOWNLOADCFG}"
fi
if [ "$OSTYPE" == 'debian' ] | [ "$OSTYPE" == 'ubuntu' ]; then
    BINFILE="metricbeat-oss-latest-amd64.deb"
    if dpkg -V metricbeat &> /dev/null; then
        echo "metricbeat package already installed on this host"
    else
        wget --no-check-certificate "${DOWNLOADBIN}/${BINFILE}"
        if ! dpkg -i $BINFILE; then
            if ! apt-get -f -y install; then
                echo -e "\e[1;31mError :\e[22m Failed to install package ${BINFILE}\e[0m"
                exit 1
            fi
        fi
    fi
    wget --no-check-certificate "${DOWNLOADCFG}"
fi

# get default NIC IP config to patch metricbeat config file
CLI_NIC=$(ip route show | grep ^default | sed 's/.*dev \([a-z][a-z0-9]\+\) .*/\1/')
CLI_ADDR=$(ip addr show dev "$CLI_NIC" | grep 'inet ' | awk '{print $2}' | cut -d '/' -f 1)
sed -i "s/^\( *host.ip:\) .*$/\1 $CLI_ADDR/" linux_metricbeat.yml

# copy RGM config file in place
cp -f linux_metricbeat.yml /etc/metricbeat/metricbeat.yml
chown root:root /etc/metricbeat/metricbeat.yml
chmod 0640 /etc/metricbeat/metricbeat.yml

# disable original system module
if [ -e /etc/metricbeat/modules.d/system.yml ]; then
    mv /etc/metricbeat/modules.d/system.yml /etc/metricbeat/modules.d/system.yml.disabled
fi

# add metricbeat modules
MODULELIST=(linux_rgm-system-core.yml linux_rgm-system-fs.yml linux_rgm-system-uptime.yml)
DOWNLODMODROOT=$(dirname "$DOWNLOADCFG")
cd /etc/metricbeat/modules.d || exit 1
for MODULE in "${MODULELIST[@]}"; do
    curl -s -O -k "${DOWNLODMODROOT}/modules/${MODULE}"
    chmod 0640 "${MODULE}"
done
cd "$PWD" || exit 1
rm -Rf "$TMPDIR"

# systemd on newer systems, legacy (initV, upstart, ...) overwise
if [[ ("$OSTYPE" == 'redhat' && $OSVERS -ge 7) ||
        ("$OSTYPE" == 'debian' && $OSVERS -ge 9) ||
        ("$OSTYPE" == 'ubuntu' && $OSVERS -ge 16) ]]; then
    systemctl enable metricbeat.service
    systemctl restart metricbeat.service
    RC=$?
else
    case "$OSTYPE" in
        'redhat')
            chkconfig metricbeat on
            RC=$?
            ;;
        'debian')
            update-rc.d metricbeat enable
            RC=$?
            ;;
        'ubuntu')
            service metricbeat restart
            RC=$?
            ;;
        *)
            ;;
    esac
fi

# call RGM API createhost
CURLTMP=$(mktemp)
RCHTTP="$(curl -s -k -XPOST -o "$CURLTMP" -w "%{http_code}" \
    -H 'Content-Type: application/json' -H "Authorization: Bearer${RGMAPI_TOKEN}" \
    "https://${RGMSRVR}/api/v2/host" \
    -d "{\"templateHostName\": \"${RGM_HOST_TMPL}\", \
        \"hostName\": \"$(hostname -f)\", \
        \"hostIp\": \"${CLI_ADDR}\", \
        \"hostAlias\": \"${RGM_HOST_ALIAS}\"}")"
if [ "$RCHTTP" != 200 ]; then
    cat "$CURLTMP"
    echo ''
    RC=2
else
    if [ $EXPORTCONFIG -gt 0 ]; then
        RCHTTP="$(curl -s -k -XPOST -o "$CURLTMP" -w "%{http_code}" \
            -H 'Content-Type: application/json' -H "Authorization: Bearer${RGMAPI_TOKEN}" \
            "https://${RGMSRVR}/api/v2/nagios/export" \
            -d '{"jobName": "Incremental Nagios Export"}')"
        if [ "$RCHTTP" != 200 ]; then
            cat "$CURLTMP"
            echo ''
            RC=2
        fi
    fi
fi
rm -f "$CURLTMP"

exit $RC
