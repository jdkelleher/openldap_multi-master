#!/bin/bash

# Author: Jason D. Kelleher
# https://github.com/jdkelleher/openldap_multi-master


SCRIPT_BASE="${0%/*}"

source ${SCRIPT_BASE}/config


# Need to move a bunch of this stuff into the config

KEY_SIZE=2048

CA_TEMPLATE=${FILE_BASE}/slapd_ca.info
CA_PRIV_KEY=${FILE_BASE}/slapd_cakey.pem
CA_CERT=${FILE_BASE}/slapd_cacert.pem

LDAP_TEMPLATE=${FILE_BASE}/slapd.info
LDAP_PRIV_KEY=${FILE_BASE}/slapd_key.pem
LDAP_CERT=${FILE_BASE}/slapd_cert.pem

print_usage() {
	echo "Usage: $0 [-h] [-k] [master master ...]"
	echo -e "\t[-h] pring usage (this message)"
	echo -e "\t[master] is one or more masters defined in the config to list in the cert."
	echo -e "\tIf not specified, all master listed in the config will be used - likley desired."
	echo -e "\n\tThis should be run once to generate a cert file shared by all masters."
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


CERTTOOL_CHECK=`which certtool`
if [ -z "${CERTTOOL_CHECK}" ] ; then
	echo "Error: certtool not found.  Aborting...."
	exit 1
fi

# Make sure ${FILE_BASE} exists
mkdir -p ${FILE_BASE}
if [ ! -d ${FILE_BASE} ] ; then
	echo "Error directory ${FILE_BASE} does not exist.  Aborting..."
	exit 1
fi


# create_ca_privkey
#
# Create a private key for the Certificate Authority
#
create_ca_privkey() {
	echo "Running ${FUNCNAME[0]}..."
	certtool --generate-privkey > ${CA_PRIV_KEY}
	if [ $? -ne 0 ] ; then echo "Error executing ${FUNCNAME[0]}..." ; exit 1 ; fi
	chmod 600 ${CA_PRIV_KEY}
}


# create_ss_ca_cert
#
# Create the self-signed CA certificate
#
create_ss_ca() {
	echo "Running ${FUNCNAME[0]}..."
	# Build template
        touch ${CA_TEMPLATE} ; chmod 644 ${CA_TEMPLATE}
        cat <<-EOInp	> ${CA_TEMPLATE}
		cn = ${ORGANIZATION}
		expiration_days = 730
		ca
		cert_signing_key
	EOInp
	certtool --generate-self-signed \
		--load-privkey ${CA_PRIV_KEY} \
		--template ${CA_TEMPLATE} \
		--outfile ${CA_CERT}
	if [ $? -ne 0 ] ; then echo "Error executing ${FUNCNAME[0]}..." ; exit 1 ; fi
}


# create_slapd_privkey
#
# Create the private key for ldap
#
create_slapd_privkey() {
	echo "Running ${FUNCNAME[0]}..."
	certtool --generate-privkey \
		--bits ${KEY_SIZE} \
		--outfile ${LDAP_PRIV_KEY}
	if [ $? -ne 0 ] ; then echo "Error executing ${FUNCNAME[0]}..." ; exit 1 ; fi
	chmod 600 ${LDAP_PRIV_KEY}
}


# create_ss_slapd_cert
#
# Create the LDAP certificate
#
create_ss_slapd_cert() {
	echo "Running ${FUNCNAME[0]}..."
	# Build template
        touch ${LDAP_TEMPLATE} ; chmod 644 ${LDAP_TEMPLATE}
        cat <<-EOInp	> ${LDAP_TEMPLATE}
		cn = "${ORGANIZATION} LDAP"
	EOInp

	for i in ${!MASTER_LIST[@]}; do
		M=${MASTER_LIST[$i]}
		echo "dns_name = ${M}.${DOMAIN}"	>> ${LDAP_TEMPLATE}
	done
        cat <<-EOInp				>> ${LDAP_TEMPLATE}
		tls_www_server
		encryption_key
		signing_key
		expiration_days = 3650
	EOInp
	certtool --generate-certificate \
		--load-privkey ${LDAP_PRIV_KEY} \
		--load-ca-certificate ${CA_CERT} \
		--load-ca-privkey ${CA_PRIV_KEY} \
		--template ${LDAP_TEMPLATE} \
		--outfile ${LDAP_CERT}
	if [ $? -ne 0 ] ; then echo "Error executing ${FUNCNAME[0]}..." ; exit 1 ; fi
}


# main...

create_ca_privkey
create_ss_ca
create_slapd_privkey
create_ss_slapd_cert

