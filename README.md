# openldap_multi-master
A set of scripts and information to install Openldap in an n-way multi-master configuration.

This has been tested on Ubuntu 16.04.6 LTS.  Updates to expand support are welcome.


* References.txt
  * List of references and resources used to create these scripts
* config
  * Sample config file
* 0_create_certs.sh
  * Script to create self-signed certs to secure Openldap
  * Run as a pre-step
* 1_master_setup.sh
  * Script to install Openldap and enable config replication
  * Run on each master (provider)
    * Installs Openldap
    * Adds a few indexes
    * Configures TLS
    * Adds a bind account and disallows bind anon
    * Adds a reader account for replication and updates ACLs
    * Loads the syncprov module
    * Sets olcServerID and updates /etc/default/slapd
    * Updates olcServerID with provicer URI for replication
    * Adds the syncprov overlay for cn=config
    * Configures SyncRepl for cn=config
    * And finally restarts slapd - hopefully with positive results
* 2_db_syncrepl_setup.sh
  * Script configure database replication
  * Run one *master* (provider)
    * Adds the syncprov overlay for the db
    * Configures SyncRepl for the db
* client_setup.sh
  * Script to run on clients
    * Install and configure client packages
    * Updates /etc/ldap.conf
    * Performs some basic checks
* server_files
  * Sample keys and certs
* ZZ_test_bind.sh
  * Tests binding to the masters after install and setup
* ZZ_test_update.sh
  * Tests replication by adding a dummy entry on one master then searching on another

