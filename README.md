# Samba Active Directory Local Setup

This repository provides a local Samba Active Directory Domain Controller running on your Mac.

## Overview

- Domain: `nrsh13-hadoop.com`
- NetBIOS domain: `NRSH13-HADOOP`
- Kerberos realm: `NRSH13-HADOOP.COM`
- Administrator password: `Dummy@2929`
- AD groups:
  - `A_HADOOP_ADMINS`
  - `A_Kafka_Users_Dev`
- AD users:
  - `768019`
  - `768020`
- Both users have password: `Dummy@2929`
- Both users are members of both AD groups

## Repository files

- `Dockerfile` — builds the Samba AD DC image
- `docker-compose.yml` — runs the AD container with persistent volumes
- `setup-samba-ad-dc.sh` — provisions the AD domain, creates users and group membership, and validates LDAP
- `README.md` — usage and integration guidance

## Local macOS deployment

### Prerequisites

- Docker Desktop installed
- `docker compose` or `docker-compose` available

### Run the AD setup

```bash
cd /Users/nrsh13/Desktop/active-directory
./setup-samba-ad-dc.sh
```

### What it configures

- builds the Docker image
- starts the Samba AD DC container
- provisions the AD domain
- sets Administrator password to `Dummy@2929`
- creates users `768019` and `768020`
- creates group `A_HADOOP_ADMINS`
- adds both users to the group
- validates the domain with an LDAP search

### Verify from host

This local setup now allows plain LDAP binds without requiring certificates or extra environment exports.

```bash
ldapsearch -LLL \
  -H ldap://127.0.0.1:389 \
  -x \
  -D "CN=Administrator,CN=Users,DC=nrsh13-hadoop,DC=com" \
  -w 'Dummy@2929' \
  -b "CN=Users,DC=nrsh13-hadoop,DC=com" \
  'userPrincipalName=*768019*'
```

### Search for user `768019`

```bash
export LDAPTLS_CACERT='/path/to/root-ca.crt'

ldapsearch -LLL \
  -H ldap://127.0.0.1:389 \
  -x \
  -ZZ \
  -D "CN=Administrator,CN=Users,DC=nrsh13-hadoop,DC=com" \
  -w 'Dummy@2929' \
  -b "CN=Users,DC=nrsh13-hadoop,DC=com" \
  'userPrincipalName=*768019*'
```

### Bind as user `768019`

```bash
ldapsearch -LLL \
  -H ldap://127.0.0.1:389 \
  -x \
  -D "CN=768019,CN=Users,DC=nrsh13-hadoop,DC=com" \
  -w 'Dummy@2929' \
  -b "CN=Users,DC=nrsh13-hadoop,DC=com" \
  'userPrincipalName=*768019*'
```

### Cleanup

```bash
docker compose down -v
```

## Cloud app integration

The AD server stays on your Mac. Any applications on AWS EC2, EKS, or AKS should connect to the AD over network/TLS.

### AD endpoint details

- LDAP host: `ldap://ldap.nrsh13-hadoop.com:389`
- LDAP port: `389`
- Bind DN: `CN=Administrator,CN=Users,DC=nrsh13-hadoop,DC=com`
- Bind password: `Dummy@2929`
- Base DN: `CN=Users,DC=nrsh13-hadoop,DC=com`
- User search filter: `(&(objectClass=user)(sAMAccountName={username}))`
- Group name: `memberof=CN=A_HADOOP_ADMINS,CN=Users,DC=nrsh13-hadoop,DC=com`

### Sample cloud app query

```bash
ldapsearch -LLL   -H ldap://ldap.nrsh13-hadoop.com:389   -x   -D "CN=Administrator,CN=Users,DC=nrsh13-hadoop,DC=com"   -w 'Dummy@2929'   -b "DC=nrsh13-hadoop,DC=com"   "(sAMAccountName=768019)"
```
