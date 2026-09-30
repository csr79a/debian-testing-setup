#!/usr/bin/env bash
#
# corregir-repos-testing.sh
# Normaliza los repositorios de Debian Testing al formato deb822 (.sources),
# dejando las suites testing (deb.debian.org) y testing-security
# (security.debian.org).
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

# ¿El sistema es testing? En testing, /etc/debian_version es "<codename>/sid"
# (p. ej. "forky/sid") y os-release trae PRETTY_NAME="Debian GNU/Linux forky/sid".
# En stable debian_version es un número (p. ej. "13.3") y en unstable es "sid"
# (sin barra). Solo si el sistema ES testing se acepta el codename como suite;
# así, cuando forky pase a stable, dejará de aceptarse automáticamente.
SISTEMA_TESTING=false
if [[ -r /etc/os-release ]] && grep -qE '^PRETTY_NAME=.*/sid' /etc/os-release; then
    SISTEMA_TESTING=true
elif [[ -r /etc/debian_version ]] && grep -qE '/sid$' /etc/debian_version; then
    SISTEMA_TESTING=true
fi

echo "[OK] Debian detectado: $CODENAME"

SOURCE_FILE="/etc/apt/sources.list.d/debian.sources"
KEYRING="/usr/share/keyrings/debian-archive-keyring.gpg"
LEGACY="/etc/apt/sources.list"

# Suites ACEPTABLES (se conservan) y DESCARTABLES (se quitan al normalizar,
# sin detener el script). Cualquier otra suite (stable, sid, un codename
# distinto del testing...) detiene el script: no se convierte a testing.
ACEPTABLES='^(testing|testing-security)$'
DESCARTABLES='^(testing-updates|testing-proposed-updates|testing-backports)$'
if [[ "$SISTEMA_TESTING" == true ]]; then
    ACEPTABLES="^(testing|testing-security|${CODENAME}|${CODENAME}-security)$"
    DESCARTABLES="^(testing-updates|testing-proposed-updates|testing-backports|${CODENAME}-updates|${CODENAME}-proposed-updates|${CODENAME}-backports)$"
    echo "[OK] Sistema testing detectado; se acepta también el codename '$CODENAME' y '$CODENAME-security'."
fi

# Contenido final deseado.
QUIERO_CONFIG="$(cat <<EOF
Types: deb
URIs: https://deb.debian.org/debian
Suites: testing
Components: main contrib non-free non-free-firmware
Signed-By: $KEYRING

Types: deb
URIs: https://security.debian.org/debian-security
Suites: testing-security
Components: main contrib non-free non-free-firmware
Signed-By: $KEYRING
EOF
)"

# Suites de $SOURCE_FILE que son de otra rama (detienen el script).
sources_file_bad_suites() {
    awk -v acc="$ACEPTABLES" -v des="$DESCARTABLES" '
        /^Suites:/ {
            for (i = 2; i <= NF; i++)
                if ($i !~ acc && $i !~ des) print $i
        }' "$SOURCE_FILE" | sort -u
}

# Suites descartables de $SOURCE_FILE (se quitan, solo informativo).
sources_file_dropped_suites() {
    awk -v acc="$ACEPTABLES" -v des="$DESCARTABLES" '
        /^Suites:/ {
            for (i = 2; i <= NF; i++)
                if ($i ~ des && $i !~ acc) print $i
        }' "$SOURCE_FILE" | sort -u
}

# Líneas activas de $LEGACY que apuntan a Debian con una suite de otra rama.
legacy_bad_lines() {
    awk -v acc="$ACEPTABLES" -v des="$DESCARTABLES" '
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
            if (f[2] !~ acc && f[2] !~ des)
                print $0
        }' "$LEGACY"
}

# Entradas de OTROS ficheros de /etc/apt/sources.list.d que apuntan a Debian
# con una suite de otra rama. Solo se consideran de Debian las entradas cuyo
# URI es de debian.org o que usan debian-archive-keyring.
other_sources_bad_entries() {
    local f
    for f in /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list; do
        [[ -f "$f" && "$f" != "$SOURCE_FILE" ]] || continue

        case "$f" in
            *.sources)
                awk -v file="$f" -v acc="$ACEPTABLES" -v des="$DESCARTABLES" '
                    function flush(   j) {
                        if (n > 0 && enabled && isdeb)
                            for (j = 1; j <= n; j++)
                                if (suites[j] !~ acc && suites[j] !~ des)
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
                awk -v file="$f" -v acc="$ACEPTABLES" -v des="$DESCARTABLES" '
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
                        if (isdeb && f2[2] !~ acc && f2[2] !~ des)
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
        echo "[ERROR] $SOURCE_FILE apunta a suites de otra rama (no testing): $otras_suites" >&2
        echo "Este script solo normaliza la rama testing y no convierte stable/sid/codenames a testing." >&2
        echo "Corrige el archivo a mano y vuelve a ejecutarlo." >&2
        exit 1
    fi
fi

if [[ -f "$LEGACY" ]]; then
    legacy_bad="$(legacy_bad_lines)"
    if [[ -n "$legacy_bad" ]]; then
        echo "[ERROR] $LEGACY contiene repositorios Debian de otra rama (no testing):" >&2
        sed 's/^/    /' <<<"$legacy_bad" >&2
        echo "Corrige esas entradas a mano y vuelve a ejecutarlo." >&2
        exit 1
    fi
fi

other_bad="$(other_sources_bad_entries)"
if [[ -n "$other_bad" ]]; then
    echo "[ERROR] Hay otros repositorios Debian en /etc/apt/sources.list.d de otra rama (no testing):" >&2
    sed 's/^/    /' <<<"$other_bad" >&2
    echo "Corrige o desactiva esas entradas a mano y vuelve a ejecutarlo." >&2
    exit 1
fi

DROPPED="$(sources_file_dropped_suites)"
if [[ -n "$DROPPED" ]]; then
    echo "[AVISO] Se quitarán estas suites de testing no deseadas: $(tr '\n' ' ' <<<"$DROPPED")"
    echo "        La configuración final será: testing + testing-security."
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

if [ "$NECESITA_CAMBIO" -eq 1 ]; then
    BACKUP="/root/backup-repos-debian-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP"
    cp -a "$LEGACY" "$BACKUP/" 2>/dev/null || true
    cp -a /etc/apt/sources.list.d "$BACKUP/" 2>/dev/null || true
    echo "[OK] Copia de seguridad: $BACKUP"
fi

# El sources.list clásico se desactiva solo si existe contenido activo,
# y únicamente después de guardar la copia de seguridad.
if [ -f "$LEGACY" ] && [ -s "$LEGACY" ]; then
    mv "$LEGACY" "${LEGACY}.disabled"
    echo "[OK] sources.list antiguo desactivado."
fi

if [ "$ya_configurado" == true ]; then
    echo "[OK] Repositorios Debian Testing ya configurados (testing + testing-security)."
    echo "[OK] No se modifica nada."
else
    printf '%s\n' "$QUIERO_CONFIG" > "$SOURCE_FILE"
    echo "[OK] $SOURCE_FILE reescrito (testing + testing-security)."
fi

apt update

echo "[OK] Repositorios de Debian Testing corregidos."
