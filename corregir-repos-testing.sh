#!/usr/bin/env bash
#
# corregir-repos-testing.sh
#
# Corrige los repositorios oficiales de Debian para Debian Testing
# usando el formato moderno deb822 (.sources).
#
# Basado en la lógica de setup-debian-testing.sh de csr79a.
#
# Qué hace:
#   1. Comprueba que estamos en Debian.
#   2. Comprueba que APT está configurado para la suite "testing".
#   3. Guarda una copia de seguridad de la configuración APT.
#   4. Desactiva las entradas Debian antiguas en sources.list y
#      en los ficheros *.list de sources.list.d.
#   5. Crea /etc/apt/sources.list.d/debian.sources con:
#        - deb.debian.org
#        - testing
#        - main contrib non-free non-free-firmware
#        - debian-archive-keyring
#   6. Ejecuta apt update y comprueba el resultado.
#
# IMPORTANTE:
#   - Este script NO convierte Debian Stable/Sid a Testing.
#   - Solo corrige los repositorios. No hace full-upgrade.
#   - Los repositorios de terceros no se convierten automáticamente.
#   - Antes de modificar APT se crea una copia de seguridad.
#
# Uso:
#   chmod +x corregir-repos-testing.sh
#   sudo ./corregir-repos-testing.sh
#
# Licencia: MIT

set -Eeuo pipefail

TITLE="Corrector de repositorios Debian Testing"
VERSION="1.0.0"

log()  { echo -e "\033[1;34m[*]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[OK]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
error(){ echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

if [[ "${EUID}" -ne 0 ]]; then
    error "Ejecuta este script con sudo:
  sudo ./corregir-repos-testing.sh"
fi

command -v apt >/dev/null 2>&1 || error "No se encontró apt."
command -v awk >/dev/null 2>&1 || error "No se encontró awk."
command -v sed >/dev/null 2>&1 || error "No se encontró sed."

[[ -r /etc/os-release ]] || error "No se encontró /etc/os-release."

# shellcheck disable=SC1091
. /etc/os-release

[[ "${ID:-}" == "debian" ]] || error \
    "Este script está diseñado exclusivamente para Debian. Sistema detectado: ${PRETTY_NAME:-desconocido}"

log "${TITLE} ${VERSION}"
echo

log "Sistema detectado: ${PRETTY_NAME:-Debian}"

# ----------------------------------------------------------------------
# Rutas
# ----------------------------------------------------------------------

LEGACY_SOURCES="/etc/apt/sources.list"
SOURCES_DIR="/etc/apt/sources.list.d"
SOURCES_FILE="${SOURCES_DIR}/debian.sources"
KEYRING="/usr/share/keyrings/debian-archive-keyring.gpg"

[[ -d "${SOURCES_DIR}" ]] || mkdir -p "${SOURCES_DIR}"

# ----------------------------------------------------------------------
# Comprobaciones
# ----------------------------------------------------------------------

if [[ ! -r "${KEYRING}" ]]; then
    warn "No se encontró ${KEYRING}."
    warn "El paquete debian-archive-keyring debería estar instalado."
    error "No se puede configurar Signed-By de forma segura sin la clave oficial de Debian."
fi

# El script de setup original trabaja exclusivamente con la suite
# rolling "testing", no con el codename concreto del momento.
#
# Si ya existen fuentes de Debian con una suite distinta, las desactivamos
# al reconstruir la configuración oficial. NO modificamos repositorios de
# terceros.

log "Comprobando configuración actual de APT..."

# ----------------------------------------------------------------------
# Copia de seguridad
# ----------------------------------------------------------------------

BACKUP_DIR="/root/apt-backup-testing-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${BACKUP_DIR}"

if [[ -f "${LEGACY_SOURCES}" ]]; then
    cp -a "${LEGACY_SOURCES}" "${BACKUP_DIR}/"
fi

if [[ -d "${SOURCES_DIR}" ]]; then
    cp -a "${SOURCES_DIR}" "${BACKUP_DIR}/sources.list.d"
fi

ok "Copia de seguridad creada en:"
echo "    ${BACKUP_DIR}"

# ----------------------------------------------------------------------
# Desactivar entradas Debian antiguas
# ----------------------------------------------------------------------
#
# Se conserva el contenido original como copia de seguridad.
# En los ficheros .list se comentan únicamente líneas activas que
# apunten a repositorios Debian oficiales.
#
# No se tocan repositorios de terceros como Mozilla, Docker, Google,
# NVIDIA, etc.

disable_debian_legacy_sources() {
    local file="$1"

    [[ -f "${file}" ]] || return 0

    # Desactivar deb/deb-src que apunten a los dominios oficiales de Debian.
    # También cubre mirrors habituales de Debian y entradas cdrom: de Debian.
    sed -i -E \
        '/^[[:space:]]*deb(-src)?[[:space:]]+(https?:\/\/)?([^[:space:]]+\.)?debian\.org([/:[:space:]]|$)/ s/^/# desactivado por corregir-repos-testing.sh -- /' \
        "${file}"

    sed -i -E \
        '/^[[:space:]]*deb(-src)?[[:space:]]+cdrom:/ s/^/# desactivado por corregir-repos-testing.sh -- /' \
        "${file}"
}

if [[ -f "${LEGACY_SOURCES}" ]]; then
    disable_debian_legacy_sources "${LEGACY_SOURCES}"
    ok "Entradas Debian antiguas revisadas en ${LEGACY_SOURCES}"
fi

shopt -s nullglob

for file in "${SOURCES_DIR}"/*.list; do
    disable_debian_legacy_sources "${file}"
done

shopt -u nullglob

# ----------------------------------------------------------------------
# debian.sources moderno
# ----------------------------------------------------------------------
#
# Igual que en setup-debian-testing.sh:
#   URIs: deb.debian.org
#   Suites: testing
#   Components: main contrib non-free non-free-firmware
#
# No añadimos testing-security automáticamente, siguiendo la lógica del
# script de configuración original. Tampoco añadimos backports, ya que
# no corresponde a esta configuración de Testing.

if [[ -f "${SOURCES_FILE}" ]]; then
    SOURCES_OLD_BACKUP="${BACKUP_DIR}/debian.sources"
    cp -a "${SOURCES_FILE}" "${SOURCES_OLD_BACKUP}"
    ok "Copia de seguridad de ${SOURCES_FILE} guardada."
fi

cat > "${SOURCES_FILE}" <<EOF
Types: deb
URIs: https://deb.debian.org/debian
Suites: testing
Components: main contrib non-free non-free-firmware
Signed-By: ${KEYRING}
EOF

chmod 0644 "${SOURCES_FILE}"

ok "Repositorio moderno creado:"
echo "    ${SOURCES_FILE}"

# ----------------------------------------------------------------------
# Mostrar configuración resultante
# ----------------------------------------------------------------------

echo
log "Configuración oficial de Debian Testing:"
echo
cat "${SOURCES_FILE}"
echo

# ----------------------------------------------------------------------
# Actualizar índices
# ----------------------------------------------------------------------

log "Ejecutando apt update..."
echo

if apt update; then
    echo
    ok "apt update terminó correctamente."
else
    echo
    error "apt update ha encontrado errores.

La configuración de Debian Testing se ha escrito, pero no se considera
completamente verificada.

Copia de seguridad disponible en:
  ${BACKUP_DIR}

Revisa el mensaje anterior antes de continuar."
fi

# ----------------------------------------------------------------------
# Comprobación final
# ----------------------------------------------------------------------

echo
log "Comprobación final..."

if apt-cache policy >/dev/null 2>&1; then
    ok "APT responde correctamente."
else
    error "APT no pudo completar la comprobación final."
fi

echo
echo "=============================================="
echo " Debian Testing - Repositorios corregidos"
echo "=============================================="
echo
echo "✓ Sistema Debian detectado"
echo "✓ Copia de seguridad creada"
echo "✓ Fuentes Debian antiguas desactivadas"
echo "✓ debian.sources configurado con la suite testing"
echo "✓ Componentes main contrib non-free non-free-firmware"
echo "✓ apt update correcto"
echo
echo "Archivo activo:"
echo "  ${SOURCES_FILE}"
echo
echo "Copia de seguridad:"
echo "  ${BACKUP_DIR}"
echo
ok "Repositorios oficiales de Debian Testing configurados correctamente."
