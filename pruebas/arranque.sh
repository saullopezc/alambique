#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# pruebas/arranque.sh — Banco del hook de arranque de skills.
#
# Uso:
#   pruebas/arranque.sh [raíz del repositorio]     por defecto, la de este script
#
# Monta un <conf> temporal con skills de mentira y comprueba qué pide el hook:
# la del marco, las que se declaran de arranque con un fichero `.arranque`, y lo
# que fija `ALAMBIQUE_SKILLS_ARRANQUE`. Cada caso va con su control. Una línea
# `ok` o `FALLA` por caso; termina 0 solo si todos pasan.
#
# Author       : Saul López
# Created Date : 2026-10-11

set -uo pipefail
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
HOOK_SRC="$RAIZ/marco/mecanismos/arranque-skills.sh"
LIB_SRC="$RAIZ/marco/mecanismos/lib"
[ -r "$HOOK_SRC" ] || { echo "no encuentro $HOOK_SRC" >&2; exit 2; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
CONF="$T/conf"
mkdir -p "$CONF/hooks" "$CONF/skills"
cp "$HOOK_SRC" "$CONF/hooks/"
cp -R "$LIB_SRC" "$CONF/hooks/"

skill() { mkdir -p "$CONF/skills/$1"; printf -- '---\nname: %s\ndescription: x\n---\n' "$1" > "$CONF/skills/$1/SKILL.md"; }
# Ejecuta el hook como lo haría el harness al abrir la sesión.
pide() { printf '{"source":"startup"}' | env -i PATH="$PATH" HOME="$T" ALAMBIQUE_CONF="$CONF" "$@" "$CONF/hooks/arranque-skills.sh" 2>/dev/null; }

CASOS=0; FALLAN=0
caso() {  # <descripción> <salida> <debe contener|no debe contener> <texto>
    CASOS=$((CASOS+1))
    local hay=1
    case "$2" in *"$4"*) hay=0 ;; esac
    if { [ "$3" = "contiene" ] && [ $hay -eq 0 ]; } || { [ "$3" = "no-contiene" ] && [ $hay -ne 0 ]; }; then
        printf '  ok     %s\n' "$1"
    else
        printf '  FALLA  %s\n' "$1"; FALLAN=$((FALLAN+1))
    fi
}

skill operacion-puesto
skill con-marca;  : > "$CONF/skills/con-marca/.arranque"
skill sin-marca

s="$(pide env)"
caso "pide la skill del marco"                         "$s" contiene    "operacion-puesto"
caso "pide la skill que trae .arranque"                "$s" contiene    "con-marca"
caso "no pide la skill instalada sin .arranque"        "$s" no-contiene "sin-marca"

rm "$CONF/skills/con-marca/.arranque"
s="$(pide env)"
caso "sin el fichero .arranque deja de pedirla"        "$s" no-contiene "con-marca"

s="$(pide env ALAMBIQUE_SKILLS_ARRANQUE="sin-marca")"
caso "la variable fija la lista: pide la nombrada"     "$s" contiene    "sin-marca"
caso "la variable fija la lista: no añade la del marco" "$s" no-contiene "operacion-puesto"

s="$(pide env ALAMBIQUE_SKILLS_ARRANQUE="sin-marca no-instalada")"
caso "avisa de la skill pedida que no está instalada"  "$s" contiene    "no-instalada"
# Que el nombre salga no basta: saldría igual en la petición de carga.
caso "… lo dice como aviso"                            "$s" contiene    "no están instaladas"
caso "… y no la pide cargar"                           "${s%%Aviso (hook*}" no-contiene "no-instalada"

rm -rf "$CONF/skills/operacion-puesto"
s="$(pide env)"
caso "avisa si falta la skill del marco"               "$s" contiene    "operacion-puesto"
caso "… lo dice como aviso"                            "$s" contiene    "no están instaladas"
caso "… y no la pide cargar"                           "${s%%Aviso (hook*}" no-contiene "operacion-puesto"

rm -rf "$CONF/hooks/lib"
s="$(pide env)"
caso "sin lib/hook.sh no calla: dice que no actúa"     "$s" contiene    "NO está actuando"

printf '\n%s casos, %s fallan\n' "$CASOS" "$FALLAN"
[ "$FALLAN" -eq 0 ]
