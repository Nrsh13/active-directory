#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${DATA_DIR:-$SCRIPT_DIR/samba-data}"
IMAGE_NAME="${IMAGE_NAME:-local-samba-ad-dc}"
CONTAINER_NAME="${CONTAINER_NAME:-samba-ad-dc}"
DOMAIN="${DOMAIN:-NRSH13-HADOOP}"
REALM="${REALM:-NRSH13-HADOOP.COM}"
DNS_DOMAIN="${DNS_DOMAIN:-nrsh13-hadoop.com}"
ADMIN_PASS="${ADMIN_PASS:-Dummy@2929}"
USER_NAME="${USER_NAME:-768019}"
USER_PASS="${USER_PASS:-Dummy@2929}"
USER2_NAME="${USER2_NAME:-768020}"
USER2_PASS="${USER2_PASS:-Dummy@2929}"
GROUP_NAME="${GROUP_NAME:-A_HADOOP_ADMINS}"
CERT_BASENAME="${CERT_BASENAME:-kafka-lab01.nrsh13-hadoop.com}"
ROOT_CA_CERT="${ROOT_CA_CERT:-root-ca.crt}"
DEFAULT_CERT_DIRS=("${HOME}/GitHub/aws_confluent_kafka_setup/confluent_kafka_setup_secure/selfSignedCertificates" "/var/ssl/private")
if [[ -n "${CERT_DIR:-}" ]]; then
  CERT_DIR="${CERT_DIR}"
else
  for candidate in "${DEFAULT_CERT_DIRS[@]}"; do
    if [[ -d "$candidate" ]]; then
      CERT_DIR="$candidate"
      break
    fi
  done
fi
if [[ -z "${CERT_DIR:-}" ]]; then
  CERT_DIR="${HOME}/GitHub/aws_confluent_kafka_setup/confluent_kafka_setup_secure/selfSignedCertificates"
fi

ROOT_CA_CANDIDATES=("${ROOT_CA_CERT:-root-ca.crt}" "ca.crt")
for candidate in "${ROOT_CA_CANDIDATES[@]}"; do
  if [[ -f "$CERT_DIR/$candidate" ]]; then
    ROOT_CA_CERT="$candidate"
    break
  fi
done

function find_cert_key_pair() {
  local dir="$1"
  if [[ -f "$dir/$CERT_BASENAME.crt" && -f "$dir/$CERT_BASENAME.key" ]]; then
    return 0
  fi

  for certfile in "$dir"/*.crt; do
    [[ -e "$certfile" ]] || continue
    local base
    base=$(basename "$certfile" .crt)
    if [[ "$base" == "root-ca" || "$base" == "ca" ]]; then
      continue
    fi
    if [[ -f "$dir/$base.key" ]]; then
      CERT_BASENAME="$base"
      echo "Using cert/key pair: $CERT_BASENAME.crt and $CERT_BASENAME.key"
      return 0
    fi
  done

  for keyfile in "$dir"/*.key; do
    [[ -e "$keyfile" ]] || continue
    local base
    base=$(basename "$keyfile" .key)
    if [[ -f "$dir/$base.crt" ]]; then
      CERT_BASENAME="$base"
      echo "Using cert/key pair: $CERT_BASENAME.crt and $CERT_BASENAME.key"
      return 0
    fi
  done

  return 1
}

if [[ -d "$CERT_DIR" ]]; then
  if ! find_cert_key_pair "$CERT_DIR"; then
    echo "Warning: expected cert/key pair not found in $CERT_DIR" >&2
  fi
fi

function install_tls_certs() {
  if [[ -d "$CERT_DIR" ]]; then
    if [[ -f "$CERT_DIR/$CERT_BASENAME.crt" && -f "$CERT_DIR/$CERT_BASENAME.key" ]]; then
      echo "Installing TLS certs from $CERT_DIR into Samba container..."
      exec_container "mkdir -p /var/lib/samba/private/tls"
      docker cp "$CERT_DIR/$CERT_BASENAME.crt" "$CONTAINER_NAME":/var/lib/samba/private/tls/cert.pem
      docker cp "$CERT_DIR/$CERT_BASENAME.key" "$CONTAINER_NAME":/var/lib/samba/private/tls/key.pem
      if [[ -f "$CERT_DIR/$ROOT_CA_CERT" ]]; then
        docker cp "$CERT_DIR/$ROOT_CA_CERT" "$CONTAINER_NAME":/var/lib/samba/private/tls/ca.pem
      fi
      exec_container "chown root:root /var/lib/samba/private/tls/cert.pem /var/lib/samba/private/tls/key.pem /var/lib/samba/private/tls/ca.pem 2>/dev/null || true"
      exec_container "chmod 0600 /var/lib/samba/private/tls/key.pem"
    else
      echo "Warning: expected cert/key not found in $CERT_DIR" >&2
    fi
  else
    echo "Warning: certificate directory $CERT_DIR does not exist" >&2
  fi
}

function configure_samba_tls() {
  if docker exec "$CONTAINER_NAME" test -f /etc/samba/smb.conf >/dev/null 2>&1; then
    echo "Configuring Samba for plain LDAP bind support..."
    docker exec "$CONTAINER_NAME" bash -lc "sed -i '/^tls enabled/d;/^tls keyfile/d;/^tls certfile/d;/^tls cafile/d;/^ldap server require strong auth/d' /etc/samba/smb.conf && awk '/^\[global\]/{print; print \"    ldap server require strong auth = no\"; print \"    tls enabled = no\"; next}1' /etc/samba/smb.conf > /tmp/smb.conf.new && mv /tmp/smb.conf.new /etc/samba/smb.conf"
  fi
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

install_tls_certs
configure_samba_tls

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

echo "Stopping any existing Samba server instances..."
exec_container "pkill -f '^samba:' || true"
exec_container "sleep 1 || true"

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
exec_container "ldapsearch -LLL -H ldap://localhost -x -D 'CN=Administrator,CN=Users,DC=nrsh13-hadoop,DC=com' -w '$ADMIN_PASS' -b 'DC=nrsh13-hadoop,DC=com' '(sAMAccountName=$USER_NAME)'"

echo
cat <<EOF
=== Completed ===

Your Samba AD DC container is running as: $CONTAINER_NAME
LDAP host: localhost
Base DN: DC=nrsh13-hadoop,DC=com
Realm: $REALM
Password: $ADMIN_PASS

Sample ldapsearch command from the Mac host:

ldapsearch -LLL \
  -H ldap://127.0.0.1:389 \
  -x \
  -D "CN=Administrator,CN=Users,DC=nrsh13-hadoop,DC=com" \
  -w '$ADMIN_PASS' \
  -b "DC=nrsh13-hadoop,DC=com" \
  "(sAMAccountName=$USER_NAME)"

EOF
