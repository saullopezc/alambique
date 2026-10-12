#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# instalar.sh — Alta de puesto y de proyecto, en un solo comando.
#
# Uso:
#   ./instalar.sh                 solo el puesto (una vez por máquina)
#   ./instalar.sh /ruta/proyecto  el puesto si falta, y el proyecto
#   ./instalar.sh --help          esta ayuda; no instala nada
#
# Idempotente: se puede ejecutar las veces que haga falta.
#
# QUÉ ESCRIBE EN EL PUESTO, y nada más:
#   - un bloque marcado en el ignore global de git (solo `_local/` y
#     `__restriccion/`): en el fichero que diga `core.excludesfile` y, si no
#     dice ninguno, en el que git lee por defecto ($XDG_CONFIG_HOME/git/ignore
#     o ~/.config/git/ignore). `core.excludesfile` no se escribe nunca. Que
#     git ignora de verdad la capa local se comprueba después, con git
#   - un bloque marcado en el fichero de contexto global del harness: las
#     siete reglas de criterio y, donde no hay adaptador, el texto de las
#     cuatro que en ese puesto tampoco vigila una máquina
#   - con adaptador: reglas de lectura y cuatro hooks en la configuración del
#     harness; los cuatro, con su `lib/hook.sh`, copiados a <conf>/hooks/
#     Lo que el marco copió —hooks y skill— se sustituye por la versión del
#     repositorio, sin copia previa; no se edita en su copia instalada. Un
#     fichero con ese nombre y sin la cabecera del marco es de la persona: no
#     se toca
#   - <conf>/.alambique-alta, y la anotación propia del adaptador: QUÉ añadió
#     y qué ficheros creó esta alta. La baja retira eso y nada más
#   - el directorio <conf>/_local/ ($ALAMBIQUE_LOCAL lo cambia): el sitio de los
#     datos del puesto. De ellos solo escribe `negocio.conf`, con el nombre, el
#     correo y la organización que PREGUNTA al instalar: en una terminal, y si
#     el fichero no existe ya. Los demás los copia la persona
#   - con proyecto, si firma con otra identidad: `<proyecto>/_local/negocio.conf`
#     (la misma pregunta, opcional; gana la más cercana al fichero escrito)
#   - con proyecto: su `.gitignore`, el esqueleto de la capa local y el
#     pre-commit, que LLAMA a este repositorio por su ruta: si el clon se mueve
#     o se borra, hay que repetir el alta del proyecto. Un pre-commit de la
#     persona no se pisa: se da por encadenada solo si la puerta es su
#     PRIMERA orden; si no, se dice qué línea añadirle y dónde. No se adivina
#     el flujo del hook: detrás de otra orden la puerta puede no alcanzarse.
#     El consejo es para un hook de shell: a uno escrito en otro lenguaje hay
#     que llamar a la puerta desde ese lenguaje. El proyecto es la RAÍZ de un
#     repositorio git, de un worktree o de un submódulo
# Antes del primer cambio de un fichero DE LA PERSONA que ya existía —el
# ignore global, el contexto, la configuración del harness, el `.gitignore`—
# deja copia `.previo.<sello>` a su lado; la del `.gitignore` de un proyecto,
# en su `_local/respaldos/`. Escribe a través de un enlace simbólico, sobre su
# destino, y conserva el modo del fichero.
#
# AL TERMINAR DICE QUÉ QUEDÓ ACTIVO Y QUÉ NO. Un instalador que promete más de
# lo que instala es peor que no tener instalador: deja a alguien creyendo que
# está protegido. Si una pieza no se pudo poner, sale en el resumen como
# NO ACTIVO —o PARCIAL, si de los hooks solo entraron algunos— y el script
# termina con salida 1.
#
# NO SE ASUME NINGÚN HARNESS. El directorio de configuración se resuelve por
# $ALAMBIQUE_CONF o detectando el primero que exista (tabla en
# mecanismos/lib/harness.sh). Lo que depende del harness —reglas de lectura y
# guard— lo pone un adaptador, y SOLO HAY UNO (Claude Code). En cualquier otro
# harness esas piezas salen como NO SOPORTADO y el script termina con salida
# 3: es un hueco declarado, no un fallo, y no se disimula escribiendo un
# fichero que nadie lee para dar la regla por activa. Sin ningún harness
# tampoco se escribe un fichero de contexto: no habría quien lo leyera.
#
# Salidas: 0 todo puesto · 1 alguna pieza falló · 3 hueco declarado (harness
# sin adaptador), sin fallos.
#
# Author        : Saul López
# Created Date  : 2026-08-31

set -uo pipefail
# El PATH se sanea y se retiran funciones que puedan ensombrecer las
# herramientas: una función de shell llamada `grep` convierte una comprobación
# fallida en silencio con salida 0.
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
unset -f grep sed awk find head tail cut sort tr wc date cat cp mv rm mkdir chmod basename dirname 2>/dev/null || true

AQUI="$(cd "$(dirname "$0")" && pwd)"
# Las opciones se resuelven ANTES de tocar nada: una opción mal escrita no
# puede acabar instalando el puesto y fallando después.
PROY=""
for a in "$@"; do
    case "$a" in
        -h|--help) grep '^#' "$0" | sed -n '3,64p' | cut -c3-; exit 0 ;;
        -*) echo "opción desconocida: $a  (ver --help)" >&2; exit 1 ;;
        *)  [ -z "$PROY" ] || { echo "solo se admite un proyecto por ejecución" >&2; exit 1; }
            PROY="$a" ;;
    esac
done
if [ -n "$PROY" ] && [ ! -d "$PROY" ]; then
    echo "no existe el directorio: $PROY" >&2; exit 1
fi
MARCA_INI="# >>> alambique"
SELLO="$(date +%Y%m%d_%H%M%S)"
MARCA_FIN="# <<< alambique"

# shellcheck source=mecanismos/lib/harness.sh
. "$AQUI/mecanismos/lib/harness.sh"

# Estado de cada pieza, para el resumen final.
ST_IGNORE_GLOBAL="NO ACTIVO"
ST_CONTEXTO="NO ACTIVO"
ST_DENY="NO ACTIVO"
ST_GUARD="NO ACTIVO"
ST_IGNORE_PROY="no aplica"
ST_LOCAL="no aplica"
ST_PUERTA="no aplica"
FALLOS=0
HUECOS=0

say() { printf '%s\n' "$*"; }
ok()  { printf '  ok   %s\n' "$*"; }
avi() { printf '  AVISO %s\n' "$*"; }

CONF="$(conf_puesto)"
# Absoluto: la ruta de cada hook se registra tal cual, y una relativa solo
# valdría desde el directorio en que se instaló.
case "$CONF" in /*) ;; *) CONF="$PWD/$CONF" ;; esac
HARNESS="$(harness_de_conf "$CONF")"
# Un <conf> que no es de ningún harness conocido usa la fila neutral de la tabla.
[ -n "$HARNESS" ] || HARNESS="alambique"
ADAPTADOR="$(harness_campo "$HARNESS" 5)"
CONTEXTO_REL="$(harness_campo "$HARNESS" 3)"
IMPORTA="$(harness_campo "$HARNESS" 6)"
CON_ADAPTADOR=0
[ -n "$ADAPTADOR" ] && [ "$ADAPTADOR" != "-" ] && CON_ADAPTADOR=1
# Importar con `@` una ruta con espacios NO está verificado en ningún harness:
# ante la duda el bloque va copiado, que es la forma que no depende de eso.
case "$AQUI" in *[[:space:]]*) IMPORTA="-" ;; esac

# --- Lo que esta alta añade, anotado -------------------------------------------
# La baja retira lo que aquí conste y nada más: un fichero que ya existía no
# se borra aunque quede vacío, y uno que creó el alta no se queda con 0 bytes.
# Una línea por hecho, `clave;ruta`:
#   creado;<fichero>      no existía y lo creó el alta
#   sin-salto;<fichero>   existía y no acababa en salto de línea
ANOTACION="$CONF/.alambique-alta"
anotar() { # <línea>
    mkdir -p "$CONF" 2>/dev/null
    grep -qxF -e "$1" "$ANOTACION" 2>/dev/null || printf '%s\n' "$1" >> "$ANOTACION"
}

# --- Bloques que se insertan en ficheros del usuario --------------------------
# Cada bloque vive en `plantillas/` y NO se copia aquí: si el instalador
# llevara su propia versión, al corregir una de las dos la otra quedaría
# atrás — que es exactamente como envejece una norma. Lo mismo los README de
# las dos capas locales del proyecto (más abajo): se copian de `plantillas/`.
bloque_ignore()        { cat "$AQUI/plantillas/gitignore"; }
bloque_ignore_global() { cat "$AQUI/plantillas/gitignore-global"; }
PLANTILLA_CONTEXTO="$AQUI/plantillas/contexto-global.bloque.md"
# Donde no hay adaptador nadie hace cumplir R-04, R-06, R-07 ni el guard de
# R-03: su texto tiene que llegar al agente, y va en este añadido. Con
# adaptador no va: gastar contexto en lo que vigila una máquina no lo hace más
# cierto.
PLANTILLA_SIN_ADAPTADOR="$AQUI/plantillas/contexto-global.sin-adaptador.md"
bloque_contexto() {
    [ -r "$PLANTILLA_CONTEXTO" ] || return 1
    [ "$CON_ADAPTADOR" -eq 1 ] || [ -r "$PLANTILLA_SIN_ADAPTADOR" ] || return 1
    if [ "$IMPORTA" = "@" ]; then
        # El harness importa ficheros con `@ruta`: una línea por fichero, y la
        # norma tiene un solo dueño. Las marcas permiten retirarlas igual que
        # al bloque.
        printf '%s\n@%s\n' "$MARCA_INI" "$PLANTILLA_CONTEXTO"
        [ "$CON_ADAPTADOR" -eq 1 ] || printf '@%s\n' "$PLANTILLA_SIN_ADAPTADOR"
        printf '%s\n' "$MARCA_FIN"
    else
        # Sin importación, el bloque va copiado; sus rutas relativas (a la
        # plantilla) se vuelven absolutas para que sigan resolviendo. El
        # añadido entra antes de la marca de cierre: lo que la baja retira es
        # lo que hay entre las marcas.
        _aqui="$(printf '%s' "$AQUI" | sed 's/[\\&|]/\\&/g')"
        if [ "$CON_ADAPTADOR" -eq 1 ]; then
            cat "$PLANTILLA_CONTEXTO"
        else
            awk -v f="$MARCA_FIN" -v n="$PLANTILLA_SIN_ADAPTADOR" '
                index($0,f)==1 { print ""; while ((getline l < n) > 0) print l; close(n) }
                { print }' "$PLANTILLA_CONTEXTO"
        fi | sed -e "s|](\.\./|](${_aqui}/|g" -e "s|\`\.\./|\`${_aqui}/|g" \
            -e "s|\`\./tarea\.md\`|\`${_aqui}/plantillas/tarea.md\`|" \
            -e "s|Plantillas: \`\./\`|Plantillas: \`${_aqui}/plantillas/\`|"
    fi
}

# Inserta un bloque en un fichero si no está ya. Idempotente por marca.
# Devuelve 0 puesto · 2 ya estaba · 3 actualizado (había otro bloque del marco) ·
# 1 no se pudo escribir · 4 las marcas del fichero están desparejadas: no se toca.
# Si hizo copia previa, su ruta queda en $COPIA.
# Escribe siempre SOBRE el fichero, sin sustituirlo por otro: un enlace
# simbólico sigue siendo un enlace y el modo no cambia.
poner_bloque() { # <destino> <función-que-emite-el-bloque> [directorio de la copia previa]
    destino="$1"; emisor="$2"; COPIA=""
    "$emisor" >/dev/null 2>&1 || return 1   # sin plantilla no se escribe nada
    _copia="$(copia_libre "${3:-$(dirname "$destino")}/$(basename "$destino").previo.$SELLO")"
    case "$(estado_bloque "$destino" "$MARCA_INI" "$MARCA_FIN")" in
    roto) return 4 ;;
    uno)
        # Ya hay bloque: si es el mismo, nada; si cambió, se sustituye SOLO el
        # bloque (lo de fuera de las marcas es del usuario) con copia previa.
        actual="$(awk -v i="$MARCA_INI" -v f="$MARCA_FIN" '
            index($0,i)==1 {d=1} d {print} index($0,f)==1 {d=0}' "$destino")"
        [ "$actual" = "$("$emisor")" ] && return 2
        cp "$destino" "$_copia" 2>/dev/null || return 1
        COPIA="$_copia"
        nuevo="$(mktemp)"; "$emisor" > "$nuevo"
        # El bloque nuevo ocupa el sitio del viejo; lo de antes y lo de después no se mueve.
        awk -v i="$MARCA_INI" -v f="$MARCA_FIN" -v n="$nuevo" '
            index($0,i)==1 {d=1; while ((getline l < n) > 0) print l; close(n)}
            !d {print}
            index($0,f)==1 {d=0}' "$_copia" > "$destino"; r=$?
        rm -f "$nuevo"; [ $r -eq 0 ] || return 1
        return 3 ;;
    esac
    if [ ! -e "$destino" ]; then
        mkdir -p "$(dirname "$destino")" 2>/dev/null
        : 2>/dev/null > "$destino" || return 1
        anotar "creado;$destino"
    elif [ -s "$destino" ]; then
        cp "$destino" "$_copia" 2>/dev/null || return 1
        COPIA="$_copia"
        # El bloque empieza en su propia línea aunque el fichero no acabe en
        # salto; se anota para que la baja lo deje como estaba.
        if [ -n "$(tail -c 1 "$destino")" ]; then
            printf '\n' >> "$destino" || return 1
            anotar "sin-salto;$destino"
        fi
    fi
    # Una línea en blanco separa el bloque de lo que ya había; en un fichero
    # vacío no hay de qué separarlo.
    { if [ -s "$destino" ]; then printf '\n'; fi; "$emisor"; } >> "$destino" || return 1
    return 0
}

# Una pieza que el marco copió se reconoce por su CABECERA, en posición fija:
# hasta la línea del título es la del repositorio, y del título cuenta el
# principio, `# <nombre> — `. Que un fichero nombre al marco no dice de quién
# es: también lo nombra el comentario de un hook propio. La misma función está
# en desinstalar.sh: alta y baja tienen que reconocer lo mismo.
es_del_marco() { # <origen en el repositorio> <fichero instalado>
    awk -v t="# ${1#"$AQUI/mecanismos/"} — " '
        FNR == NR { if (!n) { c[FNR] = $0; if (index($0, t) == 1) n = FNR }; next }
        FNR < n && $0 != c[FNR] { mal = 1 }
        FNR == n { visto = (index($0, t) == 1) }
        END { exit !(n && visto && !mal) }' "$1" "$2" 2>/dev/null
}

# Copia una pieza del marco a la configuración del puesto SIN PISAR LO AJENO:
# si el destino existe y no es una copia del marco, es de la persona y se
# respeta. Si lo es, se sustituye entera, sin copia previa: lo instalado no se
# edita en su sitio, se cambia en el repo.
# Devuelve 0 copiado · 1 no se pudo · 2 hay uno ajeno con ese nombre.
copiar_propio() { # <origen> <destino>
    if [ -e "$2" ] && ! es_del_marco "$1" "$2"; then return 2; fi
    mkdir -p "$(dirname "$2")" 2>/dev/null
    cp "$1" "$2" 2>/dev/null || return 1
    return 0
}

# =============================================================================
say ""
say "alambique — marco: instalación"
say "============================="
say ""
say "harness: $HARNESS   configuración: $CONF"

# --- 1. PUESTO: ignore global ------------------------------------------------
# El bloque va al fichero que git YA consulta (lo resuelve harness.sh): así no
# hay ajuste de git que escribir, ni que devolver en la baja.
say ""
say "Puesto"
GIT_IGNORE_GLOBAL="$(ignore_global_git)"

# Lo que cuenta es que git ignore la capa local, no que el bloque esté en un
# fichero: se le pregunta a git en un repositorio recién creado. El bloque
# puede estar puesto y no servir — otro ajuste manda sobre el fichero, o una
# línea posterior vuelve a incluir lo que el bloque excluye.
# Devuelve 0 lo ignora · 1 no lo ignora · 2 no se pudo preguntar.
git_ignora_capa_local() {
    _d="$(mktemp -d 2>/dev/null)" || return 2
    if git init -q "$_d" >/dev/null 2>&1; then
        git -C "$_d" check-ignore -q _local/x 2>/dev/null; _r=$?
        [ $_r -le 1 ] || _r=2
    else
        _r=2
    fi
    rm -rf "$_d"
    return $_r
}

poner_bloque "$GIT_IGNORE_GLOBAL" bloque_ignore_global; r=$?
case $r in
    0) ok "ignore global: $GIT_IGNORE_GLOBAL" ;;
    2) ok "ignore global ya estaba: $GIT_IGNORE_GLOBAL" ;;
    3) ok "ignore global ACTUALIZADO (anterior en $COPIA): $GIT_IGNORE_GLOBAL" ;;
    4) avi "las marcas del bloque están desparejadas en $GIT_IGNORE_GLOBAL: NO lo toco. Corrígelo a mano y repite"
       FALLOS=$((FALLOS+1)) ;;
    *) avi "no pude escribir el ignore global en $GIT_IGNORE_GLOBAL"
       FALLOS=$((FALLOS+1)) ;;
esac
case $r in 0|2|3)
    git_ignora_capa_local
    case $? in
        0) ST_IGNORE_GLOBAL="activo" ;;
        1) ST_IGNORE_GLOBAL="NO ACTIVO (el bloque está, git no lo aplica)"; FALLOS=$((FALLOS+1))
           avi "el bloque está en $GIT_IGNORE_GLOBAL y git NO ignora _local/ en un repositorio nuevo."
           avi "  O git consulta otro fichero (mira  git config --show-origin core.excludesfile), o una"
           avi "  línea posterior de ese fichero vuelve a incluir _local/. R-02 queda sin su regla de ignore" ;;
        *) ST_IGNORE_GLOBAL="NO ACTIVO (sin comprobar)"; FALLOS=$((FALLOS+1))
           avi "no pude comprobar con git que _local/ queda ignorado (¿git instalado?, ¿se puede crear"
           avi "  un directorio temporal?): no doy por activo lo que no he visto actuar" ;;
    esac ;;
esac

# --- 2. PUESTO: las reglas de criterio, en el contexto global -----------------
# Las reglas que dependen de criterio solo pueden actuar desde el fichero que
# el agente lee en cada sesión. Cuál es depende del harness (tabla).
CONTEXTO=""
if [ -n "$CONTEXTO_REL" ] && [ "$CONTEXTO_REL" != "-" ]; then
    CONTEXTO="$CONF/$CONTEXTO_REL"
    poner_bloque "$CONTEXTO" bloque_contexto; r=$?
    case $r in
        0) ST_CONTEXTO="activo"; ok "reglas en $CONTEXTO ($([ "$IMPORTA" = "@" ] && echo "por líneas @ al repo" || echo "bloque copiado"))" ;;
        2) ST_CONTEXTO="activo"; ok "bloque de reglas ya estaba en $CONTEXTO" ;;
        3) ST_CONTEXTO="activo"; ok "bloque de reglas ACTUALIZADO en $CONTEXTO (anterior en $COPIA)" ;;
        4) avi "las marcas del bloque están desparejadas en $CONTEXTO: NO lo toco. Corrígelo a mano y repite"
           FALLOS=$((FALLOS+1)) ;;
        *) avi "no pude escribir el bloque en $CONTEXTO"; FALLOS=$((FALLOS+1)) ;;
    esac
else
    ST_CONTEXTO="NO SOPORTADO"
    if [ "$HARNESS" = "alambique" ]; then
        avi "ningún harness conocido lee $CONF: no escribo ahí un fichero de contexto que nadie leería"
    else
        avi "$HARNESS no tiene fichero de contexto global"
    fi
    avi "  Las reglas de criterio van en el contexto de cada proyecto. Paso manual: pegar al final"
    avi "  de su AGENTS.md el bloque  $PLANTILLA_CONTEXTO"
    [ "$CON_ADAPTADOR" -eq 1 ] \
        || avi "  y, antes de su marca de cierre, el añadido  $PLANTILLA_SIN_ADAPTADOR"
    HUECOS=$((HUECOS+1))
fi

# --- 3. PUESTO: reglas de lectura (R-04) y hooks (R-06, R-07, R-11) ---------
# Ambas dependen de cómo el harness expresa permisos y hooks. Solo el
# adaptador lo sabe; sin adaptador, se declara el hueco.
#
# Los hooks del marco, con su evento y matcher: tres guards y el arranque de
# skills. ES DATO: añadir uno es una línea aquí, el fichero en mecanismos/, su
# línea en la lista de desinstalar.sh y su firma en FIRMAS del adaptador (cuatro
# sitios; los dos últimos para poder quitarlo). Evento y matcher van en la
# gramática del harness del adaptador, que es quien los da de alta.
hooks_marco() {
    cat <<H
PreToolUse;Bash;$CONF/hooks/guard-remoto.sh
PreToolUse;Bash;$CONF/hooks/guard-legacy-grep.sh
PostToolUse;Write|Edit;$CONF/hooks/guard-autoria-docs.sh
SessionStart;startup|resume;$CONF/hooks/arranque-skills.sh
H
}
if [ "$CON_ADAPTADOR" -eq 1 ] && [ ! -x "$AQUI/adaptadores/$ADAPTADOR.sh" ]; then
    # La tabla nombra un adaptador y el fichero no está: es una pieza rota del
    # marco, no un hueco declarado.
    avi "falta el adaptador de $HARNESS, o no es ejecutable: $AQUI/adaptadores/$ADAPTADOR.sh"
    avi "  NI las reglas de lectura NI los hooks se han puesto"
    FALLOS=$((FALLOS+1))
elif [ "$CON_ADAPTADOR" -eq 1 ]; then
    mkdir -p "$CONF/hooks" 2>/dev/null
    ESPECS=""; N_HOOKS=0; N_PUESTOS=0; SIN_PONER=""
    # El contrato de hook del harness: los cuatro hooks lo cargan desde lib/ y
    # sin él no actúan, así que va primero. Si no se puede poner, no se copia ni
    # se registra ninguno: un guard dado de alta sobre una `lib` ajena es un
    # control que nadie sabe qué hace.
    LIB_PUESTA=0
    copiar_propio "$AQUI/mecanismos/lib/hook.sh" "$CONF/hooks/lib/hook.sh"; r=$?
    if   [ $r -eq 0 ]; then LIB_PUESTA=1; ok "contrato de hook copiado: lib/hook.sh"
    elif [ $r -eq 2 ]; then avi "ya hay un hooks/lib/hook.sh que no es del marco: NO lo piso. Sin él NINGÚN hook del marco actúa: no los copio ni los registro"; FALLOS=$((FALLOS+1))
    else avi "no pude copiar lib/hook.sh a $CONF/hooks/lib/: sin él NINGÚN hook del marco actúa: no los copio ni los registro"; FALLOS=$((FALLOS+1)); fi
    while IFS=';' read -r ev ma ruta; do
        [ -n "$ruta" ] || continue
        nombre="$(basename "$ruta")"
        N_HOOKS=$((N_HOOKS+1))
        if [ "$LIB_PUESTA" -eq 0 ]; then SIN_PONER="$SIN_PONER $nombre"; continue; fi
        if [ ! -r "$AQUI/mecanismos/$nombre" ]; then
            avi "no encuentro mecanismos/$nombre"; FALLOS=$((FALLOS+1)); SIN_PONER="$SIN_PONER $nombre"; continue
        fi
        copiar_propio "$AQUI/mecanismos/$nombre" "$ruta"; r=$?
        if [ $r -eq 0 ]; then
            chmod +x "$ruta" 2>/dev/null; ok "hook copiado: $nombre"
        elif [ $r -eq 2 ]; then
            avi "ya hay un $nombre que no es del marco: NO lo piso ni lo registro"; FALLOS=$((FALLOS+1)); SIN_PONER="$SIN_PONER $nombre"; continue
        else
            avi "no pude copiar $nombre a $CONF/hooks/"; FALLOS=$((FALLOS+1)); SIN_PONER="$SIN_PONER $nombre"; continue
        fi
        N_PUESTOS=$((N_PUESTOS+1))
        ESPECS="${ESPECS}${ev};${ma};${ruta}
"
    done <<EOF
$(hooks_marco)
EOF
    # Cada especificación va como un argumento: el adaptador no reparte líneas.
    set -- "$CONF"
    while IFS= read -r l; do [ -n "$l" ] && set -- "$@" "$l"; done <<EOF
$ESPECS
EOF
    "$AQUI/adaptadores/$ADAPTADOR.sh" instalar "$@"; r=$?
    if [ $r -eq 0 ]; then
        ST_DENY="activo"; ok "reglas de lectura en la configuración del harness ($ADAPTADOR)"
        # El estado de los hooks es el de los que entraron, no el del adaptador:
        # uno que no se pudo copiar no está vigilando aunque el resto sí.
        if [ "$N_PUESTOS" -eq "$N_HOOKS" ]; then
            ST_GUARD="activo"; ok "hooks dados de alta ($ADAPTADOR): $N_PUESTOS"
        elif [ "$N_PUESTOS" -eq 0 ]; then
            ST_GUARD="NO ACTIVO (ninguno de $N_HOOKS)"
            avi "ningún hook dado de alta: R-06, R-07, R-11 y el guard de R-03 quedan descubiertas"
        else
            ST_GUARD="PARCIAL ($N_PUESTOS de $N_HOOKS; sin$SIN_PONER)"
            avi "hooks dados de alta ($ADAPTADOR): $N_PUESTOS de $N_HOOKS. SIN PONER:$SIN_PONER"
        fi
    elif [ $r -eq 2 ]; then
        avi "al adaptador $ADAPTADOR le falta una dependencia (la nombra arriba): NI las"
        avi "  reglas de lectura NI los hooks se han puesto. R-04, R-06, R-07 y R-11 quedan"
        avi "  descubiertas. Instálala y repite"
        FALLOS=$((FALLOS+1))
    elif [ $r -eq 3 ]; then
        avi "la configuración del harness existe y el adaptador $ADAPTADOR no la entiende"
        avi "  (dice cuál y por qué arriba): NO se ha tocado. NI las reglas de lectura NI"
        avi "  los hooks se han puesto. Corrígela y repite"
        FALLOS=$((FALLOS+1))
    else
        avi "el adaptador $ADAPTADOR falló escribiendo en $CONF: NI las reglas de lectura"
        avi "  NI los hooks se han puesto (R-04, R-06, R-07 y R-11 quedan descubiertas)"
        FALLOS=$((FALLOS+1))
    fi
else
    ST_DENY="NO SOPORTADO"; ST_GUARD="NO SOPORTADO"
    avi "$HARNESS: sin adaptador de reglas de lectura ni de hooks"
    avi "  R-04, R-06, R-07, R-11 y el guard de R-03 quedan PROCEDIMENTALES en este puesto:"
    avi "  ninguna máquina las hace cumplir"
    if [ "$ST_CONTEXTO" = "activo" ]; then
        avi "  El agente las conoce por el contexto: el bloque de $CONTEXTO lleva el texto de"
        avi "  R-03, R-04, R-06 y R-07 además de las siete de criterio (R-11 entre ellas)"
    else
        avi "  y el agente NO las recibe por el contexto global: ese bloque no está puesto (ver arriba)"
    fi
    HUECOS=$((HUECOS+1))
fi

# --- 3b. PUESTO: la identidad de quien firma, y lo que falta ------------------
# De los datos del puesto el instalador solo escribe uno, y no lo inventa: lo
# PREGUNTA. Sin `negocio.conf` el guard de autoría avisa en cada documento, y
# R-11 pide que de cada artefacto responda una persona identificada.
#   - solo en una terminal: sin ella (tubería, tarea programada, prueba con la
#     entrada cerrada) no pregunta, y dice que falta
#   - nunca pisa un `negocio.conf` que ya exista
#   - Enter en el nombre o en el correo lo omite: no se escribe nada a medias
# Lo tecleado va a una capa local (C2, no se versiona), con permisos 600, como
# datos `clave=valor` que se leen con grep y nunca con `source`.
#
# UNA IDENTIDAD O VARIAS. La del puesto es la de por defecto. Quien firma con
# más de una —varias empresas, marca blanca para un cliente— pone otra en la
# capa local de ese proyecto o de ese cliente, y el guard usa la más cercana
# al fichero que se escribe: la misma cascada que resuelve los alias. Por eso
# la pregunta se repite, opcional, al dar de alta un proyecto (sección 4).
LOCAL_PUESTO="${ALAMBIQUE_LOCAL:-$CONF/_local}"
mkdir -p "$LOCAL_PUESTO"
NEGOCIO="$LOCAL_PUESTO/negocio.conf"

# Lee una línea de la terminal y la deja sin espacios en los extremos.
preguntar() {
    local r=""
    printf '  %s: ' "$1" >&2
    IFS= read -r r || r=""
    r="${r#"${r%%[![:space:]]*}"}"; r="${r%"${r##*[![:space:]]}"}"
    printf '%s' "$r"
}

# pedir_identidad <fichero> <título>
# Devuelve 0 escrita · 1 omitida por la persona · 2 no se pudo escribir.
pedir_identidad() {
    local destino="$1" nombre correo org
    say ""
    say "$2"
    nombre="$(preguntar "Nombre y apellido")"
    [ -n "$nombre" ] || return 1
    correo="$(preguntar "Correo institucional")"
    case "$correo" in
        "") return 1 ;;
        *@*.*) ;;
        *) avi "eso no parece un correo (falta @ o dominio)"
           correo="$(preguntar "Correo institucional")"
           case "$correo" in *@*.*) ;; *) return 1 ;; esac ;;
    esac
    org="$(preguntar "Empresa u organización (Enter si no aplica)")"
    ( umask 077
      {
        printf '# negocio.conf — identidad de quien firma\n'
        printf '#\n'
        printf '# Clasificación: C2 (dato personal). No se versiona.\n'
        printf '# Responsable: %s\n' "$nombre"
        printf '#\n'
        printf '# Escrito por el instalador con lo que respondió la persona. Se edita a\n'
        printf '# mano. Se consume con grep, NUNCA con `source`. Qué significa cada clave\n'
        printf '# y cuáles más admite: negocio.conf.example.\n'
        printf '\n'
        printf 'autor_nombre=%s\n' "$nombre"
        printf 'autor_correo=%s\n' "$correo"
        if [ -n "$org" ]; then
            printf 'autor_empresa=%s\n' "$org"
            printf 'firma_doc=**Autor**: %s <%s> - %s\n' "$nombre" "$correo" "$org"
        else
            printf 'firma_doc=**Autor**: %s <%s>\n' "$nombre" "$correo"
        fi
      } > "$destino" ) || return 2
    return 0
}

if [ -e "$NEGOCIO" ]; then
    ok "identidad de quien firma: ya estaba ($NEGOCIO)"
elif [ ! -t 0 ]; then
    avi "sin terminal no pregunto la identidad de quien firma: falta $NEGOCIO"
    avi "  repite el instalador en una terminal, o copia negocio.conf.example y rellénalo"
else
    pedir_identidad "$NEGOCIO" "Identidad de quien firma en este puesto  (Enter en el nombre o en el correo para omitir)"
    case $? in
        0) ok "identidad de quien firma escrita en $NEGOCIO" ;;
        1) avi "identidad de quien firma omitida: falta $NEGOCIO" ;;
        *) avi "no pude escribir $NEGOCIO"; FALLOS=$((FALLOS+1)) ;;
    esac
fi
case "$ST_GUARD" in activo|PARCIAL*)
    faltan=""
    for f in negocio.conf rutas-cliente.conf modelos.conf marcas.txt clientes.conf conexiones.yaml; do
        [ -r "$LOCAL_PUESTO/$f" ] || faltan="$faltan $f"
    done
    if [ -n "$faltan" ]; then
        avi "en $LOCAL_PUESTO faltan:$faltan"
        avi "  sin ellos los guards avisan o vigilan menos. Qué copiar y desde dónde: README, 'Después de instalar'"
    fi ;;
esac

# --- 4. PROYECTO -------------------------------------------------------------
if [ -n "$PROY" ]; then
    PROY="$(cd "$PROY" && pwd)"
    say ""
    say "Proyecto — $PROY"

    # Esqueleto de la capa local. Se versiona la ESTRUCTURA, nunca el contenido.
    # El árbol es el que describe la skill operacion-puesto (una fuente): entrada,
    # los cinco directorios de estado, qa, context, respaldos, retirados.
    # Va antes que el `.gitignore`: su copia previa se guarda en `respaldos/`.
    SUBDIRS_LOCAL="entrada operacion/urgencias operacion/seguimiento operacion/pendientes operacion/planificacion operacion/sugerencias qa context respaldos retirados"
    ST_LOCAL="activo"
    # Cada ruta se compone y se entrecomilla aquí: los nombres de la lista no
    # llevan espacios, la ruta del proyecto puede llevarlos.
    for d in __restriccion _local $(printf '_local/%s ' $SUBDIRS_LOCAL); do
        if mkdir -p "$PROY/$d" 2>/dev/null; then
            [ -e "$PROY/$d/.gitkeep" ] || : 2>/dev/null > "$PROY/$d/.gitkeep" || ST_LOCAL="NO ACTIVO"
        else
            ST_LOCAL="NO ACTIVO"
        fi
    done
    if [ "$ST_LOCAL" = "activo" ]; then
        # El README de cada capa sale de su plantilla; uno que ya exista no se pisa.
        for par in "local.README.md:_local" "restriccion.README.md:__restriccion"; do
            [ -e "$PROY/${par#*:}/README.md" ] \
                || cp "$AQUI/plantillas/${par%%:*}" "$PROY/${par#*:}/README.md" 2>/dev/null \
                || { ST_LOCAL="NO ACTIVO"; avi "no pude copiar plantillas/${par%%:*} a ${par#*:}/"; FALLOS=$((FALLOS+1)); }
        done
        [ "$ST_LOCAL" = "activo" ] && ok "_local/ y __restriccion/ con su esqueleto"
    else
        avi "no pude crear la capa local en $PROY"; FALLOS=$((FALLOS+1))
    fi

    # La copia previa del `.gitignore` va a la capa local, donde la skill dice
    # que viven los respaldos: en la raíz del proyecto sería un fichero sin
    # seguir más.
    RESPALDOS="$PROY"
    [ -d "$PROY/_local/respaldos" ] && RESPALDOS="$PROY/_local/respaldos"
    poner_bloque "$PROY/.gitignore" bloque_ignore "$RESPALDOS"; r=$?
    case $r in
        0) ST_IGNORE_PROY="activo"; ok ".gitignore actualizado${COPIA:+ (anterior en $COPIA)}" ;;
        2) ST_IGNORE_PROY="activo"; ok ".gitignore ya lo tenía" ;;
        3) ST_IGNORE_PROY="activo"; ok ".gitignore: bloque ACTUALIZADO (anterior en $COPIA)" ;;
        4) ST_IGNORE_PROY="NO ACTIVO"; FALLOS=$((FALLOS+1))
           avi "las marcas del bloque están desparejadas en $PROY/.gitignore: NO lo toco. Corrígelo a mano y repite" ;;
        *) ST_IGNORE_PROY="NO ACTIVO"; avi "no pude escribir $PROY/.gitignore"; FALLOS=$((FALLOS+1)) ;;
    esac

    # Identidad propia del proyecto: opcional. Enter deja la del puesto.
    if [ "$ST_LOCAL" = "activo" ]; then
        if [ -e "$PROY/_local/negocio.conf" ]; then
            ok "este proyecto firma con su propia identidad: ya estaba"
        elif [ -t 0 ]; then
            pedir_identidad "$PROY/_local/negocio.conf" "Identidad para este proyecto, si firma con otra  (Enter = la del puesto)"
            case $? in
                0) ok "este proyecto firma con su propia identidad: $PROY/_local/negocio.conf" ;;
                1) ok "este proyecto firma con la identidad del puesto" ;;
                *) avi "no pude escribir $PROY/_local/negocio.conf"; FALLOS=$((FALLOS+1)) ;;
            esac
        fi
    fi

    # La puerta de commit. Que el proyecto sea un repositorio se le pregunta a
    # git: en un worktree y en un submódulo `.git` es un fichero.
    if raiz_git "$PROY"; then
        HOOKS="$(git -C "$PROY" rev-parse --git-path hooks 2>/dev/null)"
        [ -n "$HOOKS" ] || HOOKS="$PROY/.git/hooks"
        case "$HOOKS" in /*) ;; *) HOOKS="$PROY/$HOOKS" ;; esac
        mkdir -p "$HOOKS" 2>/dev/null
        # Con `core.hooksPath` git no lee `.git/hooks`: la puerta va al
        # directorio que diga ese ajuste, y ahí vale para todo repositorio
        # que lo comparta. Se pone donde git la ejecuta, y se dice.
        _hp="$(git -C "$PROY" config --get core.hooksPath 2>/dev/null)"
        [ -z "$_hp" ] || avi "git tiene core.hooksPath ($_hp): la puerta se pone en $HOOKS y actúa en TODOS los repositorios que usen ese directorio, no solo en este"
        # Un pre-commit que ya existe es del marco solo si es ENTERO el que se
        # escribe aquí abajo, salvo la ruta del clon, que cambia si el clon se
        # mueve: ese se reescribe. Cualquier otro es de la persona y no se
        # escribe: está encadenado si su primera orden —la primera línea que
        # no es comentario ni está vacía— llama a la puerta de este clon.
        if [ -e "$HOOKS/pre-commit" ] && ! awk '
                (NR == 1 && $0 != "#!/usr/bin/env sh") || (NR == 2 && $0 != "# alambique — puerta de commit") ||
                (NR == 3 && $0 !~ /^exec ".*\/mecanismos\/puerta[.]sh"$/) || NR > 3 { mal = 1 }
                END { exit (mal || NR != 3) }' "$HOOKS/pre-commit" 2>/dev/null; then
            if ! P="$AQUI/mecanismos/puerta.sh" awk '!/^[ \t]*#/ && index($0, ENVIRON["P"]) { s = 1 }
                    END { exit !s }' "$HOOKS/pre-commit" 2>/dev/null; then
                # Si llama a la puerta de otro clon —el clon se movió—, añadir
                # otra línea dejaría la vieja fallando en cada commit.
                if awk '!/^[ \t]*#/ && /\/mecanismos\/puerta[.]sh/ { s = 1 } END { exit !s }' "$HOOKS/pre-commit" 2>/dev/null; then
                    avi "ya hay un pre-commit distinto, que llama a la puerta de otro clon: NO lo piso. Sustituye en $HOOKS/pre-commit esa línea por la línea  \"$AQUI/mecanismos/puerta.sh\" || exit 1"
                else
                    avi "ya hay un pre-commit distinto: NO lo piso. Encadénalo a mano: añade como primera orden de $HOOKS/pre-commit, justo después de la línea #!, la línea  \"$AQUI/mecanismos/puerta.sh\" || exit 1"
                fi
                ST_PUERTA="NO ACTIVO"; FALLOS=$((FALLOS+1))
            elif ! P="$AQUI/mecanismos/puerta.sh" awk '/^[ \t]*(#|$)/ { next }
                    { exit !index($0, ENVIRON["P"]) }' "$HOOKS/pre-commit" 2>/dev/null; then
                # Que la línea esté no dice que se alcance: detrás de un `exec`
                # o de un `exit` no corre, y el pre-commit de muestra de git
                # termina en uno. No se adivina el flujo del hook: la puerta
                # cuenta solo si es su PRIMERA orden.
                avi "el pre-commit existente llama a la puerta, pero no como primera orden: puede no alcanzarse. Ponla la primera en $HOOKS/pre-commit, justo después de la línea #!"
                ST_PUERTA="NO ACTIVO"; FALLOS=$((FALLOS+1))
            elif [ -x "$HOOKS/pre-commit" ]; then
                ST_PUERTA="activo"; ok "puerta de commit encadenada en el pre-commit existente"
            else
                avi "el pre-commit existente llama a la puerta y no es ejecutable: git no lo ejecuta. Falta  chmod +x \"$HOOKS/pre-commit\""
                ST_PUERTA="NO ACTIVO"; FALLOS=$((FALLOS+1))
            fi
        elif cat > "$HOOKS/pre-commit" 2>/dev/null <<EOF
#!/usr/bin/env sh
# alambique — puerta de commit
exec "$AQUI/mecanismos/puerta.sh"
EOF
        then
            chmod +x "$HOOKS/pre-commit" 2>/dev/null
            ST_PUERTA="activo"; ok "puerta de commit instalada"
        else
            ST_PUERTA="NO ACTIVO"; avi "no pude escribir $HOOKS/pre-commit"; FALLOS=$((FALLOS+1))
        fi
    elif _arriba="$(git -C "$PROY" rev-parse --show-toplevel 2>/dev/null)" && [ -n "$_arriba" ]; then
        ST_PUERTA="NO ACTIVO"; FALLOS=$((FALLOS+1))
        avi "$PROY no es la raíz de un repositorio: está dentro de $_arriba."
        avi "  No instalo la puerta en un repositorio que no has nombrado. Da de alta su raíz"
    else
        ST_PUERTA="NO ACTIVO"; avi "$PROY no es un repositorio git: sin puerta de commit"
        FALLOS=$((FALLOS+1))
    fi
fi

# --- Resumen honesto ---------------------------------------------------------
say ""
say "Qué ha quedado activo  (harness: $HARNESS)"
say "---------------------"
printf '  %-34s %s\n' "R-02 ignore global (puesto)"     "$ST_IGNORE_GLOBAL"
printf '  %-34s %s\n' "criterio en el contexto global"  "$ST_CONTEXTO"
printf '  %-34s %s\n' "R-04 reglas de lectura"          "$ST_DENY"
printf '  %-34s %s\n' "R-06/R-07/R-11 hooks (+R-03)"    "$ST_GUARD"
printf '  %-34s %s\n' "R-02 ignore del proyecto"        "$ST_IGNORE_PROY"
printf '  %-34s %s\n' "R-02 capa local"                 "$ST_LOCAL"
printf '  %-34s %s\n' "R-02/R-03 puerta de commit"      "$ST_PUERTA"
say ""
say "Qué NO comprueba nadie, y depende de ti:"
say "  R-01 clasificar    R-05 entrada no confiable   R-08 aprobación"
say "  R-09 sin turno     R-10 permiso por tarea      R-12 fallo repetido -> mecanismo"
say "  y de R-11, el fondo: el hook vigila la firma, no que alguien responda"
if [ "$ST_DENY" = "NO SOPORTADO" ]; then
    say "  y en este harness, ADEMÁS: R-04 lectura  R-06/R-07/R-11 hooks (y el guard de R-03)"
    if [ "$ST_CONTEXTO" = "activo" ]; then
        say "  su texto va en el bloque de contexto: el agente las conoce, nadie las vigila"
    else
        say "  y su texto NO llega al agente desde el puesto: no hay bloque de contexto global"
    fi
fi
say ""
if [ "$FALLOS" -gt 0 ]; then
    say "TERMINADO CON $FALLOS PIEZA(S) SIN PONER. Repasa los AVISO de arriba."
    exit 1
fi
if [ "$HUECOS" -gt 0 ]; then
    say "Puesto lo que se puede poner. $HUECOS hueco(s) DECLARADO(S) en $HARNESS: los AVISO de"
    say "arriba dicen cuáles. Un adaptador son dos ficheros (adaptadores/<harness>.sh y su"
    say "versión de mecanismos/lib/hook.sh) y una línea en la tabla de mecanismos/lib/harness.sh."
    exit 3
fi
say "Todo puesto."
exit 0
