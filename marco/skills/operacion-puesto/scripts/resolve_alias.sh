#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# resolve_alias.sh — Resolver de alias de conexión (R-03: solo alias, nunca
# coordenadas)
#
# Fuente de verdad: la capa local del puesto, resuelta sin asumir harness
# Capa local: C2, no versionada, pero SÍ legible por el agente — existe
# precisamente para que la consulte (R-02: C2 vive en _local/, no en el repo).
# Consumidores: skills, hooks, scripts y agentes. Ninguno debe llevar hosts escritos.
#
# La coordenada real (IP/FQDN) NO vive aquí: vive en ~/.ssh/config, referenciada
# por el campo ssh_host. Este resolver entrega atributos operativos, no acceso.
#
# Uso:
#   resolve_alias.sh --list                    lista de alias con propósito
#   resolve_alias.sh <alias>                   ficha completa (clave=valor), cada clave una vez
#   resolve_alias.sh <alias> <campo>           un campo, apto para $( )
#   resolve_alias.sh --check <alias> <campo> <valor>   salida 0 si coincide, 1 si no
#   resolve_alias.sh --fuentes                 qué capas se están leyendo, en orden (diagnóstico: sale 0 aunque no haya)
#   resolve_alias.sh --validar                 comprueba el formato y el esquema de toda la cascada
#
# Salidas: 0 correcto · 1 alias no encontrado (en --check: el valor no coincide) ·
#          2 campo no encontrado o uso incorrecto (en --check: no existe el alias
#          o el campo, y no hay nada que comparar) · 3 sin fuente ·
#          4 esquema inválido (--validar)
#
# CASCADA DE CAPAS. Un dato vive en el nivel más alto donde sigue siendo cierto,
# y se busca de lo específico a lo general — así el bastión común de un cliente
# se escribe UNA vez y no se repite en cada proyecto:
#
#   <dir actual>/_local/conexiones.yaml   y el de cada ancestro, subiendo
#   ~/Proyectos/_local/conexiones.yaml    la cartera de clientes
#   <capa local del puesto>/conexiones.yaml   la raíz: lo transversal al puesto
#
# GANA LA PRIMERA APARICIÓN, campo a campo: lo específico pisa a lo general,
# nunca al revés. CONEXIONES_YAML sobreescribe todo con una fuente única.
# A un proyecto de la cartera al que se llega por un enlace simbólico desde
# fuera de ella se le leen las capas de su ruta real, hasta la cartera.
#
# FORMATO ADMITIDO: el de plantillas/conexiones.yaml.example y ninguno más.
# No hay parser de YAML detrás: una línea que no encaja en ese formato no se
# atribuye a ningún alias, y --validar la señala con su número de línea.
#
# Author        : Saul López
# Created Date  : 2026-08-28

set -uo pipefail
# Portabilidad del binario. NO se usan rutas fijas: `sed`, `grep` y
# `date` viven en /bin en Alpine y en otras rutas en macOS, y una ruta fija
# falla en SILENCIO con salida 0 sobre otras implementaciones de las utilidades. Se sanea el PATH y se
# retiran las funciones que pudieran ensombrecerlos: eso resuelve el motivo por
# el que se ponen rutas absolutas, sin atarse a una distribución.
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
# (ALAMBIQUE_LOCAL o ALAMBIQUE_CONF). --fuentes nombra la capa que consulta.
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

# Dentro de un script no se heredan las funciones de shell de la sesión que lo
# llama: se usa el binario del sistema, por nombre.
AWK=awk

# Raíz de la cartera de clientes. Se puede mover con ALAMBIQUE_PROYECTOS. Sin
# barra final: las comparaciones de ruta de abajo la añaden ellas.
RAIZ_PROYECTOS="${ALAMBIQUE_PROYECTOS:-$HOME/Proyectos}"
case "$RAIZ_PROYECTOS" in
    ?*/) RAIZ_PROYECTOS="${RAIZ_PROYECTOS%"${RAIZ_PROYECTOS##*[!/]}"}" ;;
esac
[ -n "$RAIZ_PROYECTOS" ] || RAIZ_PROYECTOS=/

legible() { [ -r "$1" ] && [ ! -d "$1" ]; }

# Capas a leer, de la MÁS ESPECÍFICA a la más general. Se emite una por línea;
# solo las que existen y son legibles. Con CONEXIONES_YAML declarado, esa manda
# y es la única: un override tiene que poder aislar de verdad.
fuentes() {
    if [ -n "${CONEXIONES_YAML:-}" ]; then
        legible "$CONEXIONES_YAML" && printf '%s\n' "$CONEXIONES_YAML"
        return 0
    fi
    # Desde el directorio actual hacia arriba, hasta $HOME sin incluirlo.
    # Si la ruta por la que se llegó no cuelga de la cartera y la física sí
    # —un enlace simbólico hacia un proyecto—, se sube por la física y solo
    # hasta la cartera: por la del enlace no se pasaría por las capas del
    # proyecto, del cliente ni de la operación, y nadie lo notaría.
    _d="$PWD"; _raiz="$RAIZ_PROYECTOS"; _tope="$HOME"
    case "$_d/" in
        "$_raiz"/*) ;;
        *)  _fis="$(pwd -P 2>/dev/null)"
            _raiz_fis="$(cd "$_raiz" 2>/dev/null && pwd -P)"
            case "${_raiz_fis:+$_fis/}" in
                "$_raiz_fis"/*) _d="$_fis"; _raiz="$_raiz_fis"; _tope="$(dirname "$_raiz_fis")" ;;
            esac ;;
    esac
    _aqui="$_d"
    while [ -n "$_d" ] && [ "$_d" != "/" ] && [ "$_d" != "$HOME" ] && [ "$_d" != "$_tope" ]; do
        legible "$_d/_local/conexiones.yaml" && printf '%s\n' "$_d/_local/conexiones.yaml"
        _d="$(dirname "$_d")"
    done
    # La cartera, si no quedó ya cubierta por el recorrido de arriba.
    case "$_aqui/" in
        "$_raiz"/*) : ;;
        *) legible "$RAIZ_PROYECTOS/_local/conexiones.yaml" \
             && printf '%s\n' "$RAIZ_PROYECTOS/_local/conexiones.yaml" ;;
    esac
    # La raíz: lo transversal al puesto.
    legible "$LOCAL_PUESTO/conexiones.yaml" && printf '%s\n' "$LOCAL_PUESTO/conexiones.yaml"
    return 0
}

# Dónde se ha buscado, dicho tal como se buscó: con CONEXIONES_YAML definida
# la cascada no se mira, y contar lo contrario manda a buscar donde no es.
donde_busco() {
    if [ -n "${CONEXIONES_YAML:-}" ]; then
        echo "  CONEXIONES_YAML=$CONEXIONES_YAML no es un fichero legible; con esa variable definida no se mira la cascada"
    else
        echo "  Buscado desde $PWD hacia arriba, luego $RAIZ_PROYECTOS/_local y $LOCAL_PUESTO"
        echo "  (la capa del puesto la mueven ALAMBIQUE_LOCAL o ALAMBIQUE_CONF)"
    fi
}

uso() {
    cat >&2 <<'USO'
Uso:
  resolve_alias.sh --list
  resolve_alias.sh <alias>          ficha: cada clave una vez, con el valor de la capa más específica
  resolve_alias.sh <alias> <campo>
  resolve_alias.sh --check <alias> <campo> <valor>
  resolve_alias.sh --fuentes        capas leídas, de la más específica a la general
  resolve_alias.sh --validar        formato de cada fuente, las diez claves en cada alias, y ssh_host sin coordenada

Se lee en cascada desde el directorio actual hacia arriba, luego la cartera de
clientes y por último la capa del puesto. Gana la primera aparición.
Salidas: 0 correcto · 1 alias no encontrado (--check: no coincide) · 2 campo no
         encontrado o uso incorrecto (--check: no existe el alias o el campo) ·
         3 sin fuente · 4 esquema inválido (--validar)
Entorno: CONEXIONES_YAML fuerza una fuente única · ALAMBIQUE_PROYECTOS mueve la cartera
         ALAMBIQUE_CONF fija el dir de configuración del harness · ALAMBIQUE_LOCAL, su capa local.
USO
}

# El uso incorrecto se decide antes de mirar el puesto: no depende de que haya
# nada configurado, y una opción mal escrita no es un alias que no existe.
case "${1:-}" in
    -h|--help) uso; exit 0 ;;
    --check)   [ $# -eq 4 ] || { uso; exit 2; } ;;
    ""|--list|--fuentes|--validar) ;;
    -*)        echo "resolve_alias: opción desconocida: $1" >&2; uso; exit 2 ;;
esac

FUENTES="$(fuentes | "$AWK" '!vistas[$0]++')"
# --fuentes es diagnóstico: con cascada vacía dice dónde buscó, y sale 0.
if [ "${1:-}" = "--fuentes" ] && [ -z "$FUENTES" ]; then
    echo "  (ninguna fuente legible)"
    donde_busco
    exit 0
fi
[ -n "$FUENTES" ] || {
    echo "resolve_alias: ninguna fuente legible en la cascada" >&2
    donde_busco >&2
    echo "  Formato del fichero: ../plantillas/conexiones.yaml.example (raíz de la skill)" >&2
    exit 3
}

# Lector del formato de plantillas/conexiones.yaml.example:
#   version: 1
#   conexiones:
#     - alias: <valor>
#       <campo>: <valor>
# De UNA fuente emite "D<TAB>alias<TAB>campo<TAB>valor" por cada campo de cada
# registro, y "P<TAB>fuente<TAB>línea<TAB>motivo" por cada línea que no encaja
# en ese formato. Las dos cosas en una sola lectura: la fuente puede ser una
# tubería, y una tubería no se lee dos veces.
#
# Un registro se acumula entero y se emite al cerrarse, con el alias que él
# mismo declara: así `alias` puede ir en cualquier posición y ningún campo
# cae en el registro de al lado. Lo que no encaja no se emite: un campo
# atribuido a medias es peor que un campo que falta, porque el que falta se
# nota (salida 2) y el otro se usa.
#
# Los motivos nombran el alias y las claves del esquema, nunca un valor ni una
# clave que el esquema no prevé: el informe de un control no puede ser el dato
# que denuncia, y en un fichero mal formado una clave puede ser un host.
analizar() {  # analizar <fichero>
    FUENTE="$1" "$AWK" '
        function problema(n, motivo) { print "P\t" ENVIRON["FUENTE"] "\t" n "\t" motivo }

        # Valor escalar de lo que sigue a `clave:`. Se recorta ANTES de mirar
        # las comillas: un espacio o un retorno de carro detrás de la comilla
        # de cierre la dejaría dentro del valor. Dentro de comillas `#` es
        # texto; fuera, abre comentario solo tras un espacio. Si no se entiende,
        # devuelve vacío y deja el motivo en NOVALE.
        function escalar(s,    q, i, resto) {
            NOVALE = ""
            sub(/^[ \t]+/, "", s)
            sub(/[ \t]+$/, "", s)
            if (s == "") return ""
            q = substr(s, 1, 1)
            if (q == "\"" || q == "\047") {
                resto = substr(s, 2)
                i = index(resto, q)
                if (i == 0) { NOVALE = "comilla sin cerrar"; return "" }
                s = substr(resto, 1, i - 1)
                resto = substr(resto, i + 1)
                if (resto !~ /^[ \t]*(#.*)?$/) { NOVALE = "texto tras la comilla de cierre"; return "" }
                gsub(/\t/, " ", s)
                return s
            }
            if (q == "#") return ""
            if (index("[{|>&*!%@`", q)) { NOVALE = "valor que no es un escalar de una línea"; return "" }
            sub(/[ \t]+#.*$/, "", s)
            gsub(/\t/, " ", s)
            return s
        }

        function campo(kv,    c, v, n) {
            c = kv; sub(/:.*$/, "", c)
            v = kv; sub(/^[^:]*:/, "", v)
            v = escalar(v)
            n = (c in esquema) ? c : "clave fuera del esquema"
            if (NOVALE != "") { problema(NR, n ": " NOVALE); return }
            if (v == "")      { problema(NR, n ": sin valor"); return }
            if (c in reg)     { problema(NR, n ": repetida en el registro"); return }
            reg[c] = v; orden[++nc] = c
        }

        function abrir() { split("", reg); nc = 0; abierto = 1; descartado = 0; linea_reg = NR }

        function cerrar(    a, h, i) {
            if (!abierto) return
            abierto = 0
            if (!("alias" in reg)) { problema(linea_reg, "registro sin alias"); return }
            a = reg["alias"]
            if (a ~ /[ \t]/) { problema(linea_reg, "alias con espacios: no sirve de clave de búsqueda"); return }
            h = ("ssh_host" in reg) ? reg["ssh_host"] : ""
            if (h ~ /^[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+$/ || h ~ /[.][A-Za-z][A-Za-z]+$/ || h ~ /[@:]/)
                problema(linea_reg, a ": ssh_host parece una coordenada, no una entrada Host")
            if (a in visto) {
                problema(linea_reg, a ": alias repetido en el mismo fichero (vale el de la línea " visto[a] ")")
                return
            }
            visto[a] = linea_reg
            print "D\t" a "\t" "alias" "\t" a
            for (i = 1; i <= nc; i++)
                if (orden[i] != "alias") print "D\t" a "\t" orden[i] "\t" reg[orden[i]]
            n_alias++
        }

        BEGIN {
            ind_reg = -1
            k = split("alias ssh_host cliente pais entorno so proposito criticidad modo legado_grep", t, " ")
            for (i = 1; i <= k; i++) esquema[t[i]] = 1
        }

        { sub(/\r$/, "") }
        /^[ \t]*$/ { next }
        /^[ \t]*#/ { next }
        # Marcador de inicio de documento: solo vale antes de todo contenido.
        /^---[ \t]*$/ && !contenido { next }
        {
            contenido = 1
            match($0, /^ */); ind = RLENGTH
            resto = substr($0, ind + 1)
        }
        substr(resto, 1, 1) == "\t" { problema(NR, "tabulador en la sangría"); next }

        # Registro: `- clave: valor`. La sangría del primero fija la de todos.
        seccion == "conexiones" && resto ~ /^-/ {
            # Más adentro que los registros es una lista anidada en un campo:
            # no abre registro ni cierra el que está abierto.
            if (ind_reg != -1 && ind > ind_reg) {
                if (!descartado) problema(NR, "lista anidada dentro de un registro: el formato no la admite")
                next
            }
            cerrar()
            if (resto !~ /^-[ \t]+[A-Za-z_][A-Za-z0-9_]*:([ \t]|$)/) {
                problema(NR, "elemento de lista que no es `- clave: valor`")
                descartado = 1; next
            }
            if (ind_reg == -1) ind_reg = ind
            if (ind != ind_reg) {
                problema(NR, "registro con una sangría distinta de la del primero")
                descartado = 1; next
            }
            abrir()
            match(resto, /^-[ \t]+/)
            col = ind + RLENGTH
            campo(substr(resto, RLENGTH + 1))
            next
        }

        # Primer nivel: cierra lo que hubiera abierto. Solo `version` y
        # `conexiones`; otra sección no se interpreta ni contamina al último alias.
        ind == 0 {
            cerrar(); descartado = 0; seccion = ""
            if (resto !~ /^[A-Za-z_][A-Za-z0-9_]*:([ \t]|$)/) { problema(NR, "línea no reconocida"); next }
            clave = resto; sub(/:.*$/, "", clave)
            valor = resto; sub(/^[^:]*:/, "", valor)
            valor = escalar(valor)
            if (clave == "conexiones") {
                seccion = "ajena"
                if (NOVALE != "" || valor != "") problema(NR, "conexiones: lleva un valor en su línea; se espera la lista debajo")
                else if (hay_seccion++)          problema(NR, "conexiones: sección repetida (vale la primera)")
                else                             seccion = "conexiones"
            } else if (clave == "version") {
                if (NOVALE != "") problema(NR, "version: " NOVALE)
            } else {
                problema(NR, "clave de primer nivel que el formato no admite (solo version y conexiones)")
                seccion = "ajena"
            }
            next
        }

        seccion == "ajena" { next }
        seccion == ""      { problema(NR, "línea con sangría fuera de una sección"); next }

        # Campo del registro abierto: misma columna que su primera clave. Más
        # adentro es una estructura anidada; fuera de un registro, otra forma
        # de fichero (un mapa por nombre, por ejemplo).
        {
            if (descartado) next
            if (!abierto)   { problema(NR, "línea fuera de un registro: se espera `- alias: ...`"); next }
            if (ind != col) { problema(NR, "sangría que no es la de las claves del registro (¿valor anidado?)"); next }
            if (resto !~ /^[A-Za-z_][A-Za-z0-9_]*:([ \t]|$)/) { problema(NR, "línea que no es `clave: valor`"); next }
            campo(resto)
        }

        END {
            cerrar()
            # Una fuente que existe y no aporta ningún alias no está «sin
            # problemas»: está vacía o escrita en una forma que no se lee.
            if (!hay_seccion)  problema(0, "no tiene sección `conexiones:`")
            else if (!n_alias) problema(0, "`conexiones:` no trae ningún registro `- alias: ...` válido")
        }
    ' "$1"
}

# Recorre la cascada en orden. VOLCADO queda como "alias<TAB>campo<TAB>valor";
# la deduplicación (primera aparición gana) la hacen los consumidores.
#
# Se vuelca UNA vez a memoria y de ahí leen todos los casos, sin tubería: con
# `pipefail`, un lector que sale en cuanto encuentra mata al productor con
# SIGPIPE, y pipefail propaga ESE fallo aunque el lector haya dicho que sí.
#
# La lista de fuentes entra por el descriptor 3: la entrada estándar queda
# libre para una fuente que sea /dev/stdin.
cascada() {
    while IFS= read -r _f <&3; do
        [ -n "$_f" ] && analizar "$_f"
    done 3<<< "$FUENTES"
}

LEIDO="$(cascada)"
VOLCADO="$("$AWK" '/^D\t/ { print substr($0, 3) }' <<< "$LEIDO")"

# Lo que no encaja en el formato no se ha leído, y quien resuelve tiene que
# saberlo aunque no haya pedido validar: un campo que falta por una sangría
# torcida se parece demasiado a un campo que nunca estuvo.
case "${1:---list}" in
    --validar|--fuentes) ;;
    *)  case "$LEIDO" in
            "P"$'\t'*|*$'\n'"P"$'\t'*)
                echo "resolve_alias: aviso: hay líneas o fuentes que no encajan en el formato y no se han leído; resolve_alias.sh --validar dice cuáles" >&2 ;;
        esac ;;
esac

# ¿Está el alias? Anclado al principio de línea: por subcadena, `app` casaría
# dentro de `cliente-prod-app` y saldría 0 con la ficha vacía.
existe_alias() {
    case "$VOLCADO" in
        "$1"$'\t'*|*$'\n'"$1"$'\t'*) return 0 ;;
    esac
    return 1
}

case "${1:---list}" in
    --fuentes)
        "$AWK" 'NF {printf "  %d. %s\n", ++i, $0}' <<< "$FUENTES"
        # La capa del puesto se nombra también cuando falta: es la que deja de
        # verse desde la copia de la skill de otro harness.
        if [ -z "${CONEXIONES_YAML:-}" ] && ! legible "$LOCAL_PUESTO/conexiones.yaml"; then
            echo "  (capa del puesto: $LOCAL_PUESTO/conexiones.yaml no existe; ALAMBIQUE_LOCAL o ALAMBIQUE_CONF la mueven)" >&2
        fi
        ;;

    --validar)
        # Tres comprobaciones. El formato, fuente a fuente: lo que el lector no
        # entiende es un problema, no un fichero limpio. La coordenada, registro
        # a registro: `ssh_host` nombra una entrada `Host`, y con una IP o un
        # FQDN dentro el fichero deja de ser insuficiente para conectarse. Y las
        # diez claves, sobre la cascada ya resuelta, que es lo que se consume.
        "$AWK" -F'\t' '
            BEGIN { n = split("ssh_host cliente pais entorno so proposito criticidad modo legado_grep", req, " "); tope = 12 }
            $1 == "P" && NF >= 4 {
                mal++
                if (++por[$2] > tope) next
                if ($3 > 0) printf "  %s:%s: %s\n", $2, $3, $4
                else        printf "  %s: %s\n", $2, $4
                next
            }
            $1 == "D" && NF >= 4 {
                if (!(($2 SUBSEP $3) in d)) d[$2 SUBSEP $3] = $4      # gana la PRIMERA
                if (!($2 in visto)) { visto[$2] = 1; orden[++m] = $2 }
            }
            END {
                for (f in por)
                    if (por[f] > tope) printf "  %s: y %d problema(s) más de formato\n", f, por[f] - tope
                for (i = 1; i <= m; i++) {
                    a = orden[i]
                    for (k = 1; k <= n; k++)
                        if (!((a SUBSEP req[k]) in d)) { printf "  %s: falta %s\n", a, req[k]; mal++ }
                }
                if (mal) { printf "esquema: %d problema(s); %d alias leídos\n", mal, m; exit 4 }
                printf "esquema: %d alias, sin problemas\n", m
            }' <<< "$LEIDO"
        ;;

    --list)
        printf '%-28s %-12s %-10s %s\n' ALIAS ENTORNO MODO PROPOSITO
        printf '%-28s %-12s %-10s %s\n' "----------------------------" "------------" "----------" "---------"
        "$AWK" -F'\t' '
            NF < 3 { next }                                # sin alias no hay fila
            { if (!(($1 SUBSEP $2) in d)) d[$1 SUBSEP $2] = $3     # gana la PRIMERA: lo específico
              if (!($1 in vistos)) { vistos[$1]=1; orden[++n]=$1 } }
            function o(a, c) { return ((a SUBSEP c) in d) ? d[a SUBSEP c] : "-" }
            END {
                for (i = 1; i <= n; i++) {
                    a = orden[i]
                    printf "%-28s %-12s %-10s %s\n", a, o(a, "entorno"), o(a, "modo"), o(a, "proposito")
                }
            }' <<< "$VOLCADO"
        ;;

    --check)
        # Tres respuestas distintas: coincide (0), no coincide (1) y «no hay
        # con qué comparar» (2). Fundir las dos últimas hace pasar por «no es
        # ese valor» un alias mal escrito, y quien condiciona con --check
        # seguiría adelante sin saberlo.
        existe_alias "$2" || {
            echo "resolve_alias: --check: alias no encontrado: $2" >&2
            exit 2
        }
        obtenido="$("$AWK" -F'\t' -v a="$2" -v c="$3" '$1==a && $2==c && !hecho++ {print $3}' <<< "$VOLCADO")"
        [ -n "$obtenido" ] || {
            echo "resolve_alias: --check: campo no encontrado: $3 (alias $2)" >&2
            exit 2
        }
        [ "$obtenido" = "$4" ] || exit 1
        ;;

    *)
        alias_buscado="$1"
        existe_alias "$alias_buscado" || {
            echo "resolve_alias: alias no encontrado: $alias_buscado" >&2
            echo "  Alias disponibles: resolve_alias.sh --list" >&2
            exit 1
        }

        if [ $# -ge 2 ]; then
            valor="$("$AWK" -F'\t' -v a="$alias_buscado" -v c="$2" '$1==a && $2==c && !hecho++ {print $3}' <<< "$VOLCADO")"
            [ -n "$valor" ] || { echo "resolve_alias: campo no encontrado: $2" >&2; exit 2; }
            printf '%s\n' "$valor"
        else
            # La ficha sale resuelta: cada clave una vez, con el valor de la
            # capa más específica. El mismo alias en dos capas no da dos fichas.
            "$AWK" -F'\t' -v a="$alias_buscado" '$1==a && !($2 in dada) { dada[$2] = 1; printf "%s=%s\n", $2, $3 }' <<< "$VOLCADO"
        fi
        ;;
esac
