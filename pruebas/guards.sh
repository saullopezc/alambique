#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# pruebas/guards.sh — Prueba funcional de los tres guards del marco.
#
# QUÉ HACE: lanza cada guard ENTERO, como queda instalado —copiado con su
# `lib/` a un <conf> temporal, con `env -i` y un HOME desechable—, y compara lo
# que responde con lo que debe responder. Cada caso que debe responder
# (`ask`, `deny`, `aviso`) va con su gemelo que debe callar: un patrón que solo
# se prueba con lo que detecta no dice nada de lo que detecta de más.
#
# POR QUÉ EL GUARD ENTERO y no el patrón suelto: el guard sanea el PATH y usa
# el grep del sistema; la shell de quien prueba puede tener otro delante, y no
# leen igual la misma expresión.
#
# USO:    pruebas/guards.sh [<raíz del repositorio>]
#         Sin argumento, la raíz es el directorio padre de este.
# SALIDA: una línea `ok` o `FALLA` por caso. Termina 0 solo si pasan todos.
#
# QUÉ COMPRUEBA ADEMÁS, en todos los casos: que la salida del guard es UN solo
# objeto JSON y que no escribe nada por la salida de error.
#
# DATOS: ninguno del puesto. Los destinos salen de `conexiones.yaml.example`,
# la identidad es inventada, y las direcciones, los accesos `usuario@host` y
# las raíces de servidor se COMPONEN al ejecutar: este fichero pasa el barrido
# del repositorio y no puede llevar ninguno escrito.
# El proyecto de prueba va FUERA de <conf>: el guard de autoría no mira la
# configuración del propio harness.
#
# DÓNDE CORRE: da igual. El guard de autoría decide por la RUTA COMPLETA del
# fichero, y la identidad la toma del `_local/negocio.conf` más cercano: bajo
# un directorio llamado `qa` o `docs`, o dentro de un proyecto con capa local,
# los mismos casos responderían otra cosa. Los temporales se crean en una base
# cuya ruta no lleve nada de eso; si $TMPDIR no vale, se usa otra y se dice.
#
# Author       : Saul López
# Created Date : 2026-10-11

set -uo pipefail

RAIZ="$(cd "${1:-$(dirname "$0")/..}" 2>/dev/null && pwd)" || { echo "no existe la raíz: ${1:-}" >&2; exit 2; }
MEC="$RAIZ/marco/mecanismos"
SKILL="$RAIZ/marco/skills/operacion-puesto"
for f in "$MEC/guard-remoto.sh" "$MEC/guard-legacy-grep.sh" "$MEC/guard-autoria-docs.sh" "$MEC/lib/hook.sh" \
         "$SKILL/scripts/resolve_alias.sh" "$SKILL/plantillas/conexiones.yaml.example"; do
    [ -r "$f" ] || { echo "falta $f" >&2; exit 2; }
done

# Una base es neutra si nada en su ruta cambia lo que los guards responden: ni
# un nombre de directorio que el de autoría mira, ni una capa local (`_local/`)
# en un ancestro, de la que saldrían la identidad y las conexiones.
neutra() { # <directorio>
    local d="$1"
    grep -qiE '(^|/)(docs?|qa|runbooks|skills|\.config)(/|$)' <<< "$d" && return 1
    while [ -n "$d" ] && [ "$d" != "/" ]; do
        [ -e "$d/_local" ] && return 1
        d="$(dirname "$d")"
    done
    return 0
}
TMP=""; descartadas=""
for base in "${TMPDIR:-/tmp}" /tmp /var/tmp; do
    base="$(cd "$base" 2>/dev/null && pwd)" || continue
    if [ -w "$base" ] && neutra "$base" && TMP="$(mktemp -d "$base/guards.XXXXXX")"; then break; fi
    TMP=""; descartadas="${descartadas:+$descartadas, }$base"
done
[ -n "$TMP" ] || { echo "no hay base neutra para los temporales (probadas: $descartadas)" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
[ -z "$descartadas" ] || echo "nota: los temporales van a $TMP; base no neutra o sin permiso: $descartadas" >&2
CONF="$TMP/conf"; PROY="$TMP/proy"
mkdir -p "$CONF/hooks" "$CONF/_local" "$TMP/home" "$PROY/docs" "$PROY/src" "$TMP/sin-lib"
cp -R "$MEC/guard-remoto.sh" "$MEC/guard-legacy-grep.sh" "$MEC/guard-autoria-docs.sh" "$MEC/lib" "$CONF/hooks/"
cp "$MEC/guard-remoto.sh" "$TMP/sin-lib/"
chmod +x "$CONF/hooks/"*.sh "$TMP/sin-lib/"*.sh
cp "$SKILL/plantillas/conexiones.yaml.example" "$CONF/_local/conexiones.yaml"
printf 'autor_nombre=Ana Ruiz\nautor_correo=ana@example.com\nfirma_doc=**Autor**: Ana Ruiz <ana@example.com>\n' \
    > "$CONF/_local/negocio.conf"

RESOLUTOR="$SKILL/scripts/resolve_alias.sh"
RES="$RESOLUTOR"                       # el resolutor que ve el guard en cada caso
RUTAS="$CONF/_local/rutas-cliente.conf"
IP="$(printf '10.20.30.%s' 40)"        # una coordenada cualquiera
LOCAL="$(printf '127.0.0.%s' 1)"       # reservada: no es coordenada de nadie
OP="operador"                          # el usuario de un acceso: va como ${OP}@<host>
OPT="/$(printf '%s%s' op t)"           # raíces de servidor, por piezas
SRV="/$(printf '%s%s' sr v)"
HOY="$(date '+%Y-%m-%d')"

total=0; fallos=0

# --- Lanzar y leer ------------------------------------------------------------
json() { # una cadena, como valor JSON
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' | \
        awk 'BEGIN { ORS = "" } NR > 1 { print "\\n" } { print }'
}
# El directorio de trabajo es el proyecto temporal: el resolutor sube por los
# ancestros buscando capas locales, y desde aquí no encuentra las del puesto.
lanza() { # <guard con ruta> <carga JSON>
    ( cd "$PROY" && printf '%s' "$2" | env -i PATH="$PATH" HOME="$TMP/home" \
        ALAMBIQUE_CONF="$CONF" ALAMBIQUE_RESOLVER="$RES" "$1" 2>"$TMP/err" )
}
# Cierto si el texto es exactamente un objeto JSON (llaves equilibradas fuera
# de las cadenas, y nada más alrededor).
un_objeto() {
    printf '%s' "$1" | awk 'BEGIN { RS = "\0" }
        { d = 0; n = 0; q = 0; mal = 0
          for (i = 1; i <= length($0); i++) {
              c = substr($0, i, 1)
              if (q) { if (c == "\\") i++; else if (c == "\"") q = 0; continue }
              if (c == "\"") q = 1
              else if (c == "{") d++
              else if (c == "}") { d--; if (d == 0) n++ }
              else if (d == 0 && c !~ /[ \t\r\n]/) mal = 1
          }
          exit !(n == 1 && d == 0 && !q && !mal) }'
}
anota() { # <guard> <espera> <salió> <descripción>
    total=$((total + 1))
    if [ "$2" = "$3" ]; then
        printf 'ok     %-8s %-10s %s\n' "$1" "$2" "$4"
    else
        fallos=$((fallos + 1))
        printf 'FALLA  %-8s %-10s %s   <-- salió: %s\n' "$1" "$2" "$4" "$3"
    fi
}

# Guards que deciden ANTES de ejecutar. <espera>: calla | ask | deny | aviso |
# ask+aviso | deny+aviso. <contiene>, si se da, tiene que estar en la
# respuesta; <no contiene>, no puede estar.
orden() { # <remoto|legacy> <espera> <orden> [<contiene> [<no contiene>]]
    local g="guard-remoto" s d a r
    [ "$1" = legacy ] && g="guard-legacy-grep"
    s="$(lanza "${GUARD_DIR:-$CONF/hooks}/$g.sh" "{\"tool_input\":{\"command\":\"$(json "$3")\"}}")"
    if [ -z "$s" ]; then r="calla"
    elif ! un_objeto "$s"; then r="salida que no es UN objeto JSON"
    else
        d="$(grep -oE '"permissionDecision":"[a-z]+"' <<< "$s" | cut -d'"' -f4)"
        a=""; case "$s" in *'"systemMessage"'*) a="aviso" ;; esac
        r="${d}${d:+${a:++}}${a}"
    fi
    [ -s "$TMP/err" ] && r="$r, y escribe por la salida de error"
    if [ -n "${4:-}" ] && [ "$r" = "$2" ]; then
        case "$s" in *"$4"*) : ;; *) r="$r, sin «$4»" ;; esac
    fi
    if [ -n "${5:-}" ]; then
        case "$s" in *"$5"*) r="$r, con «$5»" ;; esac
    fi
    anota "$1" "$2" "$r" "$(printf '%s' "${3:-(orden vacía)}" | tr '\n' ' ' | cut -c1-110)"
}

# Guard que avisa DESPUÉS de escribir. <espera>: calla, o los avisos que deben
# salir, en este orden y unidos con `+`: firma, sello, ia.
escrito() { # <espera> <fichero relativo al proyecto> <contenido, con escapes de printf %b> [<descripción> [<contiene>]]
    local s r=""
    mkdir -p "$(dirname "$PROY/$2")"
    printf '%b' "$3" > "$PROY/$2"
    s="$(lanza "$CONF/hooks/guard-autoria-docs.sh" "{\"tool_input\":{\"file_path\":\"$PROY/$2\"}}")"
    if [ -n "$s" ] && ! un_objeto "$s"; then r="salida que no es UN objeto JSON"
    else
        case "$s" in *"no lleva firma"*|*"firma NO se ha comprobado"*) r="firma" ;; esac
        case "$s" in *"no se selló"*) r="${r:+$r+}sello" ;; esac
        case "$s" in *"atribución a IA"*) r="${r:+$r+}ia" ;; esac
        [ -n "$r" ] || r="calla"
    fi
    [ -s "$TMP/err" ] && r="$r, y escribe por la salida de error"
    if [ -n "${5:-}" ] && [ "$r" = "$1" ]; then
        case "$s" in *"$5"*) : ;; *) r="$r, sin «$5»" ;; esac
    fi
    anota autoria "$1" "$r" "$2: ${4:-$(printf '%b' "$3" | tr '\n' ' ' | cut -c1-90)}"
}
FIRMA='\n\n**Autor**: Ana Ruiz <ana@example.com>\n'
CAB='# Author : Ana Ruiz\n# Created Date : 2026-01-01\n\n'
doc()    { escrito "$1" docs/c.md "$2$FIRMA" "$2"; }       # documento firmado, con una línea
codigo() { escrito "$1" "src/$2" "$CAB$3\n" "$3"; }        # código con cabecera de autoría

# =============================================================================
echo "== guard-legacy-grep · control 1: extensiones hacia un destino marcado =="
# En conexiones.yaml.example el alias `cliente-a-salto` lleva `legado_grep: true`
# y su `ssh_host` es `cliente-a-bastion`: en la orden viaja el ssh_host.
orden legacy deny  "ssh cliente-a-bastion 'grep -E foo /var/log/x'"
orden legacy calla "ssh cliente-a-bastion 'grep foo /var/log/x'"
orden legacy deny  "ssh cliente-a-salto 'grep -E foo /var/log/x'"
orden legacy calla "ssh cliente-a-salto-nuevo 'grep -E foo /var/log/x'"
orden legacy deny  "ssh ${OP}@cliente-a-bastion 'grep -E foo /var/log/x'"
orden legacy calla "ssh mi-cliente-a-bastion 'grep -E foo /var/log/x'"
orden legacy calla "ssh cliente-a-prod-app-01 'grep -E foo /var/log/x'"
# El destino es el primer argumento que no es opción, no cualquier mención
orden legacy deny  "ssh -p 2222 -o ConnectTimeout=5 cliente-a-bastion 'grep -E foo x'"
orden legacy deny  "ssh -o \"ConnectTimeout 5\" -tt cliente-a-bastion grep -E foo x"
orden legacy calla "ssh -J cliente-a-bastion cliente-a-prod-app-01 'grep -E foo x'"
orden legacy calla "ssh cliente-a-prod-app-01 'grep -E foo x; ping -c 1 cliente-a-bastion'"
# La extensión, en cualquier posición de las opciones
orden legacy deny  "ssh cliente-a-bastion 'grep -i -E foo x'"
orden legacy calla "ssh cliente-a-bastion 'grep -i -e foo x'"
orden legacy deny  "ssh cliente-a-bastion 'sed -e s/a/b/ -i f'"
orden legacy calla "ssh cliente-a-bastion 'sed -n -e 5p f'"
orden legacy deny  "ssh cliente-a-bastion 'date -u -d ayer +%F'"
orden legacy calla "ssh cliente-a-bastion 'date -u +%Y-%m-%d'"
orden legacy deny  "ssh cliente-a-bastion 'tail -n 5 -c 10 f'"
orden legacy calla "ssh cliente-a-bastion 'tail -n 5 f; head -3 f | sort -k2 -n'"
orden legacy deny  "ssh cliente-a-bastion 'ls | xargs -n 1 -r rm'"
orden legacy calla "ssh cliente-a-bastion 'ls | xargs rm -r'"
# Lo que va entre comillas es un argumento, no opciones; y pgrep no es grep
orden legacy deny  "ssh cliente-a-bastion 'ps -ef | grep -o \"java -Dfoo\"'"
orden legacy calla "ssh cliente-a-bastion 'ps -ef | grep \"java -Dfoo -Dbar\"'"
orden legacy deny  "ssh cliente-a-bastion 'pgrep -u app -c java'"
orden legacy calla "ssh cliente-a-bastion 'pgrep -P 1'"
# Solo el tramo remoto: el filtro de después corre en el puesto
orden legacy calla "ssh cliente-a-bastion 'cat /var/log/x' | grep -iE foo"
orden legacy deny  "ssh cliente-a-bastion 'cat /var/log/x | grep -iE foo'"
# ssh en cualquier sitio de la orden, y el cuerpo de un here-document
orden legacy deny  "x=\$(ssh cliente-a-bastion 'egrep foo x')"
orden legacy calla "x=\$(ssh cliente-a-prod-app-01 'egrep foo x')"
orden legacy deny  "ls; /usr/bin/ssh cliente-a-bastion 'sort -V f'"
orden legacy calla "sort -V f; ssh cliente-a-bastion"
# El destino en una variable que la misma orden asigna
orden legacy deny  "h=cliente-a-bastion; ssh \"${OP}@\$h\" 'grep -E foo x'"
orden legacy deny  "for h in cliente-a-prod-app-01 cliente-a-salto; do ssh \$h 'grep -E foo x'; done"
orden legacy calla "h=cliente-a-prod-app-01; ssh \"\$h\" 'grep -E foo x'"
orden legacy calla "h=cliente-a-salto-nuevo; ssh \"\$h\" 'grep -E foo x'"
orden legacy deny  $'ssh cliente-a-bastion bash -s <<\'EOF\'\ngrep -oE foo x\nEOF\necho fin'
orden legacy calla $'ssh cliente-a-bastion bash -s <<EOF\nls\nEOF\ngrep -E foo x'

# El ssh escrito dentro de una cadena, y lo que le entra por una tubería
orden legacy deny  "bash -c \"ssh cliente-a-bastion 'grep -E foo x'\""
orden legacy calla "bash -c \"ssh cliente-a-bastion uptime\" | grep -E foo"
orden legacy deny  "echo 'grep -E foo x' | ssh cliente-a-bastion sh"
orden legacy calla "echo 'grep -E foo x' | ssh cliente-a-bastion 'cat > f'"

echo "== guard-legacy-grep · control 2: ssh a una coordenada literal =="
orden legacy ask   "ssh $IP uptime"
orden legacy calla "ssh cliente-a-prod-app-01 uptime"
orden legacy ask   "x=\$(ssh $IP uptime)"
orden legacy calla "x=\$(ssh $LOCAL uptime)"
orden legacy ask   "echo \`ssh $IP uptime\`"
orden legacy ask   "ls;ssh ${OP}@$IP uptime"
orden legacy ask   "true&&ssh $IP uptime"
orden legacy ask   "cat lista.txt|ssh $IP 'cat > /tmp/lista.txt'"
orden legacy calla "ping -c 1 $IP; cat ~/.ssh/config"
orden legacy calla "git log --grep ssh"

echo "== guard-legacy-grep · una respuesta, un objeto; y avisa de su propio fallo =="
RES="$TMP/no-existe"
orden legacy ask+aviso "ssh $IP uptime" "no encuentro el resolutor"
orden legacy aviso     "ssh cliente-a-bastion 'grep -E foo x'" "NO está actuando"
orden legacy calla     "ls -l"
printf '#!/bin/sh\nexit 2\n' > "$TMP/resolutor-roto.sh"; chmod +x "$TMP/resolutor-roto.sh"; RES="$TMP/resolutor-roto.sh"
orden legacy aviso     "ssh cliente-a-bastion uptime" "falla (salida 2)"
printf '#!/bin/sh\nexit 3\n' > "$TMP/resolutor-sin-fuente.sh"; chmod +x "$TMP/resolutor-sin-fuente.sh"; RES="$TMP/resolutor-sin-fuente.sh"
orden legacy calla     "ssh cliente-a-bastion uptime"
# Un resolutor que sale 0 y se queja por la salida de error: se dice, y sin copiar lo que dice
printf '#!/bin/sh\necho "aviso: linea-de-la-fuente" >&2\nexit 0\n' > "$TMP/resolutor-queja.sh"; chmod +x "$TMP/resolutor-queja.sh"; RES="$TMP/resolutor-queja.sh"
orden legacy aviso     "ssh cliente-a-bastion uptime" "avisa por su salida de error" "linea-de-la-fuente"
orden legacy calla     "ls -l"
RES="$RESOLUTOR"
# Lo mismo con el resolutor del marco y una fuente que no puede leer: los
# destinos marcados dejan de verse, y el guard no puede callarlo.
grep -v '^conexiones:' "$SKILL/plantillas/conexiones.yaml.example" > "$CONF/_local/conexiones.yaml"       # sin la clave raíz
orden legacy aviso     "ssh cliente-a-bastion 'grep -E foo x'" "NO se están viendo"
sed "s/^    legado_grep/$(printf '\t')legado_grep/" "$SKILL/plantillas/conexiones.yaml.example" > "$CONF/_local/conexiones.yaml"   # sangría de tabulador
orden legacy aviso     "ssh cliente-a-bastion 'grep -E foo x'" "NO se están viendo"
cp "$SKILL/plantillas/conexiones.yaml.example" "$CONF/_local/conexiones.yaml"
orden legacy deny      "ssh cliente-a-bastion 'grep -E foo x'"
orden legacy calla     "ssh cliente-a-bastion uptime"

# =============================================================================
echo "== guard-remoto · escritura remota =="
orden remoto ask   "scp informe.txt ${OP}@servidor:$OPT/producto/"
orden remoto calla "scp ${OP}@servidor:$OPT/producto/informe.txt ."
orden remoto ask   "scp -P 2222 a.txt b.txt servidor:"
orden remoto calla "scp servidor:/a/b ./local/ 2>/dev/null"
orden remoto ask   "rsync -a --delete ./build/ servidor:$SRV/www/" "borra en el destino"
orden remoto calla "rsync -a --delete servidor:$SRV/www/ ./copia/"
orden remoto ask   "rsync -a ./build/ servidor:$SRV/www/ --dry-run"
orden remoto calla "rsync -a ./build/ ./copia/"
orden remoto ask   "rsync -a --remove-source-files servidor:/var/spool/x/ ./x/"
# El destino es el último argumento que no es opción: detrás pueden ir
# opciones, y una opción puede traer su valor en la palabra siguiente
orden remoto ask   "rsync -av ./build/ servidor:$SRV/www/ --exclude node_modules --delete" "borra en el destino"
orden remoto ask   "rsync -av --delete --exclude=node_modules ./build/ servidor:$SRV/www/" "borra en el destino"
orden remoto ask   "scp a.txt servidor:/tmp/ -P 2222"
orden remoto ask   "scp a.txt ${OP}@servidor:/tmp/ -o \"ConnectTimeout 5\" -P 2222 && echo hecho"
orden remoto ask   "rsync -a ./build/ servidor:$SRV/www/ -e ssh"
orden remoto ask   "rsync -a ./build/ servidor:$SRV/www/ --bwlimit 100"
orden remoto ask   "rsync -a ./build/ servidor:$SRV/www/ -e \"ssh -p 2222\" --bwlimit=100 2>/dev/null"
orden remoto ask   "rsync -a ./build/ servidor:$SRV/www/ --rsh=\"ssh -p 2222\""
orden remoto ask   "rsync -a ./build/ rsync://servidor/modulo/ --bwlimit 100"
orden remoto ask   "rsync -a --remove-source-files servidor:/var/spool/x/ ./x/ --bwlimit 100"
orden remoto calla "scp servidor:/etc/hosts . -P 2222"
orden remoto calla "scp -P 2222 servidor:/etc/hosts ."
orden remoto calla "scp servidor:/etc/hosts -v ."
orden remoto calla "rsync -a servidor:$SRV/www/ ./copia/ --exclude node_modules"
orden remoto calla "rsync -a servidor:$SRV/www/ --exclude node_modules ./copia/"
orden remoto calla "rsync -a -e ssh servidor:$SRV/www/ --exclude=node_modules ./copia/"
orden remoto calla "rsync -a --delete servidor:$SRV/www/ ./copia/ --bwlimit 100"
orden remoto calla "rsync -a ./build/ ./copia/ --exclude node_modules --delete"
orden remoto calla "scp servidor:/etc/hosts \"\$DIR/\" && echo \"copiado de servidor:/etc/hosts\""
orden remoto calla "scp a.txt servidor:/tmp/ -- b.txt"
# El destino es UNA palabra, y puede llevar espacios dentro
orden remoto ask   "scp a.txt \"servidor:/tmp/mi dir/\""
orden remoto ask   "rsync -a ./build/ '${OP}@servidor:$SRV/mi dir/'"
orden remoto ask   "scp a.txt servidor:\"/tmp/mi dir/\" -P 2222"
orden remoto ask   "scp a.txt servidor:/tmp/mi\\ dir/"
orden remoto ask   "scp volcado.sql servidor:/tmp/volcado_\$(date +%F).sql"
orden remoto calla "scp \"servidor:/tmp/mi dir/a.txt\" ."
orden remoto calla "scp 'servidor:/tmp/mi dir/a.txt' ./copia/ -P 2222"
orden remoto calla "rsync -a ./build/ \"./mi copia/\" --exclude 'a b'"
orden remoto ask   "ssh servidor 'sed -i s/a/b/ /etc/app.conf'"
orden remoto calla "ssh servidor 'sed -n 5p /etc/app.conf'"
orden remoto ask   "ssh servidor \"cp /etc/app.conf /tmp/app.conf.bak && tee /etc/app.conf < nuevo\""
orden remoto calla "ssh servidor 'cat /etc/app.conf' | tee evidencia.txt"
orden remoto ask   "ssh servidor 'echo hola >> notas.txt'"
orden remoto calla "ssh servidor 'cat /etc/app.conf' > copia.conf"
orden remoto calla "ssh servidor 'ls /x 2>/dev/null' 2>&1"
orden remoto calla "ssh servidor \"df -h | awk '\$5 > 80'\""
orden remoto ask   "ssh servidor 'mv a b'"
orden remoto ask   "echo 'mv a b' | ssh servidor sh"
orden remoto calla "mkdir -p salida && ssh servidor uptime > salida/u.txt"
orden remoto ask   $'ssh servidor bash -s <<\'EOF\'\nmv a b\nEOF'
orden remoto ask   $'ssh servidor \'set -e\nchmod 600 x\n\' | tee log'
orden remoto calla $'ssh servidor \'uptime\nfree -m\' | tee log'
orden remoto ask   $'ssh servidor \\\n  \'chmod 600 x\''
orden remoto ask   "ssh servidor 'sudo reboot'"
orden remoto calla "ssh servidor 'crontab -l'"
orden remoto ask   "ssh servidor 'find /var/tmp -mtime +7 -delete'"
orden remoto calla "ssh servidor 'find /var/tmp -mtime +7 -print'"
# El verbo como orden, no como trozo de un nombre ni como flecha
orden remoto ask   "ssh servidor 'service app start'"
orden remoto calla "ssh servidor 'service app status; journalctl -u app.service -n 50'"
# Cada verbo de la lista de escritura, como orden del tramo remoto
for v in rm rmdir mv mkdir touch chmod chown chgrp truncate shred tee dd kill pkill killall reboot shutdown poweroff; do
    orden remoto ask "ssh servidor '$v objetivo'"
done
orden remoto ask   "ssh servidor 'cp a b'"
orden remoto ask   "ssh servidor 'ln -s a b'"
# `systemctl` entra entero: pregunta también ante una lectura (declarado)
orden remoto ask   "ssh servidor 'systemctl status nginx'"
orden remoto ask   "ssh servidor 'systemctl daemon-reload'"
orden remoto ask   "ssh servidor 'systemctl -o cat start app'"
orden remoto ask   "ssh servidor '/bin/cp a b'"
orden remoto calla "ssh servidor 'ls -l /var/log/cp/ | grep \"->\"'"

# El ssh como ORDEN: una orden del puesto que solo lo menciona no escribe en ningún servidor
orden remoto calla "grep -rn \"ssh \" . > out.txt"
orden remoto calla "grep -rn 'ssh ' marco/ | tee /tmp/out.txt"
orden remoto calla "ls -la ~/.ssh ; cp x y"
orden remoto calla "bash -c \"ssh demo uptime\" > out.txt"
orden remoto ask   "bash -c \"ssh demo 'chmod 600 x'\""
orden remoto calla "cat lista.txt | tee copia.txt | ssh demo 'wc -l'"
# El here-document solo cuenta como guion remoto si el `<<` es de ese ssh
orden remoto calla $'cat > notas.md <<\'EOF\'\nprimero: ssh alias-demo\nluego revisar y copiar\nEOF'
orden remoto ask   $'cat > paso.sh <<\'EOF\'\nssh alias-demo \'mv a b\'\nEOF'
# El ssh como elemento de una lista, y la redirección escapada, que es del remoto
orden remoto ask   "python3 -c 'import subprocess; subprocess.run([\"ssh\",\"demo\",\"mv /a /b\"])'"
orden remoto calla "python3 -c 'import subprocess; subprocess.run([\"ssh\",\"demo\",\"uptime\"])'"
orden remoto ask   $'python3 - <<\'EOF\'\nimport subprocess\nsubprocess.run(["ssh","demo","mv /a /b"])\nEOF'
orden remoto ask   "ssh demo echo hola \\> /tmp/f"
orden remoto calla "ssh demo echo hola > /tmp/f"

echo "== guard-remoto · destructivos =="
# `rm` como orden: `--rm` es una opción, y `git rm --cached` no borra del disco
orden remoto calla "docker run --rm -v \"\$PWD\":/w -w /w gcc:13 gcc -fsyntax-only x.c"
orden remoto calla "docker compose run --rm app grep -r foo ."
orden remoto calla "git rm --cached -r dir"
orden remoto ask   "git rm -rf dir"
orden remoto ask   "ls; /bin/rm -rf build"
orden remoto ask   "git push -f origin main"
orden remoto ask   "git push origin +main"
orden remoto ask   "git push --force"
orden remoto ask   "git push --force-with-lease=main:abc origin main"
orden remoto ask   "git -C repo push --force origin main"
orden remoto ask   "git push origin :rama-vieja"
orden remoto calla "git push origin main"
orden remoto calla "git push -u origin rama-f"
orden remoto ask   "git push -fu origin rama"
orden remoto ask   "git push -uf origin rama"
orden remoto ask   "git push -du origin rama"
orden remoto calla "git push --dry-run -u origin rama"
orden remoto calla "git push -nv origin rama"
orden remoto calla "git push origin HEAD:main"
orden remoto calla "git commit -m \"no hagas push -f nunca\""
orden remoto ask   "git reset --hard"
orden remoto ask   "git reset HEAD~1 --hard"
orden remoto calla "git reset --soft HEAD~1"
orden remoto ask   "pkill -f 'java|python'" "METACARACTERES"
orden remoto ask   "pkill -f java" "más procesos de los previstos"
orden remoto ask   "pkill -f java | wc -l" "más procesos de los previstos"
orden remoto calla "pgrep -f java | wc -l"
orden remoto calla "x=\$(pgrep -f mi-servicio)"
orden remoto calla "pgrep -f 'java|python'"
orden remoto ask   "kill -9 123"
orden remoto ask   "kill -s KILL 123"
orden remoto calla "kill -0 123"
orden remoto ask   "rm -rf build"
orden remoto ask   "rm -v -R build"
orden remoto calla "rm fichero.txt"
orden remoto ask   "mkfs.ext4 /dev/sdz1"
orden remoto ask   "service app-01 restart"
orden remoto calla "systemctl status app"
orden remoto ask   "psql -c \"drop table clientes\""
orden remoto ask   "psql -c \"DELETE FROM t\""
orden remoto calla "psql -c \"delete from t where id = 1\""
orden remoto calla "ls -la; cat ~/.ssh/config"

echo "== guard-remoto · la lista de rutas de servidor =="
# Las entradas son marcadores con discriminante, como en la plantilla.
printf '# comentario\n/datos/[A-Z]{2,}/entrada/\n%s/producto[0-9]+/' "$OPT" > "$RUTAS"      # sin salto final
orden remoto ask   "cp informe.txt $OPT/producto3/salida/"
orden remoto ask   "echo hola > /datos/XX/entrada/f"
orden remoto calla "cat $OPT/producto3/salida/x.log"
orden remoto calla "cp informe.txt $OPT/producto/salida/"
# Cuenta el DESTINO de la escritura, no que la ruta se nombre
P="$OPT/producto3"
orden remoto calla "ssh demo 'ls -la $P/salida' > _local/qa/ls.txt"
orden remoto calla "echo \"revisar $P/ mañana\" >> _local/operacion/pendientes/x.md"
orden remoto calla "grep -rn \"$P/\" docs/ > hallazgos.txt"
orden remoto calla "grep -rn \"$P/\" docs/ | tee hallazgos.txt"
orden remoto ask   "grep -rn foo docs/ | tee $P/hallazgos.txt"
orden remoto ask   "echo hola >> \"$P/salida/f\""
orden remoto calla "cp $P/salida/x.log ./evidencia/"
orden remoto ask   "cp -t $P/salida/ a b"
orden remoto ask   "mv $P/salida/x.log ./evidencia/"
orden remoto calla "chmod 600 x; ls $P/"
orden remoto ask   "chmod 600 $P/x; ls"
orden remoto ask   "sed -i s/a/b/ $P/conf/x"
orden remoto calla "sed -n 5p $P/conf/x > copia.txt"
orden remoto ask   "cd $P/tmp && cp a b"
orden remoto calla "cd $P/tmp && ls -la"
orden remoto ask   "cd $P/tmp && find . -name '*.tmp' -delete"
orden remoto calla "cd $P/tmp && find . -name '*.tmp' -print"
orden remoto ask   "D=$P/tmp; touch \"\$D/x\""
orden remoto ask   "for f in $P/tmp/*.tmp; do mv \"\$f\" \"\$f.bak\"; done"
orden remoto ask   "find $P/tmp -mtime +7 -delete"
orden remoto ask   "find $P/tmp -mtime +7 | xargs chmod 600"
orden remoto calla "find $P/tmp -mtime +7 | wc -l"
orden remoto ask   "ssh demo 'touch $P/x'"
printf '%s/producto[0-9]+/\r\n/datos/[A-Z]{2,}/entrada/\r\n' "$OPT" > "$RUTAS"               # fin de línea \r\n
orden remoto ask   "cp informe.txt $OPT/producto3/salida/"
orden remoto ask   "touch /datos/XX/entrada/f"
printf '%s/producto[0-9]+/\n \n\t\n   # sangrado\n' "$OPT" > "$RUTAS"                        # líneas en blanco
orden remoto ask   "cp informe.txt $OPT/producto3/salida/"
orden remoto calla "cp a.txt b.txt"
printf '%s/producto[0-9]+/\n%s/otra[0-9/\n/x|\n%s/otra[0-9]+/\n' "$OPT" "$SRV" "$SRV" > "$RUTAS"   # una inválida, una que casa con todo
orden remoto ask+aviso "touch $SRV/otra7/x" "se ignoran las líneas 2, 3"
orden remoto aviso     "cp a.txt b.txt" "se ignoran las líneas 2, 3"
orden remoto calla     "cat $SRV/otra7/x"
rm -f "$RUTAS"
orden remoto calla "cp informe.txt $OPT/producto3/salida/"

echo "== los tres · no fallan en cerrado y no callan =="
orden remoto aviso "" "no pude leerla"
orden legacy aviso "" "no pude leerla"
GUARD_DIR="$TMP/sin-lib" orden remoto aviso "rm -rf build" "falta lib/hook.sh"

echo "== el recorrido de la orden es UNO, copiado en dos guards =="
bloque() { sed -n '/^# >>> recorrido-ssh$/,/^# <<< recorrido-ssh$/p' "$1"; }
r="distinto, o falta"
[ -n "$(bloque "$MEC/guard-remoto.sh")" ] && [ "$(bloque "$MEC/guard-remoto.sh")" = "$(bloque "$MEC/guard-legacy-grep.sh")" ] && r="idéntico"
anota los-dos idéntico "$r" "bloque recorrido-ssh de guard-remoto.sh y de guard-legacy-grep.sh"

# =============================================================================
echo "== guard-autoria-docs · atribución a IA: formas que deben verse =="
while IFS= read -r l; do doc ia "$l"; done <<'EOF'
Autor: Claude
**Autor**: Claude
| Autor | Claude |
| **Autor** | ChatGPT |
Autoría: Claude
Coautor: Claude
Authored by Claude
Analista: Gemini
Revisor: Copilot
responsable: Claude
Modified By   : Copilot
Co-Authored-By: Claude <x@example.com>
Autor: Ana Ruiz y Claude
Autor: un asistente de IA
Autor: IA
Generado con Claude
Generado automáticamente por Claude
Documento generado íntegramente con ChatGPT
Hecho con Claude
Escrito con GPT4
Redactado con GPT-4o.
Elaborado con ChatGPT
Generado con la ayuda de Claude
🤖 Generated with [Claude Code](https://claude.com)
Written by an AI assistant
Generado por IA
Generado por una IA.
AI-generated
*Generado por Claude*
_Generado por Claude_
_Generado con Claude Code_
_Documento generado por ChatGPT_
_Autor_: Claude
__Autor__: Claude
Autor: _Claude_
Autor: `Claude`
Autor:Claude
EOF

echo "== guard-autoria-docs · atribución a IA: lo que NO lo es =="
while IFS= read -r l; do doc calla "$l"; done <<'EOF'
El editor mueve el cursor al final de la línea
El autor llama a la función dos veces
Ninguna IA figura como autor, analista, editor ni revisor
Sin atribución a IA, ni Co-Authored-By
El hook guard-autoria-docs es del adaptador de Claude Code
Autor: Juan Llamas
Skill adaptada de i-have-adhd, skill de Claude Code
Generado con el script de build
Fichero creado por el instalador; la puerta llama a barrido.sh
El informe fue revisado por el equipo y el cursor queda al final
Tabla creada con un cursor sobre la consulta
Generado con make; la llama de la vela
Creado con Docker; el viento mistral no tiene nada que ver
Revisado por Devin Ortega
Responsable: María López, área de IA
Escrito por personas; ninguna IA figura como autor
Esta política prohíbe el contenido AI-generated en los commits
Creado con Docker para probar el adaptador de Claude Code
La opción generado_por_claude es un booleano
_El autor_ llama a la función dos veces
text_editor: cursor
area_responsable: IA
commit_author: Claude
Autor: Ana Ruiz; herramienta: claude_code
EOF

echo "== guard-autoria-docs · atribución a IA: en código, con cabecera y sin ella =="
codigo calla a.py   '# Tabla creada con cursor.executemany'
codigo calla b.py   '# rows written by cursor in batches'
codigo ia    c.py   '# Generated by Copilot'
codigo ia    D.java ' * @author Claude'
codigo ia    e.sh   '# Modified By   : Claude'
codigo ia    k.py   '__author__ = "Claude"'
codigo calla l.py   'is_generated_by_claude = True'
codigo calla m.py   'auto_generated_with = "make"'
codigo calla n.py   'resp = client.chat(author=user, model=claude_model)'
codigo calla o.py   'author = os.environ.get("OPENAI_AUTHOR", "")'
codigo calla p.sh   '# created with openai_api'
codigo calla q.sh   'GIT_EDITOR=cursor'
escrito ia    src/f.sh '#!/bin/sh\n# Generated with Claude\necho x\n'
escrito ia    src/g.py '# Co-Authored-By: Copilot <x@example.com>\nprint(1)\n'
escrito calla src/h.sh '#!/bin/sh\n# Tabla creada con cursor.executemany\necho x\n'
escrito calla src/i.txt 'Generado con Claude\n' 'una extensión que el guard no mira'
escrito calla src/j.js  '// Generated with Claude\n' 'otra extensión que el guard no mira'

echo "== guard-autoria-docs · atribución a IA: en todo .md, esté donde esté =="
escrito ia    NOTAS.md           'Notas\n\nGenerado con Claude\n'
escrito calla LIMPIO.md          'Notas\n\nEl autor llama a la función dos veces\n'
escrito ia    notas/2026/plan.md 'Plan\n\n**Autor**: ChatGPT\n'

echo "== guard-autoria-docs · atribución a IA: una línea ambigua no tapa la real =="
escrito ia    varias.md '| Herramienta | Uso |\n| Editor | Cursor |\ntexto\ntexto\nGenerado con Claude\n' 'ambigua en la 2, real en la 5' 'Las líneas 2, 5 parecen'
escrito ia    una.md    'texto\n| Editor | Cursor |\ntexto\n' 'solo la ambigua, en la 2' 'La línea 2 parece'
escrito ia    muchas.md 'Autor: Claude\nAutor: Claude\nAutor: Claude\nAutor: Claude\nAutor: Claude\nAutor: Claude\nAutor: Claude\n' 'siete líneas: nombra cinco' 'Las líneas 1, 2, 3, 4, 5 y 2 más parecen'
escrito calla ninguna.md 'El editor mueve el cursor\n'

echo "== guard-autoria-docs · modelos.conf: una línea que no sirve no apaga la detección =="
# La 2 no es una expresión válida y la 3 casa con cualquier cosa: se ignoran
# las dos y se dice; la 1 sigue contando, y lo que el guard ya conocía también.
printf 'modelo-x\na(b\n.*\n' > "$CONF/_local/modelos.conf"
escrito ia    m1.md 'Generado con Claude\n'   'con una línea inválida, lo de siempre se sigue viendo' 'se ignoran las líneas 2, 3'
escrito ia    m2.md 'Generado con modelo-x\n' '… y el nombre válido de la misma lista cuenta'
escrito calla m3.md 'Autor: Ana Ruiz\n'       '… y la línea que casa con todo no marca a una persona'
printf 'modelo-y\r\n' > "$CONF/_local/modelos.conf"
escrito ia    m4.md 'Generado con modelo-y\n' 'finales de línea CRLF: el nombre cuenta'
rm -f "$CONF/_local/modelos.conf"
escrito calla m5.md 'Generado con modelo-x\n' 'control: sin modelos.conf ese nombre no se conoce'

echo "== guard-autoria-docs · firma: solo los documentos de proyecto =="
escrito firma    docs/sin-firma.md    'Texto\n'
escrito calla    docs/con-pie.md      "Texto$FIRMA"
escrito calla    docs/con-cabecera.md '---\nclasificacion: C1\nresponsable: Ana Ruiz\n---\nTexto\n'
escrito firma    docs/pendiente.md    '---\nresponsable: <quien responde>\n---\nTexto\n'
escrito firma    README.md            'Texto\n'
escrito firma    qa/informe.md        'Texto\n'
escrito calla    SUELTO.md            'Texto\n'
escrito firma+ia docs/las-dos.md      'Texto\n\nGenerado con Claude\n'

echo "== guard-autoria-docs · firma: el alcance sale de la ruta completa (límite declarado) =="
# Un proyecto que cuelga de un directorio llamado `docs` o `qa` recibe el aviso
# en todo `.md`; y todo README.md cuenta, también el de `_local/`.
PROY_0="$PROY"
PROY="$TMP/neutro/proy"; escrito calla SUELTO.md       'Texto\n' 'proyecto bajo un directorio de nombre neutro'
PROY="$TMP/docs/proy";   escrito firma SUELTO.md       'Texto\n' 'proyecto bajo un directorio llamado docs'
PROY="$TMP/qa/proy";     escrito firma notas/apunte.md 'Texto\n' 'proyecto bajo un directorio llamado qa'
PROY="$PROY_0"
escrito firma _local/README.md 'Texto\n'
escrito calla _local/notas.md  'Texto\n'

echo "== guard-autoria-docs · sello: solo si la cabecera lleva fecha de modificación =="
escrito sello src/s1.sh '# Author       : Ana Ruiz\n# Created Date : 2026-01-01\n# Modified By   : Ana Ruiz\n# Modified Date : 2026-01-02\necho x\n' 'Modified Date antigua'
escrito calla src/s2.sh "# Author       : Ana Ruiz\n# Modified By   : Ana Ruiz\n# Modified Date : $HOY\necho x\n" 'Modified Date de hoy'
escrito sello src/s3.sh '# Autor : Ana Ruiz\n# Fecha de modificación : 2026-01-02\necho x\n' 'Fecha de modificación (con tilde) antigua'
escrito calla src/s4.sh '# Author       : Ana Ruiz\n# Created Date : 2026-01-01\necho x\n' 'Author y Created Date, sin campo de modificación'
escrito calla src/s5.sh '#!/bin/sh\n# Modified Date : 2026-01-02\necho x\n' 'sin línea Author'

echo
echo "casos: $total · fallan: $fallos"
[ "$fallos" -eq 0 ]
