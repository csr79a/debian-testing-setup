#!/usr/bin/env bash
#
# corregir-repos-testing.sh
# Normaliza repositorios Debian Testing al formato deb822 (.sources)
#
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    exec sudo -- bash "$0" "$@"
fi

source /etc/os-release

if [ "${ID:-}" != "debian" ]; then
    echo "[ERROR] Este script solo funciona en Debian."
    exit 1
fi

CODENAME="${VERSION_CODENAME:-}"

if [ -z "$CODENAME" ]; then
    echo "[ERROR] No se pudo detectar el codename."
    exit 1
fi

echo "[OK] Debian detectado: $CODENAME"

SOURCE_FILE="/etc/apt/sources.list.d/debian.sources"
KEYRING="/usr/share/keyrings/debian-archive-keyring.gpg"

ya_configurado=false
if [ -f "$SOURCE_FILE" ] \
    && grep -q "^Suites:[[:space:]]*testing[[:space:]]*$" "$SOURCE_FILE" \
    && grep -q "^Components:[[:space:]]*main[[:space:]]\+contrib[[:space:]]\+non-free[[:space:]]\+non-free-firmware[[:space:]]*$" "$SOURCE_FILE" \
    && grep -q "^Signed-By:[[:space:]]*$KEYRING[[:space:]]*$" "$SOURCE_FILE"; then
    ya_configurado=true
fi

# Solo se crea una copia de seguridad si realmente vamos a modificar
# la configuración de APT. Una ejecución que ya está correctamente
# configurada no genera backups innecesarios.
NECESITA_CAMBIO=1
if [ "$ya_configurado" = true ] \
    && { [ ! -f /etc/apt/sources.list ] || [ ! -s /etc/apt/sources.list ]; }; then
    NECESITA_CAMBIO=0
fi

if [ "$NECESITA_CAMBIO" -eq 1 ]; then
    BACKUP="/root/backup-repos-debian-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP"
    cp -a /etc/apt/sources.list "$BACKUP/" 2>/dev/null || true
    cp -a /etc/apt/sources.list.d "$BACKUP/" 2>/dev/null || true
    echo "[OK] Copia de seguridad: $BACKUP"
fi

# El sources.list clásico se desactiva solo si existe contenido activo,
# y únicamente después de guardar la copia de seguridad.
if [ -f /etc/apt/sources.list ] && [ -s /etc/apt/sources.list ]; then
    mv /etc/apt/sources.list /etc/apt/sources.list.disabled
    echo "[OK] sources.list antiguo desactivado."
fi

if [ "$ya_configurado" = true ]; then
    echo "[OK] Repositorios Debian Testing ya configurados."
    echo "[OK] No se modifica nada."
    apt update
    exit 0
fi

cat > "$SOURCE_FILE" <<EOF
Types: deb
URIs: https://deb.debian.org/debian
Suites: testing
Components: main contrib non-free non-free-firmware
Signed-By: $KEYRING
EOF

echo "[OK] $SOURCE_FILE reescrito con Signed-By."

apt update

echo "[OK] Repositorios de Debian Testing corregidos."
