#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${DATA_DIR:-$SCRIPT_DIR/samba-data}"
IMAGE_NAME="${IMAGE_NAME:-local-samba-ad-dc}"
CONTAINER_NAME="${CONTAINER_NAME:-samba-ad-dc}"
DOMAIN="${DOMAIN:-NRSH13-HADOOP}"
REALM="${REALM:-NRSH13-HADOOP.COM}"
DNS_DOMAIN="${DNS_DOMAIN:-nrsh13-hadoop.com}"
ADMIN_PASS="${ADMIN_PASS:-DummyPass123!@2929}"
USER_NAME="${USER_NAME:-768019}"
USER_PASS="${USER_PASS:-DummyPass123!@2929}"
USER2_NAME="${USER2_NAME:-768020}"
USER2_PASS="${USER2_PASS:-DummyPass123!@2929}"
GROUP_NAME="${GROUP_NAME:-A_HADOOP_ADMINS}"

echo "=== Samba AD DC setup script ==="

test -x "$(command -v docker)" || {
  echo "Error: Docker is not installed or not on PATH." >&2
  exit 1
}

if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose"
else
  echo "Error: docker compose command not found. Install Docker Compose or use Docker Desktop." >&2
  exit 1
fi

mkdir -p "$DATA_DIR"

echo "Building Samba AD DC image..."
cd "$SCRIPT_DIR"
docker build -t "$IMAGE_NAME" .

echo "Starting container with persistent Samba volume..."
$COMPOSE_CMD down || true
$COMPOSE_CMD up -d

function exec_container() {
  docker exec "$CONTAINER_NAME" bash -lc "$1"
}

function container_running() {
  docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || echo false
}

if [[ "$(container_running)" != "true" ]]; then
  echo "Waiting for container $CONTAINER_NAME to start..."
  sleep 3
fi

if ! docker exec "$CONTAINER_NAME" test -f /var/lib/samba/private/secrets.tdb >/dev/null 2>&1; then
  echo "Removing stale Samba configuration before provisioning..."
  exec_container "rm -f /etc/samba/smb.conf"
  echo "Provisioning Samba AD domain $REALM..."
  exec_container "samba-tool domain provision --use-rfc2307 --realm='$REALM' --domain='$DOMAIN' --adminpass='$ADMIN_PASS' --server-role=dc --dns-backend=SAMBA_INTERNAL"
else
  echo "Samba AD domain already provisioned; skipping provision step."
fi

echo "Ensuring Administrator password is set..."
exec_container "samba-tool user setpassword Administrator --newpassword='$ADMIN_PASS'"

echo "Starting Samba AD DC process inside container..."
exec_container "nohup samba -i >/var/log/samba.log 2>&1 &"
echo "Waiting for LDAP service on port 389..."
exec_container "bash -lc 'for i in {1..30}; do echo > /dev/tcp/127.0.0.1/389 >/dev/null 2>&1 && exit 0; sleep 1; done; echo LDAP did not start in time >&2; exit 1'"

for user in "$USER_NAME" "$USER2_NAME"; do
  if ! exec_container "samba-tool user list | grep -x '$user'" >/dev/null 2>&1; then
    echo "Creating user $user..."
    exec_container "samba-tool user create '$user' '$USER_PASS' --use-username-as-cn --must-change-at-next-login"
  else
    echo "User $user already exists; skipping creation."
  fi

  echo "Setting password for user $user..."
  exec_container "samba-tool user setpassword '$user' --newpassword='$USER_PASS'"
done

if ! exec_container "samba-tool group list | grep -x '$GROUP_NAME'" >/dev/null 2>&1; then
  echo "Creating group $GROUP_NAME..."
  exec_container "samba-tool group add '$GROUP_NAME'"
else
  echo "Group $GROUP_NAME already exists; skipping creation."
fi

echo "Adding users to group $GROUP_NAME..."
exec_container "samba-tool group addmembers '$GROUP_NAME' '$USER_NAME,$USER2_NAME' || true"

echo
echo "=== Test LDAP query inside container ==="
exec_container "LDAPTLS_REQCERT=never ldapsearch -LLL -H ldaps://localhost -x -D 'CN=Administrator,CN=Users,DC=nrsh13-hadoop,DC=com' -w '$ADMIN_PASS' -b 'DC=nrsh13-hadoop,DC=com' '(sAMAccountName=$USER_NAME)'"

echo
cat <<'EOF'
=== Completed ===

Your Samba AD DC container is running as: $CONTAINER_NAME
LDAP host: localhost
Base DN: DC=nrsh13-hadoop,DC=com
Realm: $REALM

Sample ldapsearch command from the Mac host:

export LDAPTLS_REQCERT=never
export ADMIN_PASS='DummyPass123!@2929'
export USER_NAME='768019'

LDAPTLS_REQCERT=never ldapsearch -LLL \
  -H ldaps://127.0.0.1 \
  -x \
  -D "CN=Administrator,CN=Users,DC=nrsh13-hadoop,DC=com" \
  -w '$ADMIN_PASS' \
  -b "DC=nrsh13-hadoop,DC=com" \
  "(sAMAccountName=$USER_NAME)"

If the certificate is trusted, remove `LDAPTLS_REQCERT=never`.
EOF
