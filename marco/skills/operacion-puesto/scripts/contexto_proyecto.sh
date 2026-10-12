#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# contexto_proyecto.sh — Identifica de quién es el directorio actual y dónde
# viven sus capas locales. Complementa a resolve_alias.sh: ese resuelve alias,
# este dice QUÉ capas hay y cuáles faltan.
#
# El dueño de un directorio NO se deduce del nombre ni de la posición en el
# árbol: se DECLARA en _local/proyecto.yaml. La estructura real no es uniforme
# —un nivel puede ser un país, un cliente o un proyecto suelto— y adivinar el
# cliente por la ruta es exactamente el error que R-01 y R-03 quieren evitar.
# Si no está declarado, este script lo dice y pide preguntarlo. Nunca lo inventa.
#
# Declarado es un valor escrito por alguien. Un marcador de plantilla —
# `<PREGUNTAR>`, `<ALIAS del cliente>`, cualquier `<...>`— cuenta como sin
# declarar: una plantilla copiada sin rellenar no identifica a nadie.
#
# El nivel del cliente es la declaración que lo nombra y NO lleva `proyecto:`.
# Si al cliente solo lo nombra una declaración de proyecto, no se sabe a qué
# altura del árbol vive lo común y hay que preguntarlo: la respuesta es la
# misma desde la raíz del proyecto que desde cualquier subdirectorio suyo.
# `cliente: ninguno` declara un proyecto sin cliente —propio, abierto—: queda
# identificado y no hay nivel de cliente por el que preguntar.
#
# Uso:
#   contexto_proyecto.sh              identifica y reporta
#   contexto_proyecto.sh --crear      además crea la _local/ de la cartera si falta;
#                                     la capa de un cliente no la crea nunca: su
#                                     altura en el árbol se pregunta
#
# Salidas: 0 identificado · 1 hay que preguntar: cliente sin declarar, declarado
#          solo a la altura del proyecto, o declaraciones que nombran clientes
#          distintos · 2 fuera de la cartera o uso incorrecto
#
# Author        : Saul López
# Created Date  : 2026-09-10

set -uo pipefail
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
unset -f grep sed awk find head cut sort tr wc date cat cp mv rm mkdir 2>/dev/null || true

# Configuración del harness en el puesto. NO se asume ninguno, y la lista de
# harness NO se copia aquí: su único dueño es la tabla del marco.
#   1. ALAMBIQUE_CONF declarado explícitamente
#   2. en el repositorio, resuelve la tabla (mecanismos/lib/harness.sh del marco)
#   3. instalado, este script vive en <conf>/skills/operacion-puesto/scripts/:
#      <conf> son tres niveles hacia arriba
#   4. ~/.alambique — neutral, si se copió suelto a otro sitio
# La capa local del puesto cuelga de ahí salvo que ALAMBIQUE_LOCAL diga otra cosa.
# El paso 3 mira el harness de ESTA copia: con la skill instalada en varios, la
# copia de uno no ve la capa que vive en otro si el entorno no lo dice
# (ALAMBIQUE_LOCAL o ALAMBIQUE_CONF).
conf_local() {
    [ -n "${ALAMBIQUE_CONF:-}" ] && { printf '%s' "$ALAMBIQUE_CONF"; return 0; }
    _aqui="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
    _raiz="$(cd "$_aqui/../../.." 2>/dev/null && pwd)"
    if [ -r "$_raiz/mecanismos/lib/harness.sh" ]; then
        . "$_raiz/mecanismos/lib/harness.sh"
        conf_puesto; return 0
    fi
    case "$_aqui" in
        */skills/operacion-puesto/scripts) printf '%s' "$_raiz"; return 0 ;;
    esac
    printf '%s' "$HOME/.alambique"
}
CONF="$(conf_local)"
LOCAL_PUESTO="${ALAMBIQUE_LOCAL:-$CONF/_local}"

# Raíz de la cartera de clientes: la fija ALAMBIQUE_PROYECTOS, y ~/Proyectos es
# solo su valor por defecto. Sin barra final: las comparaciones de ruta de abajo
# la añaden ellas, y con dos barras ningún directorio queda «dentro».
RAIZ="${ALAMBIQUE_PROYECTOS:-$HOME/Proyectos}"
case "$RAIZ" in
    ?*/) RAIZ="${RAIZ%"${RAIZ##*[!/]}"}" ;;
esac
[ -n "$RAIZ" ] || RAIZ=/

uso() {
    cat >&2 <<'USO'
Uso:
  contexto_proyecto.sh              identifica y reporta
  contexto_proyecto.sh --crear      además crea la _local/ de la cartera si falta
                                    (la de un cliente no: su altura se pregunta)

Identifica de quién es el directorio actual (por _local/proyecto.yaml, de aquí
hacia arriba) y qué capas _local hay en la cascada. Si el cliente no está
declarado, lo dice y pide preguntarlo: nunca lo deduce de la ruta. Un marcador
de plantilla sin rellenar (<PREGUNTAR>, <...>) cuenta como sin declarar.

El nivel del cliente es la declaración que lo nombra sin `proyecto:`; la
respuesta es la misma desde la raíz de un proyecto que desde sus subdirectorios.
`cliente: ninguno` declara un proyecto sin cliente (propio, abierto).

Salidas: 0 identificado · 1 hay que preguntar (sin declarar, declarado solo en
         el proyecto, o declaraciones en conflicto) · 2 fuera de la cartera o
         uso incorrecto
Entorno: ALAMBIQUE_PROYECTOS fija la cartera (por defecto, ~/Proyectos) ·
         ALAMBIQUE_CONF, el dir de configuración del harness · ALAMBIQUE_LOCAL,
         su capa local.
USO
}
CREAR=0
case "${1:-}" in
    "")        ;;
    --crear)   CREAR=1 ;;
    -h|--help) uso; exit 0 ;;
    *)         echo "uso: $(basename "$0") [--crear]" >&2; exit 2 ;;
esac

# Dónde se está. Vale la ruta lógica ($PWD) mientras cuelgue de la cartera; si
# no cuelga, se mira la física: un enlace simbólico que lleva a un directorio de
# la cartera —o una cartera que es ella misma un enlace— no saca de ella. Al
# revés no cambia nada: un proyecto enlazado DESDE la cartera sigue dentro por
# su ruta lógica.
fuera() {
    echo "contexto_proyecto: $PWD está fuera de la cartera ($RAIZ)" >&2
    if [ -n "${ALAMBIQUE_PROYECTOS:-}" ]; then
        echo "  La cartera la fija ALAMBIQUE_PROYECTOS, que ahora vale: $ALAMBIQUE_PROYECTOS" >&2
    else
        echo "  La cartera la fija ALAMBIQUE_PROYECTOS, que ahora no está definida:" >&2
        echo "  vale su valor por defecto, $RAIZ" >&2
    fi
    echo "  Si este directorio es de otra cartera, su raíz se declara en esa variable," >&2
    echo "  en el entorno desde el que se lanza el harness." >&2
    exit 2
}
AQUI="$PWD"
case "$AQUI/" in
    "$RAIZ"/*) ;;
    *)  _fis="$(pwd -P 2>/dev/null)"
        _raiz_fis="$(cd "$RAIZ" 2>/dev/null && pwd -P)"
        case "${_raiz_fis:+$_fis/}" in
            "$_raiz_fis"/*) AQUI="$_fis"; RAIZ="$_raiz_fis" ;;
            *) fuera ;;
        esac ;;
esac

# Ruta para mostrar: relativa a $HOME cuando cuelga de él.
corta() { printf '%s' "${1#"$HOME"/}"; }

# --- 1. Buscar declaraciones, del directorio actual hacia arriba ---------------
# Se recogen TODAS: la más cercana identifica el proyecto, la más alta el cliente.
DECLS=""
d="$AQUI"
while [ "$d" != "/" ] && [ "$d" != "$HOME" ]; do
    [ -r "$d/_local/proyecto.yaml" ] && DECLS="$DECLS$d/_local/proyecto.yaml
"
    [ "$d" = "$RAIZ" ] && break
    d="$(dirname "$d")"
done

# Valor de una clave de PRIMER NIVEL (columna 0): con sangría delante, la clave
# pertenece a otra estructura —un servidor de la lista, por ejemplo— y no dice
# de quién es el directorio. Se recortan espacios y retorno de carro antes de
# quitar las comillas, y `#` abre comentario solo fuera de ellas y tras un
# espacio. Un valor que no se entiende sale vacío: sin declarar, que es lo que
# obliga a preguntar.
campo() {  # campo <fichero> <clave>
    CLAVE="$2" awk '
        function escalar(s,    q, i, resto) {
            sub(/^[ \t]+/, "", s)
            sub(/[ \t]+$/, "", s)
            if (s == "") return ""
            q = substr(s, 1, 1)
            if (q == "\"" || q == "\047") {
                resto = substr(s, 2)
                i = index(resto, q)
                if (i == 0) return ""
                s = substr(resto, 1, i - 1)
                resto = substr(resto, i + 1)
                if (resto !~ /^[ \t]*(#.*)?$/) return ""
                sub(/^[ \t]+/, "", s)
                sub(/[ \t]+$/, "", s)
                return s
            }
            if (q == "#") return ""
            sub(/[ \t]+#.*$/, "", s)
            return s
        }
        BEGIN { k = ENVIRON["CLAVE"] ":" }
        { sub(/\r$/, "") }
        index($0, k) == 1 && !hecho {
            v = substr($0, length(k) + 1)
            if (v != "" && v !~ /^[ \t]/) next      # `clave:x` no es `clave: x`
            print escalar(v); hecho = 1
        }
    ' "$1" 2>/dev/null
}

# Un marcador de plantilla no es una declaración.
es_marcador() { case "$1" in "<"*">") return 0 ;; esac; return 1; }
declarado()   { if es_marcador "$1"; then printf ''; else printf '%s' "$1"; fi; }

# Valor reservado de `cliente`: el proyecto no es de ningún cliente.
SIN_CLIENTE=ninguno

printf '\n  Directorio : %s\n' "$PWD"
[ "$AQUI" = "$PWD" ] || printf '               (enlace a %s)\n' "$AQUI"

CLIENTE=""; PROYECTO=""; OPERACION=""; NIVEL_CLIENTE=""; DONDE_CLIENTE=""; CONFLICTO=""
if [ -n "$DECLS" ]; then
    printf '  Declaraciones encontradas (de la más cercana a la más alta):\n'
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        c_escrito="$(campo "$f" cliente)"
        c="$(declarado "$c_escrito")"
        p_escrito="$(campo "$f" proyecto)"
        p="$(declarado "$p_escrito")"
        o="$(declarado "$(campo "$f" operacion)")"
        if [ -n "$c" ]; then
            printf '    %s  [cliente: %s]\n' "${f#"$RAIZ"/}" "$c"
        elif [ -n "$c_escrito" ]; then
            printf '    %s  [cliente: sin declarar — marcador de plantilla sin rellenar]\n' "${f#"$RAIZ"/}"
        else
            printf '    %s  [cliente: sin declarar]\n' "${f#"$RAIZ"/}"
        fi
        [ -z "$PROYECTO" ]  && PROYECTO="$p"
        [ -z "$OPERACION" ] && OPERACION="$o"
        if [ -n "$c" ]; then
            # Dos niveles que nombran clientes distintos no identifican a
            # ninguno: elegir uno por su posición en el árbol es deducirlo.
            # Se guarda el primer par que discrepa, con su fichero: sin saber
            # cuáles son no hay nada que corregir.
            if [ -n "$CLIENTE" ] && [ "$c" != "$CLIENTE" ] && [ -z "$CONFLICTO" ]; then
                CONFLICTO="$(printf '    %s  dice  %s\n    %s  dice  %s' \
                    "$DONDE_CLIENTE" "$CLIENTE" "${f#"$RAIZ"/}" "$c")"
            fi
            CLIENTE="$c"; DONDE_CLIENTE="${f#"$RAIZ"/}"
            # El nivel del cliente es la declaración que lo nombra SIN
            # `proyecto:` —así la escribe la plantilla—; la más alta, si hay
            # varias. No se compara con el directorio actual: la respuesta
            # es la misma desde la raíz de un proyecto y desde sus
            # subdirectorios. Un `proyecto:` con el marcador sin rellenar tampoco
            # vale: no se sabe qué nivel quiso declarar quien copió la plantilla.
            [ -z "$p_escrito" ] && NIVEL_CLIENTE="$(dirname "$(dirname "$f")")"
        fi
    done <<EOF
$DECLS
EOF
else
    printf '  Declaraciones encontradas : NINGUNA\n'
fi

# --- 2. Capas locales, de la más específica a la general ----------------------
printf '\n  Capas _local (orden de resolución):\n'
CAPAS=""; d="$AQUI"
while [ "$d" != "/" ] && [ "$d" != "$HOME" ]; do
    if [ -d "$d/_local" ]; then
        n="$(ls -A "$d/_local" 2>/dev/null | wc -l)"
        printf '    [x] %-46s %s objeto(s)\n' "$(corta "$d")/_local" "$n"
        CAPAS="$CAPAS$d/_local
"
    fi
    [ "$d" = "$RAIZ" ] && break
    d="$(dirname "$d")"
done
# La raíz del puesto se nombra exista o no: la que falta es la que hay que ver.
if [ -d "$LOCAL_PUESTO" ]; then
    printf '    [x] %-46s raíz del puesto\n' "$(corta "$LOCAL_PUESTO")"
    [ -n "$CAPAS" ] || printf '    (ninguna capa propia; solo la raíz del puesto)\n'
else
    printf '    [ ] %-46s raíz del puesto: NO EXISTE\n' "$(corta "$LOCAL_PUESTO")"
    printf '        Si vive en el directorio de otro harness, lo dicen ALAMBIQUE_LOCAL o ALAMBIQUE_CONF.\n'
    [ -n "$CAPAS" ] || printf '    (ninguna capa: ni propia ni del puesto)\n'
fi

# --- 3. Qué falta -------------------------------------------------------------
FALTA=0
printf '\n'
if [ -n "$CONFLICTO" ]; then
    FALTA=1
    printf '  DECLARACIONES EN CONFLICTO: dos niveles nombran clientes distintos.\n'
    printf '%s\n' "$CONFLICTO"
    printf '  No se elige uno por su posición en el árbol: hay que PREGUNTAR cuál\n'
    printf '  vale para este directorio y corregir la declaración que sobra.\n'
elif [ -z "$CLIENTE" ]; then
    FALTA=1
    printf '  FALTA DECLARAR EL CLIENTE.\n'
    printf '  No se deduce del nombre del directorio: hay que PREGUNTARLO.\n'
    printf '  Lo que hay que consultar antes de crear nada:\n'
    printf '    - ¿De qué cliente es este trabajo, y con qué ALIAS se le nombra?\n'
    printf '      (si de ninguno —propio, abierto—, se declara `cliente: %s`)\n' "$SIN_CLIENTE"
    printf '    - ¿Es una operación propia (país, filial) o cuelga de otra mayor?\n'
    printf '    - ¿A qué nivel del árbol pertenece lo común: al cliente o a esta operación?\n'
    printf '    - ¿Qué servidores toca, por qué alias, y cómo se entra?\n'
elif [ "$CLIENTE" = "$SIN_CLIENTE" ]; then
    # Declarado sin cliente: no hay nivel de cliente ni nada común que situar.
    printf '  Cliente    : %s (proyecto propio o abierto: declarado sin cliente)\n' "$SIN_CLIENTE"
    printf '  Proyecto   : %s\n' "${PROYECTO:-sin declarar}"
else
    printf '  Cliente    : %s\n' "$CLIENTE"
    printf '  Operación  : %s\n' "${OPERACION:-sin declarar}"
    printf '  Proyecto   : %s\n' "${PROYECTO:-sin declarar}"
    if [ -z "$NIVEL_CLIENTE" ]; then
        FALTA=1
        printf '  El cliente solo está declarado a la altura de un proyecto: ninguna\n'
        printf '  declaración sin `proyecto:` lo nombra (%s).\n' "$DONDE_CLIENTE"
        printf '  No se sabe a qué altura del árbol vive lo común, y ponerlo en el proyecto\n'
        printf '  sería repetirlo en cada proyecto del mismo cliente. PREGUNTAR:\n'
        printf '    - ¿Qué directorio representa al cliente %s en el árbol?\n' "$CLIENTE"
        printf '    - ¿Hay operaciones hermanas (país, filial) que compartan acceso?\n'
        printf '    - ¿Qué es común a todas y qué es propio de esta?\n'
        printf '  Con la respuesta: declarar cliente, sin `proyecto:`, en el _local/proyecto.yaml\n'
        printf '  de ESE nivel. Si el proyecto no es de ningún cliente: `cliente: %s`.\n' "$SIN_CLIENTE"
    else
        # Su _local existe por construcción: es donde está el proyecto.yaml que lo declara.
        printf '  Nivel del cliente : %s\n' "$(corta "$NIVEL_CLIENTE")"
    fi
fi

# --- 4. Creación --------------------------------------------------------------
# Solo la capa de la cartera: su sitio no depende de ninguna respuesta. La de
# un cliente sí, y crearla en el nivel equivocado repite lo que la cascada evita.
if [ "$CREAR" -eq 1 ]; then
    printf '\n'
    [ -d "$RAIZ/_local" ] || { mkdir -p "$RAIZ/_local" && printf '  creado: %s\n' "$(corta "$RAIZ")/_local"; }
    if [ -n "$CONFLICTO" ]; then
        printf '  NO se crea capa de cliente: primero hay que resolver qué cliente es.\n'
    elif [ -z "$CLIENTE" ]; then
        printf '  NO se crea capa de cliente: primero hay que preguntar quién es.\n'
        printf '  Con la respuesta, declararlo en el _local/proyecto.yaml del nivel que le toque.\n'
    elif [ "$CLIENTE" = "$SIN_CLIENTE" ]; then
        printf '  No hay capa de cliente que crear: el proyecto está declarado sin cliente.\n'
    elif [ -z "$NIVEL_CLIENTE" ]; then
        printf '  NO se crea capa de cliente: falta saber a qué nivel del árbol pertenece.\n'
        printf '  Crearla en el proyecto repetiría lo común en cada proyecto de %s.\n' "$CLIENTE"
    fi
fi

printf '\n'
exit $FALTA
