#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# guard-remoto.sh — Confirmación ante acción destructiva o remota (R-06, R-07).
#
# QUÉ VIGILA: la orden de shell que el agente va a ejecutar. Pide confirmación
# —la persona acepta o rechaza— en cuatro casos:
#   1. `pkill -f` con metacaracteres en el patrón.
#   2. Destructivos, se ejecuten donde se ejecuten: `pkill`/`killall`,
#      `kill -9`, `rm` recursivo o forzado, `dd`/`mkfs`, parada o reinicio de
#      servicio, `git push` que fuerza o borra y `git reset --hard`, y SQL
#      destructivo o `DELETE` sin `WHERE`. Cada uno como ORDEN: `--rm` es una
#      opción de otra, y `git rm --cached` no borra nada del disco.
#   3. Escritura cuyo DESTINO es una ruta de servidor declarada en la capa
#      local: la ruta como argumento de un verbo de escritura, o como destino
#      de una redirección. Nombrarla en una orden que lee, o que escribe en
#      otro sitio (`grep <ruta> ... > hallazgos.txt`), no pregunta.
#   4. Escritura remota: `scp` o `rsync` cuyo DESTINO —el último argumento que
#      no es opción— es `host:ruta`, y `ssh` cuyo tramo REMOTO escribe, mueve,
#      mata o reinicia. Lo que corre en el puesto después del `ssh`
#      (`> evidencia.txt`, `| tee`) no cuenta.
# Los casos 3 y 4 comparten UNA lista de formas de escritura: los verbos,
# `sed -i`, `find ... -delete` y las redirecciones.
#
# LO QUE NO VE: lee el texto de la orden, no lo que la orden hará. No sigue un
# guion que se ejecuta por su nombre, ni una ruta que llega en una variable que
# la orden no asigna, ni lo que entra a `ssh` por la entrada estándar desde un
# fichero o hacia un intérprete que no es una shell, ni las comillas `$'...'`.
# En el caso 3, copiar DESDE la ruta declarada es leerla; y no ve lo que
# escribe en ella sin ser un verbo de la lista: `rsync` local, `tar -C`,
# `install`, `unzip -d`.
# Las listas de formas —los destructivos del caso 2 y la escritura de los casos
# 3 y 4— recogen las más corrientes: son un punto de partida, pueden no estar
# completas, y cada puesto las ajusta a su caso (`V_ULTIMO`, `V_TODOS`,
# `ESCRIBE`). Fuera de ellas, y por tanto sin pregunta:
#   - En el tramo remoto de `ssh`: `docker restart`, `crontab -r`, la
#     redirección `>|`, `/etc/init.d/<servicio> restart`, `halt`, y
#     `tar x... -C <directorio>`.
#   - En SQL: `TRUNCATE <tabla>` sin la palabra `TABLE`, y un `DELETE` sin
#     `WHERE` cuando hay un `WHERE` en otra sentencia de la misma orden.
# En el caso 4, además:
#   - El destino de `scp`/`rsync` o la orden remota de `ssh` que llegan en una
#     variable, la asigne la orden o no (`CMD="rm <f>"; ssh <alias> "$CMD"`).
#   - Un `scp`/`rsync` que lleva `;`, `|` o `&` entre comillas antes del
#     destino (`--rsync-path="mkdir -p <dir> && rsync"`).
#   - Otros transportes: `sftp`, `kubectl --context`, `docker -H ssh://`,
#     `ansible`. De una orden así solo ve lo que el caso 2 ve en cualquiera.
# Y pregunta de más cuando un verbo de la lista es un argumento y no la orden
# (`ssh <alias> 'ps -ef | grep kill'`), cuando en el tramo remoto hay un `>`
# seguido de un nombre o de una variable que no es una redirección —una
# comparación de `awk` o de SQL contra un nombre, una etiqueta entre
# comillas—, cuando `systemctl` solo lee (`ssh <alias> 'systemctl status
# <servicio>'`: entra entero, con sus lecturas), cuando la orden solo está escrita
# dentro de un texto, cuando un origen remoto lleva delante una opción con su
# valor y detrás una opción suelta (`scp -P 2222 <alias>:<f> -v .`), o cuando
# en una copia local el valor de una opción tiene forma `a:b`
# (`rsync -a <dir>/ --chown www:www -v <dir>/`). Por eso pregunta y no deniega.
#
# DATO DE LA CAPA LOCAL: las rutas de servidor NO se escriben aquí — son
# coordenadas (R-03) y este fichero se copia a cada puesto. Se leen de
# <conf>/_local/rutas-cliente.conf ($ALAMBIQUE_LOCAL la cambia), o de $ALAMBIQUE_RUTAS:
# una expresión regular extendida por línea. Sin ese fichero el caso 3 no
# tiene qué mirar y calla; una línea que no vale como expresión, o que casa con
# cualquier orden, se ignora y se DICE.
#
# CONTRATO: ninguno propio. La carga de entrada y la respuesta las habla
# `lib/hook.sh`; este fichero solo detecta, y vale para cualquier harness.
#
# FALLO PROPIO: no bloquea y no calla (ver `lib/hook.sh`).
#
# Author       : Saul López
# Created Date : 2026-08-31

set -uo pipefail
GUARD="guard-remoto"
_lib="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/lib/hook.sh"
if [ ! -r "$_lib" ]; then
    # La única salida que no puede delegarse: avisa de que falta el delegado.
    printf '{"systemMessage":"%s: falta lib/hook.sh — el control NO está actuando"}\n' "$GUARD"
    exit 0
fi
# shellcheck source=lib/hook.sh
. "$_lib"

hook_leer
cmd="$(hook_orden)"
if [ -z "$cmd" ]; then
    hook_orden_ilegible && hook_avisar "$GUARD: llegó una orden y no pude leerla — el control NO está actuando"
    exit 0
fi

# Con here-string y no con tubería: bajo `pipefail`, un `grep -q` que acaba
# antes que quien le escribe devuelve fallo aunque haya encontrado.
has()  { grep -qE  -- "$1" <<< "$cmd"; }
hasi() { grep -qiE -- "$1" <<< "$cmd"; }
motivo=""

SOH=$'\001'
# Una ORDEN, no un trozo de otra palabra: delante no lleva letra, `_`, `.` ni
# `-` (`--rm`, `app.service`), y detrás tampoco `/` (`/var/log/cp/`).
_o='(^|[^[:alnum:]_.-])'
_x='([^[:alnum:]_./-]|$)'
# Un argumento ENTERO: lo que va entre comillas es una sola pieza, con sus `|`
# y sus `;` dentro. Fuera de comillas, un separador lo termina.
_arg="('[^']*'|\"[^\"]*\"|[^[:space:]|;&<>()'\"\`$SOH])+"
_args="([[:space:]]+${_arg})*[[:space:]]+"
# Fin de una orden simple: opciones sueltas, una redirección, y el separador.
_fin="([[:space:]]+-[^[:space:]]+)*[[:space:]]*([0-9]*[<>][^|;&]*)?(\$|[|;&)\`])"

# --- Qué cuenta como escritura (R-06: «escriba, mueva, mate o reinicie») ------
# UNA lista para los dos casos que la usan —la ruta de servidor declarada y el
# tramo remoto de `ssh`—: con dos, la corta deja pasar lo que la larga ve.
# Va en dos clases porque el destino no está en el mismo sitio: en `cp` y `ln`
# es el último argumento, y lo anterior solo se lee; en los demás, cualquiera.
# `systemctl` entra entero, con sus lecturas (`status`): distinguirlas exige
# enumerar subórdenes y opciones, y la que falte en la enumeración pasa sin
# pregunta. Preguntar de más ante una lectura es el lado seguro, y va
# declarado en la cabecera. De `service` solo cuentan las acciones que cambian
# el servicio.
# De `find` cuenta `-delete`: con `-exec <verbo>` el verbo ya está escrito.
# De las redirecciones, la que va a /dev/null o a otro descriptor no escribe en
# ningún sitio, y `->` y `=>` no son redirecciones.
V_ULTIMO='cp|ln'
V_TODOS='rm|rmdir|mv|mkdir|touch|chmod|chown|chgrp|truncate|shred|tee|dd|kill|pkill|killall|systemctl|reboot|shutdown|poweroff'
SED_I='(-[a-zA-Z]*i|--in-place)'
REDIR='(^|[^-=>])>>?[[:space:]]*'
ESCRIBE="${_o}(${V_ULTIMO}|${V_TODOS})${_x}"
ESCRIBE="$ESCRIBE|${_o}service[[:space:]]+[^[:space:]]+[[:space:]]+(start|stop|[a-z-]*restart|[a-z-]*reload)"
ESCRIBE="$ESCRIBE|${_o}sed[[:space:]]([^|;&]*[[:space:]])?${SED_I}"
ESCRIBE="$ESCRIBE|${_o}find[[:space:]]([^|;&]*[[:space:]])?-delete${_x}"
ESCRIBE="$ESCRIBE|${REDIR}[A-Za-z_./~\$\"'{]"
escribe() { # <texto>
    sed -E 's#[0-9&]*>>?[[:space:]]*(/dev/(null|stdout|stderr|tty)|&[0-9-])##g' <<< "$1" | grep -cE -- "$ESCRIBE" >/dev/null
}

# >>> recorrido-ssh
# Recorre la orden como la lee una shell —comillas, escapes, separadores— y
# escribe, por cada invocación de `ssh`, una línea SOH+<destino> y debajo su
# tramo REMOTO: lo que recibe la shell del destino, con un nivel de comillas
# menos. Un patrón no puede hacerlo: no sabe si un `>` o un `|` van dentro de
# unas comillas, ni a quién pertenece un here-document.
#   - `ssh` cuenta como orden: palabra entera, con ruta delante o sin ella.
#     También dentro de una cadena (`bash -c "ssh ..."`) y del cuerpo de un
#     here-document ajeno, que se recorren como órdenes; y como elemento de
#     una lista (`["ssh", "<destino>", "<orden>"]`).
#   - El tramo acaba en el primer separador sin comillas. Una redirección sin
#     comillas es del puesto, y no entra; escapada (`\>`) es del remoto.
#   - El cuerpo de un here-document entra en el tramo solo si el `<<` es de
#     ese `ssh`. Lo que le llega por una tubería, solo si el remoto es una
#     shell (o no lleva orden): ahí la entrada es el guion.
# ESTE BLOQUE ES EL MISMO en guard-remoto.sh y en guard-legacy-grep.sh; el
# instalador reparte un solo fichero de `lib/`, y es el contrato de hook.
# `pruebas/guards.sh` comprueba que las dos copias son idénticas.
recorre_ssh() {
    LC_ALL=C awk '
      # Una palabra de shell de T desde p: valor en TOK, posición siguiente en
      # POS. Devuelve 0 si antes de la palabra hay un separador o el final.
      function palabra(T, p,    L, c, q, hay) {
          L = length(T); TOK = ""; hay = 0; q = ""
          while (p <= L) {
              c = substr(T, p, 1)
              if (c == " " || c == "\t") p++
              else if (c == "\\" && substr(T, p + 1, 1) == "\n") p += 2
              else break
          }
          while (p <= L) {
              c = substr(T, p, 1)
              if (q == "") {
                  if (index(" \t\n|;&)<>`", c)) break
                  if (c == "\047" || c == "\"") { q = c; hay = 1; p++; continue }
                  if (c == "\\") { p++; c = substr(T, p, 1); if (c == "\n") { p++; continue } }
              } else {
                  if (c == q) { q = ""; p++; continue }
                  if (c == "\\" && q == "\"" && index("\"\\$`", substr(T, p + 1, 1))) { p++; c = substr(T, p, 1) }
              }
              TOK = TOK c; hay = 1; p++
          }
          POS = p
          return hay
      }
      # El tramo remoto de T desde p: texto en TR, posición del separador en
      # POS, y en HD/TAB el delimitador de su here-document si lo lleva.
      function tramo(T, p,    L, c, q, ini) {
          L = length(T); TR = ""; HD = ""; TAB = 0; q = ""; ini = p
          while (p <= L) {
              c = substr(T, p, 1)
              if (q == "") {
                  if (index("\n|;&)`", c)) break
                  if (c == "<" || c == ">") {
                      TR = TR substr(T, ini, p - ini)
                      if (substr(T, p, 3) == "<<<") { p += 3; TR = TR " " }
                      else if (substr(T, p, 2) == "<<") {
                          p += 2; if (substr(T, p, 1) == "-") { TAB = 1; p++ }
                          if (palabra(T, p)) HD = TOK
                          p = POS
                      } else {
                          p++; while (p <= L && index(">&|", substr(T, p, 1))) p++
                          palabra(T, p); p = POS
                      }
                      ini = p; continue
                  }
                  if (c == "\047" || c == "\"") { TR = TR substr(T, ini, p - ini); q = c; p++; ini = p; continue }
                  if (c == "\\") {
                      TR = TR substr(T, ini, p - ini); p++
                      if (substr(T, p, 1) == "\n") { p++; ini = p } else { ini = p; p++ }
                      continue
                  }
              } else {
                  if (c == q) { TR = TR substr(T, ini, p - ini); q = ""; p++; ini = p; continue }
                  if (c == "\\" && q == "\"" && index("\"\\$`", substr(T, p + 1, 1))) {
                      TR = TR substr(T, ini, p - ini); p++; ini = p; p++; continue
                  }
              }
              p++
          }
          TR = TR substr(T, ini, p - ini); POS = p
      }
      # El cuerpo del here-document que empieza tras el salto de línea de la
      # posición p: texto en CU, posición siguiente a su delimitador en POS.
      function cuerpo(T, p, hd, tab,    L, f, lin, cmp) {
          L = length(T); CU = ""; p++
          while (p <= L) {
              f = p; while (f <= L && substr(T, f, 1) != "\n") f++
              lin = substr(T, p, f - p); p = f + 1
              cmp = lin; if (tab) sub(/^\t+/, "", cmp)
              if (cmp == hd) break
              CU = CU lin "\n"
          }
          POS = p
      }
      function recorre(T, nivel,    L, p, c, q, a, w, borde, e_ini, previa, hd, tab, hdk, k, j, dest, t, s) {
          if (nivel > 4) return
          L = length(T); p = 1; borde = 1; e_ini = 1; previa = ""; hd = ""; hdk = 0; tab = 0
          while (p <= L) {
              c = substr(T, p, 1)
              if (c == "\n") {
                  if (hd != "") {
                      cuerpo(T, p, hd, tab); p = POS - 1; t = CU
                      if (hdk) TXT[hdk] = TXT[hdk] "\n" t
                      hd = ""; hdk = 0
                      recorre(t, nivel + 1)
                  }
                  p++; borde = 1; e_ini = p; previa = ""; continue
              }
              if (c == " " || c == "\t") { borde = 1; p++; continue }
              if (c == "\\") { p += 2; borde = (substr(T, p - 1, 1) == "\n"); continue }
              if (c == "|") {
                  if (substr(T, p + 1, 1) == "|") { previa = ""; p += 2 }
                  else { previa = substr(T, e_ini, p - e_ini); p++ }
                  borde = 1; e_ini = p; continue
              }
              if (index(";&(){`", c)) { previa = ""; borde = 1; p++; e_ini = p; continue }
              if (c == "<" && substr(T, p, 2) == "<<" && substr(T, p, 3) != "<<<") {
                  p += 2; tab = 0; if (substr(T, p, 1) == "-") { tab = 1; p++ }
                  if (palabra(T, p)) { hd = TOK; hdk = 0 }
                  p = POS; borde = 0; continue
              }
              if (c == "\047" || c == "\"") {
                  q = c; p++; a = p; w = ""
                  while (p <= L) {
                      c = substr(T, p, 1)
                      if (c == q) break
                      if (c == "\\" && q == "\"" && index("\"\\$`", substr(T, p + 1, 1))) { w = w substr(T, a, p - a); p++; a = p }
                      p++
                  }
                  w = w substr(T, a, p - a); p++; borde = 0
                  if (w == "ssh" || w ~ /\/ssh$/) { tramo(T, p); p = POS; k = ++NI; DEST[k] = ""; TXT[k] = TR }
                  else recorre(w, nivel + 1)
                  continue
              }
              a = p
              while (p <= L && !index(" \t\n\\|;&(){}<>`\"\047", substr(T, p, 1))) p++
              if (p == a) { p++; borde = 0; continue }
              w = substr(T, a, p - a); c = substr(T, p, 1)
              if (borde && (w == "ssh" || w ~ /\/ssh$/) && (c == " " || c == "\t")) {
                  # Opciones de ssh: las que llevan argumento se lo comen, pegado o no.
                  dest = ""
                  while (palabra(T, p)) {
                      p = POS
                      if (TOK == "--") { if (palabra(T, p)) { dest = TOK; p = POS }; break }
                      if (substr(TOK, 1, 1) != "-") { dest = TOK; break }
                      for (j = 2; j <= length(TOK); j++)
                          if (index("BbcDEeFIiJLlmOoPpQRSWw", substr(TOK, j, 1))) {
                              if (j == length(TOK) && palabra(T, p)) p = POS
                              break
                          }
                  }
                  sub(/^ssh:\/\//, "", dest); sub(/^.*@/, "", dest); sub(/:[0-9]+$/, "", dest)
                  tramo(T, p); p = POS; t = TR
                  k = ++NI; DEST[k] = dest
                  if (HD != "") { hd = HD; tab = TAB; hdk = k }
                  s = t; sub(/^[ \t]+/, "", s); sub(/^sudo[ \t]+/, "", s)
                  if (previa != "" && (s == "" || s ~ /^([^ \t]*\/)?(ba|k|z|da|a)?sh([ \t]|$)/)) TXT[k] = previa "\n" t
                  else TXT[k] = t
                  recorre(t, nivel + 1)
              }
              borde = 0
          }
      }
      BEGIN { RS = "\0"; NI = 0 }
      { recorre($0, 0) }
      END { for (k = 1; k <= NI; k++) printf "\001%s\n%s\n", DEST[k], TXT[k] }'
}
# <<< recorrido-ssh

# --- 1. El caso que más caro sale: patrón ERE donde parece literal ------------
# `pkill -f` recibe una expresión regular extendida. Un `|` sin escapar deja una
# rama vacía que coincide con TODO: un comando escrito para matar un proceso
# mata todos los del usuario. Parece literal y no lo es.
# Se mira el patrón de ESE `pkill`, no la orden entera: el `|` de una tubería
# no es un metacaracter del patrón. `pgrep` no entra: solo lee.
if grep -oE -- "${_o}pkill([[:space:]]+${_arg})+" <<< "$cmd" | grep -cE -- '[[:space:]]-[a-zA-Z]*f.*[][|()+?*]' >/dev/null; then
    motivo="pkill -f con METACARACTERES: el patrón es una expresión regular, y un | sin escapar alcanza TODOS tus procesos"

# --- 2. Destructivos ---------------------------------------------------------
elif has "${_o}(pkill|killall)${_x}"; then
    motivo="pkill/killall: puede alcanzar más procesos de los previstos"
elif has "${_o}kill[[:space:]]+(-9|-(SIG)?KILL|-s[[:space:]]*(9|(SIG)?KILL))\\b"; then
    motivo="kill -9: termina sin cierre limpio"
# `git rm --cached` saca del índice y deja el fichero: se aparta antes de mirar.
elif sed -E "s%${_o}git${_args}rm${_args}--cached(${_args}${_arg})*%\\1%g" <<< "$cmd" | \
     grep -cE -- "${_o}rm[[:space:]]([^|;&]*[[:space:]])?(-[a-zA-Z]*[rRf]|--recursive|--force)" >/dev/null; then
    motivo="rm recursivo o forzado"
elif has "${_o}(mkfs(\\.[a-z0-9]+)?|dd)[[:space:]]"; then
    motivo="dd/mkfs: escritura directa a dispositivo"
elif has "${_o}(systemctl|service)[[:space:]]+([^[:space:]|;&]+[[:space:]]+)*(stop|[a-z-]*restart|disable|mask|kill|reboot|poweroff|halt)\\b"; then
    motivo="parada o reinicio de servicio"
else
    # `git` admite opciones propias antes de la orden (`git -C <dir> push`).
    _git="${_o}git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+"
    # Fuerza: `-f`, `--force*` y la referencia con `+`. Borra: `--delete`, `-d`,
    # la referencia `:rama`, `--mirror` y `--prune`. La `f` o la `d` cuentan en
    # cualquier sitio de un grupo de opciones cortas: `-fu` fuerza igual que `-uf`.
    if has "${_git}push([[:space:]]+[^|;&]*)?[[:space:]](-[a-zA-Z]*[fd][a-zA-Z]*|--force[^[:space:]]*|--delete|--mirror|--prune|[+:][^[:space:]]+)([[:space:]]|\$)" \
    || has "${_git}reset[[:space:]]([^|;&]*[[:space:]])?--hard"; then
        motivo="reescritura de historia, borrado en el remoto o descarte de cambios"
    elif hasi '\b(DROP|TRUNCATE)[[:space:]]+(TABLE|DATABASE|SCHEMA)\b' \
      || { hasi '\bDELETE[[:space:]]+FROM\b' && ! hasi '\bWHERE\b'; }; then
        motivo="sentencia SQL destructiva o DELETE sin WHERE"
    fi
fi

# --- 3. Escritura sobre ruta de servidor -------------------------------------
# La lista es del puesto, no del marco: las rutas de cada uno son las suyas, y
# escribirlas aquí las publicaría.
# Cuenta el DESTINO de la escritura, no que la ruta aparezca: capturar en un
# fichero del puesto lo que se lee de la ruta es el trabajo de cada día, y un
# control que pregunta por eso se aprueba sin leer.
escribe_en_ruta() { # <rutas, unidas con |>
    local en="[\"']?[^[:space:]|;&<>()'\"\`$SOH]*($1)[^[:space:]|;&<>()\`$SOH]*"
    # la redirección va a la ruta
    has "${REDIR}${en}" && return 0
    # la ruta es argumento del verbo; en `cp` y `ln`, el último o el de `-t`
    has "${_o}(${V_TODOS})${_args}${en}" && return 0
    has "${_o}(${V_ULTIMO})${_args}${en}${_fin}" && return 0
    has "${_o}(${V_ULTIMO})${_args}(-t[[:space:]]*|--target-directory=)${en}" && return 0
    has "${_o}sed${_args}${SED_I}[^[:space:]]*${_args}${en}" && return 0
    has "${_o}sed${_args}${en}${_args}${SED_I}" && return 0
    # el verbo actúa sobre lo que `find` o una tubería sacan de la ruta
    has "${_o}find${_args}${en}(${_args}${_arg})*[[:space:]]+(-delete|-(exec|execdir|ok|okdir)[[:space:]]+(sudo[[:space:]]+)?(${V_ULTIMO}|${V_TODOS})${_x})" && return 0
    has "${en}[^;&]*\\|[[:space:]]*(sudo[[:space:]]+)?xargs${_args}(sudo[[:space:]]+)?(${V_ULTIMO}|${V_TODOS})${_x}" && return 0
    # la ruta pasa a ser el directorio de trabajo o una variable: desde ahí ya
    # no se sabe qué argumento la nombra, y cuenta cualquier escritura
    if has "${_o}(cd|pushd)[[:space:]]+${en}" \
       || has "(^|[[:space:];&|(])[A-Za-z_][A-Za-z0-9_]*=${en}" \
       || has "${_o}for[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+in[[:space:]]([^;&]*[[:space:]])?${en}"; then
        escribe "$cmd" && return 0
    fi
    return 1
}
if [ -z "$motivo" ]; then
    LISTA="${ALAMBIQUE_RUTAS:-${ALAMBIQUE_LOCAL:-$(hook_conf)/_local}/rutas-cliente.conf}"
    if [ -r "$LISTA" ]; then
        RUTAS=""; malas=""; n=0
        # `|| [ -n "$l" ]`: la última línea cuenta aunque no acabe en salto.
        while IFS= read -r l || [ -n "$l" ]; do
            n=$((n + 1))
            l="${l%$'\r'}"
            l="${l#"${l%%[![:space:]]*}"}"; l="${l%"${l##*[![:space:]]}"}"
            case "$l" in ''|\#*) continue ;; esac
            # Una entrada que casa con la orden vacía casa con todas, y un
            # control que salta siempre es un control apagado. Una que grep
            # rechaza (salida 2) apagaría además a todas las demás.
            grep -qE -- "$l" <<< "" 2>/dev/null
            if [ $? -ne 1 ]; then malas="${malas:+$malas, }$n"; continue; fi
            RUTAS="${RUTAS:+$RUTAS|}$l"
        done < "$LISTA"
        # Se dice ante una orden que escribe, que es cuando el control decide:
        # repetido en cada orden, el aviso deja de leerse.
        [ -n "$malas" ] && escribe "$cmd" && hook_avisar "$GUARD: en $LISTA se ignoran las líneas $malas: no son una expresión regular válida, o casan con cualquier orden. Esas rutas NO se están vigilando."
        if [ -n "$RUTAS" ] && has "($RUTAS)" && escribe_en_ruta "$RUTAS"; then
            motivo="escritura o borrado sobre una ruta de servidor declarada"
        fi
    fi
fi

# --- 4. Escritura remota -----------------------------------------------------
# scp y rsync escriben en el servidor cuando su DESTINO —el último argumento
# que no es opción— es `[usuario@]host:ruta`. Con el origen remoto y el destino
# local solo leen, salvo que rsync borre el origen al terminar.
# El destino es UNA palabra de shell, y puede llevar espacios dentro: entre
# comillas, en un `$( )` o escapados.
_h="([^[:space:]/:@=]+@)?[^[:space:]/:@=-][^[:space:]/:@=]*:"
_ruta="('[^']*'|\"[^\"]*\"|\\\$\\([^()]*\\)|\\\\.|[^[:space:]])*"
_rem="(\"${_h}[^\"]*\"|'${_h}[^']*'|${_h})${_ruta}"
# Detrás del destino solo caben opciones, y una opción sin `=` puede traer su
# valor en la palabra siguiente (`-P 2222`, `-e ssh`, `--exclude <patrón>`).
# No hay tabla de cuáles lo traen —la que faltara en ella haría callar—: la
# palabra que sigue a una opción cuenta como su valor. `--` no es una opción.
_opc="--?[^[:space:]=-][^[:space:]=]*([[:space:]]+${_arg})?|-${_arg}|-[^[:space:]]+"
_fin_copia="([[:space:]]+(${_opc}))*[[:space:]]*([0-9]*[<>][^|;&]*)?(\$|[|;&)\`])"
# Esa lectura vale cuando delante del `host:ruta` hay algo que copiar: una
# palabra que no es opción. Sin ella es el origen, y lo que sigue a la opción
# es el destino local (`scp host:/f -v .`).
hacia_remoto() { # <órdenes, unidas con |>
    local dst="(${_rem}|rsync://[^[:space:]]+)"
    has "${_o}($1)[[:space:]]([^|;&]*[[:space:]])?${dst}${_fin}" && return 0
    has "${_o}($1)[[:space:]]([^|;&]*[[:space:]])?[^[:space:]|;&-][^|;&]*[[:space:]]${dst}${_fin_copia}"
}
if [ -z "$motivo" ] && has "${_o}(scp|rsync)[[:space:]]"; then
    if has "${_o}rsync[[:space:]]([^|;&]*[[:space:]])?(--delete[a-z-]*|--del)\\b" && hacia_remoto rsync; then
        motivo="rsync --delete hacia un servidor remoto: además de copiar, borra en el destino lo que no está en el origen"
    elif hacia_remoto 'scp|rsync'; then
        motivo="copia hacia un servidor remoto (scp/rsync con destino host:ruta)"
    elif has "${_o}rsync[[:space:]][^|;&]*--remove-source-files" && has "${_o}rsync[[:space:]]([^|;&]*[[:space:]])?${_rem}"; then
        motivo="rsync --remove-source-files con origen remoto: borra en el servidor lo que copia"
    fi
fi

# ssh: se mira el tramo REMOTO de cada invocación, no la orden entera. Lo que
# va DESPUÉS (`| tee evidencia.txt`, `> salida.txt`) corre en el puesto:
# preguntar por ello acostumbra a aprobar sin leer.
if [ -z "$motivo" ]; then
    case "$cmd" in *ssh*)
        tramos="$(printf '%s' "$cmd" | recorre_ssh | grep -v -- "^$SOH")"
        if [ -n "$tramos" ] && escribe "$tramos"; then
            motivo="orden que escribe sobre un servidor remoto"
        fi ;;
    esac
fi

[ -z "$motivo" ] && exit 0

hook_preguntar "GUARDA (R-06/R-07): $motivo. Confirma que es intencionado y que tienes el estado previo guardado."
