#!/bin/bash

# Author: Jason D. Kelleher
# https://github.com/jdkelleher/openldap_multi-master


SCRIPT_BASE="${0%/*}"

source ${SCRIPT_BASE}/config


print_usage() {
	echo "Usage: $0 [-h] [-k] [master_name]"
	echo -e "\t[-h] pring usage (this message)"
	echo -e "\t[-k] keep temporary files; this will overide the setting in config"
	echo -e "\t[master_name] name of the master being configured.  If not supplied, hostname will be used."
	echo -e "\n\tThis should only be run on _one_ master.  It will not execute successfully a second time."
	echo -e "\tmaster_name must be defined as an element of LDAP_MASTERS in the config."
}

OPTIND=1
while getopts "h?k" opt; do
	case "$opt" in
		h|\?)
			print_usage
			exit 0
			;;
		k)
			export KEEP_TEMP_FILES=1
			exit 0
			;;
	esac
done
shift $((OPTIND-1))

if [ $# -eq 1 ] ; then
	export MASTER=$1
else
	export MASTER=`hostname`
fi

# Set rid based on LDAP_MASTERS index.  This also validates MASTER
MASTER_RID=nf
for i in "${!LDAP_MASTERS[@]}"; do
	if [[ "${LDAP_MASTERS[$i]}" = "${MASTER}" ]]; then
		export MASTER_RID=$(( $i + 1 ))
		break
	fi
done
if [[ "${MASTER_RID}" = "nf" ]]; then
	echo "Error matching ${MASTER} to defined LDAP_MASTERS, please check config."
	exit 1
fi
if [[ "${MASTER_RID}" -ne 1 ]]; then
	echo -e "Warning, this should only be run on the first master defined in the config.\n"
	#exit 1
fi


# add_syncprov_overlay
#
# Add olcOverlay=syncprov to config
#
add_db_syncprov_overlay() {
        echo "Running ${FUNCNAME[0]}..."
        sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<-EOInp
	dn: olcOverlay=syncprov,olcDatabase={1}${LDAPDB},cn=config
	changetype: add
	objectClass: olcOverlayConfig
	objectClass: olcSyncProvConfig
	olcOverlay: syncprov
	EOInp
	if [ $? -ne 0 ] ; then echo "Error executing ${FUNCNAME[0]}..." ; exit 1 ; fi
}

# add_db_config_SyncRepl
#
# Add SyncRepl to the config
#
add_db_config_SyncRepl() {
        echo "Running ${FUNCNAME[0]}..."
	# Build ldif for sync_tree, only to be run on 1st master
	LDIF_FILE="${TEMP_DIR}/${$}.db_syncrepl.ldif" ; touch ${LDIF_FILE} ; chmod 600 ${LDIF_FILE}
	cat <<-EOInp													> ${LDIF_FILE}
		dn: olcDatabase={1}${LDAPDB},cn=config
		changetype: modify
		add: olcSyncRepl
	EOInp
	for i in ${!LDAP_MASTERS[@]}; do
		R=$(( $i + 1 ))
		M=${LDAP_MASTERS[$i]}
		echo "olcSyncRepl: rid=${R} provider=ldap://${M}.${DOMAIN} binddn=\"cn=${LDAP_READER},${DCNAME}\""	>> ${LDIF_FILE}
		echo "  bindmethod=simple credentials=${LDAP_READER_PASSWORD}"						>> ${LDIF_FILE}
		echo "  searchbase=\"${DCNAME}\" type=refreshAndPersist"						>> ${LDIF_FILE}
		echo "  retry=\"5 5 300 5\" timeout=1"									>> ${LDIF_FILE}
		echo "  starttls=critical tls_reqcert=demand"								>> ${LDIF_FILE}
	done
	cat <<-EOInp >> ${LDIF_FILE}
		-
		add: olcMirrorMode
		olcMirrorMode: TRUE
	EOInp
	# Make sure the LDIF is there before trying to use it.
	if [ ! -f $LDIF_FILE ] ; then
		echo "${LDIF_FILE} not found in ${FUNCNAME[0]}, aborting..."
		exit 1
	fi
	sudo ldapmodify -Y EXTERNAL -H ldapi:/// -f $LDIF_FILE
	if [ $? -ne 0 ] ; then echo "Error executing ${FUNCNAME[0]}..." ; exit 1 ; fi
	# Cleanup
	if [ $KEEP_TEMP_FILES -ne 1 ] ; then
		sudo rm -f "${LDIF_FILE}"
	fi
}


# main...
add_db_syncprov_overlay
add_db_config_SyncRepl


