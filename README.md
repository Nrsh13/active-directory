# Samba Active Directory Local Setup

This repository provides a local Samba Active Directory Domain Controller running on your Mac.

## Overview

- Domain: `nrsh13-hadoop.com`
- NetBIOS domain: `NRSH13-HADOOP`
- Kerberos realm: `NRSH13-HADOOP.COM`
- Administrator password: Configurable (see [Credentials & Security](#credentials--security) below)
- AD groups:
  - `A_HADOOP_ADMINS`
  - `A_Kafka_Users_Dev`
- AD users:
  - `768019`
  - `768020`
- Both users are members of both AD groups

## Repository files

- `Dockerfile` — builds the Samba AD DC image
- `docker-compose.yml` — runs the AD container with persistent volumes
- `setup-samba-ad-dc.sh` — provisions the AD domain, creates users and group membership, and validates LDAP
- `.env.example` — template for credential configuration (copy to `.env` and customize)
- `.gitignore` — prevents accidental commits of credentials and data
- `README.md` — usage and integration guidance

## Credentials & Security

⚠️ **This is a local development/test Active Directory setup.** The default credentials are intentionally simple and should be changed for any serious use.

**Credential Management:**
1. Copy `.env.example` to `.env`: `cp .env.example .env`
2. Edit `.env` and set your own passwords and configuration
3. The script reads from environment variables, so `.env` values will override defaults
4. **Never commit `.env` to git** — it's already in `.gitignore`

**Important:** The `.env` file is excluded from git. Each developer/environment should have their own `.env` with appropriate credentials.

## Local macOS deployment

### Prerequisites

- Docker Desktop installed
- `docker compose` or `docker-compose` available

### Run the AD setup

```bash
# Optional: Create and customize .env (uses defaults if not present)
cp .env.example .env
# Edit .env to set your own passwords

cd /Users/nrsh13/GitHub/active-directory
./setup-samba-ad-dc.sh
```

### What it configures

- Builds the Docker image
- Starts the Samba AD DC container
- Provisions the AD domain
- Sets Administrator password (from `ADMIN_PASS` env var, default: `Dummy@2929`)
- Creates users `768019` and `768020` (configurable via `USER_NAME`, `USER2_NAME`, etc.)
- Creates groups `A_HADOOP_ADMINS` and `A_Kafka_Users_Dev`
- Adds both users to both groups
- Validates the domain with an LDAP search

### Verify from host

This local setup now allows plain LDAP binds without requiring certificates or extra environment exports.

```bash
ldapsearch -LLL \
  -H ldap://127.0.0.1:389 \
  -x \
  -D "CN=Administrator,CN=Users,DC=nrsh13-hadoop,DC=com" \
  -w '${ADMIN_PASS}' \
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
  -w '${ADMIN_PASS}' \
  -b "CN=Users,DC=nrsh13-hadoop,DC=com" \
  'userPrincipalName=*768019*'
```

### Bind as user `768019`

```bash
ldapsearch -LLL \
  -H ldap://127.0.0.1:389 \
  -x \
  -D "CN=768019,CN=Users,DC=nrsh13-hadoop,DC=com" \
  -w '${USER_PASS}' \
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
- Bind password: Set in `.env` (or use default from `.env.example`)
- Base DN: `CN=Users,DC=nrsh13-hadoop,DC=com`
- User search filter: `(&(objectClass=user)(sAMAccountName={username}))`
- Group name: `memberof=CN=A_HADOOP_ADMINS,CN=Users,DC=nrsh13-hadoop,DC=com`

### Sample cloud app query

```bash
ldapsearch -LLL   -H ldap://ldap.nrsh13-hadoop.com:389   -x   -D "CN=Administrator,CN=Users,DC=nrsh13-hadoop,DC=com"   -w '${ADMIN_PASS}'   -b "DC=nrsh13-hadoop,DC=com"   "(sAMAccountName=768019)"
```
