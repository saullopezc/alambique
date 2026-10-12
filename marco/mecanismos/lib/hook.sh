# SPDX-License-Identifier: MIT
#
# lib/hook.sh — El contrato de hook del harness, en UN solo fichero.
#
# Los guards (`guard-*.sh`) hacen `source` de este fichero y no hablan con el
# harness por sí mismos. La DETECCIÓN vive en cada guard y vale para cualquier
# harness; la CARGA de entrada y la RESPUESTA de salida viven aquí.
#
# CONTRATO IMPLEMENTADO: Claude Code.
#   entrada  JSON por la entrada estándar. La orden llega en
#            `tool_input.command`; el fichero escrito, en
#            `tool_response.filePath` o `tool_input.file_path`
#   salida   `hookSpecificOutput.permissionDecision` (ask | deny) antes de
#            ejecutar; `hookSpecificOutput.additionalContext` después de
#            escribir; texto por la salida estándar al abrir la sesión;
#            `systemMessage` para avisar a la persona
# Otro harness es otra versión de ESTE fichero con las mismas funciones; los
# guards no cambian. Hasta que exista, el instalador declara el hueco.
#
# Funciones:
#   hook_leer             lee la carga; sale 0 en silencio si no llega nada
#   hook_orden            la orden de shell que se va a ejecutar
#   hook_orden_ilegible   cierto si llegó una orden y no se pudo leer
#   hook_fichero          el fichero que se acaba de escribir
#   hook_preguntar <m>    pide confirmación a la persona, y termina
#   hook_denegar <m>      deniega, y termina
#   hook_contexto <m>     devuelve un aviso al modelo, y termina
#   hook_sesion <m>       mete un texto en el contexto al abrir la sesión; NO termina
#   hook_avisar <m>       avisa a la persona; NO termina. El aviso sale DENTRO
#                         de la respuesta si después hay una, y solo si no
#   hook_conf             directorio de configuración del harness
#
# UNA RESPUESTA, UN OBJETO: el harness lee la salida como un único objeto JSON.
# Dos objetos seguidos no son JSON, y entonces se pierden el aviso y la
# decisión. Por eso el aviso se guarda y sale con la respuesta o al terminar.
#
# NO FALLA EN CERRADO: un control de intercepción que bloquea ante su propio
# error deja la herramienta inservible. Pero TAMPOCO FALLA EN SILENCIO: el
# silencio con salida 0 es el modo de fallo caro, porque un control inerte bajo
# semáforo verde es peor que no tenerlo — el ausente se ve.
#
# Author       : Saul López
# Created Date : 2026-10-09

# Se sanea el PATH y se retiran las funciones que puedan ensombrecer las
# herramientas: una función de shell llamada `grep` convierte la detección en
# silencio con salida 0. Es exactamente como se apaga un guard sin tocarlo.
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
unset -f grep sed awk find head cut sort tr wc date cat cp mv rm mkdir basename dirname 2>/dev/null || true

HOOK_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
HOOK_ENTRADA=""

# --- Directorio de configuración del harness ---------------------------------
# No se copia aquí la lista de harness: tiene un solo dueño (`harness.sh`).
#   1. $ALAMBIQUE_CONF, si está declarado
#   2. instalado, este fichero vive en <conf>/hooks/lib/: <conf> son dos niveles
#   3. en el repositorio, la tabla está al lado y resuelve ella
hook_conf() {
    [ -n "${ALAMBIQUE_CONF:-}" ] && { printf '%s' "$ALAMBIQUE_CONF"; return 0; }
    case "$HOOK_LIB" in
        */hooks/lib) ( cd "$HOOK_LIB/../.." 2>/dev/null && pwd | tr -d '\n' ); return 0 ;;
    esac
    if [ -r "$HOOK_LIB/harness.sh" ]; then
        # shellcheck source=harness.sh
        . "$HOOK_LIB/harness.sh"
        conf_puesto; return 0
    fi
    printf '%s' "$HOME/.alambique"
}

# --- Leer un valor de la carga sin jq ----------------------------------------
# `jq` no está garantizado en ningún puesto. Un extractor ingenuo tampoco vale:
# una orden lleva comillas y barras invertidas, y cortarla en la primera comilla
# falla igual que no tener guard. Este respeta los escapes y ACOTA la clave a su
# objeto padre — sin acotar, una clave igual anterior en la carga gana y el
# guard calla ante el valor real.
hook_valor_json() { # <padre> <clave>
    LC_ALL=C awk -v padre="$1" -v clave="$2" '
      BEGIN { RS="\0" }
      {
        desde = 1
        if (padre != "") {
            if (match($0, "\"" padre "\"[[:space:]]*:") == 0) exit 0
            desde = RSTART + RLENGTH
        }
        resto = substr($0, desde)
        if (match(resto, "\"" clave "\"[[:space:]]*:[[:space:]]*\"") == 0) exit 0
        i = RSTART + RLENGTH; out = ""
        while (i <= length(resto)) {
            c = substr(resto, i, 1)
            if (c == "\\") {
                n = substr(resto, i+1, 1)
                if      (n == "n") out = out "\n"
                else if (n == "t") out = out "\t"
                else if (n == "r") out = out "\r"
                else if (n == "u") { out = out "?"; i += 4 }
                else               out = out n
                i += 2; continue
            }
            if (c == "\"") break
            out = out c; i++
        }
        printf "%s", out
      }'
}

# --- Entrada -----------------------------------------------------------------
hook_leer() {
    HOOK_ENTRADA="$(cat 2>/dev/null)" || exit 0
    [ -n "$HOOK_ENTRADA" ] || exit 0
}
hook_orden() { printf '%s' "$HOOK_ENTRADA" | hook_valor_json tool_input command; }
hook_orden_ilegible() {
    case "$HOOK_ENTRADA" in *'"command"'*) return 0 ;; esac
    return 1
}
hook_fichero() {
    _f="$(printf '%s' "$HOOK_ENTRADA" | hook_valor_json tool_response filePath)"
    [ -n "$_f" ] || _f="$(printf '%s' "$HOOK_ENTRADA" | hook_valor_json tool_input file_path)"
    printf '%s' "$_f"
}

# --- Salida ------------------------------------------------------------------
hook_escapar() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'; }
# El aviso pendiente viaja como `systemMessage` del mismo objeto que la
# respuesta. Si el guard termina sin responder, lo emite la salida del proceso:
# así ningún guard tiene que acordarse de vaciarlo.
HOOK_AVISO=""
hook_avisar() { HOOK_AVISO="${HOOK_AVISO:+$HOOK_AVISO }$1"; }
_hook_emitir() { # <miembros del objeto, sin las llaves>
    if [ -n "$HOOK_AVISO" ]; then
        printf '{%s,"systemMessage":"%s"}\n' "$1" "$(hook_escapar "$HOOK_AVISO")"
    else
        printf '{%s}\n' "$1"
    fi
    HOOK_AVISO=""
}
_hook_al_salir() {
    [ -n "$HOOK_AVISO" ] && printf '{"systemMessage":"%s"}\n' "$(hook_escapar "$HOOK_AVISO")"
    return 0
}
trap _hook_al_salir EXIT
_hook_decidir() { # <decision> <motivo>
    _hook_emitir "$(printf '"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}' \
        "$1" "$(hook_escapar "$2")")"
    exit 0
}
hook_preguntar() { _hook_decidir ask  "$1"; }
hook_denegar()   { _hook_decidir deny "$1"; }
hook_contexto() {
    _hook_emitir "$(printf '"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}' "$(hook_escapar "$1")")"
    exit 0
}
# En SessionStart lo que un hook escribe por la salida estándar entra tal cual
# en el contexto de la sesión (medido). No lleva envoltorio JSON.
hook_sesion() { printf '%s\n' "$1"; }
