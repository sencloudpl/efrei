#!/usr/bin/env bash
# ==============================================================================
# prepare-lab.sh
# Préparation pédagogique Ubuntu Server 26.04 pour les TP :
#   TP 1 - Fondamentaux de l'administration sécurisée
#   TP 2 - Hardening Linux
#
# Usage :
#   sudo ./prepare-lab.sh
#   sudo ./prepare-lab.sh --prepare
#   sudo ./prepare-lab.sh --reset
#   sudo ./prepare-lab.sh --help
#
# IMPORTANT : ce script crée volontairement quelques configurations perfectibles
# pour un LAB isolé. Ne pas utiliser sur un serveur de production.
# ==============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="$(basename "$0")"
readonly LAB_STATE_DIR="/var/lib/training-lab"
readonly LAB_BACKUP_DIR="${LAB_STATE_DIR}/original"
readonly LAB_CRED_FILE="/root/training-lab-credentials.txt"
readonly SSH_LAB_DROPIN="/etc/ssh/sshd_config.d/00-training-lab.conf"
readonly SYSCTL_LAB_FILE="/etc/sysctl.d/99-training-lab.conf"
readonly SUDOERS_LAB_FILE="/etc/sudoers.d/90-training-lab"
readonly LAB_WEB_ROOT="/opt/training-lab/web"
readonly LAB_WEB_UNIT="/etc/systemd/system/training-http.service"
readonly LAB_INFO_FILE="/etc/training-lab-info.txt"
readonly FAIL2BAN_LAB_JAIL="/etc/fail2ban/jail.d/sshd-training.local"

LAB_USERS=(adminlab dev01 dev02 olduser)
LAB_STUDENT_CLEANUP_USERS=(tpuser)
LAB_SERVICE_USER="backupsvc"

log()  { printf '\033[1;34m[LAB]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[ERREUR]\033[0m %s\n' "$*" >&2; exit 1; }

trap 'printf "\n[ERREUR] Échec à la ligne %s. Consultez les messages précédents.\n" "$LINENO" >&2' ERR

usage() {
  cat <<USAGE
Usage : sudo ./${SCRIPT_NAME} [OPTION]

Options :
  --prepare   Prépare le laboratoire (option par défaut).
  --reset     Nettoie les modifications pédagogiques connues puis recrée le LAB.
  --help      Affiche cette aide.

Le script est prévu pour Ubuntu Server 26.04 LTS (Resolute).
Il installe et configure un environnement volontairement perfectible destiné
uniquement à des machines virtuelles de formation isolées (NAT / Host-only).
USAGE
}

require_root() {
  [[ ${EUID} -eq 0 ]] || die "Exécutez ce script avec sudo ou en root."
}

check_os() {
  [[ -r /etc/os-release ]] || die "/etc/os-release introuvable."
  # shellcheck disable=SC1091
  source /etc/os-release

  [[ "${ID:-}" == "ubuntu" ]] || die "Ce script est prévu pour Ubuntu. Système détecté : ${ID:-inconnu}."

  if [[ "${VERSION_ID:-}" != "26.04" ]]; then
    warn "Ubuntu ${VERSION_ID:-inconnu} détecté ; la cible prévue est Ubuntu 26.04 LTS."
    warn "Le script continue car les commandes utilisées restent standard, mais validez le LAB avant le cours."
  else
    ok "Ubuntu 26.04 LTS détecté."
  fi
}

ensure_lab_network_warning() {
  cat <<'MSG'

===============================================================================
 ATTENTION - LAB PÉDAGOGIQUE
-------------------------------------------------------------------------------
 Ce script crée volontairement quelques réglages perfectibles (ex. SSH par mot
 de passe, compte sudo trop permissif, service inutile, IP forwarding activé).
 Utilisez la VM sur un réseau NAT ou Host-only et PAS directement exposée à
 Internet ou au réseau de production.
===============================================================================
MSG
}

backup_originals_once() {
  mkdir -p "${LAB_BACKUP_DIR}"
  chmod 700 "${LAB_STATE_DIR}" "${LAB_BACKUP_DIR}"

  if [[ ! -f "${LAB_BACKUP_DIR}/sshd_config" && -f /etc/ssh/sshd_config ]]; then
    cp -a /etc/ssh/sshd_config "${LAB_BACKUP_DIR}/sshd_config"
  fi

  if [[ ! -f "${LAB_BACKUP_DIR}/nftables.conf" && -f /etc/nftables.conf ]]; then
    cp -a /etc/nftables.conf "${LAB_BACKUP_DIR}/nftables.conf"
  fi

  if [[ ! -f "${LAB_BACKUP_DIR}/fail2ban-jail.local" && -f /etc/fail2ban/jail.local ]]; then
    cp -a /etc/fail2ban/jail.local "${LAB_BACKUP_DIR}/fail2ban-jail.local"
  fi
}

install_packages() {
  log "Mise à jour de l'index APT..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y

  # Fail2ban est dans le dépôt Universe sur Ubuntu 26.04. L'activer si nécessaire.
  if ! apt-cache show fail2ban >/dev/null 2>&1; then
    log "Activation du dépôt Ubuntu Universe (nécessaire pour Fail2ban)..."
    apt-get install -y software-properties-common
    add-apt-repository -y universe
    apt-get update -y
  fi

  log "Installation des outils nécessaires aux TP..."
  apt-get install -y \
    openssh-server \
    nginx \
    ufw \
    nftables \
    fail2ban \
    rsyslog \
    python3 \
    curl \
    wget \
    net-tools \
    iproute2 \
    procps \
    lsof \
    acl \
    openssl

  systemctl enable --now ssh
  systemctl enable --now nginx
  systemctl enable --now rsyslog

  # nftables est installé pour l'observation/manipulation mais n'est pas activé
  # comme service afin de ne pas entrer en concurrence avec UFW pendant le TP.
  systemctl disable --now nftables 2>/dev/null || true

  # Fail2ban est volontairement laissé non actif pour que les étudiants le
  # configurent dans la partie durcissement SSH.
  systemctl disable --now fail2ban 2>/dev/null || true

  ok "Paquets installés."
}

random_password() {
  # Mot de passe robuste, unique à chaque VM/réinitialisation.
  printf 'Lab!%sA1' "$(openssl rand -hex 8)"
}

create_or_reset_user() {
  local user="$1"
  local shell="${2:-/bin/bash}"

  if id "$user" &>/dev/null; then
    usermod -s "$shell" "$user"
  else
    useradd -m -s "$shell" "$user"
  fi
}

configure_users() {
  log "Création des comptes pédagogiques..."

  # Recrée les comptes utilisateurs avec des mots de passe aléatoires.
  local admin_pw dev01_pw dev02_pw olduser_pw
  admin_pw="$(random_password)"
  dev01_pw="$(random_password)"
  dev02_pw="$(random_password)"
  olduser_pw="$(random_password)"

  create_or_reset_user adminlab
  create_or_reset_user dev01
  create_or_reset_user dev02
  create_or_reset_user olduser

  printf 'adminlab:%s\n' "$admin_pw" | chpasswd
  printf 'dev01:%s\n' "$dev01_pw" | chpasswd
  printf 'dev02:%s\n' "$dev02_pw" | chpasswd
  printf 'olduser:%s\n' "$olduser_pw" | chpasswd

  # Profils variés pour l'audit.
  usermod -aG sudo adminlab
  usermod -aG sudo dev01
  gpasswd -d dev02 sudo >/dev/null 2>&1 || true
  gpasswd -d olduser sudo >/dev/null 2>&1 || true

  # Âges de mots de passe volontairement hétérogènes.
  chage -m 0 -M 365 -W 14 adminlab
  chage -m 0 -M 99999 -W 7 dev01
  chage -m 1 -M 90 -W 14 dev02
  chage -m 0 -M 99999 -W 7 olduser

  # Compte technique sans shell interactif.
  if ! id "${LAB_SERVICE_USER}" &>/dev/null; then
    useradd --system --no-create-home --shell /usr/sbin/nologin "${LAB_SERVICE_USER}"
  else
    usermod --shell /usr/sbin/nologin "${LAB_SERVICE_USER}"
  fi
  passwd -l "${LAB_SERVICE_USER}" >/dev/null 2>&1 || true

  # Mauvaise pratique contrôlée : NOPASSWD ALL pour adminlab.
  cat > "${SUDOERS_LAB_FILE}" <<'SUDOEOF'
# LAB PÉDAGOGIQUE - volontairement trop permissif.
# Les étudiants doivent identifier et commenter ce risque.
adminlab ALL=(ALL:ALL) NOPASSWD: ALL
SUDOEOF
  chmod 0440 "${SUDOERS_LAB_FILE}"
  visudo -cf "${SUDOERS_LAB_FILE}" >/dev/null

  # Conserver l'utilisateur ayant lancé le script dans sudo pour éviter le lockout.
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]] && id "${SUDO_USER}" &>/dev/null; then
    usermod -aG sudo "${SUDO_USER}"
  fi

  cat > "${LAB_CRED_FILE}" <<CREDEOF
LAB pédagogique - identifiants créés le $(date -Is)

IMPORTANT : fichier réservé à l'enseignant (permissions 600).

adminlab : ${admin_pw}
dev01    : ${dev01_pw}
dev02    : ${dev02_pw}
olduser  : ${olduser_pw}
backupsvc: compte système verrouillé / shell nologin

Compte qui a exécuté le script : ${SUDO_USER:-root}
CREDEOF
  chmod 0600 "${LAB_CRED_FILE}"

  ok "Comptes pédagogiques créés."
}

configure_ssh_training_state() {
  log "Configuration SSH pédagogique..."
  mkdir -p /etc/ssh/sshd_config.d

  cat > "${SSH_LAB_DROPIN}" <<'SSHEOF'
# LAB PÉDAGOGIQUE - paramètres volontairement perfectibles.
# Le compte root reste verrouillé par Ubuntu ; ne lui définissez pas de mot de passe.
PasswordAuthentication yes
PermitRootLogin prohibit-password
MaxAuthTries 10
AllowTcpForwarding yes
X11Forwarding yes
PermitEmptyPasswords no
SSHEOF

  sshd -t
  systemctl restart ssh
  ok "SSH actif avec une configuration volontairement améliorable."
}

configure_nginx_business_service() {
  log "Préparation du service Web métier (nginx, port 80)..."
  cat > /var/www/html/index.html <<'HTMLEOF'
<!doctype html>
<html lang="fr">
<head><meta charset="utf-8"><title>Training Business App</title></head>
<body>
<h1>Application métier de démonstration</h1>
<p>Ce service HTTP sur le port 80 est considéré comme nécessaire dans le scénario du TP.</p>
</body>
</html>
HTMLEOF
  systemctl enable --now nginx
  ok "nginx actif sur le port 80."
}

configure_unnecessary_training_service() {
  log "Création du service pédagogique inutile (port 8080)..."
  mkdir -p "${LAB_WEB_ROOT}"
  cat > "${LAB_WEB_ROOT}/index.html" <<'HTMLEOF'
<!doctype html>
<html lang="fr">
<head><meta charset="utf-8"><title>Training Unnecessary Service</title></head>
<body>
<h1>Service de démonstration inutile</h1>
<p>Ce service sur le port 8080 est volontairement actif pour le TP de hardening.</p>
</body>
</html>
HTMLEOF

  cat > "${LAB_WEB_UNIT}" <<EOFUNIT
[Unit]
Description=Training Lab - service HTTP volontairement inutile
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=nobody
Group=nogroup
WorkingDirectory=${LAB_WEB_ROOT}
ExecStart=/usr/bin/python3 -m http.server 8080 --bind 0.0.0.0 --directory ${LAB_WEB_ROOT}
Restart=on-failure
RestartSec=2
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOFUNIT

  systemctl daemon-reload
  systemctl enable --now training-http.service
  ok "Service inutile training-http actif sur le port 8080."
}

configure_firewall_training_state() {
  log "Préparation UFW / Netfilter..."

  # S'assurer qu'aucun ruleset nftables indépendant ne bloque le lab.
  nft flush ruleset 2>/dev/null || true

  # UFW est volontairement désactivé, mais SSH est préautorisé afin que son
  # activation par les étudiants ne coupe pas leur session distante.
  ufw --force reset >/dev/null
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  ufw allow 22/tcp comment 'LAB - préserver SSH lors de activation UFW' >/dev/null
  ufw --force disable >/dev/null

  ok "UFW installé et désactivé ; règle SSH préchargée pour éviter le lockout."
}

configure_fail2ban_training_state() {
  log "Préparation Fail2ban..."

  # Supprime uniquement le fichier géré par ce LAB. Les étudiants devront créer
  # leur propre configuration pendant le TP.
  rm -f "${FAIL2BAN_LAB_JAIL}"

  # On laisse Fail2ban installé mais arrêté/désactivé.
  systemctl disable --now fail2ban 2>/dev/null || true
  ok "Fail2ban installé mais non configuré / non actif."
}

configure_sysctl_training_state() {
  log "Création d'un paramètre réseau volontairement perfectible..."

  cat > "${SYSCTL_LAB_FILE}" <<'SYSCTLEOF'
# LAB PÉDAGOGIQUE - ce serveur n'est PAS censé être un routeur.
# Les étudiants doivent identifier ce réglage pendant le TP.
net.ipv4.ip_forward = 1
SYSCTLEOF

  sysctl --system >/dev/null
  ok "net.ipv4.ip_forward=1 activé volontairement pour l'exercice."
}

seed_training_logs() {
  log "Création de quelques événements de journalisation pédagogiques..."

  # Rsyslog reçoit authpriv et fournit généralement /var/log/auth.log sur Ubuntu.
  systemctl restart rsyslog

  logger -p authpriv.warning -t sshd "Failed password for invalid user auditdemo from 198.51.100.23 port 54321 ssh2"
  logger -p authpriv.warning -t sshd "Failed password for dev01 from 198.51.100.23 port 54322 ssh2"
  logger -p authpriv.notice -t sshd "Accepted password for dev02 from 192.0.2.50 port 51000 ssh2 (TRAINING EVENT)"
  logger -p daemon.notice -t training-lab "Training lab initialized; review services, ports, accounts and hardening state."

  sleep 1
  ok "Événements de démonstration ajoutés aux journaux."
}

write_lab_info() {
  cat > "${LAB_INFO_FILE}" <<'INFOEOF'
LAB Ubuntu - TP Administration sécurisée / Hardening
=====================================================

État pédagogique attendu :
- SSH actif ; authentification par mot de passe autorisée.
- MaxAuthTries volontairement élevé.
- nginx actif sur TCP/80 : service métier à conserver dans le scénario.
- training-http actif sur TCP/8080 : service volontairement inutile.
- UFW installé mais désactivé ; SSH/22 est préautorisé en cas d'activation.
- nftables installé pour inspection/manipulation ; service nftables désactivé.
- Fail2ban installé mais arrêté/non configuré.
- net.ipv4.ip_forward = 1 alors que la VM n'est pas censée router.
- adminlab et dev01 disposent de privilèges sudo.
- adminlab possède un sudo NOPASSWD: ALL volontairement excessif.
- olduser est un compte humain actif mais censé être inutilisé.
- backupsvc est un compte technique avec /usr/sbin/nologin.
- Des événements SSH pédagogiques ont été injectés dans les logs.

Commandes utiles pour commencer :
  id
  getent passwd
  getent group sudo
  sudo -l
  sudo -l -U adminlab
  chage -l dev01
  last
  lastlog
  systemctl --type=service --state=running
  ss -tulpn
  sudo sshd -T | egrep 'passwordauthentication|permitrootlogin|maxauthtries|x11forwarding|allowtcpforwarding'
  sudo ufw status verbose
  sudo nft list ruleset
  sudo fail2ban-client status
  sysctl net.ipv4.ip_forward
  journalctl -p warning
  sudo tail -50 /var/log/auth.log
INFOEOF
  chmod 0644 "${LAB_INFO_FILE}"
}

verify_lab() {
  log "Vérification de l'état du LAB..."

  local failures=0

  systemctl is-active --quiet ssh || { warn "SSH n'est pas actif."; failures=$((failures+1)); }
  systemctl is-active --quiet nginx || { warn "nginx n'est pas actif."; failures=$((failures+1)); }
  systemctl is-active --quiet training-http || { warn "training-http n'est pas actif."; failures=$((failures+1)); }

  ss -lnt | grep -qE '[:.]22[[:space:]]' || { warn "Port 22 non détecté en écoute."; failures=$((failures+1)); }
  ss -lnt | grep -qE '[:.]80[[:space:]]' || { warn "Port 80 non détecté en écoute."; failures=$((failures+1)); }
  ss -lnt | grep -qE '[:.]8080[[:space:]]' || { warn "Port 8080 non détecté en écoute."; failures=$((failures+1)); }

  [[ "$(sysctl -n net.ipv4.ip_forward)" == "1" ]] || { warn "ip_forward n'est pas à 1."; failures=$((failures+1)); }

  if systemctl is-active --quiet fail2ban; then
    warn "Fail2ban est actif alors qu'il devrait être arrêté au début du TP."
    failures=$((failures+1))
  fi

  if ufw status | grep -q '^Status: active'; then
    warn "UFW est actif alors qu'il devrait être désactivé au début du TP."
    failures=$((failures+1))
  fi

  if [[ "$failures" -eq 0 ]]; then
    ok "LAB vérifié : état pédagogique conforme."
  else
    warn "LAB préparé avec ${failures} anomalie(s) de vérification. Vérifiez avant la séance."
  fi
}

print_summary() {
  local ip_addr
  ip_addr="$(hostname -I 2>/dev/null | awk '{print $1}')"

  cat <<SUMMARY

===============================================================================
 LAB READY - Ubuntu Administration sécurisée / Hardening
===============================================================================
 Hôte                 : $(hostname)
 IP principale         : ${ip_addr:-non détectée}
 Utilisateur enseignant: ${SUDO_USER:-root}

 Comptes pédagogiques : adminlab, dev01, dev02, olduser, backupsvc
 SSH                   : actif (TCP/22), PasswordAuthentication=yes
 nginx                 : actif (TCP/80) - service métier du scénario
 training-http         : actif (TCP/8080) - service inutile à identifier
 UFW                   : installé, volontairement désactivé
 nftables              : installé, service désactivé
 Fail2ban              : installé, volontairement arrêté
 ip_forward            : $(sysctl -n net.ipv4.ip_forward)

 Informations LAB      : ${LAB_INFO_FILE}
 Identifiants enseignant: ${LAB_CRED_FILE}

 Vérifications rapides :
   cat ${LAB_INFO_FILE}
   ss -tulpn
   systemctl --type=service --state=running
   getent group sudo
   sudo sshd -T | grep -E 'passwordauthentication|permitrootlogin|maxauthtries'
   sudo ufw status verbose
   sudo nft list ruleset
   sysctl net.ipv4.ip_forward

 Pour remettre la VM dans l'état initial du TP :
   sudo ./${SCRIPT_NAME} --reset
===============================================================================
SUMMARY
}

stop_and_remove_training_service() {
  systemctl disable --now training-http.service 2>/dev/null || true
  rm -f "${LAB_WEB_UNIT}"
  rm -rf /opt/training-lab
  systemctl daemon-reload
}

remove_lab_users() {
  local user
  for user in "${LAB_USERS[@]}"; do
    if id "$user" &>/dev/null; then
      userdel -r "$user" >/dev/null 2>&1 || userdel "$user" >/dev/null 2>&1 || true
    fi
  done

  if id "${LAB_SERVICE_USER}" &>/dev/null; then
    userdel "${LAB_SERVICE_USER}" >/dev/null 2>&1 || true
  fi

  # Compte explicitement créé dans le TP 1.
  for user in "${LAB_STUDENT_CLEANUP_USERS[@]}"; do
    if id "$user" &>/dev/null; then
      userdel -r "$user" >/dev/null 2>&1 || userdel "$user" >/dev/null 2>&1 || true
    fi
  done
}

reset_known_state() {
  log "Réinitialisation de l'état pédagogique..."

  # Ne jamais supprimer le compte depuis lequel le reset est lancé.
  local current_sudo_user="${SUDO_USER:-root}"
  local lab_user
  for lab_user in "${LAB_USERS[@]}"; do
    if [[ "${current_sudo_user}" == "${lab_user}" ]]; then
      die "Lancez --reset depuis le compte Ubuntu créé à l'installation, pas depuis ${current_sudo_user}."
    fi
  done

  # Éviter de couper la session SSH pendant le reset : on garde ssh actif.
  stop_and_remove_training_service

  rm -f "${SSH_LAB_DROPIN}" "${SYSCTL_LAB_FILE}" "${SUDOERS_LAB_FILE}" "${FAIL2BAN_LAB_JAIL}"
  rm -f "${LAB_INFO_FILE}" "${LAB_CRED_FILE}"

  # Restaurer le sshd_config d'origine sauvegardé lors de la première exécution.
  if [[ -f "${LAB_BACKUP_DIR}/sshd_config" ]]; then
    cp -a "${LAB_BACKUP_DIR}/sshd_config" /etc/ssh/sshd_config
  fi

  # Nettoyage des règles de firewall créées pendant les TP.
  ufw --force reset >/dev/null 2>&1 || true
  ufw --force disable >/dev/null 2>&1 || true
  nft flush ruleset 2>/dev/null || true
  systemctl disable --now nftables 2>/dev/null || true

  # Restaurer le fichier nftables d'origine (sauvegardé après installation du paquet).
  if [[ -f "${LAB_BACKUP_DIR}/nftables.conf" ]]; then
    cp -a "${LAB_BACKUP_DIR}/nftables.conf" /etc/nftables.conf
  fi

  # Remettre Fail2ban hors service et restaurer sa configuration de départ.
  systemctl disable --now fail2ban 2>/dev/null || true
  rm -f /etc/fail2ban/jail.local /etc/fail2ban/jail.d/sshd.local
  if [[ -f "${LAB_BACKUP_DIR}/fail2ban-jail.local" ]]; then
    cp -a "${LAB_BACKUP_DIR}/fail2ban-jail.local" /etc/fail2ban/jail.local
  fi

  remove_lab_users

  # Recharger les valeurs sysctl standard avant de recréer la configuration LAB.
  sysctl --system >/dev/null 2>&1 || true

  # Valider SSH après restauration et le relancer.
  sshd -t
  systemctl restart ssh

  ok "État pédagogique nettoyé."
}

prepare_lab() {
  ensure_lab_network_warning
  check_os
  install_packages
  backup_originals_once
  configure_users
  configure_ssh_training_state
  configure_nginx_business_service
  configure_unnecessary_training_service
  configure_firewall_training_state
  configure_fail2ban_training_state
  configure_sysctl_training_state
  seed_training_logs
  write_lab_info
  verify_lab
  print_summary
}

main() {
  require_root

  case "${1:---prepare}" in
    --prepare)
      prepare_lab
      ;;
    --reset)
      ensure_lab_network_warning
      check_os
      install_packages
      backup_originals_once
      reset_known_state
      configure_users
      configure_ssh_training_state
      configure_nginx_business_service
      configure_unnecessary_training_service
      configure_firewall_training_state
      configure_fail2ban_training_state
      configure_sysctl_training_state
      seed_training_logs
      write_lab_info
      verify_lab
      print_summary
      ;;
    --help|-h)
      usage
      ;;
    *)
      usage
      die "Option inconnue : $1"
      ;;
  esac
}

main "$@"
