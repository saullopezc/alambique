#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# desinstalar.sh — Retira del puesto lo que puso instalar.sh, y solo eso.
#
# Uso:
#   ./desinstalar.sh --ver [proy]       dice qué quitaría, sin tocar nada
#   ./desinstalar.sh --aplicar [proy]   lo quita de verdad
#   ./desinstalar.sh --help             esta ayuda
#
# QUÉ QUITA: el bloque del marco en el ignore global y en el contexto global
# del harness; las reglas de lectura y los hooks que el alta AÑADIÓ (vía el
# adaptador del harness); los cuatro hooks y su `lib/hook.sh` copiados a
# <conf>/hooks/; y, del proyecto que se le indique, el bloque de su .gitignore
# y la puerta de commit: el pre-commit si es entero el del marco y, de uno de
# la persona que la encadena, solo la línea que la llama.
#
# DEJA CADA FICHERO COMO ESTABA ANTES DEL ALTA, HASTA DONDE CONSTA. Qué añadió
# el alta consta en <conf>/.alambique-alta y en la anotación del adaptador:
#   - un fichero que el alta creó y que queda vacío se retira; uno que ya
#     existía se queda, aunque quede vacío
#   - una regla o un hook que ya estaban antes del alta son de la persona y se
#     quedan, aunque sean iguales a los del marco
#   - sin anotación retira solo lo inequívoco: los bloques marcados y los
#     hooks cuya orden es exactamente un guard del marco. NO retira reglas de
#     lectura ni ficheros vacíos, y lo dice
#   - con anotación parcial —el alta encontró en el puesto una instalación del
#     marco sin anotar— pasa lo mismo con lo que ya estaba: retira lo anotado,
#     y las reglas de lectura que no constan se quedan, listadas para
#     quitarlas a mano. En esos dos casos el fichero NO vuelve a como estaba
#     antes del marco: vuelve hasta donde se sabe
#
# QUÉ NO TOCA, A PROPÓSITO:
#   - reglas, hooks y líneas del usuario o de OTRAS herramientas: se retira lo
#     que lleva la marca del marco o consta en la anotación, nunca el fichero
#     entero
#   - el repositorio del marco y las skills instaladas: son artefactos del
#     usuario. Las de este repositorio se retiran a mano: son los directorios
#     <conf>/skills/<nombre> que tienen su par en `skills/` de este marco (hoy,
#     `operacion-puesto`) y contienen `.alambique-origen`. Dice dónde están.
#     El marcador solo no basta: otra skill puede llevarlo de otro repositorio
#   - la capa local `_local/` ni `__restriccion/`: ahí vive el dato. Quedan
#     SIN IGNORAR: retirado el bloque del ignore global, nada las ignora en los
#     repositorios que no tengan su propio bloque, y la baja lo dice
#   - el ajuste `core.excludesfile` de git: el alta tampoco lo escribe
#
# Antes de escribir hace copia con sufijo .previo.<fecha>, y lo que retira lo
# renombra con ese mismo sufijo en vez de borrarlo. Nada se pierde. La copia
# del `.gitignore` de un proyecto va a su `_local/respaldos/`, si existe.
#
# SI ALGO NO SE PUDO RETIRAR, LO DICE Y SALE CON 1. Si el adaptador no puede
# quitar el registro de los hooks (la configuración no se entiende, falta una
# dependencia), los ficheros de los hooks NO se mueven: un registro que apunta
# a un fichero que ya no está es peor que no haber desinstalado.
#
# Salidas: 0 retirado (o nada que retirar) · 1 alguna pieza no se pudo retirar.
#
# Author        : Saul López
# Created Date  : 2026-08-31

set -uo pipefail
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
unset -f grep sed awk find head cut sort tr wc cat cp mv rm mkdir basename dirname date 2>/dev/null || true

AQUI="$(cd "$(dirname "$0")" && pwd)"
MARCA_INI="# >>> alambique"
MARCA_FIN="# <<< alambique"
# shellcheck source=mecanismos/lib/harness.sh
. "$AQUI/mecanismos/lib/harness.sh"

MODO="ver"; PROY=""
for a in "$@"; do
    case "$a" in
        --aplicar) MODO="aplicar" ;;
        --ver)     MODO="ver" ;;
        -h|--help) grep '^#' "$0" | sed -n '3,54p' | cut -c3-; exit 0 ;;
        -*)        echo "opción desconocida: $a  (ver --help)" >&2; exit 1 ;;
        *)         [ -z "$PROY" ] || { echo "solo se admite un proyecto por ejecución" >&2; exit 1; }
                   PROY="$a" ;;
    esac
done
if [ -n "$PROY" ] && [ ! -d "$PROY" ]; then
    echo "no existe el directorio: $PROY" >&2; exit 1
fi

CONF="$(conf_puesto)"
case "$CONF" in /*) ;; *) CONF="$PWD/$CONF" ;; esac
HARNESS="$(harness_de_conf "$CONF")"; [ -n "$HARNESS" ] || HARNESS="alambique"
ADAPTADOR="$(harness_campo "$HARNESS" 5)"
CONTEXTO_REL="$(harness_campo "$HARNESS" 3)"
SELLO="$(date +%Y%m%d_%H%M%S)"
FALLOS=0
avi() { printf '  AVISO %s\n' "$*"; }

# Lo que el alta dejó anotado (formato en instalar.sh). Una línea se borra
# cuando lo que dice ya no hace falta; el fichero, cuando no le quedan líneas.
ANOTACION="$CONF/.alambique-alta"
anotado() { grep -qxF -e "$1" "$ANOTACION" 2>/dev/null; }
desanotar() { # <línea>
    anotado "$1" || return 0
    _t="$(mktemp)"
    grep -vxF -e "$1" "$ANOTACION" > "$_t"
    cat "$_t" > "$ANOTACION"; rm -f "$_t"
}

printf '\nDesinstalación del marco  [%s]\n' "$MODO"
printf 'harness: %s   configuración: %s\n' "$HARNESS" "$CONF"

# Retira SOLO las líneas entre las marcas: vaciar el fichero entero se llevaría
# por delante las reglas del usuario. Escribe SOBRE el fichero, sin sustituirlo
# por otro: un enlace simbólico sigue siendo un enlace y el modo no cambia.
quitar_bloque() { # <fichero> <etiqueta> [directorio de la copia previa]
    f="$1"; et="$2"
    [ -e "$f" ] || { printf '  %s: (no existe)\n' "$et"; return 0; }
    case "$(estado_bloque "$f" "$MARCA_INI" "$MARCA_FIN")" in
        no)   printf '  %s: sin bloque del marco\n' "$et"; return 0 ;;
        roto) avi "$et: las marcas del bloque están desparejadas: NO se toca. Retíralo a mano"
              FALLOS=$((FALLOS+1)); return 0 ;;
    esac
    n="$(awk -v a="$MARCA_INI" -v b="$MARCA_FIN" '
        index($0,a)==1{s=1} s{c++} index($0,b)==1{s=0} END{print c+0}' "$f")"
    printf '  %s: bloque de %s líneas se retira\n' "$et" "$n"
    [ "$MODO" = "aplicar" ] || return 0
    copia="$(copia_libre "${3:-$(dirname "$f")}/$(basename "$f").previo.$SELLO")"
    tmp="$(mktemp)"
    # La línea en blanco que el instalador puso delante del bloque se va con
    # él: se retiene una línea vacía y solo se imprime si lo que sigue no es
    # la marca.
    if cp "$f" "$copia" 2>/dev/null && awk -v a="$MARCA_INI" -v b="$MARCA_FIN" '
            index($0,a)==1 { s=1; pend=0 }
            !s { if (pend) print ""; pend=0; if ($0 == "") pend=1; else print }
            index($0,b)==1 { s=0 }
            END { if (pend) print "" }' "$f" > "$tmp" && cat "$tmp" 2>/dev/null > "$f"; then
        printf '    copia previa: %s\n' "$copia"
    else
        rm -f "$tmp"
        avi "$et: no pude retirar el bloque de $f"; FALLOS=$((FALLOS+1)); return 0
    fi
    # El fichero no acababa en salto de línea y el alta puso uno para que el
    # bloque empezara en su propia línea: se va con el bloque.
    if anotado "sin-salto;$f"; then
        printf '%s' "$(cat "$f")" > "$tmp" && cat "$tmp" > "$f"
        desanotar "sin-salto;$f"
    fi
    rm -f "$tmp"
    if [ ! -s "$f" ] && anotado "creado;$f"; then
        # Si es un enlace, el enlace ya estaba y es de la persona: el alta creó
        # su destino al escribir a través de él, y eso es lo que se retira.
        if [ -L "$f" ]; then
            _dest="$(readlink -f "$f" 2>/dev/null)"
            if [ -n "$_dest" ] && rm -f "$_dest" 2>/dev/null; then
                printf '    lo creó el alta y queda vacío: se retira el destino del enlace, no el enlace\n'
            else
                avi "$et: es un enlace y no pude retirar su destino, que creó el alta y queda vacío"; FALLOS=$((FALLOS+1))
            fi
        else
            rm -f "$f"
            printf '    lo creó el alta y queda vacío: se retira\n'
        fi
    elif [ ! -s "$f" ]; then
        printf '    queda vacío y no consta que lo creara el alta: se deja\n'
    fi
    desanotar "creado;$f"
}

# --- configuración del harness: reglas de lectura y hook ---------------------
printf '\nconfiguración del harness\n'
REGISTRO_QUITADO=1
if [ -n "$ADAPTADOR" ] && [ "$ADAPTADOR" != "-" ]; then
    if [ -x "$AQUI/adaptadores/$ADAPTADOR.sh" ]; then
        "$AQUI/adaptadores/$ADAPTADOR.sh" quitar "$CONF" "$MODO" "$SELLO"; r=$?
    else
        avi "falta el adaptador de $HARNESS, o no es ejecutable: $AQUI/adaptadores/$ADAPTADOR.sh"; r=1
    fi
    case $r in
        0) ;;
        2) avi "al adaptador $ADAPTADOR le falta una dependencia (la nombra arriba): la configuración del harness no se ha tocado" ;;
        3) avi "el adaptador $ADAPTADOR no entiende la configuración del harness (dice cuál y por qué arriba): no se ha tocado" ;;
        *) avi "el adaptador $ADAPTADOR falló: la configuración del harness puede seguir con las reglas y los hooks del marco" ;;
    esac
    [ $r -eq 0 ] || { REGISTRO_QUITADO=0; FALLOS=$((FALLOS+1)); }
else
    printf '  %s: sin adaptador, nada que quitar de la configuración\n' "$HARNESS"
fi

# --- hooks copiados a <conf>/hooks/ ------------------------------------------
# Solo los que son copia del marco: uno ajeno con el mismo nombre no se toca. Y
# solo si su registro ya no está en la configuración del harness.
#
# Una pieza que el marco copió se reconoce por su CABECERA, en posición fija:
# hasta la línea del título es la del repositorio, y del título cuenta el
# principio, `# <nombre> — `. Que un fichero nombre al marco no dice de quién
# es: también lo nombra el comentario de un hook propio. La misma función está
# en instalar.sh: alta y baja tienen que reconocer lo mismo.
es_del_marco() { # <origen en el repositorio> <fichero instalado>
    awk -v t="# ${1#"$AQUI/mecanismos/"} — " '
        FNR == NR { if (!n) { c[FNR] = $0; if (index($0, t) == 1) n = FNR }; next }
        FNR < n && $0 != c[FNR] { mal = 1 }
        FNR == n { visto = (index($0, t) == 1) }
        END { exit !(n && visto && !mal) }' "$1" "$2" 2>/dev/null
}
printf '\nhooks en %s/hooks\n' "$CONF"
HAY=0
for g in guard-remoto.sh guard-legacy-grep.sh guard-autoria-docs.sh arranque-skills.sh lib/hook.sh; do
    [ -f "$CONF/hooks/$g" ] || continue
    if ! es_del_marco "$AQUI/mecanismos/$g" "$CONF/hooks/$g"; then
        printf '  hooks/%s no es del marco: no se toca\n' "$g"
    elif [ "$REGISTRO_QUITADO" -eq 0 ]; then
        HAY=1; printf '  fichero = hooks/%s  (se queda: su registro sigue en la configuración)\n' "$g"
    else
        HAY=1; printf '  fichero - hooks/%s\n' "$g"
        if [ "$MODO" = "aplicar" ]; then
            mv "$CONF/hooks/$g" "$(copia_libre "$CONF/hooks/$g.previo.$SELLO")" 2>/dev/null \
                || { avi "no pude retirar hooks/$g"; FALLOS=$((FALLOS+1)); }
        fi
    fi
done
[ "$HAY" -eq 1 ] || printf '  (ninguno del marco)\n'

# --- contexto global ---------------------------------------------------------
printf '\ncontexto global\n'
if [ -n "$CONTEXTO_REL" ] && [ "$CONTEXTO_REL" != "-" ]; then
    quitar_bloque "$CONF/$CONTEXTO_REL" "$CONTEXTO_REL"
else
    printf '  %s: sin fichero de contexto global\n' "$HARNESS"
fi

# --- ignore global -----------------------------------------------------------
# El mismo fichero que resolvió el alta (harness.sh): el que diga
# `core.excludesfile` o, si no dice ninguno, el que git lee por defecto.
IG="$(ignore_global_git)"
printf '\nignore global\n'
# Con ese bloque se va lo único que ignoraba la capa local en los repositorios
# que no se dieron de alta: se dice, se nombre o no un proyecto en la baja.
IG_BLOQUE=no; [ -e "$IG" ] && IG_BLOQUE="$(estado_bloque "$IG" "$MARCA_INI" "$MARCA_FIN")"
quitar_bloque "$IG" "$IG"
case "$IG_BLOQUE" in no|roto) ;; *)
    printf '  OJO: sin ese bloque, `_local/` y `__restriccion/` dejan de estar ignorados en todo\n'
    printf '  repositorio del puesto que no tenga su propio bloque en el `.gitignore`: un `git add`\n'
    printf '  de todo el árbol los versionaría\n' ;;
esac

# --- skills -------------------------------------------------------------------
# No se retiran; se dice dónde están las de ESTE repositorio, por nombre y por
# marcador, en cada harness presente.
printf '\nskills (no se tocan: se retiran a mano)\n'
SKILLS_PUESTAS="$(harness_presentes | while IFS='|' read -r _nombre _dir; do
    _rel="$(harness_campo "$_nombre" 4)"
    [ -n "$_rel" ] && [ "$_rel" != "-" ] || continue
    for _s in "$AQUI"/skills/*/; do
        _n="$(basename "$_s")"
        [ -e "$_dir/$_rel/$_n/.alambique-origen" ] && printf '  %s\n' "$_dir/$_rel/$_n"
    done
done)"
printf '%s\n' "${SKILLS_PUESTAS:-  (ninguna de este repositorio)}"

# --- proyecto: bloque del .gitignore y puerta de commit ----------------------
# La capa local (_local/, __restriccion/) se queda: ahí vive el dato.
#
# El pre-commit que escribe el alta, ENTERO: tres líneas, y de ellas solo
# cambia la ruta del clon. Ese se retira. Cualquier otro es de la persona.
es_puerta_del_marco() { # <pre-commit>
    awk '(NR == 1 && $0 != "#!/usr/bin/env sh") || (NR == 2 && $0 != "# alambique — puerta de commit") ||
         (NR == 3 && $0 !~ /^exec ".*\/mecanismos\/puerta[.]sh"$/) || NR > 3 { mal = 1 }
         END { exit (mal || NR != 3) }' "$1" 2>/dev/null
}
# De un pre-commit de la persona se retira SOLO la línea que encadena la
# puerta, y solo si es entera la que aconseja el alta:
#   "<clon>/mecanismos/puerta.sh" || exit 1
# Vale la de cualquier clon: la de uno que se movió también sobra.
# Una llamada a la puerta de este clon escrita de otra forma no se toca
# —quitarla puede romper lo que la rodea—: se dice cuál es. Los comentarios
# no cuentan. Escribe SOBRE el fichero: conserva el modo y el enlace.
LINEA_PUERTA='function puerta(l) { return l ~ /^[ \t]*"[^"]*\/mecanismos\/puerta[.]sh" [|][|] exit 1[ \t]*$/ }'
quitar_puerta_encadenada() { # <pre-commit>
    f="$1"
    otras="$(P="$AQUI/mecanismos/puerta.sh" awk "$LINEA_PUERTA"'
        !/^[ \t]*#/ && !puerta($0) && index($0, ENVIRON["P"]) { printf "    línea %d: %s\n", NR, $0 }' "$f" 2>/dev/null)"
    if [ -n "$otras" ]; then
        avi "pre-commit: es de la persona y llama a la puerta con una línea que no es la que aconseja el alta: NO se toca."
        avi "  Quita la llamada a mano, en $f:"
        printf '%s\n' "$otras"
        FALLOS=$((FALLOS+1)); return 0
    fi
    n="$(awk "$LINEA_PUERTA"' puerta($0) { c++ } END { print c+0 }' "$f" 2>/dev/null)"
    if [ "${n:-0}" -eq 0 ]; then
        printf '  pre-commit no es del marco: no se toca\n'; return 0
    fi
    printf '  hook  ~ pre-commit (de la persona): se retira solo la línea que llama a la puerta\n'
    [ "$MODO" = "aplicar" ] || return 0
    copia="$(copia_libre "$f.previo.$SELLO")"; tmp="$(mktemp)"
    if cp "$f" "$copia" 2>/dev/null && awk "$LINEA_PUERTA"' !puerta($0)' "$f" > "$tmp" && cat "$tmp" 2>/dev/null > "$f"; then
        printf '    copia previa: %s\n' "$copia"
    else
        avi "no pude retirar del pre-commit la línea de la puerta: $f"; FALLOS=$((FALLOS+1))
    fi
    rm -f "$tmp"
}
if [ -n "$PROY" ]; then
    PROY="$(cd "$PROY" && pwd)"
    printf '\nproyecto: %s\n' "$PROY"
    RESPALDOS="$PROY"
    [ -d "$PROY/_local/respaldos" ] && RESPALDOS="$PROY/_local/respaldos"
    quitar_bloque "$PROY/.gitignore" ".gitignore" "$RESPALDOS"
    if raiz_git "$PROY"; then
        H="$(git -C "$PROY" rev-parse --git-path hooks 2>/dev/null)"
        case "$H" in /*) ;; *) H="$PROY/$H" ;; esac
        if [ -e "$H/pre-commit" ]; then
            if es_puerta_del_marco "$H/pre-commit"; then
                printf '  hook  - pre-commit (del marco)\n'
                if [ "$MODO" = "aplicar" ]; then
                    mv "$H/pre-commit" "$(copia_libre "$H/pre-commit.previo.$SELLO")" 2>/dev/null \
                        || { avi "no pude retirar $H/pre-commit"; FALLOS=$((FALLOS+1)); }
                fi
            else
                quitar_puerta_encadenada "$H/pre-commit"
            fi
        else
            printf '  sin pre-commit\n'
        fi
    else
        printf '  no es la raíz de un repositorio git: no hay puerta de commit que retirar\n'
    fi
    if [ -d "$PROY/_local" ] || [ -d "$PROY/__restriccion" ]; then
        printf '  _local/ y __restriccion/ se quedan. OJO: sin el bloque ya no los ignora nadie,\n'
        printf '  y un `git add` de todo el árbol los versionaría\n'
    fi
fi

if [ "$MODO" = "aplicar" ] && [ -f "$ANOTACION" ] && [ ! -s "$ANOTACION" ]; then
    rm -f "$ANOTACION"
fi

printf '\n'
if [ "$FALLOS" -gt 0 ]; then
    if [ "$MODO" = "ver" ]; then
        printf 'Nada se ha tocado. Con --aplicar quedarían %s pieza(s) SIN RETIRAR: repasa los AVISO de arriba.\n\n' "$FALLOS"
    else
        printf 'DESINSTALACIÓN INCOMPLETA: %s pieza(s) SIN RETIRAR. Repasa los AVISO de arriba.\n' "$FALLOS"
        printf 'Las copias .previo.%s permiten volver.\n\n' "$SELLO"
    fi
    exit 1
fi
if [ "$MODO" = "ver" ]; then
    printf 'Nada se ha tocado. Para hacerlo:  %s --aplicar %s\n\n' "$0" "${PROY:-[proyecto]}"
else
    printf 'Desinstalado. Las copias .previo.%s permiten volver.\n\n' "$SELLO"
fi
exit 0
