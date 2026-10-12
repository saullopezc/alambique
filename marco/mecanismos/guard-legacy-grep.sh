#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# guard-legacy-grep.sh — Dos controles sobre la orden que sale por SSH (R-03).
#
# QUÉ VIGILA: toda invocación de `ssh` que haya en la orden, también dentro de
# `$( )`, de comillas invertidas, tras `;`, `|` o `&&`, y con ruta delante.
# 1) COMPATIBILIDAD: evita mandar extensiones a un host que solo trae las
#    utilidades básicas (un Unix heredado, un sistema embebido, una
#    imagen mínima). No es solo grep: `sed -E/-i`, `date -d`, `xargs -r`,
#    `find -newermt`, `cat -A`, `head/tail -c`, `pgrep -c` y `sort -V` son
#    extensiones, no estándar.
#    CLASE DE FALLO QUE EVITA: sintaxis del puesto enviada a un destino que no
#    la soporta. El destino responde "illegal option", y eso tumba el script
#    remoto o rompe la tubería en silencio. El fallo no está en el comando:
#    está en dar por hecho que el destino se parece al puesto.
#    QUÉ MIRA: el DESTINO de cada `ssh` (el primer argumento que no es opción,
#    sin `usuario@`), comparado entero con el `ssh_host` y con el `alias` de
#    cada entrada marcada; y de ahí en adelante el tramo REMOTO, con el cuerpo
#    del here-document si es de ese `ssh`. La extensión se busca entre las
#    opciones de la utilidad, en cualquier posición.
#    Si el destino llega en una variable (`h=<alias>; ssh "$h" ...`), vale el
#    destino marcado que la orden nombre en otro sitio.
#    LO QUE NO VE: un destino en una variable que la orden no asigna, el guion
#    que entra por la entrada estándar desde un fichero, y las opciones largas.
# 2) USO DE ALIAS: pide confirmación cuando se hace SSH a una coordenada
#    literal en vez de a un alias. La coordenada es un dato C2 y no debe
#    circular (R-03).
#    QUÉ MIRA: una dirección IPv4 escrita como palabra detrás de `ssh`, con
#    `usuario@` delante o sin él, que no sea reservada ni de documentación.
#    LO QUE NO VE: es la forma más corriente de coordenada, un punto de
#    partida que puede no estar completo y que cada puesto ajusta a su caso.
#    No ve un nombre de host completo (`ssh <usuario>@<host>.<dominio>`), una
#    IPv6, la dirección que va en `-o HostName=<dirección>`, la que llega en
#    una variable, ni la que se le da a otra orden (`scp`, `rsync`, `sftp`,
#    `mysql -h`). Y pregunta de más: la IPv4 cuenta también cuando es un
#    argumento del tramo remoto (`ssh <alias> 'ping <dirección>'`), cuando va
#    en una orden local unida al `ssh` con `&&` o con `&`, cuando la lleva
#    un `rsync -e ssh`, y cuando no es una dirección sino cuatro números con
#    puntos: una versión, o el tramo de un identificador más largo.
#
# DATO DE LA CAPA LOCAL: QUÉ HOSTS son de ese tipo no se escribe aquí. Se
# consulta al resolutor de alias (rasgo `legado_grep: true` en
# conexiones.yaml): un hook con hosts dentro es un fichero C2 en la
# configuración del puesto, justo lo contrario de lo que el hook protege. El
# resolutor es $ALAMBIQUE_RESOLVER o, si no,
# <conf>/skills/operacion-puesto/scripts/resolve_alias.sh. Si no existe, si
# falla, o si avisa por su salida de error de que no ha podido leer algo, el
# control 1 lo DICE y no bloquea: una fuente que deja de leerse son destinos
# marcados que dejan de verse. Sin `conexiones.yaml` no hay destinos marcados:
# el control 1 no tiene qué mirar y calla.
# COSTE: una llamada al resolutor por alias. Su interfaz da la lista de alias
# y la ficha de uno, no el `ssh_host` de todos de una vez.
#
# CONTRATO: ninguno propio. La carga de entrada y la respuesta las habla
# `lib/hook.sh`; este fichero solo detecta, y vale para cualquier harness.
# Deniega en el control 1 y pide confirmación en el 2.
#
# FALLO PROPIO: no bloquea y no calla (ver `lib/hook.sh`).
#
# Author       : Saul López
# Created Date : 2026-08-28

set -uo pipefail
GUARD="guard-legacy-grep"
_lib="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/lib/hook.sh"
if [ ! -r "$_lib" ]; then
    # La única salida que no puede delegarse: avisa de que falta el delegado.
    printf '{"systemMessage":"%s: falta lib/hook.sh — el control NO está actuando"}\n' "$GUARD"
    exit 0
fi
# shellcheck source=lib/hook.sh
. "$_lib"

RESOLVER="${ALAMBIQUE_RESOLVER:-$(hook_conf)/skills/operacion-puesto/scripts/resolve_alias.sh}"

hook_leer
cmd="$(hook_orden)"
if [ -z "$cmd" ]; then
    hook_orden_ilegible && hook_avisar "$GUARD: llegó una orden y no pude leerla — el control NO está actuando"
    exit 0
fi

# Con here-string y no con tubería: bajo `pipefail`, un `grep -q` que acaba
# antes que quien le escribe devuelve fallo aunque haya encontrado.
has(){ grep -qE -- "$1" <<< "$cmd"; }

# `ssh` como orden: a principio de línea o tras un separador, una sustitución
# o una comilla, con ruta delante o sin ella. Exigir un espacio delante deja
# fuera `x=$(ssh ...)`.
_sep='[[:space:];|&(`"'\''{]'
SSH_INI="(^|${_sep})([^[:space:];|&(\`\"'{]*/)?ssh[[:space:]]"

# Solo interesan los comandos que salen por SSH
has "$SSH_INI" || exit 0

# --- Control 1: destino sin extensiones ------------------------------------
SOH=$'\001'

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

# Nombres con los que un destino marcado puede viajar en la orden: el alias y,
# sobre todo, su `ssh_host` — la entrada `Host` de ~/.ssh/config, que es lo que
# se le escribe a `ssh`.
nombres_legados() { # <salida de --list>
    printf '%s\n' "$1" | awk 'NF && $1 != "ALIAS" && $1 !~ /^-/ { print $1 }' | \
        while read -r a; do
            "$RESOLVER" --check "$a" legado_grep true >/dev/null 2>&1 || continue
            printf '%s\n' "$a"
            "$RESOLVER" "$a" ssh_host 2>/dev/null
        done
}

if [ ! -x "$RESOLVER" ]; then
    # Sin resolutor no hay lista de hosts: el control 1 NO está actuando y se
    # dice (solo cuando hay una orden SSH, para no repetirlo en cada orden).
    hook_avisar "$GUARD: no encuentro el resolutor de alias ($RESOLVER): el control de destinos sin extensiones NO está actuando. Define ALAMBIQUE_RESOLVER o instala la skill operacion-puesto."
else
    # La lista por la salida estándar y los avisos del resolutor por la de
    # error, cada uno por su lado y en una sola llamada: las líneas de error
    # llegan marcadas con SOH. Salida 3 es «sin fuente»: un puesto sin
    # conexiones.yaml no tiene destinos marcados, y eso no es un fallo.
    todo="$( { "$RESOLVER" --list 2>&1 1>&3 3>&- | sed "s/^/$SOH/"; exit "${PIPESTATUS[0]}"; } 3>&1 )"; rc=$?
    lista="$(grep -v -- "^$SOH" <<< "$todo")"
    quejas="$(grep -c -- "^$SOH" <<< "$todo")"
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 3 ]; then
        hook_avisar "$GUARD: el resolutor de alias ($RESOLVER) falla (salida $rc): el control de destinos sin extensiones NO está actuando."
    elif [ "$quejas" -gt 0 ] && [ "$rc" -eq 0 ]; then
        # Se cuenta lo que dice, no se copia: puede citar el contenido de la fuente.
        hook_avisar "$GUARD: el resolutor de alias avisa por su salida de error ($quejas líneas) al leer las fuentes: puede haber destinos marcados que NO se están viendo. Lo que no ha leído lo dice '$RESOLVER --validar'."
    fi
    legados="$(nombres_legados "$lista" | tr '\n' ' ')"

    if [ -n "${legados// /}" ]; then
        # Destino en una variable (`h=<alias>; ssh "$h" ...`): vale el marcado
        # que la orden nombre, entero, en otro sitio.
        mencionado=""
        for n in $legados; do
            if grep -qE -- "(^|[^A-Za-z0-9._-])${n//./\\.}([^A-Za-z0-9._-]|\$)" <<< "$cmd" 2>/dev/null; then
                mencionado="$n"; break
            fi
        done
        # De todas las invocaciones de `ssh`, las que van a un destino marcado:
        # su nombre (primera línea) y sus tramos remotos.
        # El destino se compara ENTERO: `host-nuevo` no es `host`, y un nombre
        # que solo aparece dentro del comando remoto no es el destino.
        # Lo que va DESPUÉS del `ssh` (`| grep -E ...`) corre en el puesto y es
        # legítimo; bloquearlo sería un falso positivo que empuja a desactivar
        # el control, que es peor que no tenerlo.
        hallado="$(printf '%s' "$cmd" | recorre_ssh | LC_ALL=C awk -v nombres="$legados" -v mencionado="$mencionado" '
            BEGIN { n = split(nombres, N, " "); for (i = 1; i <= n; i++) ES[N[i]] = 1 }
            /^\001/ { d = substr($0, 2); if (substr(d, 1, 1) == "$") d = mencionado
                      ok = (d != "" && (d in ES)); if (ok && nombre == "") nombre = d; next }
            ok      { t = t $0 "\n" }
            END     { if (nombre != "") printf "%s\n%s", nombre, t }')"
        destino_legado="${hallado%%$'\n'*}"
        remoto=""; [ "$hallado" != "$destino_legado" ] && remoto="${hallado#*$'\n'}"

        if [ -n "$destino_legado" ] && [ -n "$remoto" ]; then
            hasr(){ grep -qE -- "$1" <<< "$remoto"; }

            # La utilidad, como palabra; y sus argumentos hasta la opción, cada
            # uno entero: un patrón entre comillas es UN argumento, y lo que
            # lleve dentro (`grep "java -Dprop"`) no es una opción de nadie.
            _u='(^|[^[:alnum:]_.-])'
            _arg="('[^']*'|\"[^\"]*\"|[^[:space:]|;&<>'\"])+"
            _ops="([[:space:]]+${_arg})*[[:space:]]+"
            # xargs lleva detrás OTRA orden con sus propias opciones (`xargs rm
            # -r`): las suyas son solo las que van antes de ella.
            _ops_x="([[:space:]]+(-[IELnPsda][[:space:]]+${_arg}|-[^[:space:]|;&]+))*[[:space:]]+"

            # Extensiones que no todas las implementaciones traen. Lo que sí es común
            # (`grep -q`, `grep -e`, `wc`, `awk`) pasa sin tocar.
            motivo=""; alternativa=""
            if   hasr "${_u}egrep([[:space:]]|\$)"; then
                motivo="egrep no está garantizado"; alternativa="usa varios 'grep -e PATRON' o awk"
            elif hasr "${_u}[fz]?grep${_ops}-[A-Za-z]*[EoP]"; then
                motivo="grep -E/-o/-P pueden no existir (illegal option)"; alternativa="grep -e PATRON (sin -E), varios grep, o awk; para -o usa awk 'match(...)'"
            elif hasr "${_u}sed${_ops}-[A-Za-z]*[Ei]"; then
                motivo="sed -E/-i son extensiones"; alternativa="sed básico (sin ERE) y escribe a fichero temporal en vez de -i"
            elif hasr "${_u}date${_ops}(-d|--date)"; then
                motivo="date -d es una extensión"; alternativa="calcula la fecha en el puesto y pásala ya resuelta, o con perl -MPOSIX (strftime/mktime)"
            elif hasr "${_u}xargs${_ops_x}-[A-Za-z]*r"; then
                motivo="xargs -r es una extensión"; alternativa="comprueba antes si la entrada está vacía"
            elif hasr "${_u}find[[:space:]].*-newermt"; then
                motivo="find -newermt es una extensión"; alternativa="usa -mtime/-newer con un fichero de referencia"
            elif hasr "${_u}cat${_ops}-[A-Za-z]*A"; then
                motivo="cat -A es una extensión"; alternativa="od -c, o cat -v con -t -e"
            elif hasr "${_u}(head|tail)${_ops}-[A-Za-z]*c"; then
                motivo="head -c / tail -c no están garantizados"; alternativa="dd bs=1 count=N, o awk"
            elif hasr "${_u}pgrep${_ops}-[A-Za-z]*c"; then
                motivo="pgrep -c es una extensión"; alternativa="pgrep ... | wc -l"
            elif hasr "${_u}sort${_ops}-[A-Za-z]*V"; then
                motivo="sort -V es una extensión"; alternativa="sort -n por campos, o sort simple"
            fi
            [ -n "$motivo" ] && hook_denegar \
"GUARDA destino sin extensiones [$destino_legado]: $motivo. Ese destino está marcado legado_grep en la capa local. En el comando REMOTO, $alternativa. Si lo que quieres filtrar es la salida YA TRAÍDA, pon el filtro en una tubería DESPUÉS del ssh: ahí sí corre el binario del puesto."
        fi
    fi
fi

# --- Control 2: SSH a coordenada literal en vez de a alias --------------------
# Solo una IPv4, y solo detrás de `ssh`: lo que queda fuera está en la cabecera.
# Se descartan las IP reservadas y de documentación: no son coordenadas de nadie.
destino_ip="$(printf '%s' "$cmd" | grep -oE "${SSH_INI}([^|;]*[[:space:]@])?([0-9]{1,3}\\.){3}[0-9]{1,3}" 2>/dev/null | \
    grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)"

if [ -n "$destino_ip" ]; then
    case "$destino_ip" in
        0.*|127.*|169.254.*|192.0.2.*|198.51.100.*|203.0.113.*) : ;;
        *)
            hook_preguntar \
"GUARDA (R-03): SSH a una coordenada literal ($destino_ip) en lugar de a un alias. La coordenada es un dato C2 y no debe circular en comandos, logs ni transcripciones. Lo correcto es 'ssh <alias>' con la entrada en ~/.ssh/config. Confirma si aún así quieres ejecutarlo."
            ;;
    esac
fi

exit 0
