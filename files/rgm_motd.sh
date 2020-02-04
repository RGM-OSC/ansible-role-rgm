#!/bin/bash
# Ansible Managed
#
# Custom Message Of The Day for RGM
#
# 2019-05-07 - RGM Team - Eric Belhomme <ebelhomme@fr.scc.com>

BAKIFS=$IFS

function get_ip_fqdn() {
	host $1 &> /dev/null
	if [ $? -eq 0 ]; then
		host $1 | awk '{print $5}'
	else
		echo '*'
	fi
}

# set some system-wide aliases for RGM
alias rgmvenv='. /srv/rgm/python-rgm/bin/activate'

# compute CPU and memory info, display system stats
CPU_INFO="$(grep processor /proc/cpuinfo | wc -l)x$(grep 'model name' /proc/cpuinfo | uniq | awk -F ':' '{print $2}')"
MEMORY="$(free -m |grep Mem: | awk -F " " '{print $2}') MB"
MEMORY_USED="$(free -m |grep Mem: | awk -F " " '{print $3}') MB"

echo -e "\n\e[1m -+- Welcome \e[34mRGM\e[39m server - http://www.rgm-cloud.io -+-\e[0m\n"
echo -e "Kernel     : \e[97m$(uname -r)\e[0m"
echo -e "Uptime     : \e[97m$(uptime -p | cut -c 4-)\e[0m"
echo -e "CPU Info   : \e[97m$CPU_INFO\e[0m"
echo -e "Memory info: \e[97m$MEMORY ($MEMORY_USED used)\e[0m"

# display disk occupation (filtering only ext4 and xfs local filesystems)
IFS=$'\n'
for item in $(df -hl -t xfs -t ext4 --output=pcent,target | tail -n+2); do
	PCENT=$(echo $item | awk '{print $1}' | sed 's/%//')
	MNTPT=$(echo $item | awk '{print $2}')
	COL='\e[32;1m' # green
	BLD=
	if [ $PCENT -gt 80 ]; then
		COL='\e[33;1m' # yellow
		BLD=';1'
	fi
	if [ $PCENT -gt 95 ]; then
		COL='\e[31;1m' # red
	fi
	echo -e "Mountpoint : \e[97${BLD}m$MNTPT\e[0m (disk usage: ${COL}${PCENT}%\e[0m)"
done
IFS=$BAKIFS

ARIPAD=()
ARFQDN=()
# Retrieve the default network interface (the one connected to the default gateway)
DEFNIC=$(ip route | grep ^default | awk '{print $5}')
ARIPAD+=("$(ip addr show $DEFNIC | grep 'inet ' | awk '{print $2}' | cut -d '/' -f 1)")
ARFQDN+=("$(get_ip_fqdn ${ARIPAD[0]})")
# add secondary network interfaces and retrieve the corresponding FQDN if exists
for IP in $(ip addr | grep 'inet ' | awk '{print $2}' | cut -d '/' -f 1 | grep -v "\(127.0.0.1\)\|\(${ARIPAD[0]}\)"); do
	ARIPAD+=("$IP")
	ARFQDN+=("$(get_ip_fqdn $IP)")
done
# display RGM links for each interface
echo -e "\nYou can access the \e[34;1mRGM\e[0m web interface by pointing your browser to :"
for (( idx=0; idx < ${#ARIPAD[*]}; idx++ )); do
	COL='\e[97m'
	if [ $idx -eq 0 ]; then
		COL='\e[1m'
	fi
	echo -en " - ${COL}https://${ARIPAD[$idx]}/\e[0m"
	if [ "${ARFQDN[$idx]}" != "*" ]; then
		echo -en " or ${COL}https://${ARFQDN[$idx]}/\e[0m\n"
	else
		echo ""
	fi
done

echo -e "\e[0m" # EOF