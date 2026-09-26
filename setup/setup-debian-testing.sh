#!/usr/bin/env bash
#
# setup-debian-testing.sh — Configurador de Debian Testing csr79a
#
# Script de configuración inicial para Debian Testing con KDE Plasma.
# Configura los repositorios oficiales (deb822) apuntando a testing,
# actualiza el sistema, instala un set de paquetes de
# desarrollo/multimedia/sistema/utilidades de disco/OCR, el microcode
# correcto según el fabricante de CPU, fuentes de Windows y de Ubuntu,
# añade el remoto de Flathub, y ofrece (opcional, tras detectar el
# hardware) zram y Firefox de Mozilla.
#
# El driver NVIDIA y switcheroo-control (GPU híbrida) NO se instalan
# desde este script; gestiónalos aparte según tu hardware.
#
# Interfaz por pantallas (whiptail) para bienvenida, decisiones y
# resumen final; el progreso de comandos largos (apt, sed, etc.) se
# muestra como texto normal de terminal.
#
# IMPORTANTE: este script asume que ya tienes un sistema Debian
# instalado y funcionando apuntando a testing. Este script NO instala
# Debian ni migra desde stable por ti.
#
# Uso:
#   chmod +x setup-debian-testing.sh
#   ./setup-debian-testing.sh          # modo interactivo (pide confirmación)
#   ./setup-debian-testing.sh -y       # modo no interactivo (asume "sí" en todo,
#                                      # incluidas operaciones destructivas; ver --help)
#
# Licencia: MIT

set -euo pipefail

TITLE="Configurador de Debian Testing csr79a"
VERSION="1.0.0"

log()   { echo -e "\e[1;34m[*]\e[0m $*"; }
ok()    { echo -e "\e[1;32m[OK]\e[0m $*"; }
warn()  { echo -e "\e[1;33m[!]\e[0m $*"; }
error() { echo -e "\e[1;31m[ERROR]\e[0m $*" >&2; exit 1; }

# ----------------------------------------------------------------------
# 0. Opciones de línea de comandos
# ----------------------------------------------------------------------

ASSUME_YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)
      ASSUME_YES=1
      shift
      ;;
    -h|--help)
      cat <<EOF
Uso: $0 [-y|--yes] [-h|--help]

  -y, --yes   Modo no interactivo (sin pantallas): acepta automáticamente TODAS
              las preguntas del script, incluidas operaciones destructivas:
                - comentar el contenido activo de /etc/apt/sources.list (con
                  copia de seguridad previa);
                - eliminar Firefox ESR, su configuración (/etc/firefox-esr) y
                  TODOS sus perfiles y datos (~/.mozilla/firefox), de forma
                  irreversible;
                - configurar zram y ajustar vm.swappiness (sysctl).
              Las comprobaciones críticas NO se saltan con -y: si los
              repositorios configurados no son Debian Testing, el script
              se detiene.

  -h, --help  Muestra esta ayuda.
EOF
      exit 0
      ;;
    *)
      echo "Opción desconocida: $1" >&2
      exit 1
      ;;
  esac
done

# Pequeño helper para confirmaciones. En modo -y no se muestra ninguna
# pantalla (whiptail se salta por completo); en modo interactivo, cada
# decisión se muestra como una pantalla whiptail --yesno, que ya
# devuelve 0 (Sí) / 1 (No) directamente utilizable en un "if confirm...".
confirm() {
  local prompt="$1"
  local height="${2:-14}"
  local width="${3:-70}"
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    return 0
  fi
  whiptail --title "$TITLE" --yesno "$prompt" "$height" "$width"
}

# Con -y también evitamos que apt/debconf se queden esperando input
# (p. ej. avisos de licencia de firmware/fuentes no libres). OJO: esto
# silencia TODOS los prompts de debconf durante la instalación, no solo
# los de firmware, así que solo se activa en modo no interactivo
# explícito.
if [[ "$ASSUME_YES" -eq 1 ]]; then
  export DEBIAN_FRONTEND=noninteractive
  warn "MODO -y ACTIVO: se aceptarán automáticamente TODAS las preguntas, incluidas operaciones destructivas:"
  warn "  - comentar el contenido activo de /etc/apt/sources.list (con copia de seguridad);"
  warn "  - eliminar Firefox ESR, /etc/firefox-esr y TODOS los perfiles y datos de ESR (irreversible);"
  warn "  - configurar zram y ajustar vm.swappiness (sysctl)."
  warn "Las comprobaciones críticas siguen activas: si los repositorios no son Testing, el script se detiene."
fi

# ----------------------------------------------------------------------
# 1. Comprobaciones previas
# ----------------------------------------------------------------------

if [[ $EUID -eq 0 ]]; then
  error "No ejecutes este script directamente como root. Usa un usuario normal; se te pedirá la contraseña de sudo cuando haga falta."
fi

if ! command -v apt >/dev/null 2>&1; then
  error "Este script está pensado para sistemas basados en APT (Debian/derivados)."
fi

if ! command -v sudo >/dev/null 2>&1; then
  error "No se encontró el comando 'sudo' en este sistema."
fi

# whiptail hace falta para las pantallas de este propio script; si no
# está (Debian mínimo sin tareas de escritorio), se instala antes de
# mostrar nada.
if ! command -v whiptail >/dev/null 2>&1; then
  log "Instalando whiptail (necesario para las pantallas de este instalador)..."
  sudo apt update
  sudo apt install -y whiptail
fi

log "Comprobando permisos de sudo..."
if ! sudo -v; then
  error "No se pudieron validar los permisos de sudo."
fi

# ----------------------------------------------------------------------
# Detección de CPU (fabricante -> microcode; modelo -> solo informativo)
# ----------------------------------------------------------------------

CPU_VENDOR="$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $NF}' || true)"
CPU_MODEL_NAME="$(grep -m1 'model name' /proc/cpuinfo | sed 's/^.*: //' || true)"
CPU_MODEL_NAME="${CPU_MODEL_NAME:-desconocido}"

case "$CPU_VENDOR" in
  GenuineIntel)
    MICROCODE_PKG="intel-microcode"
    ;;
  AuthenticAMD)
    MICROCODE_PKG="amd64-microcode"
    ;;
  *)
    warn "No se ha podido determinar el fabricante de CPU (vendor_id='$CPU_VENDOR'). No se instalará ningún paquete de microcode automáticamente."
    MICROCODE_PKG=""
    ;;
esac

# NOTA: Debian solo distribuye microcode genérico por fabricante
# (intel-microcode / amd64-microcode), no hay paquetes específicos por
# modelo de CPU. El kernel/iucode-tool aplican en arranque solo el
# fragmento que corresponde a tu CPU exacta (family/model/stepping).
# Por eso el modelo detectado aquí (CPU_MODEL_NAME) es puramente
# informativo: se muestra en pantalla, pero no cambia qué paquete se
# instala.

# ----------------------------------------------------------------------
# Pantalla de bienvenida
# ----------------------------------------------------------------------

confirm "Versión del Configurador de Debian Testing csr79a ${VERSION}\n\nEste programa configura los repositorios oficiales, actualiza el sistema, instala un set de paquetes de desarrollo/multimedia/sistema/utilidades de disco/OCR, fuentes de Windows y de Ubuntu, y ofrece de forma opcional zram y Firefox de Mozilla según el hardware detectado.\n\nCPU detectada: ${CPU_MODEL_NAME}\n\nRecuerda: Testing es la rama de desarrollo de la próxima versión estable. Se comporta de forma bastante estable la mayor parte del ciclo, pero antes de cada lanzamiento entra en 'freeze' (deja de recibir paquetes nuevos, solo parches de errores) durante varios meses.\n\n¿Desea continuar?" 20 76 || exit 0

# A diferencia de Sid, en Testing el campo VERSION_CODENAME de
# /etc/os-release SÍ es fiable: refleja el codename real de la versión
# en desarrollo que sea testing en cada momento (p. ej. "forky" tras el
# lanzamiento de trixie). No se compara contra un valor fijo porque ese
# codename cambia con cada ciclo de Debian; solo se muestra a título
# informativo. La comprobación que de verdad importa (que los repos
# apunten a la suite "testing") se hace más abajo, sobre debian.sources.
DETECTED_CODENAME=""
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  DETECTED_CODENAME="${VERSION_CODENAME:-}"
  ok "Codename de Testing detectado: ${DETECTED_CODENAME:-desconocido} (${PRETTY_NAME:-desconocido})"
fi

# ----------------------------------------------------------------------
# 2. Repositorios (formato deb822) — apuntando a testing
# ----------------------------------------------------------------------

LEGACY_SOURCES="/etc/apt/sources.list"
SOURCES_DIR="/etc/apt/sources.list.d"
SOURCES_FILE="$SOURCES_DIR/debian.sources"

# ----------------------------------------------------------------------
# 2a. Comprobación de suites: este script SOLO trabaja con Testing
# ----------------------------------------------------------------------
#
# Se comprueban debian.sources, /etc/apt/sources.list y el resto de
# ficheros *.sources y *.list de /etc/apt/sources.list.d que apunten a Debian.
# Solo se acepta la suite "testing" (el alias rolling; NO el codename fijo
# de turno, como "forky" o "trixie", que deja de significar "testing" en
# cuanto esa versión se convierte en stable). Cualquier otra suite
# (unstable, sid, bookworm, trixie, stable...) detiene el script ANTES de
# continuar con apt update/full-upgrade, y también con -y: es una
# comprobación de seguridad, no una pregunta que se pueda aceptar
# automáticamente. El script no convierte esas suites a Testing.

# Suites de $SOURCES_FILE que no son testing (una por línea).
sources_file_bad_suites() {
  awk '/^Suites:/ { for (i = 2; i <= NF; i++) if ($i != "testing") print $i }' "$SOURCES_FILE" | sort -u
}

# Líneas activas de $LEGACY_SOURCES que apuntan a un repositorio de Debian
# con una suite distinta de testing. Las entradas de cdrom: se ignoran
# (son inofensivas y este script las comenta más abajo).
legacy_bad_lines() {
  awk '
    /^[[:space:]]*deb(-src)?[[:space:]]/ {
      line = $0
      sub(/^[[:space:]]*deb(-src)?[[:space:]]+/, "", line)
      if (line ~ /^\[/) sub(/^\[[^]]*\][[:space:]]*/, "", line)
      split(line, f, /[[:space:]]+/)
      if (f[1] ~ /^cdrom:/) next
      if (tolower(f[1]) !~ /debian/) next
      if (f[2] != "testing") print $0
    }' "$LEGACY_SOURCES"
}

# Entradas de OTROS ficheros de $SOURCES_DIR (*.sources y *.list, además de
# debian.sources) que apuntan al archivo de Debian con una suite distinta de
# testing. Una entrada se considera "de Debian" si su URI es de debian.org
# o si usa debian-archive-keyring como clave; así no se marcan
# repositorios de terceros (Docker, Brave...) aunque usen nombres de suite
# parecidos. Se ignoran las entradas con "Enabled: no".
# Limitación: un mirror con dominio propio y sin debian-archive-keyring no se
# reconoce como Debian.
other_sources_bad_entries() {
  local f
  for f in "$SOURCES_DIR"/*.sources "$SOURCES_DIR"/*.list; do
    [[ -f "$f" && "$f" != "$SOURCES_FILE" ]] || continue
    case "$f" in
      *.sources)
        awk -v file="$f" '
          function flush(   j) {
            if (n > 0 && enabled && isdeb)
              for (j = 1; j <= n; j++)
                if (suites[j] != "testing") print file ": Suites: " suites[j]
            n = 0; enabled = 1; isdeb = 0
          }
          BEGIN { enabled = 1 }
          /^[[:space:]]*$/ { flush(); next }
          /^#/ { next }
          /^URIs:/ { if (tolower($0) ~ /[\/.]debian\.org(\/|[[:space:]]|$)/) isdeb = 1 }
          /^Signed-By:/ { if ($0 ~ /debian-archive-keyring/) isdeb = 1 }
          /^Enabled:/ { if (tolower($2) == "no" || tolower($2) == "false") enabled = 0 }
          /^Suites:/ { for (k = 2; k <= NF; k++) suites[++n] = $k }
          END { flush() }
        ' "$f"
        ;;
      *.list)
        awk -v file="$f" '
          /^[[:space:]]*deb(-src)?[[:space:]]/ {
            line = $0; opts = ""
            sub(/^[[:space:]]*deb(-src)?[[:space:]]+/, "", line)
            if (line ~ /^\[/) { opts = line; sub(/\].*$/, "]", opts); sub(/^\[[^]]*\][[:space:]]*/, "", line) }
            split(line, f2, /[[:space:]]+/)
            if (f2[1] ~ /^cdrom:/) next
            isdeb = (tolower(f2[1]) ~ /[\/.]debian\.org(\/|$)/) || (opts ~ /debian-archive-keyring/)
            if (isdeb && f2[2] != "testing") print file ": " $0
          }
        ' "$f"
        ;;
    esac
  done
}

if [[ -f "$SOURCES_FILE" ]]; then
  if [[ -z "$(awk '/^Suites:/ { print $2 }' "$SOURCES_FILE")" ]]; then
    error "No se encontró ninguna línea 'Suites:' en $SOURCES_FILE, así que no se puede comprobar que los repositorios apunten a testing. Revisa el fichero y vuelve a ejecutar el script."
  fi

  SOURCES_BAD_SUITES="$(sources_file_bad_suites)"
  if [[ -n "$SOURCES_BAD_SUITES" ]]; then
    warn "$SOURCES_FILE contiene suites que no son testing:"
    sed 's/^/      · /' <<<"$SOURCES_BAD_SUITES"
    error "Este script solo trabaja con Debian Testing y no convierte otras suites automáticamente (tampoco con -y). Ajusta $SOURCES_FILE a mano (Suites: testing) y vuelve a ejecutar el script."
  fi
  ok "$SOURCES_FILE ya existe y solo apunta a testing; no se sobrescribe."
fi

if [[ -f "$LEGACY_SOURCES" ]]; then
  LEGACY_BAD_LINES="$(legacy_bad_lines)"
  if [[ -n "$LEGACY_BAD_LINES" ]]; then
    warn "$LEGACY_SOURCES contiene repositorios activos de Debian que no apuntan a testing:"
    sed 's/^/      · /' <<<"$LEGACY_BAD_LINES"
    error "Este script solo trabaja con Debian Testing y no convierte otras suites automáticamente (tampoco con -y). Corrige o comenta esas líneas a mano y vuelve a ejecutar el script."
  fi
fi

OTHER_BAD_ENTRIES="$(other_sources_bad_entries)"
if [[ -n "$OTHER_BAD_ENTRIES" ]]; then
  warn "Hay otros ficheros en $SOURCES_DIR con repositorios de Debian que no apuntan a testing:"
  sed 's/^/      · /' <<<"$OTHER_BAD_ENTRIES"
  error "Este script solo trabaja con Debian Testing y no convierte otras suites automáticamente (tampoco con -y). Corrige o desactiva esas entradas a mano y vuelve a ejecutar el script."
fi

# ----------------------------------------------------------------------
# 2b. Limpieza de /etc/apt/sources.list y 2c. escritura de debian.sources
# ----------------------------------------------------------------------

if [[ -f "$LEGACY_SOURCES" ]] && grep -qE '^\s*deb(-src)?\s' "$LEGACY_SOURCES"; then
  if confirm "Se ha detectado contenido activo en $LEGACY_SOURCES (típico de una instalación desde la ISO oficial, a veces con una entrada de CD-ROM).\n\nPara evitar repositorios duplicados, se comentará su contenido, dejando que $SOURCES_FILE (creado a continuación) sea la única fuente de los repos oficiales de Debian.\n\n¿Continuar? (se guarda una copia de seguridad antes de tocar nada)" 16 76; then
    LEGACY_BACKUP="${LEGACY_SOURCES}.bak.$(date +%Y%m%d%H%M%S)"
    sudo cp "$LEGACY_SOURCES" "$LEGACY_BACKUP"
    ok "Copia de seguridad: $LEGACY_BACKUP"
    sudo sed -i -E '/^\s*deb(-src)?\s/ s/^/# desactivado por setup-debian-testing.sh -- /' "$LEGACY_SOURCES"
    ok "Contenido de $LEGACY_SOURCES comentado."
  else
    warn "Se omite la limpieza de $LEGACY_SOURCES. Es probable que 'apt update' muestre avisos de repos duplicados."
  fi
fi

if [[ ! -f "$SOURCES_FILE" ]]; then
  log "Escribiendo $SOURCES_FILE ..."
  # Solo se configura la suite "testing". A día de hoy, la cobertura de
  # seguridad de testing NO está gestionada de forma fiable/puntual por
  # el equipo de seguridad de Debian (situación que varía a lo largo del
  # ciclo: mejora según se acerca el freeze). Por eso no se añade aquí
  # ninguna suite "testing-security" de forma automática: si en algún
  # momento necesitas parches de seguridad garantizados, la propia
  # documentación de Debian recomienda apuntar temporalmente esas
  # entradas a la suite de la stable actual (ver resumen final y
  # https://www.debian.org/releases/testing/). Backports tampoco aplica
  # aquí: solo existe para la rama stable.
  sudo tee "$SOURCES_FILE" >/dev/null <<'EOF'
Types: deb
URIs: https://deb.debian.org/debian
Suites: testing
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
  ok "$SOURCES_FILE escrito."
fi

log "Actualizando índices de paquetes..."
if ! sudo apt update; then
  warn "'apt update' terminó con errores (puede ser un repositorio concreto o la red). Se continúa con los índices disponibles."
fi

FULL_UPGRADE_FAILED=0
if confirm "¿Quieres hacer 'apt full-upgrade' antes de continuar?\n\nEn Testing conviene hacerlo con cierta regularidad (los paquetes migran desde unstable de forma continua, salvo en fase de freeze), aunque no es tan crítico como en Sid." 14 76; then
  if sudo apt full-upgrade -y; then
    ok "apt full-upgrade completado."
  else
    FULL_UPGRADE_FAILED=1
    warn "'apt full-upgrade' ha fallado (puede deberse a una migración de paquetes en curso desde unstable, o a dependencias temporalmente rotas; menos frecuente que en Sid, pero puede pasar)."
    # Solo se continúa si dpkg no ha quedado en un estado inconsistente:
    # instalar paquetes o compilar módulos DKMS sobre un sistema a medio
    # actualizar podría empeorarlo.
    DPKG_AUDIT="$(sudo dpkg --audit 2>&1 || true)"
    if [[ -n "$DPKG_AUDIT" ]]; then
      warn "dpkg ha detectado paquetes en un estado inconsistente:"
      echo "$DPKG_AUDIT"
      error "No es seguro continuar. Resuelve el problema (por ejemplo con 'sudo dpkg --configure -a' y 'sudo apt -f install') y vuelve a ejecutar el script."
    fi
    warn "dpkg está consistente: se continúa con el resto del script. Al terminar, resuelve y reintenta: sudo apt update && sudo apt full-upgrade"
  fi
else
  warn "Se omite full-upgrade. Puedes ejecutarlo luego con: sudo apt full-upgrade"
fi

if [[ -n "$MICROCODE_PKG" ]]; then
  ok "CPU detectada: ${CPU_MODEL_NAME} (${CPU_VENDOR}) -> se instalará $MICROCODE_PKG"
fi

# ----------------------------------------------------------------------
# 3. Lista de paquetes
# ----------------------------------------------------------------------
#
# Se instalan agrupados en bloques temáticos, cada uno con su propio
# "apt install", en vez de un único comando con los ~25 paquetes juntos.
# Con "set -e" activo, un solo paquete roto/en tránsito (algo frecuente
# en Sid durante transiciones de librerías) haría abortar TODO el
# script de golpe -- y a estas alturas ya se cambiaron los repos a
# unstable y se corrió full-upgrade, así que un aborto total dejaría el
# sistema a mitad de camino sin fuentes/Flathub/zram/Firefox. Al
# instalar por grupos con su propia comprobación de resultado, un fallo
# puntual solo omite ESE grupo (se avisa cuál y con qué paquetes) y el
# resto de la instalación sigue igual.

if apt-cache show 7zip >/dev/null 2>&1; then
  ARCHIVE_PACKAGES=(unzip zip 7zip)
else
  warn "El paquete '7zip' no está disponible en tus repos; se usará 'p7zip-full' en su lugar."
  ARCHIVE_PACKAGES=(unzip zip p7zip-full)
fi

# Dos arrays paralelos (los índices deben corresponderse 1 a 1): nombre
# descriptivo del grupo y string con sus paquetes separados por espacio.
GROUP_NAMES=(
  "Control de versiones / descargas"
  "Compresión"
  "Sistema / diagnóstico"
  "Utilidades de disco"
  "Desarrollo / compilación"
  "Multimedia"
  "Firmware"
  "Gestión de paquetes (GUI)"
  "Flatpak + integración KDE"
  "OCR (extracción de texto de capturas)"
)

GROUP_PACKAGES=(
  "git git-lfs curl wget"
  "${ARCHIVE_PACKAGES[*]}"
  "btop fastfetch tree jq ripgrep fd-find pciutils usbutils lshw dmidecode inxi hwinfo lm-sensors acpi"
  "gnome-disk-utility"
  "build-essential gcc g++ make cmake ninja-build pkg-config autoconf automake libtool openssh-client"
  "ffmpeg gstreamer1.0-libav gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly pavucontrol"
  "firmware-linux"
  "synaptic"
  "flatpak plasma-discover-backend-flatpak"
  # OCR para extraer texto de las capturas de pantalla (Spectacle):
  # motor Tesseract con datos de inglés, español y detección de orientación.
  "tesseract-ocr tesseract-ocr-eng tesseract-ocr-spa tesseract-ocr-osd"
)

if [[ -n "$MICROCODE_PKG" ]]; then
  GROUP_NAMES+=("Microcode de CPU")
  GROUP_PACKAGES+=("$MICROCODE_PKG")
fi

# Solo para mostrar el listado completo al usuario antes de confirmar.
ALL_PACKAGES=()
for pkgs in "${GROUP_PACKAGES[@]}"; do
  # shellcheck disable=SC2206
  ALL_PACKAGES+=($pkgs)
done

echo
echo "Se van a instalar los siguientes paquetes (agrupados en ${#GROUP_NAMES[@]} bloques):"
printf '  - %s\n' "${ALL_PACKAGES[@]}"
echo
confirm "Se van a instalar ${#ALL_PACKAGES[@]} paquetes (desarrollo, multimedia, sistema, utilidades de disco, OCR), en ${#GROUP_NAMES[@]} bloques independientes. Si alguno falla (típico en Sid durante transiciones de paquetes), se avisa y se continúa con el resto en vez de abortar toda la instalación.\n\n¿Continuar con la instalación?" || { warn "Instalación cancelada por el usuario."; exit 0; }

FAILED_GROUPS=()
for i in "${!GROUP_NAMES[@]}"; do
  group_name="${GROUP_NAMES[$i]}"
  # shellcheck disable=SC2206
  group_pkgs=(${GROUP_PACKAGES[$i]})
  log "Instalando (${group_name}): ${group_pkgs[*]}"
  if sudo apt install -y "${group_pkgs[@]}"; then
    ok "${group_name}: instalado correctamente."
  else
    warn "${group_name}: FALLÓ la instalación de este grupo (${group_pkgs[*]})."
    warn "Se continúa con el resto del script; puedes reintentar este grupo a mano luego con: sudo apt install ${group_pkgs[*]}"
    FAILED_GROUPS+=("$group_name")
  fi
done

if [[ ${#FAILED_GROUPS[@]} -gt 0 ]]; then
  warn "Grupos que fallaron y se omitieron: ${FAILED_GROUPS[*]}"
  warn "El resto de los pasos continúa. Los que necesitan un paquete de un grupo fallido (wget, flatpak, lspci) lo reintentan o se omiten con aviso."
fi

# ----------------------------------------------------------------------
# 3b. Prerrequisitos de los pasos siguientes
# ----------------------------------------------------------------------
#
# Firefox usa wget (grupo "Control de versiones / descargas"); la nota
# final sobre NVIDIA usa lspci (pciutils, grupo "Sistema / diagnóstico").
# Si ese grupo falló, se reintenta instalar solo lo imprescindible; si aun
# así no está disponible, el paso que lo necesite se omite con un aviso en
# vez de abortar el script entero por "set -e".

# ensure_cmd <comando> <paquete>: devuelve 0 si el comando existe (o se ha
# podido instalar) y 1 si no.
ensure_cmd() {
  local cmd="$1" pkg="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi
  warn "No se encontró '$cmd'; se intenta instalar '$pkg'..."
  if sudo apt install -y "$pkg" && command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi
  warn "No se pudo instalar '$pkg'."
  return 1
}

WGET_OK=0
if ensure_cmd wget wget; then
  WGET_OK=1
fi

# ----------------------------------------------------------------------
# 4. Fuentes de Windows y de Ubuntu (opcional)
# ----------------------------------------------------------------------
#
# Fuentes de Windows: ttf-mscorefonts-installer (Arial, Times New Roman,
# Courier New, etc.). Vive en el componente "contrib" (ya activado en
# nuestro sources.list) porque el propio paquete descarga los .ttf
# originales de Microsoft en tiempo de instalación y requiere aceptar
# su EULA. En modo -y (DEBIAN_FRONTEND=noninteractive) debconf acepta la
# licencia automáticamente vía preseed; en modo interactivo, debconf
# puede mostrar su propia pantalla de aceptación durante el "apt install".
#
# Fuentes de Ubuntu: fonts-ubuntu, ya empaquetada tal cual en los repos
# oficiales de Debian, sin pasos adicionales.

if confirm "¿Instalar fuentes de Windows (Arial, Times New Roman, Courier New...) vía ttf-mscorefonts-installer?\n\nEste paquete descarga las fuentes originales de Microsoft y requiere aceptar su licencia (EULA). En modo no interactivo (-y) se acepta automáticamente." 16 76; then
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | sudo debconf-set-selections
  fi
  if sudo apt install -y ttf-mscorefonts-installer; then
    ok "Fuentes de Windows instaladas."
  else
    warn "No se pudieron instalar las fuentes de Windows (el paquete las descarga de servidores externos, que a veces fallan). Se continúa; reintenta luego con: sudo apt install ttf-mscorefonts-installer"
  fi
else
  warn "Se omiten las fuentes de Windows."
fi

if confirm "¿Instalar las fuentes de Ubuntu (fonts-ubuntu)?"; then
  if sudo apt install -y fonts-ubuntu; then
    ok "Fuentes de Ubuntu instaladas."
  else
    warn "No se pudieron instalar las fuentes de Ubuntu. Se continúa; reintenta luego con: sudo apt install fonts-ubuntu"
  fi
else
  warn "Se omiten las fuentes de Ubuntu."
fi

# ----------------------------------------------------------------------
# 5. Flathub
# ----------------------------------------------------------------------

if command -v flatpak >/dev/null 2>&1; then
  FLATPAK_REMOTES="$(flatpak remote-list --columns=name 2>/dev/null || true)"
  if ! grep -qx 'flathub' <<<"$FLATPAK_REMOTES"; then
    log "Añadiendo el remoto de Flathub..."
    sudo flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  else
    ok "El remoto de Flathub ya está configurado."
  fi
else
  warn "Flatpak no está instalado (el grupo 'Flatpak + integración KDE' no se instaló); se omite la configuración de Flathub."
fi

# ----------------------------------------------------------------------
# 6. ZRAM (swap comprimido en RAM, tamaño automático según RAM total)
# ----------------------------------------------------------------------

TOTAL_RAM_KB="$(grep -m1 '^MemTotal:' /proc/meminfo | awk '{print $2}')"
TOTAL_RAM_MB=$(( TOTAL_RAM_KB / 1024 ))
ZRAM_SIZE_MB=$(( TOTAL_RAM_MB / 2 ))

if [[ -z "$TOTAL_RAM_KB" || "$ZRAM_SIZE_MB" -le 0 ]]; then
  warn "No se ha podido determinar la RAM total del sistema; se omite la configuración de zram."
else
  if confirm "RAM total detectada: ${TOTAL_RAM_MB} MiB.\n\n¿Configurar zram (swap comprimido en RAM) con ${ZRAM_SIZE_MB} MiB (mitad de la RAM)?" 14 70; then
    ZRAM_TOOLS_OK=1
    if ! dpkg -s zram-tools >/dev/null 2>&1; then
      log "Instalando zram-tools..."
      if ! sudo apt install -y zram-tools; then
        ZRAM_TOOLS_OK=0
      fi
    else
      ok "zram-tools ya está instalado."
    fi

    ZRAM_CONF="/etc/default/zramswap"

    if [[ "$ZRAM_TOOLS_OK" -ne 1 ]]; then
      warn "No se pudo instalar zram-tools; se omite la configuración de zram. Reintenta luego con: sudo apt install zram-tools"
    elif [[ -f "$ZRAM_CONF" ]]; then
      ZRAM_BACKUP="${ZRAM_CONF}.bak.$(date +%Y%m%d%H%M%S)"
      sudo cp "$ZRAM_CONF" "$ZRAM_BACKUP"
      ok "Copia de seguridad de la configuración previa: $ZRAM_BACKUP"

      if grep -q '^#\?SIZE=' "$ZRAM_CONF"; then
        SIZE_VAR="SIZE"
      elif grep -q '^#\?ALLOCATION=' "$ZRAM_CONF"; then
        SIZE_VAR="ALLOCATION"
      else
        SIZE_VAR=""
      fi

      if [[ -n "$SIZE_VAR" ]]; then
        sudo sed -i -E "/^(PERCENT|PERCENTAGE)=/ s/^/#/" "$ZRAM_CONF"

        if grep -q "^${SIZE_VAR}=" "$ZRAM_CONF"; then
          sudo sed -i "s/^${SIZE_VAR}=.*/${SIZE_VAR}=${ZRAM_SIZE_MB}/" "$ZRAM_CONF"
        else
          sudo sed -i "s/^#${SIZE_VAR}=.*/${SIZE_VAR}=${ZRAM_SIZE_MB}/" "$ZRAM_CONF"
        fi

        ok "Configurado ${SIZE_VAR}=${ZRAM_SIZE_MB} (${ZRAM_SIZE_MB} MiB) en $ZRAM_CONF"
        sudo systemctl restart zramswap.service 2>/dev/null || sudo service zramswap restart \
          || warn "No se pudo reiniciar zramswap; la nueva configuración se aplicará tras reiniciar."

        SWAPPINESS_VALUE=130
        SWAPPINESS_CONF="/etc/sysctl.d/99-zram-swappiness.conf"
        if confirm "¿Ajustar vm.swappiness a ${SWAPPINESS_VALUE} (recomendado con zram; por defecto es 60 y está pensado para swap en disco)?"; then
          echo "vm.swappiness=${SWAPPINESS_VALUE}" | sudo tee "$SWAPPINESS_CONF" >/dev/null
          if sudo sysctl -p "$SWAPPINESS_CONF" >/dev/null; then
            ok "Configurado vm.swappiness=${SWAPPINESS_VALUE} de forma persistente en $SWAPPINESS_CONF"
          else
            warn "No se pudo aplicar vm.swappiness ahora; el valor quedó guardado en $SWAPPINESS_CONF y se aplicará al reiniciar."
          fi
        else
          warn "Se omite el ajuste de vm.swappiness."
        fi
      else
        warn "No se reconoció el formato de $ZRAM_CONF. Revísalo a mano: https://wiki.debian.org/ZRam"
      fi
    else
      warn "No se encontró $ZRAM_CONF tras instalar zram-tools. Revisa manualmente: https://wiki.debian.org/ZRam"
    fi
  else
    warn "Se omite la configuración de zram."
  fi
fi

# ----------------------------------------------------------------------
# 7. Firefox oficial de Mozilla (sustituye a Firefox ESR, opcional)
# ----------------------------------------------------------------------
#
# Debian solo empaqueta "firefox-esr" en su archivo oficial (no
# distribuye la versión release por su política de marca), también en
# Testing. Se usa siempre el formato deb822 para el repositorio de
# Mozilla.
#
# NOTA sobre la migración: el objetivo es quedarse SOLO con Firefox de
# Mozilla, sin conservar nada de ESR (paquete, configuración ni perfiles).
# El orden es deliberado:
#   1) se descarga y verifica la clave de Mozilla, se añade su repositorio
#      y se comprueba que está disponible (pasos no destructivos);
#   2) solo si todo eso sale bien se elimina ESR con todos sus datos;
#   3) por último se instala Firefox.
# Así, un fallo de red o de verificación no deja el equipo sin navegador
# ni sin perfil.
#
# Los perfiles solo se borran si firefox-esr estaba instalado al empezar
# esta sección. Si no lo estaba (por ejemplo, en una reejecución del
# script), lo que haya en ~/.mozilla/firefox ya pertenece al Firefox
# normal y no se toca.

MOZILLA_PROFILES_DIR="$HOME/.mozilla/firefox"
ESR_PROFILES_REMOVED=0
ESR_PURGE_FAILED=0
FIREFOX_INSTALL_FAILED=0

if [[ "$WGET_OK" -ne 1 ]]; then
  warn "Falta 'wget' (necesario para descargar la clave de Mozilla) y no se pudo instalar. Se omite la sustitución de Firefox."
elif confirm "¿Sustituir Firefox ESR de Debian por Firefox oficial del repositorio de Mozilla?\n\nAVISO: si Firefox ESR está instalado, se eliminarán también su configuración (/etc/firefox-esr) y TODOS sus perfiles y datos en ~/.mozilla/firefox (marcadores, contraseñas, historial, extensiones). Es irreversible. Firefox normal empezará con un perfil limpio." 18 76; then

  FIREFOX_ESR_PKGS=()
  for pkg in firefox-esr firefox-esr-l10n-es; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
      FIREFOX_ESR_PKGS+=("$pkg")
    fi
  done

  MOZILLA_KEY_OK=0
  MOZILLA_READY=0

  # --- 1) Clave de Mozilla: descarga y verificación de la huella ---
  if ! command -v gpg >/dev/null 2>&1; then
    log "Instalando gnupg (necesario para verificar la clave de Mozilla)..."
    sudo apt install -y gnupg || warn "No se pudo instalar gnupg."
  fi

  if ! command -v gpg >/dev/null 2>&1; then
    warn "Sin 'gpg' no se puede verificar la clave de Mozilla. Se omite la sustitución de Firefox; ESR y sus perfiles no se han tocado."
  else
    sudo install -d -m 0755 /etc/apt/keyrings
    if wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- \
        | sudo tee /etc/apt/keyrings/packages.mozilla.org.asc >/dev/null; then
      MOZILLA_GPG_TMPHOME="$(mktemp -d)"
      trap 'rm -rf "$MOZILLA_GPG_TMPHOME"' EXIT

      MOZILLA_EXPECTED_FPR="35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3"
      MOZILLA_ACTUAL_FPR="$(
        GNUPGHOME="$MOZILLA_GPG_TMPHOME" gpg -n -q --import --import-options import-show \
          /etc/apt/keyrings/packages.mozilla.org.asc \
          | awk '/pub/{getline; gsub(/^ +| +$/,""); print; exit}'
      )" || true

      rm -rf "$MOZILLA_GPG_TMPHOME"
      trap - EXIT

      if [[ "$MOZILLA_ACTUAL_FPR" == "$MOZILLA_EXPECTED_FPR" ]]; then
        ok "Huella digital de la clave de Mozilla verificada correctamente."
        MOZILLA_KEY_OK=1
      else
        warn "ERROR: la huella digital de la clave de Mozilla NO coincide."
        warn "  Esperada: $MOZILLA_EXPECTED_FPR"
        warn "  Obtenida: ${MOZILLA_ACTUAL_FPR:-<vacía>}"
        warn "Por seguridad, se aborta este paso. Firefox ESR y sus perfiles no se han tocado."
        sudo rm -f /etc/apt/keyrings/packages.mozilla.org.asc
      fi
    else
      warn "No se pudo descargar la clave de Mozilla (¿sin conexión?). Se omite la sustitución de Firefox; ESR y sus perfiles no se han tocado."
      sudo rm -f /etc/apt/keyrings/packages.mozilla.org.asc
    fi
  fi

  # --- 2) Repositorio de Mozilla ---
  if [[ "$MOZILLA_KEY_OK" -eq 1 ]]; then
    MOZILLA_SOURCES="/etc/apt/sources.list.d/mozilla.sources"
    sudo tee "$MOZILLA_SOURCES" >/dev/null <<'EOF'
Types: deb
URIs: https://packages.mozilla.org/apt
Suites: mozilla
Components: main
Signed-By: /etc/apt/keyrings/packages.mozilla.org.asc
EOF
    ok "Repositorio de Mozilla escrito en $MOZILLA_SOURCES (formato deb822)."

    sudo tee /etc/apt/preferences.d/mozilla >/dev/null <<'EOF'
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000
EOF

    if ! sudo apt update; then
      warn "'apt update' terminó con errores; se intenta igualmente instalar Firefox por si el repositorio de Mozilla sí se descargó bien."
    fi

    # --- 3) Instalación de Firefox normal (PRIMERO, antes de tocar ESR) ---
    # No se usa "apt-cache policy" como comprobación previa: puede dar
    # falso negativo (sin candidato visible) aunque "apt install" funcione
    # perfectamente. La única forma fiable de saber si Firefox está
    # disponible es intentar instalarlo de verdad.
    if sudo apt install -y firefox; then
      MOZILLA_READY=1
      FIREFOX_L10N_CANDIDATES=(firefox-l10n-es-es firefox-l10n-es-mx firefox-l10n-es-ar firefox-l10n-es)
      FIREFOX_L10N_PKG=""
      for pkg in "${FIREFOX_L10N_CANDIDATES[@]}"; do
        if apt-cache show "$pkg" >/dev/null 2>&1; then
          FIREFOX_L10N_PKG="$pkg"
          break
        fi
      done

      if confirm "¿Instalar también el paquete de idioma español${FIREFOX_L10N_PKG:+ ($FIREFOX_L10N_PKG)}?"; then
        if [[ -n "$FIREFOX_L10N_PKG" ]]; then
          sudo apt install -y "$FIREFOX_L10N_PKG" \
            || warn "No se pudo instalar $FIREFOX_L10N_PKG. Reintenta luego con: sudo apt install $FIREFOX_L10N_PKG"
        else
          warn "No se encontró ningún paquete de idioma español disponible (se probó: ${FIREFOX_L10N_CANDIDATES[*]})."
        fi
      fi

      ok "Firefox de Mozilla instalado. Comprueba la versión con: firefox --version"
    else
      FIREFOX_INSTALL_FAILED=1
      warn "No se pudo instalar Firefox de Mozilla. Se omite la sustitución; ESR y sus perfiles no se han tocado."
      warn "Reintenta manualmente con: sudo apt update && sudo apt install firefox"
    fi
  fi

  # --- 4) Eliminación de Firefox ESR y sus datos (SOLO si Firefox normal
  # ya quedó instalado y funcionando) ---
  if [[ "$MOZILLA_READY" -eq 1 ]]; then
    ESR_PURGED=0
    if [[ ${#FIREFOX_ESR_PKGS[@]} -gt 0 ]]; then
      log "Quitando Firefox ESR: ${FIREFOX_ESR_PKGS[*]}"
      # "purge" en vez de "remove": si se usa "remove", dpkg deja el
      # paquete en estado "rc" (removido, config sin purgar) y
      # /etc/firefox-esr queda con restos de config para siempre.
      if sudo apt purge -y "${FIREFOX_ESR_PKGS[@]}"; then
        ESR_PURGED=1
        sudo apt autoremove -y || warn "'apt autoremove' falló (no es crítico)."
      else
        ESR_PURGE_FAILED=1
        warn "No se pudo eliminar Firefox ESR: puede seguir instalado junto a Firefox normal. Por seguridad no se toca /etc/firefox-esr ni se borran sus perfiles."
      fi
    else
      warn "Firefox ESR no estaba instalado como paquete (o ya se había quitado antes). No se borra ningún perfil."
    fi

    # Solo se borra /etc/firefox-esr si el purge terminó bien o si ESR ya no
    # estaba instalado (resto huérfano). Si el purge falla, ESR puede seguir
    # instalado y su configuración se deja intacta.
    if [[ -d /etc/firefox-esr && ( "$ESR_PURGED" -eq 1 || ${#FIREFOX_ESR_PKGS[@]} -eq 0 ) ]]; then
      # dpkg no borra el directorio si queda algo dentro que no le
      # pertenece a ningún paquete (por ejemplo /etc/firefox-esr/pref/).
      log "Quitando restos de configuración en /etc/firefox-esr"
      sudo rm -rf /etc/firefox-esr
    fi

    if [[ "$ESR_PURGED" -eq 1 && -d "$MOZILLA_PROFILES_DIR" ]]; then
      log "Eliminando perfiles y datos de Firefox ESR: $MOZILLA_PROFILES_DIR"
      if rm -rf -- "$MOZILLA_PROFILES_DIR"; then
        ESR_PROFILES_REMOVED=1
        ok "Perfiles y datos de Firefox ESR eliminados."
      else
        warn "No se pudieron eliminar por completo los perfiles de $MOZILLA_PROFILES_DIR. Revísalo a mano."
      fi
    fi
  fi
else
  warn "Se omite la sustitución de Firefox."
fi

# ----------------------------------------------------------------------
# 8. Driver NVIDIA, switcheroo-control y nvidia-run
# ----------------------------------------------------------------------
#
# Deliberadamente fuera de alcance de este script: la instalación del
# driver NVIDIA (repo, keyring, pin de apt, blacklist de nouveau, GRUB,
# initramfs, servicios de suspensión), switcheroo-control (GPU híbrida)
# y el wrapper nvidia-run se gestionan aparte, según el hardware de cada
# equipo. Pendiente de decidir si este proyecto tendrá su propio script
# dedicado a NVIDIA para Testing.

# ----------------------------------------------------------------------
# 9. Resumen final
# ----------------------------------------------------------------------

cat <<EOF

Instalación completada.

CPU detectada: ${CPU_MODEL_NAME}

Notas específicas de Testing:
  - A día de hoy, la cobertura de seguridad de testing NO está
    garantizada en plazos cortos por el equipo de seguridad de Debian
    (mejora según se acerca el freeze del ciclo). Si en algún momento
    necesitas parches de seguridad con más garantía, la documentación
    oficial recomienda apuntar temporalmente tus entradas a la suite de
    la stable actual. Más info: https://www.debian.org/releases/testing/
  - Antes de cada lanzamiento, testing entra en "freeze": deja de
    recibir paquetes con funcionalidades nuevas, solo correcciones de
    errores aprobadas por el equipo de release. Es normal notar que el
    ritmo de actualizaciones baja mucho durante esos meses.
  - Volver a stable desde testing es, en general, más sencillo que
    desde Sid: basta con cambiar el sources.list a la suite stable y
    ejecutar un full-upgrade, aunque siempre conviene revisar antes si
    hay downgrades de versión de por medio.

Notas generales:
  - fd-find se instala como binario "fdfind", no "fd". Si lo quieres
    como "fd":
      mkdir -p ~/.local/bin
      ln -s "\$(command -v fdfind)" ~/.local/bin/fd

  - Puede que haga falta reiniciar sesión (o el sistema) para que
    algunos cambios de firmware/microcode surtan efecto.

  - GNOME Disk Utility instalado (comando: gnome-disks) como
    herramienta de gestión de discos/particiones.

  - Si el grupo OCR se instaló, la extracción de texto de las capturas
    de pantalla (Spectacle) ya dispone de los datos de idioma de
    Tesseract (inglés, español y detección de orientación). Comprueba
    los idiomas disponibles con: tesseract --list-langs

  - Si configuraste zram, comprueba su estado con:
      zramswap status
      swapon --show
    El tamaño se calculó automáticamente a partir de tu RAM total
    (${TOTAL_RAM_MB:-desconocida} MiB detectados -> ${ZRAM_SIZE_MB:-N/A} MiB de zram).
    Si además ajustaste vm.swappiness, comprueba el valor activo con:
      sudo sysctl vm.swappiness

  - Si instalaste Firefox desde el repositorio de Mozilla, comprueba
    la versión con: firefox --version (debería ser una versión release,
    no "esr" en el nombre).

  - Si instalaste las fuentes de Windows, ya están disponibles para
    cualquier aplicación (LibreOffice, navegadores, etc.).

  - Si el script detectó y comentó contenido en /etc/apt/sources.list
    (típico de una instalación desde la ISO oficial), tienes la copia
    original en /etc/apt/sources.list.bak.<fecha> por si quieres
    revisarla o revertir el cambio.
EOF

if [[ "${ESR_PROFILES_REMOVED:-0}" -eq 1 ]]; then
  cat <<'EOF'

  - Se eliminaron también los perfiles y datos de Firefox ESR
    (~/.mozilla/firefox).
    Al abrir el Firefox nuevo se creará un perfil limpio desde cero
    (sin marcadores/contraseñas del ESR anterior).
EOF
fi

if lspci 2>/dev/null | grep -qi nvidia; then
  cat <<'EOF'

  - Se ha detectado una GPU NVIDIA, pero este script no instala su
    driver: gestiónalo aparte (repo/keyring, blacklist de nouveau,
    GRUB, initramfs) según tu hardware.
EOF
fi

if [[ "${FULL_UPGRADE_FAILED:-0}" -eq 1 ]]; then
  echo
  echo "  - ATENCIÓN: 'apt full-upgrade' falló durante la ejecución y el script"
  echo "    continuó con el resto de pasos. Cuando puedas, resuélvelo y reintenta:"
  echo "      sudo apt update && sudo apt full-upgrade"
fi

if [[ "${ESR_PURGE_FAILED:-0}" -eq 1 ]]; then
  echo
  echo "  - ATENCIÓN: no se pudo eliminar Firefox ESR, así que puede seguir"
  echo "    instalado junto a Firefox de Mozilla. Su configuración (/etc/firefox-esr)"
  echo "    y sus perfiles no se han tocado. Cuando puedas, reintenta:"
  echo "      sudo apt purge firefox-esr firefox-esr-l10n-es"
fi

if [[ "${FIREFOX_INSTALL_FAILED:-0}" -eq 1 ]]; then
  echo
  echo "  - ATENCIÓN: no se pudo instalar Firefox de Mozilla (Firefox ESR ya se"
  echo "    había eliminado). Reintenta con:"
  echo "      sudo apt update && sudo apt install firefox"
fi

if [[ ${#FAILED_GROUPS[@]} -gt 0 ]]; then
  echo
  echo "  - ATENCIÓN: los siguientes grupos de paquetes fallaron durante la"
  echo "    instalación y se omitieron (revisa el log de arriba y reintenta"
  echo "    a mano con 'sudo apt install <paquetes>'):"
  printf '      · %s\n' "${FAILED_GROUPS[@]}"
fi

echo "Detalles completos de cada paso en MANUAL.md."

if [[ "$ASSUME_YES" -ne 1 ]]; then
  whiptail --title "$TITLE" --msgbox "Instalación completada.\n\nRevisa el resumen impreso en la terminal para los detalles y próximos pasos." 12 70
fi
