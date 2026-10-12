#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# pruebas/instaladores.sh — Banco de prueba de los instaladores del marco:
# `instalar.sh`, `marco/instalar.sh`, `marco/desinstalar.sh` y el adaptador.
#
# Uso:
#   pruebas/instaladores.sh [raíz]   raíz del repositorio a probar; por defecto,
#                                    la del repositorio de este fichero
#
# CÓMO PRUEBA. Cada caso monta un HOME desechable, ejecuta el instalador con
# `env -i` —nunca contra el HOME del puesto: instalaría de verdad— y la entrada
# cerrada, y mira el EFECTO: el fichero byte a byte, el código de salida, lo
# que git ignora de verdad, que la orden registrada arranque. Un caso por
# línea, `ok` o `FALLA` con el motivo. Sale 0 solo si pasan todos.
#
# QUÉ CUBRE: códigos de salida (0 con adaptador, 3 sin él, 1 sin harness);
# idempotencia; ida y vuelta sobre una configuración que ya tiene reglas,
# hooks, contexto e ignore de la persona; rutas con espacios y con caracteres
# no ASCII; enlaces simbólicos y modo 600; configuración que no se entiende;
# worktree y subdirectorio; `core.excludesfile` previo, en un `[include]` y
# con `XDG_CONFIG_HOME`, y que git ignore de verdad la capa local;
# el bloque de contexto con y sin adaptador, citado en prosa o sin cerrar;
# las reglas de lectura; la pregunta de identidad (necesita `script`, que le
# da una terminal); y que lo de la persona se reconoce por su forma y no por
# nombrar al marco: un pre-commit propio, encadenado o no, y un hook propio.
#
# Necesita: bash, git, python3 (lo pide el adaptador), sha256sum, script.
#
# Author       : Saul López
# Created Date : 2026-10-11

set -uo pipefail
# El PATH se sanea y se retiran funciones que puedan ensombrecer las
# herramientas: el banco tiene que medir con las mismas que los instaladores.
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
unset -f grep sed awk find sort xargs cmp stat cp ln rm mkdir tail cut tr git 2>/dev/null || true

case "${1:-}" in
    -h|--help) grep '^#' "$0" | sed -n '3,29p' | cut -c3-; exit 0 ;;
esac
RAIZ="$(cd "${1:-$(dirname "$0")/..}" 2>/dev/null && pwd)" || { echo "no existe la raíz: ${1:-}" >&2; exit 1; }
[ -x "$RAIZ/instalar.sh" ] && [ -x "$RAIZ/marco/instalar.sh" ] && [ -x "$RAIZ/marco/desinstalar.sh" ] \
    || { echo "en $RAIZ no están los instaladores" >&2; exit 1; }

BASE="$(mktemp -d)"
trap 'rm -rf "$BASE"' EXIT
N_OK=0; N_FALLA=0

# --- Herramientas del banco ----------------------------------------------------
# Entorno limpio: ni el HOME ni la configuración de git del puesto entran.
limpio() { env -i PATH="$PATH" GIT_CONFIG_NOSYSTEM=1 "$@"; }
casa()   { mktemp -d "$BASE/casa.XXXXXX"; }
# La salida de cada ejecución queda junto a la casa, fuera de ella.
alta()   { local h="$1"; shift; limpio HOME="$h" "$RAIZ/instalar.sh" "$@" </dev/null >"$h.alta" 2>&1; }
marco()  { local h="$1"; shift; limpio HOME="$h" "$RAIZ/marco/instalar.sh" "$@" </dev/null >"$h.alta" 2>&1; }
baja()   { local h="$1"; shift; limpio HOME="$h" "$RAIZ/marco/desinstalar.sh" "$@" </dev/null >"$h.baja" 2>&1; }
g()      { local h="$1"; shift
           limpio HOME="$h" GIT_AUTHOR_NAME=p GIT_AUTHOR_EMAIL=p@example.org \
               GIT_COMMITTER_NAME=p GIT_COMMITTER_EMAIL=p@example.org git "$@"; }
repo()   { # <casa> <dir>: un repositorio con un commit
           mkdir -p "$2" && g "$1" -C "$2" init -q && printf 'hola\n' > "$2/LEEME.txt" \
               && g "$1" -C "$2" add LEEME.txt && g "$1" -C "$2" commit -q -m inicial; }
# Suma de un árbol: contenido, enlaces, modos y nombres. No entra la fecha.
suma()   { ( cd "$1" && { find . \( -type f -o -type l \) -print0 | sort -z | xargs -0 -r sha256sum
                          find . -printf '%m %y %p %l\n' | sort; } ) | sha256sum | cut -d' ' -f1; }
ordenes() { sed -n 's/^ *"command": "\(.*\)"$/\1/p' "$1"; }   # las órdenes de hook registradas
sin()    { echo "$*"; exit 1; }   # motivo del fallo; cada caso corre en su subshell

prueba() { # <nombre> <función>
    local motivo
    if motivo="$("$2" 2>&1)"; then
        N_OK=$((N_OK+1)); printf 'ok     %s\n' "$1"
    else
        N_FALLA=$((N_FALLA+1)); printf 'FALLA  %s — %s\n' "$1" "$(printf '%s' "$motivo" | tail -n 1)"
    fi
}

# Una configuración que ya es de alguien: reglas, un hook, contexto, ignore
# global configurado con `~` y un proyecto con su `.gitignore`. Deja copia de
# cada fichero en <casa>.antes/ para comparar byte a byte.
casa_con_vida() { # <casa> <proyecto>
    local h="$1" p="$2"
    mkdir -p "$h/.claude" "$h.antes"
    printf '%s\n' '{"model":"x","permissions":{"allow":["Bash(ls:*)"],"deny":["Read(./**/.env)","Read(./mio/**)"]},"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/usr/local/bin/mi-hook.sh"}]}]}}' > "$h/.claude/settings.json"
    printf '# Mis reglas\n\nNo tocar esto.\n' > "$h/.claude/CLAUDE.md"
    printf '[core]\n\texcludesfile = ~/.gitignore_global\n' > "$h/.gitconfig"
    printf '*.swp\n*.mio' > "$h/.gitignore_global"          # sin salto final, a propósito
    repo "$h" "$p" && printf 'node_modules/\n' > "$p/.gitignore" \
        && g "$h" -C "$p" add .gitignore && g "$h" -C "$p" commit -q -m ignore
    cp "$h/.claude/settings.json" "$h/.claude/CLAUDE.md" "$h/.gitconfig" "$h/.gitignore_global" "$h.antes/"
    cp "$p/.gitignore" "$h.antes/gitignore-proyecto"
}
igual() { cmp -s "$1" "$2" || sin "$3 no quedó como estaba"; }

# --- Códigos de salida ---------------------------------------------------------
c_codigo_0() {
    local h; h="$(casa)"; mkdir -p "$h/.claude"
    alta "$h"; [ $? -eq 0 ] || sin "con .claude debía salir 0"
    grep -q '^Todo puesto\.$' "$h.alta" || sin "falta 'Todo puesto.'"
}
c_codigo_3() {
    local h; h="$(casa)"; mkdir -p "$h/.codex"
    alta "$h"; r=$?; [ $r -eq 3 ] || sin "con .codex debía salir 3 y salió $r"
}
c_codigo_1_sin_harness() {
    local h; h="$(casa)"
    alta "$h"; r=$?; [ $r -eq 1 ] || sin "sin harness el instalador de la raíz debía salir 1 y salió $r"
}
c_sin_harness_no_escribe_contexto() {
    local h; h="$(casa)"
    marco "$h"; r=$?; [ $r -eq 3 ] || sin "sin harness marco/instalar.sh debía salir 3 y salió $r"
    [ ! -e "$h/.alambique/AGENTS.md" ] || sin "escribió ~/.alambique/AGENTS.md, que no lee nadie"
    grep -q 'criterio en el contexto global  *NO SOPORTADO' "$h.alta" || sin "el contexto no sale como NO SOPORTADO"
}
c_dos_proyectos() {
    local h; h="$(casa)"; mkdir -p "$h/.claude" "$h.a" "$h.b"
    alta "$h" "$h.a" "$h.b"; r=$?; [ $r -eq 1 ] || sin "dos proyectos debían rechazarse con 1 y salió $r"
    [ ! -e "$h/.claude/skills" ] && [ ! -e "$h/.claude/settings.json" ] || sin "instaló antes de rechazar"
}

# --- Idempotencia --------------------------------------------------------------
c_idempotencia() {
    local h p a b; h="$(casa)"; p="$h.proy"; mkdir -p "$h/.claude"; repo "$h" "$p" || sin "no pude crear el repo"
    alta "$h" "$p" || sin "primera pasada: salida $?"
    a="$(suma "$h") $(suma "$p")"
    sleep 1     # un sello o una fecha escritos en cada pasada cambian aquí
    alta "$h" "$p" || sin "segunda pasada: salida $?"
    b="$(suma "$h") $(suma "$p")"
    [ "$a" = "$b" ] || sin "la segunda pasada cambió algo"
}

# --- Ida y vuelta --------------------------------------------------------------
c_ida_y_vuelta() {
    local h p; h="$(casa)"; p="$h.proy"; casa_con_vida "$h" "$p" || sin "no pude montar la casa"
    alta "$h" "$p" || sin "alta: salida $?"
    # Control: el alta tiene que haber escrito, o la vuelta no prueba nada.
    grep -q 'guard-remoto.sh' "$h/.claude/settings.json" || sin "el alta no registró hooks"
    grep -q '^# >>> alambique' "$h/.claude/CLAUDE.md" "$h/.gitignore_global" "$p/.gitignore" || sin "el alta no puso bloques"
    [ -x "$p/.git/hooks/pre-commit" ] || sin "el alta no puso la puerta"
    baja "$h" --aplicar "$p" || sin "baja: salida $?"
    igual "$h/.claude/settings.json" "$h.antes/settings.json" "settings.json" || return 1
    igual "$h/.claude/CLAUDE.md" "$h.antes/CLAUDE.md" "CLAUDE.md" || return 1
    igual "$h/.gitconfig" "$h.antes/.gitconfig" ".gitconfig" || return 1
    igual "$h/.gitignore_global" "$h.antes/.gitignore_global" "el ignore global" || return 1
    igual "$p/.gitignore" "$h.antes/gitignore-proyecto" "el .gitignore del proyecto" || return 1
    [ ! -e "$p/.git/hooks/pre-commit" ] || sin "queda el pre-commit"
    ! g "$h" -C "$p" status --porcelain --untracked-files=all | grep -q '^?? [^/]*previo' \
        || sin "queda una copia .previo sin seguir en la raíz del proyecto"
    [ -z "$(find "$h/.claude" -maxdepth 1 -name '.alambique-alta*')" ] || sin "queda la anotación del alta"
}
c_copia_previa_no_se_pisa() {
    # Alta y baja en el mismo segundo comparten sello: la copia del estado
    # original tiene que seguir existiendo después de la baja.
    local h p f; h="$(casa)"; p="$h.proy"; casa_con_vida "$h" "$p" || sin "no pude montar la casa"
    alta "$h" "$p" || sin "alta: salida $?"
    baja "$h" --aplicar "$p" || sin "baja: salida $?"
    for f in "$h/.claude"/settings.json.previo.*; do
        cmp -s "$f" "$h.antes/settings.json" && return 0
    done
    sin "ninguna copia .previo de settings.json conserva el original"
}
c_lo_que_no_existia_no_existe() {
    local h p; h="$(casa)"; p="$h.proy"; mkdir -p "$h/.claude" "$h.antes"; repo "$h" "$p" || sin "no pude crear el repo"
    printf '{"model":"x"}' > "$h/.claude/settings.json"; cp "$h/.claude/settings.json" "$h.antes/"
    alta "$h" "$p" || sin "alta: salida $?"
    [ -s "$h/.claude/CLAUDE.md" ] && [ -s "$h/.config/git/ignore" ] && [ -s "$p/.gitignore" ] || sin "el alta no creó los ficheros"
    baja "$h" --aplicar "$p" || sin "baja: salida $?"
    igual "$h/.claude/settings.json" "$h.antes/settings.json" "settings.json" || return 1
    [ ! -e "$h/.claude/CLAUDE.md" ] || sin "queda un CLAUDE.md que no existía"
    [ ! -e "$h/.config/git/ignore" ] || sin "queda un ignore global que no existía"
    [ ! -e "$p/.gitignore" ] || sin "queda un .gitignore de proyecto que no existía"
    [ ! -e "$h/.gitconfig" ] && [ ! -e "$h/.config/git/config" ] || sin "queda configuración de git que no existía"
}
c_enlace_colgante_se_queda() {
    # El ignore global es un enlace hacia un fichero que aún no existe: el alta
    # crea el destino a través de él, y la baja retira ese destino, no el enlace.
    local h; h="$(casa)"; mkdir -p "$h/.claude" "$h/.config/git" "$h/dot"
    ln -s "$h/dot/ignore" "$h/.config/git/ignore"
    alta "$h" || sin "alta: salida $?"
    [ -L "$h/.config/git/ignore" ] && [ -s "$h/dot/ignore" ] || sin "control: el alta no escribió a través del enlace"
    baja "$h" --aplicar || sin "baja: salida $?"
    [ -L "$h/.config/git/ignore" ] || sin "la baja borró un enlace que era de la persona"
    [ "$(readlink "$h/.config/git/ignore")" = "$h/dot/ignore" ] || sin "el enlace ya no apunta a donde apuntaba"
    [ ! -e "$h/dot/ignore" ] || sin "queda el destino que creó el alta"
}
c_settings_que_no_existia() {
    local h; h="$(casa)"; mkdir -p "$h/.claude"
    alta "$h" || sin "alta: salida $?"
    [ -s "$h/.claude/settings.json" ] || sin "el alta no creó settings.json"
    baja "$h" --aplicar || sin "baja: salida $?"
    [ ! -e "$h/.claude/settings.json" ] || sin "queda un settings.json que no existía"
}
c_fichero_vacio_que_existia() {
    local h; h="$(casa)"; mkdir -p "$h/.claude"; : > "$h/.claude/CLAUDE.md"
    alta "$h" || sin "alta: salida $?"
    baja "$h" --aplicar || sin "baja: salida $?"
    [ -e "$h/.claude/CLAUDE.md" ] && [ ! -s "$h/.claude/CLAUDE.md" ] || sin "un CLAUDE.md vacío que ya existía no quedó vacío y en su sitio"
}
c_hook_de_la_persona() {
    # Un hook propio que se llama como un guard del marco: ni se pisa, ni
    # pierde su registro, ni el resumen lo da por activo.
    local h; h="$(casa)"; mkdir -p "$h/.claude/hooks" "$h.antes"
    printf '#!/bin/sh\nexit 0\n' > "$h/.claude/hooks/guard-remoto.sh"
    printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"%s/.claude/hooks/guard-remoto.sh"}]}]}}\n' "$h" > "$h/.claude/settings.json"
    cp "$h/.claude/settings.json" "$h/.claude/hooks/guard-remoto.sh" "$h.antes/"
    alta "$h"; r=$?; [ $r -eq 1 ] || sin "con un guard ajeno debía salir 1 y salió $r"
    grep -q 'hooks (+R-03)  *PARCIAL' "$h.alta" || sin "el resumen no dice PARCIAL: $(grep 'hooks (+R-03)' "$h.alta")"
    baja "$h" --aplicar || sin "baja: salida $?"
    igual "$h/.claude/settings.json" "$h.antes/settings.json" "settings.json (el registro del hook propio)" || return 1
    igual "$h/.claude/hooks/guard-remoto.sh" "$h.antes/guard-remoto.sh" "el hook propio" || return 1
}
c_lib_ajena() {
    local h; h="$(casa)"; mkdir -p "$h/.claude/hooks/lib"
    printf '# la mía\n' > "$h/.claude/hooks/lib/hook.sh"
    alta "$h"; r=$?; [ $r -eq 1 ] || sin "con una lib ajena debía salir 1 y salió $r"
    grep -q 'hooks (+R-03)  *NO ACTIVO' "$h.alta" || sin "el resumen no dice NO ACTIVO: $(grep 'hooks (+R-03)' "$h.alta")"
    ! grep -q 'guard-' "$h/.claude/settings.json" || sin "registró guards que no pueden actuar"
}
c_sin_anotacion() {
    # Sin anotación la baja retira los hooks de ruta exacta y no toca ninguna
    # regla de lectura, y lo dice.
    local h; h="$(casa)"; mkdir -p "$h/.claude"
    alta "$h" || sin "alta: salida $?"
    rm -f "$h/.claude"/.alambique-alta*
    baja "$h" --aplicar || sin "baja: salida $?"
    ! grep -q 'guard-\|arranque-skills' "$h/.claude/settings.json" || sin "quedan hooks del marco registrados"
    grep -qF 'Read(./**/*.pem)' "$h/.claude/settings.json" || sin "retiró reglas de lectura sin saber de quién eran"
    grep -q 'no hay anotación' "$h.baja" || sin "no dice que falta la anotación"
}
c_anotacion_parcial() {
    # El alta encuentra hooks del marco registrados y ninguna anotación: lo
    # que ya estaba no se sabe de quién es. La baja retira lo que esta alta
    # añadió, deja el resto, y no afirma que fuera de la persona.
    local h s; h="$(casa)"; mkdir -p "$h/.claude"; s="$h/.claude/settings.json"
    alta "$h" || sin "alta: salida $?"
    rm -f "$h/.claude/.alambique-alta.claude.json"
    sed -i '/\*\.pfx/d' "$s"                      # una regla que esa instalación no traía
    alta "$h" || sin "segunda alta: salida $?"
    grep -qF 'Read(./**/*.pfx)' "$s" || sin "control: la segunda alta no añadió la regla que faltaba"
    grep -q '"previa_sin_anotar": true' "$h/.claude/.alambique-alta.claude.json" || sin "el alta no anota que había una instalación sin anotar"
    baja "$h" --aplicar || sin "baja: salida $?"
    ! grep -qF 'Read(./**/*.pfx)' "$s" || sin "no retiró la regla que sí añadió"
    grep -qF 'Read(./**/*.pem)' "$s" || sin "retiró reglas sin saber de quién eran"
    ! grep -q 'guard-\|arranque-skills' "$s" || sin "quedan hooks del marco registrados"
    grep -q 'no consta quién las puso' "$h.baja" || sin "no dice que no consta quién puso las reglas que se quedan"
    ! grep -q 'son tuyas' "$h.baja" || sin "afirma que son de la persona unas reglas que pudo poner el marco"
}
c_skills_del_repositorio() {
    # El marcador solo no distingue las skills de este repositorio: los
    # mensajes las nombran, y no señalan una ajena que lleve el mismo marcador.
    local h; h="$(casa)"; mkdir -p "$h/.claude/skills/de-otro-repo"
    printf 'origen: otro\n' > "$h/.claude/skills/de-otro-repo/.alambique-origen"
    alta "$h" || sin "alta: salida $?"
    grep '^Para retirarlas' "$h.alta" | grep -q 'skills/operacion-puesto' || sin "el alta no nombra la skill de este repositorio"
    baja "$h" --ver || sin "baja --ver: salida $?"
    grep -q '/skills/operacion-puesto$' "$h.baja" || sin "la baja no dice dónde está la skill de este repositorio"
    ! grep -q 'de-otro-repo' "$h.baja" || sin "la baja señala una skill de otro repositorio"
}

# --- Rutas difíciles -----------------------------------------------------------
c_espacios() {
    local h p v n=0 o; h="$BASE/ca sa"; p="$BASE/pro yecto"; v="$BASE/vacio"; mkdir -p "$h/.claude" "$v"
    repo "$h" "$p" || sin "no pude crear el repo"
    ( cd "$v" && alta "$h" "$p" ) || sin "alta: salida $?"
    [ -z "$(ls -A "$v")" ] || sin "escribió en el directorio actual: $(ls -A "$v" | tr '\n' ' ')"
    [ -e "$p/_local/operacion/urgencias/.gitkeep" ] && [ -e "$p/__restriccion/.gitkeep" ] || sin "el esqueleto no está en el proyecto"
    while IFS= read -r o; do
        n=$((n+1))
        limpio HOME="$h" sh -c "$o" </dev/null >/dev/null 2>&1 || sin "la orden registrada no arranca: $o"
    done <<EOF
$(ordenes "$h/.claude/settings.json")
EOF
    [ "$n" -eq 4 ] || sin "esperaba 4 órdenes de hook y hay $n"
    printf 'nota\n' > "$p/nota.txt"; g "$h" -C "$p" add nota.txt
    g "$h" -C "$p" commit -q -m nota >/dev/null 2>&1 || sin "la puerta de commit no deja pasar un commit inocuo"
    baja "$h" --aplicar "$p" || sin "baja: salida $?"
}
c_repositorio_con_espacios() {
    local h p r; h="$(casa)"; p="$h.proy"; r="$BASE/re po"; mkdir -p "$h/.claude" "$r"
    cp -R "$RAIZ/instalar.sh" "$RAIZ/marco" "$r/"; repo "$h" "$p" || sin "no pude crear el repo"
    limpio HOME="$h" "$r/instalar.sh" "$p" </dev/null >"$h.alta" 2>&1 || sin "alta: salida $?"
    # Importar con @ una ruta con espacios no está verificado: el bloque va copiado.
    ! grep -q '^@' "$h/.claude/CLAUDE.md" || sin "importa con @ una ruta con espacios"
    grep -q 'R-01 ·' "$h/.claude/CLAUDE.md" || sin "el bloque copiado no trae las reglas"
    printf 'nota\n' > "$p/nota.txt"; g "$h" -C "$p" add nota.txt
    g "$h" -C "$p" commit -q -m nota >/dev/null 2>&1 || sin "la puerta no arranca desde un clon con espacios"
}
c_no_ascii() {
    local h n; h="$BASE/cañón"; mkdir -p "$h/.claude"
    alta "$h" || sin "primera pasada: salida $?"
    alta "$h" || sin "segunda pasada: salida $?"
    n="$(grep -c 'guard-remoto.sh' "$h/.claude/settings.json")"
    [ "$n" -eq 1 ] || sin "guard-remoto registrado $n veces tras dos pasadas"
}
c_enlaces_y_modo() {
    local h d f; h="$(casa)"; d="$h.dot"; mkdir -p "$h/.claude" "$h/.config/git" "$d" "$h.antes"
    printf '{"model":"x"}\n' > "$d/settings.json"; chmod 600 "$d/settings.json"
    printf '# Mis reglas\n' > "$d/CLAUDE.md"; printf '*.swp\n' > "$d/ignore"
    cp "$d"/* "$h.antes/"
    ln -s "$d/settings.json" "$h/.claude/settings.json"; ln -s "$d/CLAUDE.md" "$h/.claude/CLAUDE.md"
    ln -s "$d/ignore" "$h/.config/git/ignore"
    alta "$h" || sin "alta: salida $?"
    grep -q 'guard-remoto.sh' "$d/settings.json" || sin "el alta no escribió en el destino del enlace"
    for f in "$h/.claude/settings.json" "$h/.claude/CLAUDE.md" "$h/.config/git/ignore"; do
        [ -L "$f" ] || sin "tras el alta $f ya no es un enlace"
    done
    [ "$(stat -c %a "$d/settings.json")" = 600 ] || sin "tras el alta settings.json es $(stat -c %a "$d/settings.json"), no 600"
    baja "$h" --aplicar || sin "baja: salida $?"
    for f in "$h/.claude/settings.json" "$h/.claude/CLAUDE.md" "$h/.config/git/ignore"; do
        [ -L "$f" ] || sin "tras la baja $f ya no es un enlace"
    done
    [ "$(stat -c %a "$d/settings.json")" = 600 ] || sin "tras la baja settings.json es $(stat -c %a "$d/settings.json"), no 600"
    for f in settings.json CLAUDE.md ignore; do igual "$d/$f" "$h.antes/$f" "$f" || return 1; done
}

# --- Configuración que no se entiende ------------------------------------------
c_settings_invalido_alta() {
    local h; h="$(casa)"; mkdir -p "$h/.claude"
    printf '{ "model": "x", }\n' > "$h/.claude/settings.json"; cp "$h/.claude/settings.json" "$h.antes"
    alta "$h"; r=$?; [ $r -eq 1 ] || sin "debía salir 1 y salió $r"
    igual "$h/.claude/settings.json" "$h.antes" "settings.json" || return 1
    grep -q 'R-04 reglas de lectura  *NO ACTIVO' "$h.alta" || sin "las reglas de lectura no salen como NO ACTIVO"
}
c_settings_invalido_baja() {
    local h; h="$(casa)"; mkdir -p "$h/.claude"
    alta "$h" || sin "alta: salida $?"
    printf '{ roto\n' > "$h/.claude/settings.json"
    baja "$h" --aplicar; r=$?; [ $r -eq 1 ] || sin "con la configuración rota la baja debía salir 1 y salió $r"
    [ -f "$h/.claude/hooks/guard-remoto.sh" ] && [ -f "$h/.claude/hooks/lib/hook.sh" ] \
        || sin "retiró los hooks dejando su registro en la configuración"
    ! grep -q '^Desinstalado' "$h.baja" || sin "dice 'Desinstalado' sin haberlo hecho"
}

# --- Proyecto ------------------------------------------------------------------
c_worktree() {
    local h p w; h="$(casa)"; p="$h.proy"; w="$h.wt"; mkdir -p "$h/.claude"; repo "$h" "$p" || sin "no pude crear el repo"
    g "$h" -C "$p" worktree add -q "$w" -b otra >/dev/null 2>&1 || sin "no pude crear el worktree"
    alta "$h" "$w" || sin "en un worktree debía salir 0 y salió $?"
    grep -q 'puerta de commit  *activo' "$h.alta" || sin "la puerta no sale activa en un worktree"
    [ -x "$p/.git/hooks/pre-commit" ] || sin "no hay pre-commit en el repositorio del worktree"
    baja "$h" --aplicar "$w" || sin "baja: salida $?"
    [ ! -e "$p/.git/hooks/pre-commit" ] || sin "la baja no retiró la puerta del worktree"
}
c_subdirectorio() {
    # Un subdirectorio de un repositorio no es un proyecto: la puerta no se
    # instala en el repositorio de arriba, que nadie ha nombrado.
    local h p; h="$(casa)"; p="$h.proy"; mkdir -p "$h/.claude"; repo "$h" "$p" || sin "no pude crear el repo"
    mkdir -p "$p/sub"
    alta "$h" "$p/sub"; r=$?; [ $r -eq 1 ] || sin "debía salir 1 y salió $r"
    [ ! -e "$p/.git/hooks/pre-commit" ] || sin "instaló la puerta en el repositorio de arriba"
}

# --- Ignore global: el efecto, no el fichero -----------------------------------
ignora() { g "$1" -C "$2" check-ignore -q "$3"; }   # <casa> <repo> <ruta>
c_baja_avisa_capa_local() {
    # Retirado el bloque del ignore global, la capa local queda sin ignorar en
    # los repositorios que no se dieron de alta: la baja lo dice, también sin
    # nombrarle un proyecto.
    local h p; h="$(casa)"; p="$h.proy"; mkdir -p "$h/.claude"; repo "$h" "$p" || sin "no pude montar el repositorio"
    alta "$h" || sin "alta: salida $?"
    mkdir -p "$p/_local"; printf 'dato\n' > "$p/_local/d.txt"
    ignora "$h" "$p" _local/d.txt || sin "control: con el marco puesto la capa local no se ignora"
    baja "$h" --ver || sin "baja --ver: salida $?"
    grep -q 'OJO: sin ese bloque' "$h.baja" || sin "--ver no avisa de que la capa local quedaría sin ignorar"
    baja "$h" --aplicar || sin "baja: salida $?"
    grep -q 'OJO: sin ese bloque' "$h.baja" || sin "la baja no avisa de que la capa local queda sin ignorar"
    ! ignora "$h" "$p" _local/d.txt || sin "el aviso sobra: tras la baja la capa local sigue ignorada"
    baja "$h" --aplicar || sin "segunda baja: salida $?"
    ! grep -q 'OJO' "$h.baja" || sin "avisa sin que hubiera bloque que retirar"
}
c_excludesfile_previo() {
    local h p; h="$(casa)"; p="$h.proy"; casa_con_vida "$h" "$p" || sin "no pude montar la casa"
    ignora "$h" "$p" x.mio || sin "control: git no aplica el ignore global de la persona antes del alta"
    ! ignora "$h" "$p" LEEME.txt || sin "control: git lo ignora todo"
    marco "$h" || sin "alta: salida $?"
    igual "$h/.gitconfig" "$h.antes/.gitconfig" ".gitconfig (core.excludesfile)" || return 1
    ignora "$h" "$p" _local/dato.txt || sin "git no ignora _local/ tras el alta"
    ignora "$h" "$p" x.mio || sin "el ignore global de la persona dejó de aplicarse"
}
c_xdg_config_home() {
    local h p x; h="$(casa)"; p="$h.proy"; x="$h/xdg"; mkdir -p "$h/.claude" "$x/git"; repo "$h" "$p" || sin "no pude crear el repo"
    printf '*.mio\n' > "$x/git/ignore"; cp "$x/git/ignore" "$h.antes"
    limpio HOME="$h" XDG_CONFIG_HOME="$x" git -C "$p" check-ignore -q x.mio || sin "control: git no lee el ignore de XDG_CONFIG_HOME"
    limpio HOME="$h" XDG_CONFIG_HOME="$x" "$RAIZ/marco/instalar.sh" </dev/null >"$h.alta" 2>&1 || sin "alta: salida $?"
    limpio HOME="$h" XDG_CONFIG_HOME="$x" git -C "$p" check-ignore -q x.mio || sin "el ignore global de la persona dejó de aplicarse"
    limpio HOME="$h" XDG_CONFIG_HOME="$x" git -C "$p" check-ignore -q _local/dato.txt || sin "git no ignora _local/ tras el alta"
    [ ! -e "$h/.gitconfig" ] && [ ! -e "$x/git/config" ] || sin "escribió configuración de git"
    limpio HOME="$h" XDG_CONFIG_HOME="$x" "$RAIZ/marco/desinstalar.sh" --aplicar </dev/null >"$h.baja" 2>&1 || sin "baja: salida $?"
    igual "$x/git/ignore" "$h.antes" "el ignore de XDG_CONFIG_HOME" || return 1
}
c_sin_excludesfile() {
    local h p; h="$(casa)"; p="$h.proy"; mkdir -p "$h/.claude"; repo "$h" "$p" || sin "no pude crear el repo"
    ! ignora "$h" "$p" _local/dato.txt || sin "control: git ya ignoraba _local/ antes del alta"
    marco "$h" || sin "alta: salida $?"
    ignora "$h" "$p" _local/dato.txt || sin "git no ignora _local/ tras el alta"
    [ ! -e "$h/.gitconfig" ] || sin "escribió ~/.gitconfig sin hacer falta"
}
c_excludesfile_en_un_include() {
    # El ajuste vive en un fichero incluido: git lo sigue, y el alta también.
    local h p; h="$(casa)"; p="$h.proy"; mkdir -p "$h/.claude" "$h/.gitconfig.d"; repo "$h" "$p" || sin "no pude crear el repo"
    printf '[include]\n\tpath = ~/.gitconfig.d/extra\n' > "$h/.gitconfig"; cp "$h/.gitconfig" "$h.antes"
    printf '[core]\n\texcludesfile = ~/.mi_ignore\n' > "$h/.gitconfig.d/extra"; printf '*.mio\n' > "$h/.mi_ignore"
    ignora "$h" "$p" x.mio || sin "control: git no sigue el include antes del alta"
    marco "$h" || sin "alta: salida $?"
    mkdir -p "$p/_local"; : > "$p/_local/x"
    [ -z "$(g "$h" -C "$p" status --short)" ] || sin "git status muestra: $(g "$h" -C "$p" status --short | tr '\n' ' ')"
    ignora "$h" "$p" x.mio || sin "el ignore global de la persona dejó de aplicarse"
    igual "$h/.gitconfig" "$h.antes" ".gitconfig" || return 1
    [ ! -e "$h/.config/git/ignore" ] || sin "escribió el bloque en un fichero que git no consulta"
}
c_bloque_puesto_y_sin_efecto() {
    # El bloque está y git no ignora la capa local: el estado es el efecto.
    local h; h="$(casa)"; mkdir -p "$h/.claude"
    marco "$h" || sin "alta: salida $?"
    grep -q 'R-02 ignore global (puesto)  *activo$' "$h.alta" || sin "control: con el bloque en efecto no sale activo"
    printf '!_local/**\n' >> "$h/.config/git/ignore"       # la persona lo re-incluye después del bloque
    marco "$h"; r=$?; [ $r -eq 1 ] || sin "con el bloque sin efecto debía salir 1 y salió $r"
    grep -q 'R-02 ignore global (puesto)  *NO ACTIVO' "$h.alta" || sin "da por activo un ignore que git no aplica"
}

# --- Bloque de contexto --------------------------------------------------------
plano() { tr '\n' ' ' | sed -e 's/\*\*//g' -e 's/  */ /g'; }
regla_de_la_norma() { # <nn>: el texto de la regla en NORMA.md, sin negritas
    awk -F'|' -v r="R-$1" 'index($2, r) { print $3; exit }' "$RAIZ/marco/NORMA.md" \
        | sed -e 's/^ *//' -e 's/ *$//' | plano | sed 's/ $//'
}
c_contexto_con_adaptador() {
    local h f n; h="$(casa)"; mkdir -p "$h/.claude"
    marco "$h" || sin "alta: salida $?"
    [ "$(grep -c '^@' "$h/.claude/CLAUDE.md")" -eq 1 ] || sin "esperaba una línea @ en CLAUDE.md"
    f="$(sed -n 's/^@//p' "$h/.claude/CLAUDE.md")"; [ -r "$f" ] || sin "la línea @ apunta a un fichero que no existe: $f"
    for n in 01 05 08 09 10 11 12; do grep -q "R-$n ·" "$f" || sin "falta R-$n en el bloque"; done
    for n in 03 04 06 07; do ! grep -q "R-$n ·" "$f" || sin "con adaptador el bloque no debe traer R-$n"; done
}
c_contexto_sin_adaptador() {
    local h n t b; h="$(casa)"; mkdir -p "$h/.codex"
    marco "$h"; [ $? -eq 3 ] || sin "con .codex debía salir 3"
    b="$(plano < "$h/.codex/AGENTS.md")"
    for n in 01 05 08 09 10 11 12; do grep -q "R-$n ·" "$h/.codex/AGENTS.md" || sin "falta R-$n en el bloque"; done
    for n in 03 04 06 07; do
        t="$(regla_de_la_norma "$n")"; [ -n "$t" ] || sin "no encuentro R-$n en NORMA.md"
        case "$b" in *"R-$n · $t"*) ;; *) sin "R-$n no está en el bloque con el texto de la norma" ;; esac || return 1
    done
    grep -q 'conoce por el contexto' "$h.alta" || sin "el instalador no dice que el texto va en el contexto"
    baja "$h" --aplicar || sin "baja: salida $?"
    [ ! -e "$h/.codex/AGENTS.md" ] || sin "la baja no retiró el bloque entero"
}
c_contexto_sin_adaptador_con_importacion() {
    local h f todo="" n; h="$(casa)"; mkdir -p "$h/.gemini"
    marco "$h"; [ $? -eq 3 ] || sin "con .gemini debía salir 3"
    while IFS= read -r f; do
        [ -r "$f" ] || sin "la línea @ apunta a un fichero que no existe: $f"
        todo="$todo$(cat "$f")"
    done <<EOF
$(sed -n 's/^@//p' "$h/.gemini/GEMINI.md")
EOF
    for n in 01 03 04 05 06 07 08 09 10 11 12; do
        case "$todo" in *"R-$n ·"*) ;; *) sin "falta R-$n en lo que importa GEMINI.md" ;; esac || return 1
    done
    baja "$h" --aplicar || sin "baja: salida $?"
    [ ! -e "$h/.gemini/GEMINI.md" ] || sin "la baja no retiró las líneas @"
}
c_sin_contexto_no_promete() {
    # Sin fichero de contexto global el agente no recibe nada: el instalador
    # no puede decir que conoce las reglas por el contexto.
    local h; h="$(casa)"; mkdir -p "$h/.cursor"
    marco "$h"; [ $? -eq 3 ] || sin "con .cursor debía salir 3"
    ! grep -q 'conoce por el contexto' "$h.alta" || sin "dice que el agente las conoce por un contexto que no ha escrito"
}
c_marca_citada_en_prosa() {
    local h; h="$(casa)"; mkdir -p "$h/.claude"
    printf 'Nota: la marca `# >>> alambique` abre el bloque del marco.\n' > "$h/.claude/CLAUDE.md"
    cp "$h/.claude/CLAUDE.md" "$h.antes"
    marco "$h" || sin "alta: salida $?"
    ! grep -q 'ACTUALIZADO' "$h.alta" || sin "dice ACTUALIZADO sin que hubiera bloque"
    [ "$(grep -c '^# >>> alambique' "$h/.claude/CLAUDE.md")" -eq 1 ] || sin "no puso el bloque"
    baja "$h" --aplicar || sin "baja: salida $?"
    igual "$h/.claude/CLAUDE.md" "$h.antes" "CLAUDE.md" || return 1
}
c_bloque_sin_cierre() {
    # Una marca de inicio sin su cierre: sustituir o retirar «el bloque» se
    # llevaría todo lo que la persona escribió después.
    local h; h="$(casa)"; mkdir -p "$h/.claude"
    printf 'antes\n# >>> alambique\nalgo\ndespués, mío\n' > "$h/.claude/CLAUDE.md"; cp "$h/.claude/CLAUDE.md" "$h.antes"
    marco "$h"; r=$?; [ $r -eq 1 ] || sin "con las marcas desparejadas debía salir 1 y salió $r"
    igual "$h/.claude/CLAUDE.md" "$h.antes" "CLAUDE.md (tras el alta)" || return 1
    baja "$h" --aplicar; r=$?; [ $r -eq 1 ] || sin "la baja debía salir 1 y salió $r"
    igual "$h/.claude/CLAUDE.md" "$h.antes" "CLAUDE.md (tras la baja)" || return 1
}

# --- Reglas de lectura ---------------------------------------------------------
c_reglas_de_lectura() {
    local h s pat; h="$(casa)"; mkdir -p "$h/.claude"
    marco "$h" || sin "alta: salida $?"
    s="$h/.claude/settings.json"
    grep -qF '"Read(./**/__restriccion*/**)"' "$s" || sin "la capa vedada solo se veta en la raíz"
    grep -qF "\"Read(/$h/.claude/__restriccion*/**)\"" "$s" || sin "no hay regla derivada de <conf>"
    # Lo que la plantilla del proyecto no deja versionar por ser credencial,
    # el agente tampoco lo lee.
    while IFS= read -r pat; do
        grep -qF "\"Read(./**/$pat)\"" "$s" || sin "la plantilla gitignore ignora $pat y ninguna regla lo veta"
    done <<EOF
$(awk '/^# Credenciales/ {d=1; next} d && /^#/ {exit} d && !/^!/ && NF' "$RAIZ/marco/plantillas/gitignore")
EOF
}

# --- Identidad -----------------------------------------------------------------
c_identidad() {
    local h; h="$(casa)"; mkdir -p "$h/.claude"
    command -v script >/dev/null 2>&1 || sin "no hay \`script\` para darle una terminal al instalador"
    printf 'Ana Ruiz\nana@example.org\nEjemplo SA\n' \
        | script -qec "env -i PATH='$PATH' HOME='$h' '$RAIZ/instalar.sh'" /dev/null >/dev/null 2>&1
    [ "$(grep -c '^autor_correo=ana@example.org$' "$h/.claude/_local/negocio.conf" 2>/dev/null)" = 1 ] \
        || sin "no escribió la identidad preguntada"
    [ "$(stat -c %a "$h/.claude/_local/negocio.conf")" = 600 ] || sin "negocio.conf no es 600"
}

# --- Lo propio se reconoce por su forma, no por nombrar al marco ---------------
HOOKS_MARCO="guard-remoto.sh guard-legacy-grep.sh guard-autoria-docs.sh arranque-skills.sh lib/hook.sh"
# Una copia del marco en un directorio con el nombre que da `git clone`: su
# ruta acaba escrita en el pre-commit, y así nombra al marco corra el banco
# donde corra.
clon() { local r="$BASE/alambique"
         [ -d "$r" ] || { mkdir -p "$r" && cp -R "$RAIZ/instalar.sh" "$RAIZ/marco" "$r/"; } || return 1
         printf '%s' "$r"; }
alta_de() { local r="$1" h="$2"; shift 2; limpio HOME="$h" "$r/instalar.sh" "$@" </dev/null >"$h.alta" 2>&1; }
baja_de() { local r="$1" h="$2"; shift 2; limpio HOME="$h" "$r/marco/desinstalar.sh" "$@" </dev/null >"$h.baja" 2>&1; }
# Un proyecto con un pre-commit de la persona, que deja huella cuando corre.
# Cómo estaba queda en <casa>.antes.
con_precommit_propio() { # <casa> <proyecto>
    mkdir -p "$1/.claude"; repo "$1" "$2" || return 1
    printf '#!/bin/sh\n: > "$0.huella" || exit 1\n' > "$2/.git/hooks/pre-commit"
    chmod +x "$2/.git/hooks/pre-commit"; cp "$2/.git/hooks/pre-commit" "$1.antes"
}
# El consejo del aviso: la línea de la puerta, la primera, tras el `#!`.
primera_orden() { # <pre-commit> <línea>
    { sed -n '1p' "$1"; printf '%s\n' "$2"; sed '1d' "$1"; } > "$1.nuevo" && cat "$1.nuevo" > "$1" && rm -f "$1.nuevo"
}
c_precommit_propio_encadenado() {
    local h p r pc linea x; h="$(casa)"; p="$h.proy"; pc="$p/.git/hooks/pre-commit"
    r="$(clon)" || sin "no pude copiar el marco"; con_precommit_propio "$h" "$p" || sin "no pude montar el proyecto"
    alta_de "$r" "$h" "$p"; x=$?; [ $x -eq 1 ] || sin "sobre un pre-commit propio sin encadenar debía salir 1 y salió $x"
    igual "$pc" "$h.antes" "el pre-commit propio" || return 1
    # El consejo, al pie de la letra: la línea que el aviso dice que se añada.
    linea="$(sed -n 's/^.* la línea  \(".*\/puerta\.sh" || exit 1\)$/\1/p' "$h.alta")"
    [ -n "$linea" ] || sin "el aviso no da la línea con la que encadenar"
    grep -q 'añade como primera orden .* justo después de la línea #!' "$h.alta" || sin "el aviso no dice que la línea va la primera"
    primera_orden "$pc" "$linea" || sin "no pude encadenar"; cp "$pc" "$h.antes"
    alta_de "$r" "$h" "$p"; x=$?; [ $x -eq 0 ] || sin "con la puerta encadenada debía salir 0 y salió $x"
    igual "$pc" "$h.antes" "el pre-commit propio, ya encadenado," || return 1
    grep -q 'puerta de commit  *activo' "$h.alta" || sin "la puerta encadenada no sale activa"
    # El efecto: en un commit corre lo de la persona, y la puerta detiene.
    printf 'nota\n' > "$p/nota.txt"; g "$h" -C "$p" add nota.txt
    g "$h" -C "$p" commit -q -m nota >/dev/null 2>&1 || sin "un commit inocuo no pasa"
    [ -e "$pc.huella" ] || sin "en el commit no corrió lo que la persona tenía en su pre-commit"
    printf 'dato\n' > "$p/_local/dato.txt"; g "$h" -C "$p" add -f _local/dato.txt
    ! g "$h" -C "$p" commit -q -m dato >/dev/null 2>&1 || sin "la puerta encadenada no detiene un commit con _local/"
}
c_precommit_propio_de_otro_clon() {
    # El pre-commit de la persona llama a la puerta de un clon que ya no es
    # este: el aviso dice que esa línea se sustituye, no que se añada otra.
    local h p r pc x; h="$(casa)"; p="$h.proy"; pc="$p/.git/hooks/pre-commit"
    r="$(clon)" || sin "no pude copiar el marco"; con_precommit_propio "$h" "$p" || sin "no pude montar el proyecto"
    printf '"%s/otro/marco/mecanismos/puerta.sh" || exit 1\n' "$BASE" >> "$pc"; cp "$pc" "$h.antes"
    alta_de "$r" "$h" "$p"; x=$?; [ $x -eq 1 ] || sin "con la puerta de otro clon encadenada debía salir 1 y salió $x"
    igual "$pc" "$h.antes" "el pre-commit propio" || return 1
    grep -q 'Sustituye en .* esa línea por la línea  ".*/puerta\.sh" || exit 1$' "$h.alta" || sin "el aviso no dice que la línea vieja se sustituye"
    ! grep -q 'añade como primera orden' "$h.alta" || sin "el aviso aconseja añadir otra línea junto a la que falla"
}
c_precommit_propio_con_exec() {
    # El pre-commit de la persona termina en `exec`, como el de muestra de git:
    # detrás de él la línea de la puerta no corre nunca, y no se da por activa.
    # Puesta la primera, como dice el aviso, corre ella y corre lo de la persona.
    local h p r pc linea x; h="$(casa)"; p="$h.proy"; pc="$p/.git/hooks/pre-commit"
    r="$(clon)" || sin "no pude copiar el marco"; con_precommit_propio "$h" "$p" || sin "no pude montar el proyecto"
    printf '#!/bin/sh\n: > "$0.huella"\nexec true\n' > "$pc"; cp "$pc" "$h.antes"
    alta_de "$r" "$h" "$p"
    linea="$(sed -n 's/^.* la línea  \(".*\/puerta\.sh" || exit 1\)$/\1/p' "$h.alta")"
    [ -n "$linea" ] || sin "el aviso no da la línea con la que encadenar"
    printf '%s\n' "$linea" >> "$pc"
    alta_de "$r" "$h" "$p"; x=$?; [ $x -eq 1 ] || sin "con la puerta detrás de un exec debía salir 1 y salió $x"
    grep -q 'puerta de commit  *NO ACTIVO' "$h.alta" || sin "da por activa una puerta que no se alcanza"
    grep -q 'no como primera orden' "$h.alta" || sin "no dice por qué la puerta no cuenta"
    # El control: así puesta, la puerta no detiene. Es lo que el aviso evita.
    printf 'dato\n' > "$p/_local/dato.txt"; g "$h" -C "$p" add -f _local/dato.txt
    g "$h" -C "$p" commit -q -m dato >/dev/null 2>&1 || sin "el control no vale: detrás del exec la puerta sí corrió"
    g "$h" -C "$p" rm -q --cached _local/dato.txt; g "$h" -C "$p" commit -q --no-verify -m fuera >/dev/null 2>&1
    rm -f "$pc.huella"; cp "$h.antes" "$pc"; primera_orden "$pc" "$linea" || sin "no pude encadenar"; cp "$pc" "$h.antes"
    alta_de "$r" "$h" "$p"; x=$?; [ $x -eq 0 ] || sin "con la puerta la primera debía salir 0 y salió $x"
    igual "$pc" "$h.antes" "el pre-commit propio, ya encadenado," || return 1
    grep -q 'puerta de commit  *activo' "$h.alta" || sin "la puerta, la primera, no sale activa"
    printf 'nota\n' > "$p/nota.txt"; g "$h" -C "$p" add nota.txt
    g "$h" -C "$p" commit -q -m nota >/dev/null 2>&1 || sin "un commit inocuo no pasa"
    [ -e "$pc.huella" ] || sin "en el commit no corrió lo que la persona tenía en su pre-commit"
    g "$h" -C "$p" add -f _local/dato.txt
    ! g "$h" -C "$p" commit -q -m dato >/dev/null 2>&1 || sin "la puerta, la primera, no detiene un commit con _local/"
}
c_precommit_propio_primera_orden() {
    # La puerta cuenta solo si es la primera orden: delante de ella valen un
    # comentario o una línea vacía, y ninguna orden. `@` separa lo esperado.
    local h p r pc linea espera f x; h="$(casa)"; p="$h.proy"; pc="$p/.git/hooks/pre-commit"
    r="$(clon)" || sin "no pude copiar el marco"; con_precommit_propio "$h" "$p" || sin "no pude montar el proyecto"
    linea="\"$r/marco/mecanismos/puerta.sh\" || exit 1"
    while IFS=@ read -r espera f; do
        printf '#!/bin/sh\n%s\n%s\n' "$f" "$linea" > "$pc"
        alta_de "$r" "$h" "$p"; x=$?
        case "$espera" in
            no) [ $x -eq 1 ] && grep -q 'puerta de commit  *NO ACTIVO' "$h.alta" || sin "da por activa la puerta detrás de: $f" ;;
            si) [ $x -eq 0 ] && grep -q 'puerta de commit  *activo' "$h.alta" || sin "no da por activa la puerta detrás de: $f" ;;
        esac
    done <<'EOF'
no@exit 0
no@[ -z "$(git diff --cached --name-only)" ] && exit 0
no@exec 1>&2
no@true || exit 1
no@set -e
si@# exit 0
si@
EOF
}
c_hookspath_se_dice() {
    # Con `core.hooksPath`, git no lee `.git/hooks`: la puerta va a ese
    # directorio, que es de todos los repositorios que lo usen, y se avisa.
    local h p; h="$(casa)"; p="$h.proy"; mkdir -p "$h/.claude" "$h/ganchos"; repo "$h" "$p" || sin "no pude montar el repositorio"
    alta "$h" "$p" || sin "alta sin core.hooksPath: salida $?"
    ! grep -q 'core.hooksPath' "$h.alta" || sin "control: avisa de core.hooksPath sin que esté definido"
    h="$(casa)"; p="$h.proy"; mkdir -p "$h/.claude" "$h/ganchos"; repo "$h" "$p" || sin "no pude montar el repositorio"
    g "$h" config --global core.hooksPath "$h/ganchos"
    alta "$h" "$p" || sin "alta con core.hooksPath: salida $?"
    [ -x "$h/ganchos/pre-commit" ] || sin "la puerta no está donde git la ejecuta"
    grep -q 'AVISO.*core.hooksPath.*TODOS los repositorios' "$h.alta" || sin "no avisa de que la puerta vale para todos los repositorios"
}
c_precommit_propio_baja() {
    # Sin repetir el alta: lo que se mide aquí es la baja.
    local h p r pc; h="$(casa)"; p="$h.proy"; pc="$p/.git/hooks/pre-commit"
    r="$(clon)" || sin "no pude copiar el marco"; con_precommit_propio "$h" "$p" || sin "no pude montar el proyecto"
    alta_de "$r" "$h" "$p"
    printf '"%s/marco/mecanismos/puerta.sh" || exit 1\n' "$r" >> "$pc"; cp "$pc" "$h.encadenado"
    baja_de "$r" "$h" --aplicar "$p" || sin "baja: salida $?"
    [ -e "$pc" ] || sin "la baja retiró entero un pre-commit que es de la persona"
    igual "$pc" "$h.antes" "el pre-commit propio, sin la línea de la puerta," || return 1
    [ -x "$pc" ] || sin "el pre-commit dejó de ser ejecutable"
    cmp -s "$(ls "$pc".previo.* 2>/dev/null | tail -n 1)" "$h.encadenado" || sin "no hay copia .previo del pre-commit encadenado"
}
c_precommit_propio_otra_forma() {
    # La puerta llamada dentro de una orden de la persona: quitar esa línea
    # rompería lo suyo. No se toca, sale 1 y se dice qué línea es.
    local h p r pc x; h="$(casa)"; p="$h.proy"; pc="$p/.git/hooks/pre-commit"
    r="$(clon)" || sin "no pude copiar el marco"; con_precommit_propio "$h" "$p" || sin "no pude montar el proyecto"
    alta_de "$r" "$h" "$p"
    primera_orden "$pc" "$(printf 'if ! "%s/marco/mecanismos/puerta.sh"; then exit 1; fi' "$r")"; cp "$pc" "$h.antes"
    alta_de "$r" "$h" "$p"; x=$?; [ $x -eq 0 ] || sin "con la puerta llamada como primera orden debía salir 0 y salió $x"
    igual "$pc" "$h.antes" "el pre-commit propio (tras el alta)" || return 1
    baja_de "$r" "$h" --aplicar "$p"; x=$?; [ $x -eq 1 ] || sin "sin poder retirar la llamada la baja debía salir 1 y salió $x"
    igual "$pc" "$h.antes" "el pre-commit propio (tras la baja)" || return 1
    grep -q '^    línea 2: if ! ' "$h.baja" || sin "la baja no dice qué línea hay que quitar a mano"
}
c_precommit_propio_que_nombra() {
    # Nombra al marco en un comentario y no llama a la puerta: es de la persona.
    local h p pc x; h="$(casa)"; p="$h.proy"; pc="$p/.git/hooks/pre-commit"
    con_precommit_propio "$h" "$p" || sin "no pude montar el proyecto"
    printf '# pendiente: probar la puerta de alambique\n' >> "$pc"; cp "$pc" "$h.antes"
    alta "$h" "$p"; x=$?; [ $x -eq 1 ] || sin "sobre un pre-commit propio sin encadenar debía salir 1 y salió $x"
    igual "$pc" "$h.antes" "el pre-commit propio (tras el alta)" || return 1
    grep -q 'puerta de commit  *NO ACTIVO' "$h.alta" || sin "da por activa una puerta que nadie llama"
    baja "$h" --aplicar "$p" || sin "baja: salida $?"
    igual "$pc" "$h.antes" "el pre-commit propio (tras la baja)" || return 1
}
c_hook_propio_que_nombra() {
    # Un guard y una `lib` de la persona, con el nombre de los del marco y un
    # comentario que lo nombra: se respetan en el alta y en la baja.
    local h f x; h="$(casa)"; f="$h/.claude/hooks/guard-remoto.sh"; mkdir -p "$h/.claude/hooks"
    printf '#!/bin/sh\n# el mío: lo que hace el guard de alambique, a mi manera\nexit 0\n' > "$f"; chmod +x "$f"; cp "$f" "$h.antes"
    alta "$h"; x=$?; [ $x -eq 1 ] || sin "con un guard propio debía salir 1 y salió $x"
    igual "$f" "$h.antes" "el guard propio (tras el alta)" || return 1
    grep -q 'hooks (+R-03)  *PARCIAL' "$h.alta" || sin "el resumen no dice PARCIAL: $(grep 'hooks (+R-03)' "$h.alta")"
    ! grep -q 'guard-remoto' "$h/.claude/settings.json" || sin "registró un guard que no es el del marco"
    baja "$h" --aplicar || sin "baja: salida $?"
    igual "$f" "$h.antes" "el guard propio (tras la baja)" || return 1
    h="$(casa)"; f="$h/.claude/hooks/lib/hook.sh"; mkdir -p "$h/.claude/hooks/lib"
    printf '# SPDX-License-Identifier: MIT\n#\n# mi contrato de hook; no es el de alambique\n' > "$f"; cp "$f" "$h.antes"
    alta "$h"; x=$?; [ $x -eq 1 ] || sin "con una lib propia debía salir 1 y salió $x"
    baja "$h" --aplicar || sin "baja con la lib propia: salida $?"
    igual "$f" "$h.antes" "la lib propia" || return 1
}
c_hook_propio_registrado_que_nombra() {
    # El mismo guard propio, que además nombra al marco en un comentario y
    # tiene su registro en la configuración: la baja no retira ese registro.
    local h x; h="$(casa)"; mkdir -p "$h/.claude/hooks" "$h.antes"
    printf '#!/bin/sh\n# el mío: lo que hace el guard de alambique, a mi manera\nexit 0\n' > "$h/.claude/hooks/guard-remoto.sh"
    printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"%s/.claude/hooks/guard-remoto.sh"}]}]}}\n' "$h" > "$h/.claude/settings.json"
    cp "$h/.claude/settings.json" "$h/.claude/hooks/guard-remoto.sh" "$h.antes/"
    alta "$h"; x=$?; [ $x -eq 1 ] || sin "con un guard propio debía salir 1 y salió $x"
    baja "$h" --aplicar || sin "baja: salida $?"
    igual "$h/.claude/settings.json" "$h.antes/settings.json" "settings.json (el registro del guard propio)" || return 1
    igual "$h/.claude/hooks/guard-remoto.sh" "$h.antes/guard-remoto.sh" "el guard propio" || return 1
}
c_modulos_del_directorio_actual() {
    # Se instala desde un directorio que trae un `shlex.py` propio: el
    # adaptador no lo carga, y lo que el resumen da por activo está escrito.
    local h d; h="$(casa)"; d="$h.cwd"; mkdir -p "$h/.claude" "$d"
    printf 'import sys\nsys.exit(0)\n' > "$d/shlex.py"
    ( cd "$d" && alta "$h" ) || sin "alta: salida $?"
    grep -q 'guard-remoto.sh' "$h/.claude/settings.json" 2>/dev/null || sin "el resumen dice activo y los hooks no están registrados"
}
c_marco_de_otra_instalacion() {
    # Control de los anteriores: lo que SÍ puso el marco se sigue reconociendo.
    # El clon se movió y los hooks instalados son de otra versión (el mismo
    # fichero con otro cuerpo): el alta repara la puerta y los actualiza, y la
    # baja los retira.
    local h p r r0 pc n; h="$(casa)"; p="$h.proy"; pc="$p/.git/hooks/pre-commit"; r0="$h.clon"
    r="$(clon)" || sin "no pude copiar el marco"; mkdir -p "$h/.claude"; repo "$h" "$p" || sin "no pude crear el repo"
    cp -R "$r" "$r0"; alta_de "$r0" "$h" "$p" || sin "alta desde el primer clon: salida $?"
    grep -qF "exec \"$r0/marco/mecanismos/puerta.sh\"" "$pc" || sin "control: el pre-commit no llama al primer clon"
    rm -rf "$r0"
    for n in $HOOKS_MARCO; do
        printf '# una línea que el repositorio ya no trae\n' >> "$h/.claude/hooks/$n" || sin "no pude preparar hooks/$n"
    done
    alta_de "$r" "$h" "$p" || sin "alta repetida desde el clon nuevo: salida $?"
    for n in $HOOKS_MARCO; do
        cmp -s "$h/.claude/hooks/$n" "$r/marco/mecanismos/$n" || sin "hooks/$n, de otra versión del marco, no se actualizó"
    done
    grep -qF "exec \"$r/marco/mecanismos/puerta.sh\"" "$pc" || sin "la puerta sigue llamando al clon que ya no está"
    printf 'nota\n' > "$p/nota.txt"; g "$h" -C "$p" add nota.txt
    g "$h" -C "$p" commit -q -m nota >/dev/null 2>&1 || sin "la puerta reparada no deja pasar un commit inocuo"
    baja_de "$r" "$h" --aplicar "$p" || sin "baja: salida $?"
    [ ! -e "$pc" ] || sin "la baja no retiró el pre-commit del marco"
    for n in $HOOKS_MARCO; do
        [ ! -e "$h/.claude/hooks/$n" ] || sin "la baja no retiró hooks/$n, que es del marco"
    done
}

# --- Los casos -----------------------------------------------------------------
prueba "salida 0 con adaptador (.claude)"                         c_codigo_0
prueba "salida 3 sin adaptador (.codex)"                          c_codigo_3
prueba "salida 1 sin harness (instalador de la raíz)"             c_codigo_1_sin_harness
prueba "sin harness: salida 3 y no escribe contexto"              c_sin_harness_no_escribe_contexto
prueba "dos proyectos: se rechaza antes de instalar"              c_dos_proyectos
prueba "idempotencia: la segunda pasada no cambia nada"           c_idempotencia
prueba "ida y vuelta: todo byte a byte como estaba"               c_ida_y_vuelta
prueba "ida y vuelta: la copia del original no se pisa"           c_copia_previa_no_se_pisa
prueba "ida y vuelta: lo que no existía no existe"                c_lo_que_no_existia_no_existe
prueba "ida y vuelta: un enlace colgante de la persona se queda"  c_enlace_colgante_se_queda
prueba "ida y vuelta: settings.json que no existía"               c_settings_que_no_existia
prueba "ida y vuelta: un fichero vacío que ya existía se queda"   c_fichero_vacio_que_existia
prueba "hook de la persona con nombre de guard: PARCIAL y vuelve" c_hook_de_la_persona
prueba "lib/hook.sh ajena: hooks NO ACTIVO y sin registrar"       c_lib_ajena
prueba "baja sin anotación: conservadora, y lo dice"              c_sin_anotacion
prueba "anotación parcial: lo que ya estaba no se atribuye"       c_anotacion_parcial
prueba "skills: los mensajes nombran las de este repositorio"     c_skills_del_repositorio
prueba "HOME y proyecto con espacios, de extremo a extremo"       c_espacios
prueba "repositorio del marco en una ruta con espacios"           c_repositorio_con_espacios
prueba "<conf> con carácter no ASCII: no duplica hooks"           c_no_ascii
prueba "enlaces simbólicos y modo 600 se conservan"               c_enlaces_y_modo
prueba "settings.json inválido en el alta: no se toca, salida 1"  c_settings_invalido_alta
prueba "settings.json inválido en la baja: hooks en su sitio"     c_settings_invalido_baja
prueba "proyecto en un worktree: puerta puesta y retirada"        c_worktree
prueba "subdirectorio de un repositorio: sin puerta arriba"       c_subdirectorio
prueba "baja: avisa de que la capa local queda sin ignorar"       c_baja_avisa_capa_local
prueba "core.excludesfile previo: no se reescribe y sigue activo" c_excludesfile_previo
prueba "XDG_CONFIG_HOME: el ignore de la persona sigue activo"    c_xdg_config_home
prueba "sin core.excludesfile: git ignora _local/ sin configurar" c_sin_excludesfile
prueba "core.excludesfile en un [include]: se sigue"              c_excludesfile_en_un_include
prueba "bloque puesto y sin efecto en git: NO ACTIVO"             c_bloque_puesto_y_sin_efecto
prueba "contexto con adaptador: las siete de criterio"            c_contexto_con_adaptador
prueba "contexto sin adaptador: además R-03, R-04, R-06 y R-07"   c_contexto_sin_adaptador
prueba "contexto sin adaptador y con @: dos líneas, once reglas"  c_contexto_sin_adaptador_con_importacion
prueba "sin contexto global: no promete lo que no escribe"        c_sin_contexto_no_promete
prueba "marca citada en prosa: no es un bloque"                   c_marca_citada_en_prosa
prueba "marca de inicio sin cierre: el fichero no se toca"         c_bloque_sin_cierre
prueba "reglas de lectura: profundidad, <conf> y plantilla"       c_reglas_de_lectura
prueba "identidad preguntada en una terminal"                     c_identidad
prueba "pre-commit propio y puerta encadenada: entero y activo"   c_precommit_propio_encadenado
prueba "pre-commit propio encadenado a otro clon: se dice"        c_precommit_propio_de_otro_clon
prueba "pre-commit propio que termina en exec: la puerta, la primera" c_precommit_propio_con_exec
prueba "pre-commit propio: la puerta cuenta solo si es la primera" c_precommit_propio_primera_orden
prueba "core.hooksPath: la puerta va donde git la ejecuta, y se dice" c_hookspath_se_dice
prueba "baja: de un pre-commit propio, solo la línea de la puerta" c_precommit_propio_baja
prueba "baja: la puerta llamada de otra forma no se toca, se dice" c_precommit_propio_otra_forma
prueba "pre-commit propio que nombra al marco: ni pisado ni ido"  c_precommit_propio_que_nombra
prueba "guard y lib propios que nombran al marco: se respetan"    c_hook_propio_que_nombra
prueba "guard propio registrado que nombra al marco: su registro" c_hook_propio_registrado_que_nombra
prueba "un shlex.py en el directorio actual no engaña al adaptador" c_modulos_del_directorio_actual
prueba "control: clon movido y hooks de otra versión, al día"     c_marco_de_otra_instalacion

printf '\n%s ok · %s FALLA\n' "$N_OK" "$N_FALLA"
[ "$N_FALLA" -eq 0 ]
