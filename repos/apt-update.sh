#!/usr/bin/env bash
# Sincroniza los índices de APT (apt update).
# No actualiza paquetes instalados ni modifica las fuentes configuradas.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    exec sudo -- bash "$0" "$@"
fi

apt update
