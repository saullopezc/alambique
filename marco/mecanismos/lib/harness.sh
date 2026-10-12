# SPDX-License-Identifier: MIT
#
# lib/harness.sh — Qué harness hay en el puesto y qué ofrece cada uno, y lo
# que el alta y la baja tienen que resolver IGUAL (última sección).
#
# Se hace `source` desde los instaladores. No ejecuta nada por sí mismo.
#
# LA TABLA ES DATO, NO LÓGICA. Una línea por harness:
#   nombre | dir de configuración (relativo a $HOME) | fichero de contexto
#   global (relativo al dir; `-` si no tiene) | dir de skills (relativo al
#   dir; `-` si no lee skills) | adaptador de reglas de lectura y guard
#   (`-` si no hay: entonces R-04, R-06, R-07 y R-11 (y el guard de R-03) quedan procedimentales,
#   el instalador LO DICE en vez de dar por puesto lo que no puso, y el texto
#   de las que solo vigilaba la máquina va al bloque de contexto) | `@` si el
#   fichero de contexto admite importar otro con `@ruta` (entonces el bloque
#   de reglas es UNA línea que apunta al repo, y la norma tiene un solo dueño;
#   `-` si no, y el bloque va copiado).
#
# Si tu harness no está o cambió de ruta, se añade o corrige su línea aquí, y
# en ningún otro sitio: los guards y los scripts de las skills resuelven <conf>
# por su propia ubicación o haciendo `source` de este fichero, nunca con una
# copia de la lista.
# Un adaptador nuevo son dos ficheros: `adaptadores/<nombre>.sh`, con el mismo
# contrato que `adaptadores/claude.sh`, y una versión de `lib/hook.sh` que
# hable la carga y la respuesta de hook de ese harness.
#
# La última fila, `alambique`, no es un harness: es el directorio neutral al
# que se cae cuando no hay ninguno y $ALAMBIQUE_CONF no dice otra cosa. No
# tiene fichero de contexto: ningún agente lo leería, y escribirlo sería dar
# por puestas unas reglas que no llegan a nadie.
#
# Author       : Saul López
# Created Date : 2026-09-12

harness_tabla() {
    cat <<'TABLA'
claude|.claude|CLAUDE.md|skills|claude|@
codex|.codex|AGENTS.md|skills|-|-
gemini|.gemini|GEMINI.md|skills|-|@
cursor|.cursor|-|skills|-|-
opencode|.config/opencode|AGENTS.md|skills|-|-
aider|.aider|-|-|-|-
alambique|.alambique|-|skills|-|-
TABLA
}

# Columna N de la fila cuyo nombre es $1. Vacío si no existe.
harness_campo() { # <nombre> <columna 1..6>
    harness_tabla | awk -F'|' -v n="$1" -v c="$2" '$1 == n { print $c; exit }'
}

# Nombre del harness al que pertenece un directorio de configuración.
# Se compara por el último tramo de la ruta (`.claude`, `opencode`...), no por
# la ruta entera: $ALAMBIQUE_CONF puede apuntar a cualquier sitio.
harness_de_conf() { # <dir>
    _b="$(basename "$1")"
    harness_tabla | awk -F'|' -v b="$_b" '
        { n = split($2, p, "/"); if (p[n] == b) { print $1; exit } }'
}

# Directorio de configuración del puesto. No se asume ningún harness:
# $ALAMBIQUE_CONF manda; si no, el primero que exista en el orden de la tabla; si
# ninguno, ~/.alambique.
conf_puesto() {
    [ -n "${ALAMBIQUE_CONF:-}" ] && { printf '%s' "$ALAMBIQUE_CONF"; return 0; }
    harness_tabla | while IFS='|' read -r _n _d _c _s _a _i; do
        [ -d "$HOME/$_d" ] && { printf '%s' "$HOME/$_d"; break; }
    done | head -n 1 | { read -r _r; [ -n "$_r" ] && printf '%s' "$_r" || printf '%s' "$HOME/.alambique"; }
}

# Todos los harness presentes en el puesto, uno por línea: `nombre|dir-absoluto`.
# Para lo que se instala en CADA harness (las skills), no solo en el principal.
# $ALAMBIQUE_CONF cuenta aunque no esté en ninguna ruta conocida: quien lo
# declara está diciendo dónde vive su configuración. Si su último tramo no es
# el de ningún harness de la tabla, se trata con la fila neutral `alambique`.
harness_presentes() {
    {
        if [ -n "${ALAMBIQUE_CONF:-}" ] && [ -d "$ALAMBIQUE_CONF" ]; then
            _h="$(harness_de_conf "$ALAMBIQUE_CONF")"
            printf '%s|%s\n' "${_h:-alambique}" "$ALAMBIQUE_CONF"
        fi
        harness_tabla | while IFS='|' read -r _n _d _c _s _a _i; do
            [ -d "$HOME/$_d" ] && printf '%s|%s\n' "$_n" "$HOME/$_d"
        done
    } | awk -F'|' '!visto[$2]++'
}

# --- Lo que el alta y la baja resuelven igual ---------------------------------
# Viven aquí, y no en cada instalador, porque una baja que resuelve distinto
# que el alta busca lo que hay que quitar en un sitio donde no está.

# Fichero de ignore global que git consulta DE VERDAD en este puesto:
#   1. el que la persona tenga en `core.excludesfile` (git expande `~`). Se
#      lee con `--includes`: la configuración global puede traer el ajuste en
#      un fichero incluido con `[include]`, y sin esa opción git no lo sigue.
#      Si la persona fija `GIT_CONFIG_GLOBAL`, `--global` ya lee ese fichero
#   2. si no hay ninguno, el que git lee sin que nadie se lo diga:
#      $XDG_CONFIG_HOME/git/ignore, o ~/.config/git/ignore
# En el caso 2 no hay nada que configurar, y por eso `core.excludesfile` no se
# escribe nunca: el ajuste es de la persona.
# Esto es dónde escribir, no la prueba de que sirva: el alta comprueba después
# con git que la capa local queda ignorada.
ignore_global_git() {
    _ig="$(git config --global --includes --path core.excludesfile 2>/dev/null || true)"
    [ -n "$_ig" ] || _ig="$(git config --system --includes --path core.excludesfile 2>/dev/null || true)"
    [ -n "$_ig" ] || _ig="${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore"
    printf '%s' "$_ig"
}

# Cierto si <dir> es la RAÍZ de un árbol de trabajo de git: un repositorio, un
# worktree o un submódulo (en estos dos `.git` es un fichero, no un directorio,
# y por eso se le pregunta a git). Un subdirectorio de un repositorio NO lo es:
# su puerta de commit sería la del repositorio de arriba, que nadie ha nombrado.
raiz_git() { # <dir>
    _t="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" || return 1
    [ -n "$_t" ] && [ "$(cd "$_t" 2>/dev/null && pwd -P)" = "$(cd "$1" 2>/dev/null && pwd -P)" ]
}

# Estado del bloque del marco en un fichero: `no` no lo tiene · `uno` tiene uno
# bien formado · `roto` hay marcas desparejadas o más de un bloque. Las marcas
# cuentan solo a principio de línea, igual que al sustituir y al retirar: una
# línea de prosa que CITA la marca no es un bloque. Un bloque `roto` no se toca:
# sin marca de cierre, sustituirlo o retirarlo se llevaría el resto del fichero.
estado_bloque() { # <fichero> <marca de inicio> <marca de fin>
    [ -e "$1" ] || { printf 'no'; return 0; }
    awk -v i="$2" -v f="$3" '
        index($0,i)==1 { ni++; if (d) roto=1; d=1 }
        index($0,f)==1 { nf++; if (!d) roto=1; d=0 }
        END { if (ni+nf == 0) printf "no"
              else if (ni == 1 && nf == 1 && !roto && !d) printf "uno"
              else printf "roto" }' "$1" 2>/dev/null
}

# Nombre libre para una copia previa. Dos pasadas en el mismo segundo comparten
# sello, y la segunda no puede pisar la copia de la primera: esa copia es el
# único camino de vuelta.
copia_libre() { # <ruta de la copia>
    _c="$1"; _n=1
    while [ -e "$_c" ] || [ -L "$_c" ]; do _n=$((_n+1)); _c="$1.$_n"; done
    printf '%s' "$_c"
}
