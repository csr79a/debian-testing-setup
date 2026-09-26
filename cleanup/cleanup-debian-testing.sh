#!/usr/bin/env bash
#
# cleanup-debian-testing.sh — Limpiador de Debian Testing csr79a
#
# Elimina aplicaciones de KDE Plasma que Debian instala por defecto junto
# a la tarea "KDE Plasma Workspaces" pero que muchos usuarios no llegan a
# usar (suite PIM/Kontact, algunas herramientas de accesibilidad,
# Konqueror, KDE Partition Manager). Pensado como complemento
# independiente de setup-debian-testing.sh: ese script instala, este quita.
#
# No depende de la rama de Debian: esta limpieza actúa solo sobre
# paquetes de escritorio KDE que no cambian según la suite configurada.
#
# El script está organizado en GRUPOS. Cada grupo se revisa y confirma
# por separado (pantallas whiptail), y solo intenta eliminar los
# paquetes de ese grupo que estén realmente instalados. Por defecto usa
# "apt remove" (deja los ficheros de configuración); usa --purge si
# además quieres borrarlos.
#
# Uso:
#   chmod +x cleanup-debian-testing.sh
#   ./cleanup-debian-testing.sh              # modo interactivo, pantallas whiptail
#   ./cleanup-debian-testing.sh -y            # no interactivo, confirma todos los grupos
#   ./cleanup-debian-testing.sh --purge       # como el anterior pero borrando también configuración
#   ./cleanup-debian-testing.sh --imagemagick # además, evalúa quitar ImageMagick (ver aviso abajo)
#
# Licencia: MIT

set -euo pipefail

TITLE="Limpiador de Debian Testing csr79a"
VERSION="1.0.0"

log()   { echo -e "\e[1;34m[*]\e[0m $*"; }
ok()    { echo -e "\e[1;32m[OK]\e[0m $*"; }
warn()  { echo -e "\e[1;33m[!]\e[0m $*"; }
error() { echo -e "\e[1;31m[ERROR]\e[0m $*" >&2; exit 1; }

# ----------------------------------------------------------------------
# 0. Opciones de línea de comandos
# ----------------------------------------------------------------------

ASSUME_YES=0
PURGE=0
INCLUDE_IMAGEMAGICK=0
APT_ACTION="remove"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)
      ASSUME_YES=1
      shift
      ;;
    --purge)
      PURGE=1
      APT_ACTION="purge"
      shift
      ;;
    --imagemagick)
      INCLUDE_IMAGEMAGICK=1
      shift
      ;;
    -h|--help)
      echo "Uso: $0 [-y|--yes] [--purge] [--imagemagick]"
      echo "  -y, --yes      No pedir confirmación por grupo (modo no interactivo)."
      echo "  --purge        Usar 'apt purge' en vez de 'apt remove' (borra también config)."
      echo "  --imagemagick  Evaluar también la eliminación de ImageMagick (grupo aparte)."
      exit 0
      ;;
    *)
      echo "Opción desconocida: $1" >&2
      exit 1
      ;;
  esac
done

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
# durante la eliminación/purga (p. ej. plantillas debconf de algún
# paquete PIM). Mismo patrón que setup-debian-testing.sh.
if [[ "$ASSUME_YES" -eq 1 ]]; then
  export DEBIAN_FRONTEND=noninteractive
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

if ! command -v whiptail >/dev/null 2>&1; then
  log "Instalando whiptail (necesario para las pantallas de este script)..."
  sudo apt update
  sudo apt install -y whiptail
fi

log "Comprobando permisos de sudo..."
if ! sudo -v; then
  error "No se pudieron validar los permisos de sudo."
fi

# ----------------------------------------------------------------------
# Pantalla de bienvenida
# ----------------------------------------------------------------------

confirm "Versión del Limpiador de Debian Testing csr79a ${VERSION}\n\nEste programa revisa, grupo por grupo, aplicaciones de KDE Plasma instaladas por defecto en Debian que muchos usuarios no llegan a usar (suite PIM/Kontact, accesibilidad, Konqueror, xterm, KDE Connect, Dragon Player, Juk, KDE Partition Manager, e ImageMagick de forma opcional).\n\nNo se eliminará nada sin tu confirmación explícita de cada grupo.\n\n¿Desea continuar?" 18 76 || exit 0

# ----------------------------------------------------------------------
# 2. Utilidades
# ----------------------------------------------------------------------

is_installed() {
  # dpkg -s también devuelve éxito para paquetes en estado "rc"
  # (eliminados con "apt remove" pero con config residual, algo típico
  # si ya corriste este script antes sin --purge). Comprobamos el
  # estado real ("install ok installed") para no volver a ofrecer
  # eliminar algo que ya no está instalado.
  local status
  status="$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" || return 1
  [[ "$status" == "install ok installed" ]]
}

# remove_group <nombre> <pkg1> [pkg2 ...]
remove_group() {
  local group_name="$1"
  shift
  local candidates=("$@")
  local to_remove=()

  for pkg in "${candidates[@]}"; do
    if is_installed "$pkg"; then
      to_remove+=("$pkg")
    fi
  done

  echo
  echo "== Grupo: $group_name =="
  if [[ ${#to_remove[@]} -eq 0 ]]; then
    ok "Nada que hacer (ninguno de estos paquetes está instalado)."
    return
  fi

  echo "Instalados en este grupo: ${to_remove[*]}"
  if ! confirm "Grupo: ${group_name}\n\nInstalados: ${to_remove[*]}\n\n¿Eliminar este grupo con 'apt ${APT_ACTION}'?" 16 76; then
    warn "Grupo omitido."
    return
  fi

  # Sin -y aquí: dejamos que apt muestre su propio resumen (incluyendo
  # cualquier dependencia que se lleve por delante) en la terminal
  # normal, salvo que el usuario haya pedido explícitamente modo no
  # interactivo.
  #
  # IMPORTANTE: esto va dentro de un if/else a propósito. Con "set -e"
  # activo, si el usuario contesta "n" en la pregunta [Y/n] de apt (o
  # si apt falla por cualquier otro motivo), el comando devuelve un
  # código distinto de 0 -- y sin este if, eso mataría TODO el script
  # ahí mismo, dejando sin procesar el resto de los grupos, el
  # autoremove/autoclean final y el resumen. Tratamos un "no" de apt
  # como "se omite este grupo", igual que un "no" de whiptail.
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    if sudo apt "$APT_ACTION" -y "${to_remove[@]}"; then
      ok "Grupo '${group_name}' procesado."
    else
      warn "Grupo '${group_name}': falló 'apt ${APT_ACTION}'. Se omite y se continúa con el resto."
    fi
  else
    if sudo apt "$APT_ACTION" "${to_remove[@]}"; then
      ok "Grupo '${group_name}' procesado."
    else
      warn "Grupo '${group_name}': cancelado o falló 'apt ${APT_ACTION}'. Se continúa con el resto."
    fi
  fi
}

# ----------------------------------------------------------------------
# 3. Grupos de paquetes
# ----------------------------------------------------------------------

# GRUPO 1 — Suite PIM / Kontact
PIM_GROUP=(
  kmail
  kaddressbook
  ktnef
  kdepim-themeeditors
  pim-sieve-editor
  pim-data-exporter
  korganizer
  akregator
)

# GRUPO 2 — Accesibilidad
ACCESSIBILITY_GROUP=(
  kmousetool
  kmouth
  kontrast
)

# GRUPO 3 — Konqueror
KONQUEROR_GROUP=(
  konqueror
)

# GRUPO 3b — xterm
XTERM_GROUP=(
  xterm
)

# GRUPO 3c — KDE Connect
KDECONNECT_GROUP=(
  kdeconnect
)

# GRUPO 3d — Dragon Player
DRAGONPLAYER_GROUP=(
  dragonplayer
)

# GRUPO 3e — Juk
JUK_GROUP=(
  juk
)

# GRUPO 3f — KDE Partition Manager
# Se elimina porque el setup instala GNOME Disk Utility como
# alternativa para gestión de discos/particiones. Independiente de los
# demás grupos: no comparte árbol de dependencias con ninguno.
#
# A diferencia de los demás grupos, este no usa remove_group() genérico:
# comprueba explícitamente si gnome-disk-utility está instalado (no solo
# por comentario) para avisar si no habría alternativa gráfica de
# gestión de discos/particiones tras la eliminación.
remove_partitionmanager_group() {
  echo
  echo "== Grupo: KDE Partition Manager =="
  if ! is_installed partitionmanager; then
    ok "Nada que hacer (partitionmanager no está instalado)."
    return
  fi

  local warning_text=""
  if ! is_installed gnome-disk-utility; then
    warning_text="\n\nAVISO: gnome-disk-utility NO está instalado en este sistema. Si eliminas KDE Partition Manager, te quedarás sin gestor de particiones gráfico salvo que instales uno (p. ej.: sudo apt install gnome-disk-utility)."
  fi

  echo "Instalados en este grupo: partitionmanager"
  if ! confirm "Instalado: partitionmanager${warning_text}\n\n¿Eliminar este grupo con 'apt ${APT_ACTION}'?" 18 78; then
    warn "Grupo omitido."
    return
  fi

  # Ver el comentario equivalente en remove_group(): sin el if/else acá,
  # un "no" en la pregunta de apt (o un fallo) cortaría todo el script
  # por "set -e" y no llegaría a procesar ImageMagick, autoremove, etc.
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    if sudo apt "$APT_ACTION" -y partitionmanager; then
      ok "Grupo 'KDE Partition Manager' procesado."
    else
      warn "Grupo 'KDE Partition Manager': falló 'apt ${APT_ACTION}'. Se omite y se continúa."
    fi
  else
    if sudo apt "$APT_ACTION" partitionmanager; then
      ok "Grupo 'KDE Partition Manager' procesado."
    else
      warn "Grupo 'KDE Partition Manager': cancelado o falló 'apt ${APT_ACTION}'. Se continúa."
    fi
  fi
}

# GRUPO 4 (opcional, --imagemagick) — ImageMagick
IMAGEMAGICK_GROUP=(
  imagemagick
)

# ----------------------------------------------------------------------
# 4. Ejecución
# ----------------------------------------------------------------------

remove_group "Suite PIM / Kontact (KMail, KAddressBook, KTnef, editores de tema, Sieve, exportador PIM, KOrganizer, Akregator)" "${PIM_GROUP[@]}"
remove_group "Accesibilidad (KMouseTool, KMouth, Kontrast)" "${ACCESSIBILITY_GROUP[@]}"
remove_group "Konqueror" "${KONQUEROR_GROUP[@]}"
remove_group "xterm" "${XTERM_GROUP[@]}"
remove_group "KDE Connect" "${KDECONNECT_GROUP[@]}"
remove_group "Dragon Player" "${DRAGONPLAYER_GROUP[@]}"
remove_group "Juk" "${JUK_GROUP[@]}"
remove_partitionmanager_group

if [[ "$INCLUDE_IMAGEMAGICK" -eq 1 ]]; then
  echo
  echo "== Grupo opcional: ImageMagick =="
  if is_installed imagemagick; then
    RDEPENDS="$(apt-cache rdepends imagemagick | sed -n '1,15p')"
    if confirm "ImageMagick no es una app de Plasma: puede que otros programas lo usen por debajo.\n\nPaquetes que dependen de él (primeras líneas):\n${RDEPENDS}\n\n¿Aun así quieres eliminarlo?" 22 78; then
      # Mismo motivo que en remove_group(): if/else para que un "no" o
      # un fallo de apt no corte el script antes del autoremove/autoclean.
      if [[ "$ASSUME_YES" -eq 1 ]]; then
        if sudo apt "$APT_ACTION" -y imagemagick; then
          ok "ImageMagick eliminado."
        else
          warn "Falló 'apt ${APT_ACTION} imagemagick'. Se omite y se continúa."
        fi
      else
        if sudo apt "$APT_ACTION" imagemagick; then
          ok "ImageMagick eliminado."
        else
          warn "Cancelado o falló 'apt ${APT_ACTION} imagemagick'. Se continúa."
        fi
      fi
    else
      warn "Se omite ImageMagick."
    fi
  else
    ok "ImageMagick no está instalado."
  fi
fi

echo
if confirm "¿Ejecutar 'apt autoremove' para limpiar dependencias huérfanas?"; then
  if sudo apt autoremove; then
    ok "autoremove completado."
  else
    warn "Cancelado o falló 'apt autoremove'. Se continúa igualmente."
  fi
fi

echo
if confirm "¿Ejecutar 'apt autoclean' para limpiar el caché de paquetes .deb descargados que ya no están disponibles?"; then
  if sudo apt autoclean; then
    ok "autoclean completado."
  else
    warn "Cancelado o falló 'apt autoclean'. Se continúa igualmente."
  fi
fi

cat <<'EOF'

Limpieza completada.

Notas:
  - Se usó "apt remove" (o "apt purge" si pasaste --purge). Con "remove"
    los ficheros de configuración en tu $HOME y en /etc no se tocan; si
    quieres borrarlos también, vuelve a ejecutar con --purge.
  - Si más adelante echas en falta alguna app, se reinstala igual que
    cualquier otro paquete: sudo apt install <paquete>.
  - Si quitaste KDE Partition Manager y necesitas gestionar discos o
    particiones, usa GNOME Disk Utility (comando: gnome-disks), que
    instala setup-debian-testing.sh.
  - Este script es intencionadamente conservador: pide confirmación por
    grupo y dentro de cada "apt remove/purge" verás el resumen real de
    la transacción antes de que se aplique (salvo en modo -y).
  - Tras un "apt full-upgrade", alguno de estos paquetes podría volver
    a aparecer si otro paquete lo reintroduce como dependencia. Si pasa,
    vuelve a ejecutar este script.
EOF
