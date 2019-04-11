#!/bin/bash

# Author: Jason D. Kelleher
# https://github.com/jdkelleher/openldap_multi-master

# add then delete dummy entry to verify replication and update CSN
#

SCRIPT_BASE="${0%/*}"

source ${SCRIPT_BASE}/config

SLEEP_TIME=3


print_usage() {
	echo "Usage: $0 [-h] [-k] [master_1] [master_2]"
	echo -e "\t[-h] pring usage (this message)"
	echo -e "\t[master_1] name of master being updated, defaults to 1st defined in config"
	echo -e "\t[master_2] name of master being searched, defaults to 2nd defined in config"
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

MASTER_1=${LDAP_MASTERS[0]}
MASTER_2=${LDAP_MASTERS[1]}

if [ $# -eq 1 ] ; then
	MASTER_1=$1
	MASTER_2=$MASTER_1
elif [ $# -eq 2 ] ; then
	MASTER_1=$1
	MASTER_2=$2
elif [ $# -gt 2 ] ; then
	print_usage
	exit 1
fi


add_dummy_entry() {
	echo -e "Adding dummy entry on $MASTER_1 \n"
	ldapadd -x -H ldap://${MASTER_1}.${DOMAIN} -D cn=${LDAP_ADMIN},${DCNAME} -w ${LDAP_ADMIN_PASSWORD} <<-EOInp
		dn: cn=dummy,${DCNAME}
		changetype: add
		objectClass: organizationalRole
		objectclass: simpleSecurityObject
		userpassword: {SSHA}invalid_dummy_pass
		cn: dummy
		description: dummy entry for replication testing
	EOInp
	if [ $? -ne 0 ] ; then
		echo "Error performing add, exiting..."
		exit 1
	fi
}


delete_dummy_entry() {
	echo -e "Deleting dummy entry on $MASTER_1 \n"
	ldapmodify -x -H ldap://${MASTER_1}.${DOMAIN} -D cn=${LDAP_ADMIN},${DCNAME} -w ${LDAP_ADMIN_PASSWORD} <<-EOInp
		dn: cn=dummy,${DCNAME}
		changetype: delete
	EOInp
	if [ $? -ne 0 ] ; then
		echo "Error performing delete, exiting..."
		exit 1
	fi
}


search_dummy_entry() {
	echo -e "Searching for dummy entry on $MASTER_2 \n"
	ldapsearch -x -LLL -H ldap://${MASTER_2}.${DOMAIN} -D cn=${LDAP_ADMIN},${DCNAME} -w ${LDAP_ADMIN_PASSWORD} -b ${DCNAME} "cn=dummy" 
	if [ $? -ne 0 ] ; then
		echo "Error performing search, exiting..."
		exit 1
	fi
}



# Begin main....

add_dummy_entry
echo -e "Sleeping for $SLEEP_TIME seconds...\n"
sleep $SLEEP_TIME

search_dummy_entry

delete_dummy_entry
echo -e "Sleeping for $SLEEP_TIME seconds...\n"
sleep $SLEEP_TIME

search_dummy_entry


