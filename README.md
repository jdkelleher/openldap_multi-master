# openldap_multi-master
A set of scripts and information to install Openldap in an n-way multi-master configuration.  This consolidates a number of items found in documents and code on the web all in one place...
* Installation, configuration, and test all driven by a config file
* Unattended install based on apt and debconf-set-selections
* N-Way Multi-Master support (why?  ...why not?)
* Replication using SyncRepl of config and data
* Everything done in bash so it can be easily understood - documentation via code
* Configures daily backups via ldap-git-backup
* Hardened for security
  * Unprivileged accounts for replication and bind
  * No privileged remote access to cn=config
  * Disallows bind_anon
  * TLS (self-signed certs)
* Includes test scripts to understand what is/isn't working
* Fully tested on Ubuntu 16.04.6 LTS
* Everything available via git - push requests to expand functionality and test cases welcome


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
    * Updates olcServerID with provider URI for replication
    * Adds the syncprov overlay for cn=config
    * Configures SyncRepl for cn=config
    * And finally restarts slapd - hopefully with positive results
* 2_db_syncrepl_setup.sh
  * Script to configure database replication
  * Run on one*master* (provider)
    * Adds the syncprov overlay for the db
    * Configures SyncRepl for the db
  * Note, if a single master is rebuilt this will need to be run on it to bring it into the replication group
* client_setup.sh
  * Script to run on clients
    * Install and configure client packages
    * Updates /etc/ldap.conf
    * Performs basic checks
* server_files
  * Sample keys and certs
  * These files are generated by 0_create_certs.sh
* ZZ_test_bind.sh
  * Tests binding to the masters after install and setup
* ZZ_test_update.sh
  * Tests replication by adding a dummy entry on one master then searching on another

