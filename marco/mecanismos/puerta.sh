#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# puerta.sh — La puerta de commit (R-02, R-03).
#
# Se instala como hook pre-commit. Comprueba dos cosas y solo dos:
#   1. que no se esté versionando contenido de la capa local ni de la vedada
#   2. que lo preparado no lleve datos C2/C3 dentro
#
# Mira todo lo que entra al commit salvo los borrados: altas, cambios,
# renombrados y cambios de tipo. Detiene con hallazgos ALTA; los MEDIA los
# avisa y no detienen. Los ficheros que el barrido no mira —los que se declaran
# exentos y los binarios— los cuenta y los nombra: pasan, pero a la vista. Y
# si el barrido no encontró ninguna lista de marcas del puesto, lo repite: un
# commit que pasa dice con qué se miró.
# La lista se busca donde la busca el barrido (ver su cabecera). El
# `pre-commit` no lleva `$ALAMBIQUE_CONF`: con varios harness en el puesto, y
# sin esa variable en el entorno desde el que se hace el commit, se lee la del
# primero que exista, que puede no ser el que guarda la lista.
#
# FALLA EN CERRADO, a propósito y al revés que el guard: si esta puerta se rompe,
# lo correcto es no dejar pasar el commit. Un guard que bloquea ante su propio
# error deja la herramienta inservible; una puerta que deja pasar ante su propio
# error no es una puerta. Vale igual para el barrido: si no termina con un
# veredicto, no hay commit.
#
# Se salta con `git commit --no-verify`, y eso es deliberado: la puerta protege
# del descuido, no del empeño. Ese salto no queda anotado en ningún sitio:
# ningún mecanismo registra un `--no-verify`.
# Tampoco pasa por aquí lo que git incorpora sin ejecutar `pre-commit`: un
# merge que cierra solo, sin conflictos, o que solo avanza la rama
# (fast-forward), y `cherry-pick`, `rebase`, `revert` y `git am`. Lo que entra
# por esos caminos no lo ha mirado la puerta: queda para el barrido del árbol
# (`barrido.sh` sin `--staged`), que busca patrones en el contenido y no avisa
# de que un fichero de `_local/` haya quedado versionado.
#
# Author       : Saul López
# Created Date : 2026-08-31

set -uo pipefail
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
unset -f grep sed awk find head cut sort tr wc cat 2>/dev/null || true

# Fallo propio -> se bloquea. Es la diferencia entre una puerta y un adorno.
set -E
trap 'printf "\n  BLOQUEADO: la puerta falló (línea %s). No se hace commit a ciegas.\n\n" "$LINENO"; exit 1' ERR

AQUI="$(cd "$(dirname "$0")" && pwd)"
RC=0

# Un nombre de fichero ocupa siempre una línea del aviso.
visible() { printf '%s' "${1//[[:cntrl:]]/?}"; }

# Los ficheros que el barrido lista con una etiqueta, contados y uno por línea.
nombrar() {  # <etiqueta del barrido> <qué son>
    local lista
    lista="$(printf '%s\n' "$SALIDA" | sed -n "s/^  $1 //p")"
    [ -n "$lista" ] || return 0
    printf '  aviso %s fichero(s) %s:\n' "$(printf '%s\n' "$lista" | awk 'END { print NR }')" "$2"
    printf '%s\n' "$lista" | sed 's/^/        /'
}

printf '\npuerta de commit\n'

# --- 1. Capa local y capa vedada ---------------------------------------------
# Solo el esqueleto puede subir: los `.gitkeep` y el README de cada capa, lo
# mismo que deja pasar la regla de ignore. Cualquier otra cosa es un dato en
# el árbol.
# Los nombres se leen separados por NUL: git no entrecomilla así los que llevan
# ñ, tildes o espacios, y uno con salto de línea no se parte en dos. Si el
# listado falla, la puerta falla con él: sin lista no hay nada comprobado.
LISTA="$(mktemp)"
trap 'rm -f "$LISTA"' EXIT
git diff --cached --name-only -z --no-renames --diff-filter=d > "$LISTA"

COLADOS=""
while IFS= read -r -d '' f; do
    case "/$f" in
        */_local/*|*/__restriccion/*) ;;
        *) continue ;;
    esac
    case "/$f" in
        */.gitkeep|*/_local/README.md|*/__restriccion/README.md) continue ;;
    esac
    COLADOS="${COLADOS}    $(visible "$f")"$'\n'
done < "$LISTA"

if [ -n "$COLADOS" ]; then
    printf '\n  BLOQUEADO — contenido de la capa local preparado para commit:\n\n'
    printf '%s' "$COLADOS"
    printf '\n  Eso es C2 o C3 (R-02). Sácalo del índice:\n'
    printf '    git restore --staged <fichero>\n'
    RC=1
else
    printf '  ok   nada de _local/ ni __restriccion/ en el índice\n'
fi

# --- 2. Barrido de lo preparado ----------------------------------------------
if [ -x "$AQUI/barrido.sh" ]; then
    # La asignación va DENTRO de un `if`: una salida != 0 del barrido es su
    # veredicto, no un fallo de la puerta. Fuera del `if`, el trap ERR se
    # dispara con el hallazgo y la puerta se acusa a sí misma de rota.
    if SALIDA="$("$AQUI/barrido.sh" --staged 2>&1)"; then BRC=0; else BRC=$?; fi
    # Solo 0 y 2 dejan pasar. Cualquier otro código que no sea el de hallazgos
    # es un barrido que no terminó, y un barrido sin veredicto no es «limpio».
    case $BRC in
        0) printf '  ok   barrido sin hallazgos\n' ;;
        2) printf '  aviso barrido con hallazgos MEDIA (no bloquea):\n'
           # awk lee la salida entera aunque solo enseñe diez: un `head` que
           # corta la tubería mata al que escribe y, con pipefail, el aviso se
           # vuelve bloqueo.
           printf '%s\n' "$SALIDA" | awk '
               /^ +MEDIA / { n++; if (n <= 10) print "  " $0 }
               END { if (n > 10) printf "      … y %d más\n", n - 10 }' ;;
        1) printf '\n  BLOQUEADO — el barrido encontró datos C2/C3 en lo preparado:\n\n'
           printf '%s\n' "$SALIDA" | sed 's/^/  /'
           printf '  Los valores salen enmascarados. Para verlos:\n'
           printf '    %s --staged --full\n' "$AQUI/barrido.sh"
           RC=1 ;;
        *) printf '\n  BLOQUEADO — el barrido no terminó (código %s). Sin veredicto no hay commit:\n\n' "$BRC"
           printf '%s\n' "$SALIDA" | sed 's/^/  /'
           RC=1 ;;
    esac
    # Lo que el barrido no mira —exentos y binarios— se dice siempre que el
    # commit pueda pasar; cuando se detiene, ya va en la salida del barrido.
    case $BRC in
        0|2) nombrar EXENTO  'exento(s) del barrido — no se han mirado'
             nombrar BINARIO 'binario(s) — el barrido no los lee'
             # Sin lista de marcas el barrido solo pasó los patrones generales,
             # y un «sin hallazgos» callado se leería como que miró también los
             # nombres del puesto. La línea es la que escribe `barrido.sh`, y se
             # compara ENTERA: la misma frase dentro de un hallazgo no cuenta.
             if printf '%s\n' "$SALIDA" | grep -qxF 'sin lista de marcas propias — solo patrones generales'; then
                 printf '  aviso sin lista de marcas propias: el barrido solo pasó los patrones generales\n'
             fi ;;
    esac
else
    printf '\n  BLOQUEADO: no encuentro barrido.sh. Una puerta que no puede\n'
    printf '  comprobar no deja pasar.\n'
    RC=1
fi

printf '\n'
if [ "$RC" -ne 0 ]; then
    printf 'Commit detenido. Si estás seguro: git commit --no-verify\n\n'
fi
exit "$RC"
