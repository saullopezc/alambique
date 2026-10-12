#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# instalar.sh — Pone la skill del marco en cada harness del puesto y el marco
# en el principal.
#
# Uso:
#   ./instalar.sh                  skill + marco del puesto
#   ./instalar.sh /ruta/proyecto   además, alta del proyecto (capa local, puerta)
#   ./instalar.sh --solo-skills    solo la skill, sin tocar el marco
#
# NO SE ASUME NINGÚN HARNESS. La skill va a TODOS los que estén presentes y
# lean skills (tabla en marco/mecanismos/lib/harness.sh); el marco va al
# principal ($ALAMBIQUE_CONF o el primero detectado). Lo que en ese harness no se
# pueda poner, marco/instalar.sh lo declara: aquí no se maquilla.
#
# Idempotente: una skill ya instalada por este script se sustituye por la
# versión del repositorio, y si ya es esa versión no se toca. Una del mismo
# nombre que NO puso este script se respeta y se avisa.
#
# Lo que el marco copió —hooks y skill— se sustituye ENTERO por la versión del
# repositorio, sin copia previa: no se edita en su copia instalada. Un fichero
# dejado dentro de una skill instalada por este script se va con ella.
#
# Salidas: 0 todo puesto · 1 alguna pieza falló · 3 hueco declarado por el
# marco (harness sin adaptador), sin fallos.
#
# Author       : Saul López
# Created Date : 2026-09-12

set -uo pipefail
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
unset -f grep sed awk find cat cp rm mkdir basename dirname date diff 2>/dev/null || true

AQUI="$(cd "$(dirname "$0")" && pwd)"
MARCADOR=".alambique-origen"   # dentro de cada skill copiada: quién la puso y de dónde
ESTADO="$(mktemp)"             # contadores del bucle: en tubería viven en subshell
trap 'rm -f "$ESTADO"' EXIT
# shellcheck source=marco/mecanismos/lib/harness.sh
. "$AQUI/marco/mecanismos/lib/harness.sh"

SOLO_SKILLS=0; PROY=""
for a in "$@"; do
    case "$a" in
        --solo-skills) SOLO_SKILLS=1 ;;
        -h|--help) grep '^#' "$0" | sed -n '4,26p' | cut -c3-; exit 0 ;;
        -*) echo "opción desconocida: $a" >&2; exit 1 ;;
        *)  [ -z "$PROY" ] || { echo "solo se admite un proyecto por ejecución" >&2; exit 1; }
            PROY="$a" ;;
    esac
done

# Antes de tocar nada: una combinación sin sentido no se ignora en silencio, y
# un proyecto que no existe no se descubre después de repartir las skills.
if [ "$SOLO_SKILLS" -eq 1 ] && [ -n "$PROY" ]; then
    echo "--solo-skills no da de alta proyectos: sobra '$PROY'" >&2; exit 1
fi
if [ -n "$PROY" ] && [ ! -d "$PROY" ]; then
    echo "no existe el directorio: $PROY" >&2; exit 1
fi

say() { printf '%s\n' "$*"; }
ok()  { printf '  ok   %s\n' "$*"; }
avi() { printf '  AVISO %s\n' "$*"; }
FALLOS=0; PUESTAS=0; RESPETADAS=0

say ""
say "alambique — instalación de skills"
say "================================="

# Si el puesto declara $ALAMBIQUE_CONF y aún no existe, se crea: es una orden, no una pista.
if [ -n "${ALAMBIQUE_CONF:-}" ] && [ ! -d "$ALAMBIQUE_CONF" ]; then
    mkdir -p "$ALAMBIQUE_CONF" 2>/dev/null && ok "creado \$ALAMBIQUE_CONF: $ALAMBIQUE_CONF" \
        || avi "no pude crear \$ALAMBIQUE_CONF ($ALAMBIQUE_CONF)"
fi
PRESENTES="$(harness_presentes)"
if [ -z "$PRESENTES" ]; then
    say ""
    avi "no detecto ningún harness en $HOME, y \$ALAMBIQUE_CONF no apunta a un directorio. Nada que hacer."
    avi "  Sin harness, el destino lo declaras tú:  export ALAMBIQUE_CONF=~/.alambique  y repite."
    avi "  O a mano: cp -r marco/skills/* <conf>/skills/"
    exit 1
fi

printf '%s\n' "$PRESENTES" | while IFS='|' read -r nombre dir; do
    rel="$(harness_campo "$nombre" 4)"
    say ""
    if [ -z "$rel" ] || [ "$rel" = "-" ]; then
        say "$nombre ($dir): no lee skills — se omite"
        continue
    fi
    destino="$dir/$rel"
    say "$nombre → $destino"
    mkdir -p "$destino" 2>/dev/null || { avi "no puedo crear $destino"; echo FALLO >> "$ESTADO"; continue; }
    for s in "$AQUI"/marco/skills/*/; do
        n="$(basename "$s")"
        [ -r "$s/SKILL.md" ] || continue
        if [ -e "$destino/$n" ] && [ ! -e "$destino/$n/$MARCADOR" ]; then
            avi "$n ya existe y no la puso este script: se respeta"
            echo RESPETADA >> "$ESTADO"
            continue
        fi
        # La que ya es la del repositorio no se toca: repetir el instalador no
        # cambia nada, tampoco la fecha del marcador.
        if [ -e "$destino/$n/$MARCADOR" ] && diff -rq -x "$MARCADOR" "$s" "$destino/$n" >/dev/null 2>&1; then
            ok "$n (ya estaba)"; echo PUESTA >> "$ESTADO"
            continue
        fi
        # Sustituir solo lo que es nuestro: el marcador lo garantiza.
        [ -e "$destino/$n/$MARCADOR" ] && rm -rf "${destino:?}/$n"
        if cp -R "$s" "$destino/$n" 2>/dev/null; then
            printf 'origen: %s\nfecha: %s\n' "$AQUI" "$(date '+%Y-%m-%d %H:%M:%S')" > "$destino/$n/$MARCADOR"
            ok "$n"; echo PUESTA >> "$ESTADO"
        else
            avi "no pude copiar $n a $destino"; echo FALLO >> "$ESTADO"
        fi
    done
done
# El bucle corre en subshell (tubería): los contadores vuelven por fichero.
# `grep -c` sale 1 sin coincidencias; `wc -l` siempre imprime un número.
PUESTAS="$(grep PUESTA "$ESTADO" | wc -l | tr -d ' ')"
RESPETADAS="$(grep RESPETADA "$ESTADO" | wc -l | tr -d ' ')"
FALLOS="$(grep FALLO "$ESTADO" | wc -l | tr -d ' ')"

say ""
say "skills: $PUESTAS puestas · $RESPETADAS respetadas · $FALLOS fallos"
# Se nombran las de ESTE repositorio: el marcador solo no las distingue, otra
# skill puede llevarlo de otro repositorio.
NOMBRES=""
for s in "$AQUI"/marco/skills/*/; do
    [ -r "$s/SKILL.md" ] && NOMBRES="$NOMBRES <conf>/skills/$(basename "$s")"
done
say "Para retirarlas: borrar${NOMBRES:- (ninguna)} — y solo si el directorio contiene $MARCADOR"
say "Para retirar el marco: marco/desinstalar.sh --ver  (y --aplicar)"

if [ "$SOLO_SKILLS" -eq 1 ]; then
    [ "$FALLOS" -gt 0 ] && exit 1
    exit 0
fi

# --- El marco, en el harness principal ---------------------------------------
say ""
"$AQUI/marco/instalar.sh" ${PROY:+"$PROY"}; r=$?
[ "$FALLOS" -gt 0 ] && exit 1
exit $r
