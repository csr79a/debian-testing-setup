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

# Antes de modificar nada, comprobamos que las fuentes de Debian que
# ya existen no apunten a otra suite. Este script normaliza a Testing,
# pero NO convierte automáticamente una instalación que use stable,
# unstable/sid, un codename concreto u otra suite.
#
# Se revisa debian.sources, el sources.list clásico y otros .sources/.list
# que parezcan ser repositorios de Debian. Las fuentes de terceros no se
# bloquean por usar nombres de suite propios.

sources_file_bad_suites() {
    awk '/^Suites:/ {
        for (i = 2; i <= NF; i++)
            if ($i != "testing") print $i
    }' "$SOURCE_FILE" | sort -u
}

legacy_bad_lines() {
    awk '
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
            if (f[2] != "testing")
                print $0
        }' /etc/apt/sources.list
}

other_sources_bad_entries() {
    local f
    for f in /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list; do
        [[ -f "$f" && "$f" != "$SOURCE_FILE" ]] || continue

        case "$f" in
            *.sources)
                awk -v file="$f" '
                    function flush(   j) {
                        if (n > 0 && enabled && isdeb)
                            for (j = 1; j <= n; j++)
                                if (suites[j] != "testing")
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
                awk '
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
                        if (isdeb && f2[2] != "testing")
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
        echo "[ERROR] $SOURCE_FILE apunta a suites distintas de testing: $otras_suites" >&2
        echo "Este script no convierte otras suites a testing. Corrige el archivo a mano y vuelve a ejecutarlo." >&2
        exit 1
    fi
fi

if [[ -f /etc/apt/sources.list ]]; then
    legacy_bad="$(legacy_bad_lines)"
    if [[ -n "$legacy_bad" ]]; then
        echo "[ERROR] /etc/apt/sources.list contiene repositorios Debian que no apuntan a testing:" >&2
        sed 's/^/    /' <<<"$legacy_bad" >&2
        echo "Este script no convierte otras suites a testing. Corrige esas entradas a mano y vuelve a ejecutarlo." >&2
        exit 1
    fi
fi

other_bad="$(other_sources_bad_entries)"
if [[ -n "$other_bad" ]]; then
    echo "[ERROR] Hay otros repositorios Debian en /etc/apt/sources.list.d que no apuntan a testing:" >&2
    sed 's/^/    /' <<<"$other_bad" >&2
    echo "Este script no convierte otras suites a testing. Corrige o desactiva esas entradas a mano y vuelve a ejecutarlo." >&2
    exit 1
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
