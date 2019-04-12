#!/bin/bash

# Author: Jason D. Kelleher
# https://github.com/jdkelleher/openldap_multi-master


export SCRIPT_BASE="${0%/*}"

source ${SCRIPT_BASE}/config


print_usage() {
	echo "Usage: $0 [-h] [-k] [master_name]"
	echo -e "\t[-h] pring usage (this message)"
	echo -e "\t[-k] keep temporary files; this will overide the setting in config"
	echo -e "\t[master_name] name of the master being configured.  If not supplied, hostname will be used."
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


echo "$MASTER $DOMAIN $ORG $DCNAME $RID"
#sleep 10


# pkg_install
#
# Installs slapd (openLDAP) unattended using debconf and updates config files
#
pkg_install() {
	echo "Running ${FUNCNAME[0]}..."
	#cat <<-EOInp
	debconf-set-selections <<-EOInp
		slapd	slapd/internal/generated_adminpw	password	${LDAP_ADMIN_PASSWORD}
		slapd	slapd/password2	password	${LDAP_ADMIN_PASSWORD}
		slapd	slapd/internal/adminpw	password	${LDAP_ADMIN_PASSWORD}
		slapd	slapd/password1	password	${LDAP_ADMIN_PASSWORD}
		slapd	slapd/domain	string	${DOMAIN}
		slapd	slapd/purge_database	boolean	false
		slapd	slapd/allow_ldap_v2	boolean	false
		slapd	shared/organization	string	${ORGANIZATION}
		slapd	slapd/backend	select	${SLAPD_BE}
		slapd	slapd/move_old_database	boolean	true
	EOInp

	#debconf-get-selections | egrep "ldap|slapd"

	sudo apt -y install slapd ldap-utils
	sudo apt -y install migrationtools

	#sudo dpkg-reconfigure slapd 

	LDAP_CONF="/etc/ldap/ldap.conf"

	# add entries to /etc/ldap/ldap.conf, while making sure there is a backup of the original
	if [ ! -e ${LDAP_CONF}.orig ] ; then
		sudo cp -p ${LDAP_CONF} ${LDAP_CONF}.orig
	fi
	# comment out any existing BASE or URI entries in LDAP_CONF
	sudo perl -pi -e "s@(^(BASE|URI).+)@#\$1@" ${LDAP_CONF}
	# Append to ldap.conf
	cat <<-EOInp					>> ${LDAP_CONF}

		# Entries for ${DOMAIN}
		BASE    ${DCNAME}
		URI	${LDAP_URI_LIST}
	EOInp
}


# add_indexes()
#
# Adds base indexes via ldapmodify
#
add_indexes() {
	echo "Running ${FUNCNAME[0]}..."
	# Tweak as needed, don't pull an AT
	sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<-EOInp
		dn: olcDatabase={1}${LDAPDB},cn=config
		changetype: modify
		add: olcDbIndex
		olcDbIndex: entryCSN eq
		-
		add: olcDbIndex
		olcDbIndex: entryUUID eq

		dn: olcDatabase={1}${LDAPDB},cn=config
		changetype: modify
		add: olcDbIndex
		olcDbIndex: sn,givenName,mail eq,subinitial
	EOInp
	if [ $? -ne 0 ] ; then echo "Error executing ${FUNCNAME[0]}..." ; exit 1 ; fi
}


# config_tls()
#
# Install certificates and configure TLS
#
config_tls() {
	echo "Running ${FUNCNAME[0]}..."
	# BEGIN using certs which were manually pre-created; should replace with letsencrypt and certbot
	sudo apt -y install gnutls-bin ssl-cert
	sudo gpasswd -a openldap ssl-cert
	sudo systemctl restart slapd.service	# restart here is necessary due to the ssl-cert group add
	RETURN_DIR=`pwd`
	cd ${FILE_BASE}
	sudo cp -p slapd_cert.pem slapd_cacert.pem /etc/ssl/certs
	sudo chown root:root /etc/ssl/certs/slapd*.pem
	sudo chmod 0644 /etc/ssl/certs/slapd*.pem
	sudo cp -p slapd*_key.pem /etc/ssl/private
	sudo chown root:ssl-cert /etc/ssl/private/slapd_*key.pem
	sudo chmod 0640 /etc/ssl/private/slapd_*key.pem
	cd $RETURN_DIR
	# END using certs which were manually pre-created; should replace with letsencrypt and certbot
	#
	# Lets's Encrypt - https://letsencrypt.org/
	# Lets's Encryp for internal servers - https://blog.heckel.xyz/2018/08/05/issuing-lets-encrypt-certificates-for-65000-internal-servers/
	# Certbot - https://certbot.eff.org/
	# Ubuntu DynDns - https://help.ubuntu.com/community/DynamicDNS
	#
	sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<-EOInp
		dn: cn=config
		add: olcTLSCACertificateFile
		olcTLSCACertificateFile: /etc/ssl/certs/slapd_cacert.pem
		-
		add: olcTLSCertificateFile
		olcTLSCertificateFile: /etc/ssl/certs/slapd_cert.pem
		-
		add: olcTLSCertificateKeyFile
		olcTLSCertificateKeyFile: /etc/ssl/private/slapd_key.pem
	EOInp
	if [ $? -ne 0 ] ; then echo "Error executing ${FUNCNAME[0]}..." ; exit 1 ; fi
}


# add_bind_account
#
# Add bind account to be used for client connections
#
add_bind_account() {
	echo "Running ${FUNCNAME[0]}..."
	# *** need to call slappasswd here to create password hash
	PASSWORD_HASH=`slappasswd -s ${BIND_ACCOUNT_PASSWORD}`
	sudo ldapadd -x -H ldap://${MASTER}.${DOMAIN} -D cn=${LDAP_ADMIN},${DCNAME} -w ${LDAP_ADMIN_PASSWORD} <<-EOInp
		dn: cn=${BIND_ACCOUNT},${DCNAME}
		changetype: add
		userPassword: ${PASSWORD_HASH}
		objectClass: top
		objectClass: organizationalRole
		objectClass: simpleSecurityObject
		cn: ${BIND_ACCOUNT}
		description: Bind Account used for client connections
	EOInp
	if [ $? -ne 0 ] ; then echo "Error executing ${FUNCNAME[0]}..." ; exit 1 ; fi
}


# disallow_bind_anon
#
# Disallow anonymous binding
#
disallow_bind_anon() {
	echo "Running ${FUNCNAME[0]}..."
	sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<-EOInp
		dn: cn=config
		changetype: modify
		add: olcDisallows
		olcDisallows: bind_anon

		dn: cn=config
		changetype: modify
		add: olcRequires
		olcRequires: authc

		dn: olcDatabase={-1}frontend,cn=config
		changetype: modify
		add: olcRequires
		olcRequires: authc
	EOInp
	if [ $? -ne 0 ] ; then echo "Error executing ${FUNCNAME[0]}..." ; exit 1 ; fi
}


# add_config_olcRootPW
#
# Not set on ubuntu - only needed for priviledged remote access to config
#
# *** No longer needed here since LDAP_READER was added ***
#
add_config_olcRootPW() {
	echo "Running ${FUNCNAME[0]}..."
	# *** need to call slappasswd here to create password hash
	PASSWORD_HASH=`slappasswd -s ${LDAP_ADMIN_PASSWORD}`
	sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<-EOInp
		dn: olcDatabase={0}config,cn=config
		changetype: modify
		add: olcRootPW
		olcRootPW: ${PASSWORD_HASH}
	EOInp
	if [ $? -ne 0 ] ; then echo "Error executing ${FUNCNAME[0]}..." ; exit 1 ; fi
}


# add_ldap_reader
#
# Add read-only account to use for replication.  Since this consumer pulls from provider, no write
# permision is needed.  Since the credentials will be stored in olcSyncrepl in plain-text, best not
# to use an account with priviledge.  (Even though this is done in all the examples I could find.)
#
add_ldap_reader() {
	echo "Running ${FUNCNAME[0]}..."
	# *** need to call slappasswd here to create password hash
	PASSWORD_HASH=`slappasswd -s ${LDAP_READER_PASSWORD}`
	sudo ldapadd -x -H ldap://${MASTER}.${DOMAIN} -D cn=${LDAP_ADMIN},${DCNAME} -w ${LDAP_ADMIN_PASSWORD} <<-EOInp
		dn: cn=${LDAP_READER},${DCNAME}
		changetype: add
		userPassword: ${PASSWORD_HASH}
		objectClass: top
		objectClass: organizationalRole
		objectClass: simpleSecurityObject
		cn: ${LDAP_READER}
		description: LDAP reader used for synchronization
	EOInp
	if [ $? -ne 0 ] ; then echo "Error executing ${FUNCNAME[0]}..." ; exit 1 ; fi
}


# add_ldap_reader_acl
#
# LDAP_READER must be given read access to everything
#
# Note, adding an olcAccess entry of N pushes existing entries down, so order matters
#
add_ldap_reader_acl() {
	echo "Running ${FUNCNAME[0]}..."
	sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<-EOInp
	dn: olcDatabase={0}config,cn=config
	changetype: modify
	add: olcAccess
	olcAccess: {1}to * by dn="cn=${LDAP_READER},${DCNAME}" read

	dn: olcDatabase={1}${LDAPDB},cn=config
	changetype: modify
	delete: olcAccess
	olcAccess: {0}
	-
	add: olcAccess
	olcAccess: {0}to attrs=userPassword by self write by dn="cn=${LDAP_READER},${DCNAME}" read by anonymous auth by * none
	EOInp
	if [ $? -ne 0 ] ; then echo "Error executing ${FUNCNAME[0]}..." ; exit 1 ; fi
	# Should result in following olcAccess entries on dn: olcDatabase={1}${LDAPDB},cn=config
	#  olcAccess: {0}to attrs=userPassword by self write by dn="cn=${LDAP_READER},${DCNAME}" read by anonymous auth by * none
	#  olcAccess: {1}to attrs=shadowLastChange by self write by * read
	#  olcAccess: {2}to * by * read
}


# load_modules
#
# Load necessary modules, e.g. syncprov
#
load_modules() {
	echo "Running ${FUNCNAME[0]}..."
	sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<-EOInp
		dn: cn=module{0},cn=config
		changetype: modify
		add: olcModuleLoad
		olcModuleLoad: syncprov
	EOInp
	if [ $? -ne 0 ] ; then echo "Error executing ${FUNCNAME[0]}..." ; exit 1 ; fi
}


# set_olcServerID
#
# Set olcServerID based on RID extracted from provider name
#
set_olcServerID() {
	echo "Running ${FUNCNAME[0]}..."
	# update SLAPD_SERVICES in /etc/default/slapd
	sudo perl -pi -e "s@(^SLAPD_SERVICES.+)@#\$1\\nSLAPD_SERVICES=\"ldap://${MASTER}.${DOMAIN} ldapi://\"@" /etc/default/slapd
	sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<-EOInp
		dn: cn=config
		changeType: modify
		add: olcServerID
		olcServerID: ${MASTER_RID}
	EOInp
	if [ $? -ne 0 ] ; then echo "Error executing ${FUNCNAME[0]}..." ; exit 1 ; fi
}


# update_olcServerID_URI
#
# Update olcServerID with provider URI for replication
#
update_olcServerID_URI() {
	echo "Running ${FUNCNAME[0]}..."
	LDIF_FILE="${TEMP_DIR}/${$}.update_olcserverid.ldif" ; touch ${LDIF_FILE} ; chmod 600 ${LDIF_FILE}
	cat <<-EOInp > ${LDIF_FILE}
		dn: cn=config
		changetype: modify
		replace: olcServerID
	EOInp
	for i in ${!LDAP_MASTERS[@]}; do
		R=$(( $i + 1 ))
		M=${LDAP_MASTERS[$i]}
		echo "olcServerID: ${R} ldap://${M}.${DOMAIN}"	>> ${LDIF_FILE}
	done
	# Make sure the LDIF is there before trying to use it.
	if [ ! -f ${LDIF_FILE} ] ; then
		echo "${LDIF_FILE} not found, aborting."
		echo "Error executing ${FUNCNAME[0]}..."
		exit 1
	fi
	sudo ldapmodify -Y EXTERNAL -H ldapi:/// -f ${LDIF_FILE}
	# Make sure ldapmodify existed successfully
	if [ $? -ne 0 ] ; then echo "Error executing ${FUNCNAME[0]}..." ; exit 1 ; fi
	# Cleanup
	if [ $KEEP_TEMP_FILES -ne 1 ] ; then
		sudo rm -f "${LDIF_FILE}"
	fi
	if [ $? -ne 0 ] ; then echo "Error executing ${FUNCNAME[0]}..." ; exit 1 ; fi
}


# add_syncprov_overlay
#
# Add olcOverlay=syncprov to config
#
add_syncprov_overlay() {
	echo "Running ${FUNCNAME[0]}..."
	sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<-EOInp
		dn: olcOverlay=syncprov,olcDatabase={0}config,cn=config
		changetype: add
		objectClass: olcOverlayConfig
		objectClass: olcSyncProvConfig
		olcOverlay: syncprov
	EOInp
	if [ $? -ne 0 ] ; then echo "Error executing ${FUNCNAME[0]}..." ; exit 1 ; fi
}


# add_config_SyncRepl
#
# Add SyncRepl to the config
#
add_config_SyncRepl() {
	echo "Running ${FUNCNAME[0]}..."
	# Build ldif for add_config_SyncRepl
	LDIF_FILE="${TEMP_DIR}/${$}.config_syncrepl.ldif" ; touch ${LDIF_FILE} ; chmod 600 ${LDIF_FILE}
	cat <<-EOInp > ${LDIF_FILE}
		dn: olcDatabase={0}config,cn=config
		changetype: modify
		add: olcSyncRepl
	EOInp
	for i in ${!LDAP_MASTERS[@]}; do
		R=$(( $i + 1 ))
		M=${LDAP_MASTERS[$i]}
		echo "olcSyncRepl: rid=${R} provider=ldap://${M}.${DOMAIN} binddn=\"cn=${LDAP_READER},${DCNAME}\""	>> ${LDIF_FILE}
		echo "  bindmethod=simple credentials=${LDAP_READER_PASSWORD}"	>> ${LDIF_FILE}
		echo "  searchbase=\"cn=config\" type=refreshAndPersist"	>> ${LDIF_FILE}
		echo "  retry=\"5 5 300 5\" timeout=1"				>> ${LDIF_FILE}
		echo "  starttls=critical tls_reqcert=demand"			>> ${LDIF_FILE}
	done
	cat <<-EOInp >> ${LDIF_FILE}
		-
		add: olcMirrorMode
		olcMirrorMode: TRUE
	EOInp
	# Make sure the LDIF is there before trying to use it.
	if [ ! -f ${LDIF_FILE} ] ; then
		echo "${LDIF_FILE} not found, aborting."
		echo "Error executing ${FUNCNAME[0]}..."
		exit 1
	fi
	sudo ldapmodify -Y EXTERNAL -H ldapi:/// -f ${LDIF_FILE}
	# Make sure ldapmodify existed successfully
	if [ $? -ne 0 ] ; then echo "Error executing ${FUNCNAME[0]}..." ; exit 1 ; fi
	# Cleanup
	if [ $KEEP_TEMP_FILES -ne 1 ] ; then
		sudo rm -f "${LDIF_FILE}"
	fi
	if [ $? -ne 0 ] ; then echo "Error executing ${FUNCNAME[0]}..." ; exit 1 ; fi
}


# setup_daily_backup
#
# Install and configure daily backups
#
setup_daily_backup() {
	echo "Running ${FUNCNAME[0]}..."
	# ldap-git-backup handles everything nicely
	apt -y install ldap-git-backup
	if [ $? -ne 0 ] ; then echo "Error executing ${FUNCNAME[0]}..." ; exit 1 ; fi
}



# main...

pkg_install
add_indexes
config_tls
add_bind_account
disallow_bind_anon
#add_config_olcRootPW	# not be needed since LDAP_READER is being used for replication
add_ldap_reader
add_ldap_reader_acl
load_modules
set_olcServerID
update_olcServerID_URI
add_syncprov_overlay
add_config_SyncRepl
setup_daily_backup

echo "Executing final restart..."
sudo systemctl restart slapd.service

