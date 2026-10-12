#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# arranque-skills.sh — Al iniciar o reanudar una sesión, pide al agente que
# cargue las skills de arranque.
#
# POR QUÉ EXISTE: la skill del marco, `operacion-puesto`, es de arranque: dice
# dónde vive cada cosa y cómo se clasifica, y eso hace falta desde el primer
# mensaje. Pero declararla en el contexto no la carga: mientras no se invoca,
# solo actúa el resumen que haya de ella. Este hook convierte la declaración en
# una petición que llega al principio de cada sesión.
#
# QUÉ HACE: comprueba qué skills de la lista están instaladas y pide cargarlas.
# No bloquea ni falla: si una no está, lo avisa y sigue. No es un guard: no
# vigila ninguna regla; hace que las skills que ya pide el contexto se carguen.
#
# QUÉ SKILLS: la del marco y, además, toda skill instalada que traiga en su
# directorio un fichero `.arranque`. Así una skill de otro repositorio se
# declara de arranque ella misma, y el marco no tiene que nombrarla.
# `ALAMBIQUE_SKILLS_ARRANQUE`, una lista separada por espacios, sustituye a
# todo lo anterior. El directorio de skills es <conf>/skills.
#
# CONTRATO: ninguno propio. Cómo llega la petición al contexto lo dice
# `lib/hook.sh` (`hook_sesion`); este fichero solo decide qué pedir.
#
# Author       : Saul López
# Created Date : 2026-10-10

set -uo pipefail
HOOK="arranque-skills"
_lib="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/lib/hook.sh"
if [ ! -r "$_lib" ]; then
    printf '{"systemMessage":"%s: falta lib/hook.sh — el hook NO está actuando"}\n' "$HOOK"
    exit 0
fi
# shellcheck source=lib/hook.sh
. "$_lib"

SKILLS_DIR="$(hook_conf)/skills"
if [ -n "${ALAMBIQUE_SKILLS_ARRANQUE:-}" ]; then
    SKILLS="$ALAMBIQUE_SKILLS_ARRANQUE"
else
    SKILLS="operacion-puesto"
    for _m in "$SKILLS_DIR"/*/.arranque; do
        [ -e "$_m" ] || continue
        _n="$(basename "$(dirname "$_m")")"
        case " $SKILLS " in *" $_n "*) ;; *) SKILLS="$SKILLS $_n" ;; esac
    done
fi

presentes=""
ausentes=""
for skill in $SKILLS; do
    if [ -r "$SKILLS_DIR/$skill/SKILL.md" ]; then
        presentes="$presentes $skill"
    else
        ausentes="$ausentes $skill"
    fi
done

if [ -n "$presentes" ]; then
    hook_sesion "Arranque de sesión (hook $HOOK): antes de responder al primer mensaje, carga con la herramienta de skills estas skills de arranque:$presentes. Sin cargarlas solo actúa el resumen que haya de ellas en el fichero de contexto."
fi
# También por `hook_sesion`: en SessionStart toda la salida va al contexto, y
# mezclar texto con una línea JSON de aviso lo vuelve ilegible.
if [ -n "$ausentes" ]; then
    hook_sesion "Aviso (hook $HOOK): no están instaladas en $SKILLS_DIR:$ausentes."
fi
exit 0
