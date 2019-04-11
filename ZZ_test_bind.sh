#!/bin/bash

# Author: Jason D. Kelleher
# https://github.com/jdkelleher/openldap_multi-master


SCRIPT_BASE="${0%/*}"

source ${SCRIPT_BASE}/config

SLEEP_TIME=3


print_usage() {
	echo "Usage: $0 [-h] [-k] [master master ...]"
	echo -e "\t[-h] pring usage (this message)"
	echo -e "\t[master] is one or more masters defined in the config to bind to"
	echo -e "\tif not specified, all master listed in the config will be used"
	echo -e "\n\tmaster must be defined as an element of LDAP_MASTERS in the config"
}

OPTIND=1
while getopts "h?k" opt; do
	case "$opt" in
		h|\?)
			print_usage
			exit 0
			;;
	esac
done
shift $((OPTIND-1))

if [ $# -ge 1 ] ; then
	MASTER_LIST=( "$@" )
else
	MASTER_LIST=("${LDAP_MASTERS[@]}")
fi


# bind_check
# $1 is the master to check against
# $2 is the account to use
# $3 is the password to use
#
bind_check() {
	echo -n -e "Executing ldapwhoami on master \"${1}\" with account \"${2}\"...\n\t"
	ldapwhoami -x -H ldap://${1}.${DOMAIN} -D cn=${2},${DCNAME} -w ${3} 
	if [ $? -ne 0 ] ; then
		echo -e "\tFail!"
	else
		echo -e "\tSuccess!"
	fi
}



# Begin main....

for i in ${!MASTER_LIST[@]}; do
	M=${MASTER_LIST[$i]}
	bind_check ${M} ${LDAP_ADMIN} ${LDAP_ADMIN_PASSWORD}
	bind_check ${M} ${LDAP_READER} ${LDAP_READER_PASSWORD}
	bind_check ${M} ${BIND_ACCOUNT} ${BIND_ACCOUNT_PASSWORD}
done


