#!/usr/bin/env bash
set -euo pipefail

# ---------- COLORS ----------
if [[ -t 1 ]]; then
  GREEN=$'\033[1;32m'
  CYAN=$'\033[1;36m'
  YELLOW=$'\033[1;33m'
  RED=$'\033[1;31m'
  BLUE=$'\033[1;34m'
  RESET=$'\033[0m'
else
  GREEN=""; CYAN=""; YELLOW=""; RED=""; BLUE=""; RESET=""
fi

log_step()    { printf "\n${BLUE}▶ %s\n${RESET}\n" "$*"; }
log_info()    { printf "${CYAN}[INFO]${RESET} %s\n" "$*"; }
log_success() { printf "${GREEN}[SUCCESS]${RESET} %s\n" "$*"; }
log_warning() { printf "${YELLOW}[WARN]${RESET} %s\n" "$*"; }
log_error()   { printf "${RED}[ERROR]${RESET} %s\n" "$*" >&2; }

# ---------- START BANNER ----------
echo
printf "${BLUE}=======================================${RESET}\n"
printf "${GREEN} Active Directory Setup Starting 🚀${RESET}\n"
printf "${BLUE}=======================================${RESET}\n"

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
SECOND_GROUP_NAME="${SECOND_GROUP_NAME:-A_Kafka_Users_Dev}"
CERT_BASENAME="${CERT_BASENAME:-kafka-lab01.nrsh13-hadoop.com}"
ROOT_CA_CERT="${ROOT_CA_CERT:-root-ca.crt}"

DEFAULT_CERT_DIRS=("/usr/nrsh13/GitHub/aws_confluent_kafka_setup/confluent_kafka_setup_secure/selfSignedCertificates" "/var/ssl/private")

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
  CERT_DIR="/usr/nrsh13/GitHub/aws_confluent_kafka_setup/confluent_kafka_setup_secure/selfSignedCertificates"
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
      log_info "Using cert/key pair: $CERT_BASENAME.crt and $CERT_BASENAME.key"
      return 0
    fi
  done

  for keyfile in "$dir"/*.key; do
    [[ -e "$keyfile" ]] || continue
    local base
    base=$(basename "$keyfile" .key)
    if [[ -f "$dir/$base.crt" ]]; then
      CERT_BASENAME="$base"
      log_info "Using cert/key pair: $CERT_BASENAME.crt and $CERT_BASENAME.key"
      return 0
    fi
  done

  return 1
}

if [[ -d "$CERT_DIR" ]]; then
  if ! find_cert_key_pair "$CERT_DIR"; then
    log_warning "expected cert/key pair not found in $CERT_DIR"
  fi
fi

function install_tls_certs() {
  if [[ -d "$CERT_DIR" ]]; then
    if [[ -f "$CERT_DIR/$CERT_BASENAME.crt" && -f "$CERT_DIR/$CERT_BASENAME.key" ]]; then
      log_step "Installing TLS certs from $CERT_DIR"
      exec_container "mkdir -p /var/lib/samba/private/tls"
      docker cp "$CERT_DIR/$CERT_BASENAME.crt" "$CONTAINER_NAME":/var/lib/samba/private/tls/cert.pem
      docker cp "$CERT_DIR/$CERT_BASENAME.key" "$CONTAINER_NAME":/var/lib/samba/private/tls/key.pem
      if [[ -f "$CERT_DIR/$ROOT_CA_CERT" ]]; then
        docker cp "$CERT_DIR/$ROOT_CA_CERT" "$CONTAINER_NAME":/var/lib/samba/private/tls/ca.pem
      fi
      exec_container "chown root:root /var/lib/samba/private/tls/* 2>/dev/null || true"
      exec_container "chmod 0600 /var/lib/samba/private/tls/key.pem"
    else
      log_warning "expected cert/key not found in $CERT_DIR"
    fi
  else
    log_warning "certificate directory $CERT_DIR does not exist"
  fi
}

function configure_samba_tls() {
  if docker exec "$CONTAINER_NAME" test -f /etc/samba/smb.conf >/dev/null 2>&1; then
    echo "Configuring Samba TLS settings..."
    docker exec "$CONTAINER_NAME" bash -lc "sed -i '/^[[:space:]]*tls enabled/d;/^[[:space:]]*tls keyfile/d;/^[[:space:]]*tls certfile/d;/^[[:space:]]*tls cafile/d;/^[[:space:]]*ldap server require strong auth/d' /etc/samba/smb.conf"

    ##  ldap server require strong auth must be set to no to allow Samba to accept simple binds over TLS, which is required for LDAPS to work properly. If this is not set, you may see errors about "strong authentication required" when trying to connect via LDAPS. Setting it to no allows Samba to accept the simple bind as long as it's protected by TLS encryption.
    if docker exec "$CONTAINER_NAME" test -f /var/lib/samba/private/tls/cert.pem >/dev/null 2>&1 && docker exec "$CONTAINER_NAME" test -f /var/lib/samba/private/tls/key.pem >/dev/null 2>&1; then
      docker exec "$CONTAINER_NAME" bash -lc "awk '/^\[global\]/{print; print \"    ldap server require strong auth = no\"; print \"    tls enabled = yes\"; print \"    tls certfile = /var/lib/samba/private/tls/cert.pem\"; print \"    tls keyfile = /var/lib/samba/private/tls/key.pem\"; print \"    tls cafile = /var/lib/samba/private/tls/ca.pem\"; next}1' /etc/samba/smb.conf > /tmp/smb.conf.new && mv /tmp/smb.conf.new /etc/samba/smb.conf"
    else
      docker exec "$CONTAINER_NAME" bash -lc "awk '/^\[global\]/{print; print \"    ldap server require strong auth = no\"; next}1' /etc/samba/smb.conf > /tmp/smb.conf.new && mv /tmp/smb.conf.new /etc/samba/smb.conf"
      echo "Warning: TLS cert/key pair unavailable, LDAPS will not be enabled." >&2
    fi
  fi
}

if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose"
else
  log_error "docker compose command not found"
  exit 1
fi

mkdir -p "$DATA_DIR"

log_step "Building Samba AD DC image..."
cd "$SCRIPT_DIR"
docker build -t "$IMAGE_NAME" .

log_step "Starting container with persistent Samba volume..."
$COMPOSE_CMD down || true
$COMPOSE_CMD up -d

function exec_container() {
  docker exec "$CONTAINER_NAME" bash -lc "$1"
}

function container_running() {
  docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || echo false
}

install_tls_certs

if [[ "$(container_running)" != "true" ]]; then
  log_info "Waiting for container $CONTAINER_NAME to start"
  sleep 3
fi

if ! docker exec "$CONTAINER_NAME" test -f /var/lib/samba/private/secrets.tdb >/dev/null 2>&1; then
  log_step "Provisioning Samba AD domain $REALM"
  exec_container "rm -f /etc/samba/smb.conf"
  exec_container "samba-tool domain provision --use-rfc2307 --realm='$REALM' --domain='$DOMAIN' --adminpass='$ADMIN_PASS' --server-role=dc --dns-backend=SAMBA_INTERNAL"
else
  log_info "Samba AD already provisioned"
fi

configure_samba_tls

log_step "Setting Administrator password"
exec_container "samba-tool user setpassword Administrator --newpassword='$ADMIN_PASS'"

log_step "Restarting Samba"
exec_container "pkill -f '^samba:' || true"
exec_container "sleep 1 || true"

log_step "Starting Samba AD DC"
exec_container "nohup samba -i >/var/log/samba.log 2>&1 &"

log_step "Waiting for LDAP (389)"
exec_container "bash -lc 'for i in {1..30}; do echo > /dev/tcp/127.0.0.1/389 && exit 0; sleep 1; done; exit 1'"

for user in "$USER_NAME" "$USER2_NAME"; do
  if ! exec_container "samba-tool user list | grep -x '$user'" >/dev/null 2>&1; then
    log_step "Creating user $user"
    exec_container "samba-tool user create '$user' '$USER_PASS' --use-username-as-cn --must-change-at-next-login"
  else
    log_info "User $user exists"
  fi

  log_info "Setting password for $user"
  exec_container "samba-tool user setpassword '$user' --newpassword='$USER_PASS'"
done

for group in "$GROUP_NAME" "$SECOND_GROUP_NAME"; do
  if ! exec_container "samba-tool group list | grep -x '$group'" >/dev/null 2>&1; then
    log_step "Creating group $group"
    exec_container "samba-tool group add '$group'"
  else
    log_info "Group $group exists"
  fi
done

log_step "Adding users to groups"

for group in "$GROUP_NAME" "$SECOND_GROUP_NAME"; do
  for user in "$USER_NAME" "$USER2_NAME"; do
    if exec_container "samba-tool group listmembers '$group' | grep -x '$user'" >/dev/null 2>&1; then
      log_info "User $user already in group $group"
    else
      log_info "Adding $user to $group"
      exec_container "samba-tool group addmembers '$group' '$user'"
    fi
  done
done

log_step "LDAP Test (connectivity check only)"

# Run silently just to verify it works
if exec_container "ldapsearch -LLL -H ldap://localhost -x -D 'CN=Administrator,CN=Users,DC=nrsh13-hadoop,DC=com' -w '$ADMIN_PASS' -b 'DC=nrsh13-hadoop,DC=com' '(sAMAccountName=$USER_NAME)'" >/dev/null 2>&1; then
  log_success "LDAP query successful"
else
  log_error "LDAP query failed"
fi

log_step "Sample ldapsearch command from the Mac host:"

cat <<EOF
Your Samba AD DC container is running as: $CONTAINER_NAME
LDAP host: localhost
Base DN: DC=nrsh13-hadoop,DC=com
Realm: $REALM
Password: $ADMIN_PASS

ldapsearch -LLL \\
  -H ldap://127.0.0.1:389 \\
  -x \\
  -D "CN=Administrator,CN=Users,DC=nrsh13-hadoop,DC=com" \\
  -w '$ADMIN_PASS' \\
  -b "DC=nrsh13-hadoop,DC=com" \\
  "(sAMAccountName=$USER_NAME)"

EOF
# ---------- END BANNER ----------
echo
printf "${BLUE}=======================================${RESET}\n"
printf "${GREEN} Active Directory Setup Complete 🎉${RESET}\n"
printf "${BLUE}=======================================${RESET}\n"
echo