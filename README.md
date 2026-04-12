# Samba Active Directory Local Setup

This repository provides a local Samba Active Directory Domain Controller running on your Mac.

## Overview

- Domain: `nrsh13-hadoop.com`
- NetBIOS domain: `NRSH13-HADOOP`
- Kerberos realm: `NRSH13-HADOOP.COM`
- Administrator password: `Kamla@2929`
- AD group: `A_HADOOP_ADMINS`
- AD users:
  - `768019`
  - `768020`
- Both users have password: `Kamla@2929`
- Both users are members of `A_HADOOP_ADMINS`

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
- sets Administrator password to `Kamla@2929`
- creates users `768019` and `768020`
- creates group `A_HADOOP_ADMINS`
- adds both users to the group
- validates the domain with an LDAPS search

### Verify from host

```bash
LDAPTLS_REQCERT=never ldapsearch -LLL \
  -H ldaps://127.0.0.1 \
  -x \
  -D "CN=Administrator,CN=Users,DC=nrsh13-hadoop,DC=com" \
  -w 'Kamla@2929' \
  -b "CN=Users,DC=nrsh13-hadoop,DC=com" \
  'userPrincipalName=*768019*'
```

### Search for user `768019`

```bash
LDAPTLS_REQCERT=never ldapsearch -LLL \
  -H ldaps://127.0.0.1 \
  -x \
  -D "CN=Administrator,CN=Users,DC=nrsh13-hadoop,DC=com" \
  -w 'Kamla@2929' \
  -b "CN=Users,DC=nrsh13-hadoop,DC=com" \
  'userPrincipalName=*768019*'
```

### Bind as user `768019`

```bash
LDAPTLS_REQCERT=never ldapsearch -LLL \
  -H ldaps://127.0.0.1 \
  -x \
  -D "CN=768019,CN=Users,DC=nrsh13-hadoop,DC=com" \
  -w 'Kamla@2929' \
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

- LDAP host: `<your-mac-host-or-ip>`
- LDAP port: `389`
- LDAPS port: `636`
- Bind DN: `CN=Administrator,CN=Users,DC=nrsh13-hadoop,DC=com`
- Bind password: `Kamla@2929`
- Base DN: `CN=Users,DC=nrsh13-hadoop,DC=com`
- User search filter: `(&(objectClass=user)(sAMAccountName={username}))`
- Group name: `A_HADOOP_ADMINS`
> Note: Because the domain is `nrsh13-hadoop.com`, the correct domain component form is `DC=nrsh13-hadoop,DC=com`. If you instead provision the domain as `nrsh13.hadoop.com`, then you would use `DC=nrsh13,DC=hadoop,DC=com`.
### Sample cloud app query

```bash
ldapsearch -H ldaps://<your-mac-host-or-ip>:636 \
  -D "CN=Administrator,CN=Users,DC=nrsh13-hadoop,DC=com" \
  -w 'Kamla@2929' \
  -b "CN=Users,DC=nrsh13-hadoop,DC=com" \
  'userPrincipalName=*768019*'
```

### Connectivity guidance

- Your Mac must be reachable from the cloud app host.
- Use VPN, SSH tunnel, or secure networking if your Mac is behind NAT/firewall.
- Do not expose the AD host directly to the public internet without access controls.
- Prefer `ldaps://` for encrypted traffic.

## AWS EC2 / EKS / AKS notes

This repository does not deploy AD on AWS. It documents how cloud applications can authenticate against your Mac-hosted AD.

### AWS EC2

- Use Docker or Docker Compose on an EC2 host if you want a separate AD instance.
- Use private networking and security groups to restrict access.
- Mount durable storage for `/var/lib/samba` and `/etc/samba`.

### EKS / AKS

- Use internal networking or VPN to reach the Mac-hosted AD.
- Do not expose the AD server directly to the public internet.
- Use a secure service discovery pattern and load only trusted traffic.

## Integration summary

Use these values in your application:

- LDAP base DN: `CN=Users,DC=nrsh13-hadoop,DC=com`
- Bind DN: `CN=Administrator,CN=Users,DC=nrsh13-hadoop,DC=com`
- Bind password: `Kamla@2929`
- User search filter: `(&(objectClass=user)(sAMAccountName={username}))`
- Group name: `A_HADOOP_ADMINS`
- Users: `768019`, `768020`

## Notes

- Both users `768019` and `768020` have password `Kamla@2929`.
- The group `A_HADOOP_ADMINS` includes both users.
- Use a dedicated production AD environment for serious workloads.
