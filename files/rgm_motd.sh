#!/bin/bash
# Ansible Managed
#
# Custom Message Of The Day for RGM

BAKIFS=$IFS
DEFNIC=$(ip route | grep ^default | awk '{print $5}')
IP_ADDRESS=$(ip addr show $DEFNIC | grep 'inet ' | awk '{print $2}' | cut -d '/' -f 1)

KERNEL="$(uname -r)"
CPU_INFO="$(grep processor /proc/cpuinfo | wc -l)x$(grep 'model name' /proc/cpuinfo | uniq | awk -F ':' '{print $2}')"
MEMORY="$(free -m |grep Mem: | awk -F " " '{print $2}') MB"
MEMORY_USED="$(free -m |grep Mem: | awk -F " " '{print $3}') MB"
 
echo -e "\n\e[1m -+- Welcome \e[34mRGM\e[39m server - http://www.rgm-cloud.io -+-\e[0m\n"
echo -e "Kernel     : \e[97m$KERNEL\e[0m"
echo -e "Uptime     : \e[97m$(uptime -p | cut -c 4-)\e[0m"
echo -e "CPU Info   : \e[97m$CPU_INFO\e[0m"
echo -e "Memory info: \e[97m$MEMORY ($MEMORY_USED used)\e[0m"

IFS=$'\n'
for item in $(df -hl -t xfs -t ext4 --output=pcent,target | tail -n+2); do
	PCENT=$(echo $item | awk '{print $1}' | sed 's/%//')
	MNTPT=$(echo $item | awk '{print $2}')
	COL='\e[32;1m' # green
	if [ $PCENT -gt 80 ]; then
		COL='\e[33;1m' # yellow
	fi
	if [ $PCENT -gt 95 ]; then
		COL='\e[31;1m' # red
	fi
	echo -e "Mountpoint : \e[97m$MNTPT\e[0m (disk usage: ${COL}${PCENT}%\e[0m)"
done
IFS=$BAKIFS
echo -e "\nYou can access the \e[34mRGM\e[0m web interface by pointing you browser to \e[1mhttps://${IP_ADDRESS}/\e[0m\n"
