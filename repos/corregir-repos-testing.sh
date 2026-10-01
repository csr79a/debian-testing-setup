#!/usr/bin/env bash
#
# corregir-repos-testing.sh
# Normaliza los repositorios de Debian Testing al formato deb822 (.sources),
# incluyendo las tres suites que existen en el archivo:
#   - testing         (deb.debian.org)
#   - testing-updates (deb.debian.org)
#   - testing-security (security.debian.org)
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

# Testing y unstable NO definen VERSION_ID en /etc/os-release; una release
# estable sí. Si existe, es una release estable: no se toca nada.
if [ -n "${VERSION_ID:-}" ]; then
    echo "[ERROR] /etc/os-release define VERSION_ID=$VERSION_ID: este sistema es una release estable, no testing." >&2
    echo "Este script no convierte stable a testing. No se ha modificado nada." >&2
    exit 1
fi

echo "[OK] Debian detectado: $CODENAME (sin VERSION_ID: testing/unstable)"

SOURCE_FILE="/etc/apt/sources.list.d/debian.sources"
KEYRING="/usr/share/keyrings/debian-archive-keyring.gpg"
LEGACY="/etc/apt/sources.list"

if [ ! -r "$KEYRING" ]; then
    echo "[ERROR] No existe $KEYRING. Instala debian-archive-keyring antes de continuar." >&2
    exit 1
fi

# Contenido final deseado: las tres suites de testing.
QUIERO_CONFIG="$(cat <<EOF
Types: deb
URIs: https://deb.debian.org/debian
Suites: testing
Components: main contrib non-free non-free-firmware
Signed-By: $KEYRING

Types: deb
URIs: https://deb.debian.org/debian
Suites: testing-updates
Components: main contrib non-free non-free-firmware
Signed-By: $KEYRING

Types: deb
URIs: https://security.debian.org/debian-security
Suites: testing-security
Components: main contrib non-free non-free-firmware
Signed-By: $KEYRING
EOF
)"

# Antes de modificar nada, comprobamos que las fuentes de Debian que ya
# existen no apunten a otra rama. Se aceptan SOLO estas suites:
#   testing, testing-updates, testing-security
# y, como el instalador de testing deja el codename (p. ej. forky) en vez de
# "testing", ese mismo codename con sus sufijos (forky, forky-updates,
# forky-security). El codename solo se acepta porque arriba se ha comprobado
# con /etc/os-release que el sistema NO es una release estable. No se aceptan
# testing-proposed-updates, testing-backports ni ninguna otra suite, y NO se
# convierte stable/unstable/sid ni otra rama.
#
# Se revisan debian.sources, el sources.list clásico y otros .sources/.list
# que parezcan ser repositorios de Debian. Las fuentes de terceros no se
# bloquean por usar nombres de suite propios.

sources_file_bad_suites() {
    awk -v cn="$CODENAME" 'function okSuite(s) { return (s == "testing" || s == "testing-updates" || s == "testing-security" || s == cn || s == cn "-updates" || s == cn "-security") }
/^Suites:/ {
        for (i = 2; i <= NF; i++) {
            s = $i
            if (!okSuite(s)) print s
        }
    }' "$SOURCE_FILE" | sort -u
}

legacy_bad_lines() {
    awk -v cn="$CODENAME" '
        function okSuite(s) { return (s == "testing" || s == "testing-updates" || s == "testing-security" || s == cn || s == cn "-updates" || s == cn "-security") }
        /^[[:space:]]*deb(-src)?[[:space:]]/ {
            line = $0
            sub(/^[[:space:]]*deb(-src)?[[:space:]]+/, "", line)
            if (line ~ /^\[/)
                sub(/^\[[^]]*\][[:space:]]*/, "", line)
            split(line, f, /[[:space:]]+/)
            if (f[1] ~ /^cdrom:/)
                next
            if (tolower(f[1]) !~ /debian/)
                next
            if (!okSuite(f[2]))
                print $0
        }' "$LEGACY"
}

other_sources_bad_entries() {
    local f
    for f in /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list; do
        [[ -f "$f" && "$f" != "$SOURCE_FILE" ]] || continue

        case "$f" in
            *.sources)
                awk -v file="$f" -v cn="$CODENAME" '
                    function okSuite(s) { return (s == "testing" || s == "testing-updates" || s == "testing-security" || s == cn || s == cn "-updates" || s == cn "-security") }
                    function flush(   j) {
                        if (n > 0 && enabled && isdeb)
                            for (j = 1; j <= n; j++)
                                if (!okSuite(suites[j]))
                                    print file ": Suites: " suites[j]
                        n = 0
                        enabled = 1
                        isdeb = 0
                        delete suites
                    }
                    BEGIN { enabled = 1 }
                    /^[[:space:]]*$/ { flush(); next }
                    /^#/ { next }
                    /^URIs:/ {
                        if (tolower($0) ~ /[\/.]debian\.org(\/|[[:space:]]|$)/)
                            isdeb = 1
                    }
                    /^Signed-By:/ {
                        if ($0 ~ /debian-archive-keyring/)
                            isdeb = 1
                    }
                    /^Enabled:/ {
                        if (tolower($2) == "no" || tolower($2) == "false")
                            enabled = 0
                    }
                    /^Suites:/ {
                        for (k = 2; k <= NF; k++)
                            suites[++n] = $k
                    }
                    END { flush() }
                ' "$f"
                ;;
            *.list)
                awk -v file="$f" -v cn="$CODENAME" '
                    function okSuite(s) { return (s == "testing" || s == "testing-updates" || s == "testing-security" || s == cn || s == cn "-updates" || s == cn "-security") }
                    /^[[:space:]]*deb(-src)?[[:space:]]/ {
                        line = $0
                        sub(/^[[:space:]]*deb(-src)?[[:space:]]+/, "", line)
                        opts = ""
                        if (line ~ /^\[/) {
                            opts = line
                            sub(/\].*$/, "]", opts)
                            sub(/^\[[^]]*\][[:space:]]*/, "", line)
                        }
                        split(line, f2, /[[:space:]]+/)
                        if (f2[1] ~ /^cdrom:/)
                            next
                        isdeb = (tolower(f2[1]) ~ /[\/.]debian\.org(\/|$)/) || (opts ~ /debian-archive-keyring/)
                        if (isdeb && !okSuite(f2[2]))
                            print file ": " $0
                    }
                ' "$f"
                ;;
        esac
    done
}

if [[ -f "$SOURCE_FILE" ]]; then
    if ! grep -q '^Suites:' "$SOURCE_FILE"; then
        echo "[ERROR] No se encontró la línea 'Suites:' en $SOURCE_FILE; no se puede verificar la suite con seguridad." >&2
        exit 1
    fi

    otras_suites="$(sources_file_bad_suites)"
    if [[ -n "$otras_suites" ]]; then
        echo "[ERROR] $SOURCE_FILE apunta a suites que no son de testing: $otras_suites" >&2
        echo "Este script solo acepta: testing, testing-updates, testing-security (o el codename actual: $CODENAME, $CODENAME-updates, $CODENAME-security)." >&2
        echo "Corrige el archivo a mano y vuelve a ejecutarlo." >&2
        exit 1
    fi
fi

if [[ -f "$LEGACY" ]]; then
    legacy_bad="$(legacy_bad_lines)"
    if [[ -n "$legacy_bad" ]]; then
        echo "[ERROR] $LEGACY contiene repositorios Debian que no son de testing:" >&2
        sed 's/^/    /' <<<"$legacy_bad" >&2
        echo "Corrige esas entradas a mano y vuelve a ejecutarlo." >&2
        exit 1
    fi
fi

other_bad="$(other_sources_bad_entries)"
if [[ -n "$other_bad" ]]; then
    echo "[ERROR] Hay otros repositorios Debian en /etc/apt/sources.list.d que no son de testing:" >&2
    sed 's/^/    /' <<<"$other_bad" >&2
    echo "Corrige o desactiva esas entradas a mano y vuelve a ejecutarlo." >&2
    exit 1
fi

# ¿Ya está exactamente como queremos? Entonces no hay nada que reescribir.
ya_configurado=false
if [[ -f "$SOURCE_FILE" ]] && [[ "$(<"$SOURCE_FILE")" == "$QUIERO_CONFIG" ]]; then
    ya_configurado=true
fi

# Solo se crea una copia de seguridad si realmente vamos a modificar algo.
NECESITA_CAMBIO=1
if [[ "$ya_configurado" == true ]] \
    && { [ ! -f "$LEGACY" ] || [ ! -s "$LEGACY" ]; }; then
    NECESITA_CAMBIO=0
fi

BACKUP=""
DISABLED=""

if [ "$NECESITA_CAMBIO" -eq 1 ]; then
    BACKUP="/root/backup-repos-debian-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP"
    # Sin "|| true": si la copia falla, el script se detiene ANTES de tocar nada.
    if [ -f "$LEGACY" ]; then
        cp -a "$LEGACY" "$BACKUP/"
    fi
    if [ -d /etc/apt/sources.list.d ]; then
        cp -a /etc/apt/sources.list.d "$BACKUP/"
    fi
    echo "[OK] Copia de seguridad: $BACKUP"
fi

# Restaura el estado anterior si falla una operación sobre ficheros.
rollback() {
    echo "[ERROR] Falló la modificación de las fuentes; restaurando desde $BACKUP" >&2
    if [ -n "$DISABLED" ] && [ -f "$DISABLED" ] && [ ! -e "$LEGACY" ]; then
        mv "$DISABLED" "$LEGACY"
    fi
    if [ -f "$BACKUP/sources.list.d/debian.sources" ]; then
        cp -a "$BACKUP/sources.list.d/debian.sources" "$SOURCE_FILE"
    else
        rm -f "$SOURCE_FILE"
    fi
}

# El sources.list clásico se desactiva solo si tiene contenido, y
# únicamente después de guardar la copia de seguridad. Si ya existe un
# .disabled previo no se sobrescribe: se añade marca de tiempo.
if [ -f "$LEGACY" ] && [ -s "$LEGACY" ]; then
    DISABLED="${LEGACY}.disabled"
    if [ -e "$DISABLED" ]; then
        DISABLED="${DISABLED}.$(date +%Y%m%d-%H%M%S)"
    fi
    if ! mv "$LEGACY" "$DISABLED"; then
        rollback
        exit 1
    fi
    echo "[OK] sources.list antiguo desactivado: $DISABLED"
fi

if [ "$ya_configurado" == true ]; then
    echo "[OK] Repositorios Debian Testing ya configurados (testing + testing-updates + testing-security)."
    echo "[OK] No se modifica nada."
else
    if ! printf '%s\n' "$QUIERO_CONFIG" > "$SOURCE_FILE"; then
        rollback
        exit 1
    fi
    echo "[OK] $SOURCE_FILE reescrito (testing + testing-updates + testing-security)."
fi

# Un fallo de 'apt update' puede ser de red y no de configuración, así que
# no se revierte solo: se informa de cómo volver atrás.
if ! apt update; then
    echo "[ERROR] 'apt update' ha fallado (red o configuración de repositorios)." >&2
    if [ -n "$BACKUP" ]; then
        echo "Copia del estado anterior en: $BACKUP (sources.list y sources.list.d/)." >&2
        echo "Para volver atrás: restaura esos ficheros con 'cp -a' y elimina ${DISABLED:-el .disabled} si lo creó el script." >&2
    fi
    exit 1
fi

echo "[OK] Repositorios de Debian Testing corregidos."
