#!/bin/bash

export SCRIPT_BASE="${0%/*}"

source ${SCRIPT_BASE}/config


print_usage() {
	echo "Usage: $0 [-h] [-k]"
	echo -e "\t[-h] pring usage (this message)"
	echo -e "\t[-k] keep temporary files; this will overide the setting in config"
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


# These depend on values in the config file
export MASTER_1=`echo ${LDAP_URI_LIST} | cut -d ' ' -f1`
export BINDDN="cn=${BIND_ACCOUNT},${DCNAME}"
export BINDPW=${BIND_ACCOUNT_PASSWORD}



cat<<-EOInp
	${LDAP_URI_LIST}
	${DOMAIN}
	${BIND_ACCOUNT}
	${BIND_ACCOUNT_PASSWORD}
	${MASTER_1}
	${DCNAME}
	${BINDDN}
	${BINDPW}

	# if mistake
	sudo dpkg-reconfigure libpam-ldap nscd nslcd ldap-utils libnss-ldapd ldap-auth-config

EOInp


# client_setup()
#
# Installs ldap client packages unattended using debconf
#
client_setup() {

		#ldap-auth-config	ldap-auth-config/rootbinddn	string	cn=manager,dc=example,dc=net
		#ldap-auth-config	ldap-auth-config/rootbindpw	password	

	#cat <<-EOInp
	debconf-set-selections <<-EOInp
		ldap-auth-config	ldap-auth-config/dblogin	boolean	true
		ldap-auth-config	ldap-auth-config/binddn	string	${BINDDN}
		ldap-auth-config	ldap-auth-config/bindpw	password	${BINDPW}
		ldap-auth-config	ldap-auth-config/override	boolean	true
		ldap-auth-config	ldap-auth-config/dbrootlogin	boolean	false
		ldap-auth-config	ldap-auth-config/ldapns/ldap_version	select	3
		ldap-auth-config	ldap-auth-config/pam_password	select	md5
		ldap-auth-config	ldap-auth-config/ldapns/base-dn	string	${DCNAME}
		ldap-auth-config	ldap-auth-config/ldapns/ldap-server	string	${LDAP_URI_LIST}
		libnss-ldapd	libnss-ldapd/nsswitch	multiselect	group, passwd, shadow
		libnss-ldapd:amd64	libnss-ldapd/nsswitch	multiselect	group, passwd, shadow
		nslcd	nslcd/ldap-bindpw	password	${BINDPW}
		nslcd	nslcd/ldap-binddn	string	${BINDDN}
		nslcd	nslcd/ldap-base	string	${DCNAME}
		nslcd	nslcd/ldap-uris	string	${LDAP_URI_LIST}
		nslcd	nslcd/ldap-starttls	boolean	true
		nslcd	nslcd/ldap-reqcert	string	allow
		nslcd	nslcd/ldap-cacertfile	string	/etc/ssl/certs/ca-certificates.crt
	EOInp

	sudo apt -y install libpam-ldap nscd ldap-utils libnss-ldapd ldap-auth-config
	if [ $? -ne 0 ] ; then echo "Error executing ${FUNCNAME[0]}..." ; exit 1 ; fi
}


check_setup(){
	# check /etc/ldap.conf for proper configuration, should see:
	# uri ldap://ldap01.sv.grumpydude.com ldap://ldap02.sv.grumpydude.com ldap://ldap03.sv.grumpydude.com
	echo "Check uri in /etc/ldap.conf..."
	grep '^uri' /etc/ldap.conf
	if [ $? -ne 0 ] ; then echo "Error executing ${FUNCNAME[0]}..." ; exit 1 ; fi

	# check bind credentials
	echo "Check bind credentials in /etc/ldap.conf..."
	egrep '^binddn|^bindpw' /etc/ldap.conf
	if [ $? -ne 0 ] ; then echo "Error executing ${FUNCNAME[0]}..." ; exit 1 ; fi

	echo "Verifying bind..."
	ldapwhoami -x -H ${MASTER_1} -D ${BINDDN} -w ${BINDPW}
	if [ $? -ne 0 ] ; then echo "Error executing ${FUNCNAME[0]}..." ; exit 1 ; fi

	echo "Verifying read..."
	ldapsearch -x -H ${MASTER_1} -b ${DCNAME} -D ${BINDDN} -w ${BINDPW} | grep "${BIND_ACCOUNT}"
	if [ $? -ne 0 ] ; then echo "Error executing ${FUNCNAME[0]}..." ; exit 1 ; fi
}




# main...

client_setup
check_setup

