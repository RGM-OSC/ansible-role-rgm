#!/bin/bash
# {{ ansible_managed }}
# vim: bs=4 ts=4 expandtab:
#
# RGM deployment script for Linux MetricBeat

RC=1
if [ $UID -ne 0 ]; then
    echo -e "\e[1;31mError :\e[22m This script requires root privileges to execute\e[0m"
    exit 1
fi

# OS & major release detection
OSTYPE=
OSVERS=
if [ -e /etc/redhat-release ]; then
    grep -P '^(CentOS|RedHat|Red Hat)' /etc/redhat-release &> /dev/null
    if [ $? -eq 0 ]; then
        OSTYPE='redhat'
        OSVERS=$(sed 's/.*release \([0-9]\+\).*/\1/' /etc/redhat-release)
    fi
fi
if [ -e /etc/debian_version ]; then
    OSTYPE=$(lsb_release -a 2>&1 | grep ^Distributor | awk '{print tolower($3)}')
    OSVERS=$(lsb_release -a 2>&1 | grep ^Release | awk '{print $2}' | cut -d '.' -f 1)
fi

if [ -z $OSTYPE ]; then
    echo -e "\e[1;31mError :\e[22m Failed to detect OS type\e[0m"
    exit 1
fi

# download files
TMPDIR=$(mktemp -d)
cd $TMPDIR
DOWNLOADBIN="https://{{ ansible_default_ipv4.address }}/distrib/packages"
DOWNLOADCFG="https://{{ ansible_default_ipv4.address }}/distrib/conf/linux_metricbeat.yml"
if [ "$OSTYPE" == 'redhat' ]; then
    BINFILE="metricbeat-oss-latest-x86_64.rpm"
    rpm -qi metricbeat &> /dev/null
    if [ $? -eq 0 ]; then
        echo "metricbeat package already installed on this host"
    else
        curl -O -k "${DOWNLOADBIN}/${BINFILE}"
        yum localinstall -y $BINFILE
    fi
    curl -O -k "${DOWNLOADCFG}"
fi
if [ "$OSTYPE" == 'debian' ]; then
    BINFILE="metricbeat-oss-latest-amd64.deb"
    dpkg -V metricbeat &> /dev/null
    if [ $? -eq 0 ]; then
        echo "metricbeat package already installed on this host"
    else
        wget --no-check-certificate "${DOWNLOADBIN}/${BINFILE}"
        dpkg -i $BINFILE
        if [ $? -ne 0 ]; then
            apt-get -f -y install
            if [ $? -ne 0 ]; then
                echo -e "\e[1;31mError :\e[22m Failed to install package ${BINFILE}\e[0m"
                exit 1
            fi
        fi
    fi
    wget --no-check-certificate "${DOWNLOADCFG}"
fi

# get default NIC IP config to patch metricbeat config file
CLI_NIC=$(ip route show | grep ^default | sed 's/.*dev \([a-z][a-z0-9]\+\) .*/\1/')
CLI_ADDR=$(ip addr show dev $CLI_NIC | grep 'inet ' | awk '{print $2}' | cut -d '/' -f 1)
sed -i "s/^\( *host.ip:\) .*$/\1 $CLI_ADDR/" linux_metricbeat.yml

# copy RGM config file in place
cp -f linux_metricbeat.yml /etc/metricbeat/metricbeat.yml
chown root:root /etc/metricbeat/metricbeat.yml
chmod 0640 /etc/metricbeat/metricbeat.yml

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

exit $RC
