#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# puerta_barrido.sh — Banco de prueba de la puerta de commit y del barrido.
#
# Uso:
#   pruebas/puerta_barrido.sh [raíz]   raíz del repositorio que se prueba
#                                      (por defecto, la de este script)
#
# Salidas: 0 todos los casos pasan · 1 alguno falla · 2 no se pudo montar
#
# Cada caso va CON SU CONTROL: lo que debe detenerse y el gemelo que debe pasar.
# Un banco que solo comprueba que algo se detiene no distingue una puerta que
# funciona de una que lo detiene todo.
#
# La puerta se prueba por su EFECTO: se intenta un `git commit` de verdad, con
# la puerta puesta como pre-commit, y se mira si el commit existe. El barrido,
# por su código de salida y por lo que imprime.
#
# Es autosuficiente y no toca el puesto: monta repositorios temporales con un
# HOME desechable y sin red, y los borra al salir.
#
# Las IP, los hosts, las rutas de servidor y los valores de prueba se COMPONEN
# al ejecutar: este fichero no contiene ninguno y pasa el barrido que prueba.
#
# Author       : Saul López
# Created Date : 2026-10-11

set -uo pipefail
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
unset -f grep sed awk find head cut sort tr wc cat 2>/dev/null || true
unset CDPATH

RAIZ="$(cd -- "${1:-$(dirname "$0")/..}" 2>/dev/null && pwd)" \
    || { printf 'no existe la raíz indicada\n' >&2; exit 2; }
PUERTA="$RAIZ/marco/mecanismos/puerta.sh"
BARRIDO="$RAIZ/marco/mecanismos/barrido.sh"
for s in "$PUERTA" "$BARRIDO"; do
    [ -x "$s" ] || { printf 'no encuentro %s, o no es ejecutable\n' "$s" >&2; exit 2; }
done

TMP="$(mktemp -d)" || exit 2
trap 'chmod -R u+rw "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/casa/conf" "$TMP/puesto"

# Entorno vacío: ni la configuración de git ni la lista de marcas del puesto
# entran en la prueba.
ENT=(env -i PATH="$PATH" HOME="$TMP/casa" ALAMBIQUE_CONF="$TMP/casa/conf"
     GIT_CONFIG_NOSYSTEM=1
     GIT_AUTHOR_NAME=Prueba GIT_AUTHOR_EMAIL=prueba@example.org
     GIT_COMMITTER_NAME=Prueba GIT_COMMITTER_EMAIL=prueba@example.org)
G() { "${ENT[@]}" git "$@"; }

# --- Material de prueba, compuesto ---------------------------------------------
IP="$(printf '10.20.30.%s' 40)"          # una IP privada cualquiera
IP_BAJA="$(printf '10.0.0.%s' 7)"
SUBRED="$(printf '10.0.0.%s/24' 0)"      # contiene la «cualquiera» como subcadena
IP_110="$(printf '110.0.0.%s' 0)"        # ídem
VERSION="$(printf '1.2.3.%s' 4)"
DOC1="$(printf '192.0.2.%s' 10)"; DOC2="$(printf '198.51.100.%s' 7)"; DOC3="$(printf '203.0.113.%s' 9)"
LAZO="$(printf '127.0.0.%s' 1)"; NULA="$(printf '0.0.0.%s' 0)"; DIFUSION="$(printf '255.255.255.%s' 255)"
ACCESO="$(printf '%s operador@%s' ssh "$IP")"
HOST="$(printf 'db01.interna.%s' corp)"
SERVIDOR="$(printf '/%s/acme/volcado' opt)"
EXENTA="$(printf '# alambique: %s' exento)"
CLAVE="$(printf -- '-----BEGIN RSA %s KEY-----' PRIVATE)"

# --- Utilidades ------------------------------------------------------------------
N=0; MAL=0
comprobar() {  # <caso> <esperado> <obtenido>
    N=$((N+1))
    if [ "$2" = "$3" ]; then
        printf 'ok     %s\n' "$1"
    else
        printf 'FALLA  %s — esperado: %s · obtenido: %s\n' "$1" "$2" "$3"
        MAL=$((MAL+1))
    fi
}

# Repositorio nuevo con un commit inicial y, como pre-commit, la puerta que se
# indique (por defecto, la que se prueba). El hook es el mismo que escribe el
# instalador: una línea que llama a la puerta por su ruta.
repo_nuevo() {  # [puerta]
    local r
    r="$(mktemp -d "$TMP/repo.XXXXXX")"
    G -C "$r" -c init.defaultBranch=principal init -q
    printf 'inicio\n' > "$r/LEEME.md"
    G -C "$r" add LEEME.md
    G -C "$r" commit -q --no-verify -m inicio
    printf '#!/usr/bin/env bash\nexec "%s"\n' "${1:-$PUERTA}" > "$r/.git/hooks/pre-commit"
    chmod +x "$r/.git/hooks/pre-commit"
    printf '%s' "$r"
}

# Intenta el commit de lo preparado. Dice «hecho» o «detenido» según exista o
# no un commit nuevo; lo que imprimió la puerta queda en $TMP/salida.
entregar() {  # <repo>
    local antes
    antes="$(G -C "$1" rev-parse HEAD)"
    G -C "$1" commit -q -m prueba > "$TMP/salida" 2>&1
    if [ "$(G -C "$1" rev-parse HEAD)" != "$antes" ]; then echo hecho; else echo detenido; fi
}

# Prepara un fichero con una línea y entrega. El nombre se usa tal cual.
entregar_fichero() {  # <nombre> <línea> [opción de git add]
    local r; r="$(repo_nuevo)"
    mkdir -p "$r/$(dirname "$1")"
    printf '%s\n' "$2" > "$r/$1"
    G -C "$r" add ${3:+"$3"} -- "$1"
    entregar "$r"
}

# Código de salida del barrido; su salida queda en $TMP/salida y $TMP/error.
barrer() {  # <directorio de trabajo> [argumentos del barrido]
    local d="$1"; shift
    ( cd "$d" && "${ENT[@]}" ${LOCAL:+ALAMBIQUE_LOCAL="$LOCAL"} ${REGION:+LC_ALL="$REGION"} "$BARRIDO" "$@" ) \
        > "$TMP/salida" 2> "$TMP/error"
    echo $?
}
LOCAL=""; REGION=""

# Código del barrido sobre un directorio con un único fichero de una línea.
barrer_linea() {  # <línea>
    local d; d="$(mktemp -d "$TMP/arbol.XXXXXX")"
    printf '%s\n' "$1" > "$d/nota.md"
    barrer "$d" .
}

dice() {  # <fichero> <texto> → sí | no
    if grep -qF -- "$2" "$1"; then echo sí; else echo no; fi
}

# --- Sin regresión -----------------------------------------------------------------
printf '\nsin regresión\n'
comprobar 'un commit limpio pasa la puerta'              hecho    "$(entregar_fichero notas.md 'nada que ver aquí')"
comprobar 'una IP en notas.md detiene el commit'         detenido "$(entregar_fichero notas.md "host $IP")"
d="$(mktemp -d "$TMP/arbol.XXXXXX")"; printf 'host %s\n' "$IP_BAJA" > "$d/nota.md"
comprobar 'barrido: una IP da ALTA y sale 1'             1        "$(barrer "$d" .)"
comprobar 'barrido: por defecto no enseña la IP'         no       "$(dice "$TMP/salida" "$IP_BAJA")"
comprobar 'barrido: con --full sale 1 igual'             1        "$(barrer "$d" . --full)"
comprobar 'barrido: … y la enseña'                       sí       "$(dice "$TMP/salida" "$IP_BAJA")"
comprobar 'barrido: un árbol limpio sale 0'              0        "$(barrer_linea 'nada que ver aquí')"
comprobar 'barrido: --help sale 0'                       0        "$(barrer "$TMP" --help)"
comprobar 'barrido: --help enseña el uso'                sí       "$(barrer "$TMP" --help >/dev/null; dice "$TMP/salida" '--staged')"
r="$(repo_nuevo)"; printf 'host %s\n' "$IP" > "$r/a.md"; G -C "$r" add a.md
comprobar 'barrido: --staged ve lo preparado y sale 1'   1        "$(barrer "$r" --staged)"
r="$(repo_nuevo)"; printf 'host %s\n' "$IP" > "$r/a.md"
comprobar 'barrido: --staged no mira lo sin preparar'    0        "$(barrer "$r" --staged)"
r="$(repo_nuevo)"; printf 'base en %s\n' "$HOST" > "$r/a.md"; G -C "$r" add a.md
comprobar 'barrido: un host interno es MEDIA y sale 2'   2        "$(barrer "$r" --staged)"
comprobar 'un hallazgo MEDIA no detiene el commit'       hecho    "$(entregar "$r")"

# --- Nombres de fichero ---------------------------------------------------------
printf '\nnombres con ñ, tildes, espacios y saltos de línea\n'
comprobar 'IP en notas-año.md detiene el commit'         detenido "$(entregar_fichero 'notas-año.md' "host $IP")"
comprobar 'notas-año.md sin IP pasa'                     hecho    "$(entregar_fichero 'notas-año.md' 'nada que ver aquí')"
comprobar 'IP en «mi nota.md» detiene el commit'         detenido "$(entregar_fichero 'mi nota.md' "host $IP")"
comprobar '«mi nota.md» sin IP pasa'                     hecho    "$(entregar_fichero 'mi nota.md' 'nada que ver aquí')"
PARTIDO=$'dos\nrenglones.md'
comprobar 'IP en un nombre con salto de línea detiene'   detenido "$(entregar_fichero "$PARTIDO" "host $IP")"
comprobar 'el mismo nombre sin IP pasa'                  hecho    "$(entregar_fichero "$PARTIDO" 'nada que ver aquí')"
comprobar '_local/plano.md forzado detiene el commit'    detenido "$(entregar_fichero '_local/plano.md' 'apunte' -f)"
comprobar '_local/configuración.md forzado detiene'      detenido "$(entregar_fichero '_local/configuración.md' 'apunte' -f)"
comprobar '_local/«mi apunte.md» forzado detiene'        detenido "$(entregar_fichero '_local/mi apunte.md' 'apunte' -f)"
comprobar 'el esqueleto (_local/README.md) pasa'         hecho    "$(entregar_fichero '_local/README.md' 'capa local' -f)"
comprobar 'el esqueleto (_local/año/.gitkeep) pasa'      hecho    "$(entregar_fichero '_local/año/.gitkeep' '' -f)"
comprobar 'un README más abajo no es esqueleto'          detenido "$(entregar_fichero '_local/cliente/README.md' 'apunte' -f)"
comprobar '__restriccion/llave.txt forzado detiene'      detenido "$(entregar_fichero '__restriccion/llave.txt' 'apunte' -f)"
comprobar 'la capa vedada más abajo también detiene'     detenido "$(entregar_fichero 'sub/__restriccion/llave.txt' 'apunte' -f)"
comprobar 'el esqueleto (__restriccion/README.md) pasa'  hecho    "$(entregar_fichero '__restriccion/README.md' 'capa vedada' -f)"
# Sin el barrido a su lado la puerta no puede comprobar, y no deja pasar.
mkdir -p "$TMP/sola"; cp "$PUERTA" "$TMP/sola/puerta.sh"
r="$(repo_nuevo "$TMP/sola/puerta.sh")"; printf 'nada\n' > "$r/a.md"; G -C "$r" add .
comprobar 'la puerta sin barrido.sh al lado: detenido'   detenido "$(entregar "$r")"
comprobar '… y dice por qué'                             sí       "$(dice "$TMP/salida" 'no encuentro barrido.sh')"
r="$(repo_nuevo)"; printf 'host %s\n' "$IP" > "$r/diseño.md"
comprobar 'barrido de un árbol git: IP en diseño.md, 1'  1        "$(barrer "$r" .)"
printf 'nada que ver aquí\n' > "$r/diseño.md"
comprobar 'barrido de un árbol git: diseño.md limpio, 0' 0        "$(barrer "$r" .)"
# Lo preparado que no se puede leer: se quita del almacén el objeto del fichero.
r="$(repo_nuevo)"; printf 'host %s\n' "$IP" > "$r/a.md"; G -C "$r" add a.md
comprobar 'barrido: lo preparado se lee (control), 1'    1        "$(barrer "$r" --staged)"
o="$(G -C "$r" rev-parse :a.md)"; rm -f "$r/.git/objects/${o%"${o#??}"}/${o#??}"
comprobar 'barrido: si no puede leerlo, error (3)'       3        "$(barrer "$r" --staged)"

# --- Renombrados y cambios de tipo ----------------------------------------------
printf '\nrenombrados y cambios de tipo\n'
guia() { local r; r="$(repo_nuevo)"; seq 1 40 | sed 's/^/renglón de la guía /' > "$r/guia.md"
         G -C "$r" add guia.md; G -C "$r" commit -q --no-verify -m guia; printf '%s' "$r"; }
r="$(guia)"; G -C "$r" mv guia.md manual.md; printf '%s\n' "$ACCESO" >> "$r/manual.md"; G -C "$r" add manual.md
comprobar 'git lo ve como renombrado (control)'          sí       "$(G -C "$r" status --short > "$TMP/estado"; dice "$TMP/estado" 'R  guia.md -> manual.md')"
comprobar 'renombrado + línea con acceso: detenido'      detenido "$(entregar "$r")"
r="$(guia)"; G -C "$r" mv guia.md manual.md
comprobar 'renombrado sin contenido nuevo: pasa'         hecho    "$(entregar "$r")"
r="$(guia)"; rm "$r/guia.md"; ln -s "nodo-$IP" "$r/guia.md"; G -C "$r" add guia.md
comprobar 'fichero que pasa a enlace con IP: detenido'   detenido "$(entregar "$r")"
r="$(guia)"; rm "$r/guia.md"; ln -s LEEME.md "$r/guia.md"; G -C "$r" add guia.md
comprobar 'fichero que pasa a enlace inocuo: pasa'       hecho    "$(entregar "$r")"

# --- Cada IP de la línea, por separado --------------------------------------------
printf '\ncada IP se juzga por separado y entera\n'
comprobar 'IP real junto a un loopback: 1'               1 "$(barrer_linea "nodo $IP (antes $LAZO)")"
comprobar 'subred que contiene la «cualquiera»: 1'       1 "$(barrer_linea "red $SUBRED")"
comprobar 'IP que contiene la «cualquiera»: 1'           1 "$(barrer_linea "host $IP_110")"
comprobar 'IP real junto a rangos de documentación: 1'   1 "$(barrer_linea "de $DOC1 a $IP")"
comprobar 'IP real y la palabra «version» al lado: 1'    1 "$(barrer_linea "nodo $IP (version 2 del plano)")"
comprobar 'IP que cierra la frase, con su punto: 1'      1 "$(barrer_linea "el nodo está en $IP.")"
comprobar 'loopback y «cualquiera» solos: 0'             0 "$(barrer_linea "escucha en $LAZO y en $NULA")"
comprobar 'difusión sola: 0'                             0 "$(barrer_linea "difusión $DIFUSION")"
comprobar 'los tres rangos de documentación: 0'          0 "$(barrer_linea "ejemplos: $DOC1, $DOC2 y $DOC3")"
comprobar 'número de versión tras «version»: 0'          0 "$(barrer_linea "\"version\": \"$VERSION\"")"
comprobar 'número de versión con v delante: 0'           0 "$(barrer_linea "publicada la v$VERSION")"
comprobar 'número de versión con sufijo: 0'              0 "$(barrer_linea "paquete $VERSION-beta")"
comprobar 'nombre de fichero con cuatro cifras: 0'       0 "$(barrer_linea "baja lib-$VERSION.tar.gz")"

# --- El barrido que no puede barrer ----------------------------------------------
printf '\nun barrido que no puede barrer no dice «limpio»\n'
d="$(mktemp -d "$TMP/arbol.XXXXXX")"; printf 'host %s\n' "$IP" > "$d/nota.md"
comprobar 'ruta que existe, con IP (control): 1'         1  "$(barrer "$d" .)"
comprobar 'ruta inexistente: error (3)'                  3  "$(barrer "$d" "$TMP/no/existe")"
comprobar '… y lo dice por la salida de error'           sí "$([ -s "$TMP/error" ] && echo sí || echo no)"
comprobar 'opción mal escrita: error (3)'                3  "$(barrer "$d" --stagged)"
comprobar '… y lo dice por la salida de error'           sí "$([ -s "$TMP/error" ] && echo sí || echo no)"
comprobar 'dos rutas: error (3), no se calla la primera' 3  "$(barrer "$d" . "$TMP/casa")"
comprobar '--staged fuera de un repositorio: error (3)'  3  "$(barrer "$d" --staged)"
# Cómo lee la puerta el código del barrido: se le pone al lado un barrido falso.
falsa() {  # <cuerpo del barrido falso> → ruta de una puerta con ese barrido al lado
    local d; d="$(mktemp -d "$TMP/falsa.XXXXXX")"
    cp "$PUERTA" "$d/puerta.sh"
    printf '#!/usr/bin/env bash\n%s\n' "$1" > "$d/barrido.sh"; chmod +x "$d/puerta.sh" "$d/barrido.sh"
    printf '%s' "$d/puerta.sh"
}
con_barrido_falso() {  # <cuerpo> → hecho | detenido
    local r; r="$(repo_nuevo "$(falsa "$1")")"
    printf 'nada\n' > "$r/a.md"; G -C "$r" add a.md
    entregar "$r"
}
comprobar 'la puerta con un barrido que sale 0: pasa'    hecho    "$(con_barrido_falso 'exit 0')"
comprobar 'la puerta con un barrido que sale 3: detiene' detenido "$(con_barrido_falso 'echo roto >&2; exit 3')"
comprobar 'la puerta con un barrido que muere: detiene'  detenido "$(con_barrido_falso 'kill -9 $$')"
comprobar 'la puerta fuera de un repositorio: falla'     1        "$(cd "$TMP" && "${ENT[@]}" "$PUERTA" >/dev/null 2>&1; echo $?)"

# --- Miles de hallazgos MEDIA ----------------------------------------------------
printf '\nMEDIA no detiene nunca\n'
MILES='i=0; while [ $i -lt 6000 ]; do i=$((i+1)); printf "  MEDIA fichero-largo-de-prueba.md:%s\n        texto\n" $i; done; exit 2'
comprobar 'seis mil MEDIA: el commit pasa'               hecho    "$(con_barrido_falso "$MILES")"
comprobar '… y la puerta avisa de ellos'                 sí       "$(dice "$TMP/salida" 'MEDIA fichero-largo-de-prueba.md:1')"
comprobar 'un ALTA entre ellos (sale 1): detiene'        detenido "$(con_barrido_falso "${MILES%exit 2}exit 1")"

# --- Una exención se dice ---------------------------------------------------------
printf '\nla puerta nombra los exentos\n'
r="$(repo_nuevo)"; printf '%s\nhost %s\n' "$EXENTA" "$IP" > "$r/catalogo exento.md"; G -C "$r" add .
comprobar 'fichero exento con IP: el commit pasa'        hecho    "$(entregar "$r")"
comprobar '… la puerta dice que hubo un exento'          sí       "$(dice "$TMP/salida" '1 fichero(s) exento(s)')"
comprobar '… y dice cuál'                                sí       "$(dice "$TMP/salida" 'catalogo exento.md')"
r="$(repo_nuevo)"; printf 'sobre la marca «alambique: exento»\nhost %s\n' "$IP" > "$r/catalogo.md"; G -C "$r" add .
comprobar 'nombrar la marca en prosa no exime: detenido' detenido "$(entregar "$r")"
# La exención es un comentario: con su signo exime, la frase suelta no.
EXENTO_F="$(printf 'alambique: %s' exento)"
for forma in "/* $EXENTO_F */" "<!-- $EXENTO_F -->" "// $EXENTO_F" "-- $EXENTO_F" "; $EXENTO_F"; do
    r="$(repo_nuevo)"; printf '%s\nhost %s\n' "$forma" "$IP" > "$r/catalogo.txt"; G -C "$r" add .
    comprobar "exención «${forma%% *} …»: el commit pasa"   hecho    "$(entregar "$r")"
done
for forma in "$EXENTO_F" "- $EXENTO_F" "% $EXENTO_F"; do
    r="$(repo_nuevo)"; printf '%s\nhost %s\n' "$forma" "$IP" > "$r/catalogo.txt"; G -C "$r" add .
    comprobar "«$forma»: sin signo de comentario conocido, no exime" detenido "$(entregar "$r")"
done
r="$(repo_nuevo)"; printf 'nada\n' > "$r/a.md"; G -C "$r" add .
comprobar 'sin exentos, el commit pasa'                  hecho    "$(entregar "$r")"
comprobar '… y la puerta no habla de exentos'            no       "$(dice "$TMP/salida" 'exento')"

# --- Un barrido que no detecta no dice «limpio» ------------------------------------
printf '\nel barrido se comprueba antes de barrer\n'
# Copia del barrido con una utilidad que falla puesta delante en su PATH.
mkdir -p "$TMP/ciego/arbol"
printf 'host %s\n' "$IP" > "$TMP/ciego/arbol/a.txt"
comprobar 'control: con las utilidades del sistema ve la IP, 1' 1 "$(barrer "$TMP/ciego/arbol" .)"
for u in awk sed; do
    mkdir -p "$TMP/ciego/$u"; printf '#!/bin/sh\nexit 127\n' > "$TMP/ciego/$u/$u"; chmod +x "$TMP/ciego/$u/$u"
    sed "s#^PATH=.*#PATH=$TMP/ciego/$u:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin#" "$BARRIDO" > "$TMP/ciego/barrido-$u.sh"
    chmod +x "$TMP/ciego/barrido-$u.sh"
    ( cd "$TMP/ciego/arbol" && "${ENT[@]}" "$TMP/ciego/barrido-$u.sh" . ) > "$TMP/salida" 2> "$TMP/error"
    comprobar "con un $u que falla no dice limpio: sale 3"  3        "$?"
    comprobar '… y dice que es la autocomprobación'          sí       "$(dice "$TMP/error" 'autocomprobación')"
done

# --- Sin lista de marcas, se dice --------------------------------------------------
printf '\nla puerta dice con qué miró el barrido\n'
r="$(repo_nuevo)"; printf 'nada\n' > "$r/a.md"; G -C "$r" add .
comprobar 'sin lista de marcas, el commit limpio pasa'   hecho    "$(entregar "$r")"
comprobar '… y la puerta lo repite al pasar'             sí       "$(dice "$TMP/salida" 'aviso sin lista de marcas propias')"
mkdir -p "$TMP/casa/conf/_local"; printf 'Zafiro Telecom\n' > "$TMP/casa/conf/_local/marcas.txt"
r="$(repo_nuevo)"; printf 'nada\n' > "$r/a.md"; G -C "$r" add .
comprobar 'con lista de marcas, el commit limpio pasa'   hecho    "$(entregar "$r")"
comprobar '… y la puerta no dice que falte la lista'     no       "$(dice "$TMP/salida" 'sin lista de marcas')"
r="$(repo_nuevo)"; printf 'contrato con Zafiro Telecom\n' > "$r/a.md"; G -C "$r" add .
comprobar '… y esa lista se está leyendo: detenido'      detenido "$(entregar "$r")"
# La frase del barrido, citada en una línea con hallazgo MEDIA: no es su aviso.
r="$(repo_nuevo)"; printf 'dice «sin lista de marcas propias — solo patrones generales» en %s\n' "$HOST" > "$r/a.md"; G -C "$r" add .
comprobar 'la frase citada en un hallazgo MEDIA: pasa'   hecho    "$(entregar "$r")"
comprobar '… y la puerta no la toma por el aviso'        no       "$(dice "$TMP/salida" 'aviso sin lista de marcas')"
rm "$TMP/casa/conf/_local/marcas.txt"

# --- El informe enmascarado no enseña lo que denuncia -----------------------------
printf '\nel informe enmascara lo que casó\n'
printf 'Zafiro Telecom\n' > "$TMP/puesto/marcas.txt"      # lista literal
printf 'cliente[0-9]+\n'  > "$TMP/puesto/clientes.conf"   # lista de expresiones
d="$(mktemp -d "$TMP/arbol.XXXXXX")"
{ printf 'contrato con ZAFIRO TELECOM firmado por cliente77\n'
  printf 'entrar con %s -p 22\n' "$ACCESO"
  printf 'la base vive en %s y se copia a %s cada noche\n' "$HOST" "$SERVIDOR"
  printf '%s = "%s" en %s\n' password 'P@ss!w0rd#2024' "$IP_BAJA"
} > "$d/nota.md"
LOCAL="$TMP/puesto"
comprobar 'el árbol de prueba da hallazgos (control): 1' 1 "$(barrer "$d" . --full)"
cp "$TMP/salida" "$TMP/completo"
comprobar 'por defecto también da hallazgos: 1'          1 "$(barrer "$d" .)"
LOCAL=""; rm "$TMP/puesto/clientes.conf"
for par in 'la marca literal|ZAFIRO' 'la marca por expresión|cliente77' \
           'el usuario del acceso|operador' "la IP del acceso|$IP" \
           'el host|db01' 'la ruta de servidor|acme/volcado' 'el valor secreto|w0rd#2024'; do
    comprobar "--full enseña ${par%%|*} (control)"       sí "$(dice "$TMP/completo" "${par#*|}")"
    comprobar "por defecto no enseña ${par%%|*}"         no "$(dice "$TMP/salida" "${par#*|}")"
done
comprobar 'la frase de alrededor se conserva'            sí "$(dice "$TMP/salida" 'contrato con [marca] firmado por [marca]')"

# --- Otros casos límite de los dos scripts ----------------------------------------------
printf '\notros casos límite\n'
comprobar 'cabecera de clave privada: 1'                 1 "$(barrer_linea "$CLAVE")"
comprobar 'cabecera de clave privada PGP: 1'             1 "$(barrer_linea "$(printf -- '-----BEGIN PGP %s KEY BLOCK-----' PRIVATE)")"
comprobar 'cabecera de clave pública PGP: 0'             0 "$(barrer_linea '-----BEGIN PGP PUBLIC KEY BLOCK-----')"
comprobar 'contraseña con símbolos: 1'                 1 "$(barrer_linea "$(printf '%s = "%s"' password 'P@ss!w0rd#2024')")"
comprobar 'marcador en lugar de contraseña: 0'           0 "$(barrer_linea "$(printf '%s = "%s"' password '<la-de-cada-uno>')")"
asignar() { printf '%s%s%s' "$1" "$2" "$3"; }   # nombre, separador y valor, juntos solo al ejecutar
VALOR='wJalrXUtnFEMI/K7MDENG'
comprobar 'el nombre escrito con ñ: 1'                   1 "$(barrer_linea "$(asignar contraseña ': ' "$VALOR")")"
comprobar 'el mismo nombre en mayúsculas: 1'             1 "$(barrer_linea "$(asignar CONTRASEÑA ': ' "$VALOR")")"
comprobar 'variable de entorno acabada en _KEY: 1'       1 "$(barrer_linea "$(asignar AWS_SECRET_ACCESS_KEY = "$VALOR")")"
comprobar 'la misma en minúsculas y con espacios: 1'     1 "$(barrer_linea "$(asignar aws_secret_access_key ' = ' "$VALOR")")"
comprobar 'variable acabada en _PASSWORD, exportada: 1'  1 "$(barrer_linea "export $(asignar DB_PASSWORD = "$VALOR")")"
comprobar 'variable con el nombre en medio: 1'           1 "$(barrer_linea "$(asignar API_TOKEN_PROD = "$VALOR")")"
comprobar 'variable con un marcador por valor: 0'        0 "$(barrer_linea "$(asignar AWS_SECRET_ACCESS_KEY = '<la-de-cada-uno>')")"
comprobar 'variable que toma otra variable: 0'           0 "$(barrer_linea "$(asignar DB_PASSWORD = '$OTRA_VARIABLE')")"
comprobar 'variable leída del entorno: 0'                0 "$(barrer_linea "$(asignar SECRET_KEY ' = ' 'os.environ["SECRET_KEY"]')")"
comprobar 'variable que recibe una llamada: 0'           0 "$(barrer_linea "$(asignar API_TOKEN ' = ' 'pedir_credencial(servicio)')")"
# El nombre o el valor dicen que lo asignado no es el secreto. Cada caso, con
# el gemelo que sí lo es.
OPACO='q7Zr2mXv9LpT4c'
comprobar 'valor opaco bajo el nombre a secas: 1'        1 "$(barrer_linea "$(asignar token ': ' "$OPACO")")"
comprobar 'nombre acabado en _url, con una URL: 0'       0 "$(barrer_linea "$(asignar token_url ': ' 'https://ejemplo.org/oauth/emision')")"
comprobar 'nombre acabado en _file, con una ruta: 0'     0 "$(barrer_linea "$(asignar password_file ': ' '/run/secretos/base')")"
comprobar 'nombre acabado en _name: 0'                   0 "$(barrer_linea "$(asignar secret_name ': ' 'credencial-de-la-base')")"
comprobar 'nombre acabado en _header: 0'                 0 "$(barrer_linea "$(asignar api_key_header ': ' 'X-Clave-Interna')")"
comprobar 'nombre acabado en _ttl: 0'                    0 "$(barrer_linea "$(asignar token_ttl ' = ' '86400segundos')")"
comprobar 'nombre acabado en _min_length: 0'             0 "$(barrer_linea "$(asignar password_min_length ' = ' '0000000012')")"
comprobar 'nombre en mayúsculas acabado en _EXPIRES_IN: 0' 0 "$(barrer_linea "$(asignar TOKEN_EXPIRES_IN ' = ' '0086400000')")"
comprobar 'el mismo valor bajo un nombre de secreto: 1'  1 "$(barrer_linea "$(asignar TOKEN_PROD ' = ' '0086400000')")"
comprobar 'URL sin credenciales por valor: 0'            0 "$(barrer_linea "$(asignar token ': ' 'https://ejemplo.org/emision/larga')")"
comprobar 'ruta de fichero por valor: 0'                 0 "$(barrer_linea "$(asignar password ': ' './secretos/base.txt')")"
comprobar 'ruta de servidor por valor: sigue MEDIA, 2'   2 "$(barrer_linea "$(asignar password_file ': ' "$SERVIDOR")")"
comprobar 'valor que empieza por / y no es ruta: 1'      1 "$(barrer_linea "$(asignar token ': ' '/K7MDENG+bPxRfiCY=')")"
comprobar 'la asignación inocua no tapa a la real: 1'    1 "$(barrer_linea "$(asignar token_url ': ' 'https://ejemplo.org/emision') $(asignar token ': ' "$OPACO")")"
URL_CLAVE="$(printf 'postgresql://%s:%s@basedatos/ventas' admin_db Clave1234)"
d="$(mktemp -d "$TMP/arbol.XXXXXX")"; printf 'database_url: %s\n' "$URL_CLAVE" > "$d/nota.md"
comprobar 'URL con usuario y clave dentro: 1'            1  "$(barrer "$d" . --full)"
comprobar '… --full enseña la clave (control)'           sí "$(dice "$TMP/salida" 'Clave1234')"
comprobar '… por defecto sale 1 igual'                   1  "$(barrer "$d" .)"
comprobar '… y no enseña ni el usuario'                  no "$(dice "$TMP/salida" 'admin_db')"
comprobar '… ni la clave'                                no "$(dice "$TMP/salida" 'Clave1234')"
comprobar 'la misma URL sin credenciales: 0'             0  "$(barrer_linea 'database_url: postgresql://basedatos/ventas')"
comprobar 'la misma URL con un marcador por clave: 0'    0  "$(barrer_linea "$(printf 'database_url: postgresql://%s:%s@basedatos/ventas' admin_db '${CLAVE}')")"
comprobar 'URL con puerto y una arroba en la ruta: 0'    0  "$(barrer_linea 'ver http://ejemplo.org:8080/perfil/@fulano')"
comprobar 'un nombre que solo empieza igual: 0'          0 "$(barrer_linea "$(asignar tokenizador ' = ' 'modelo-largo-de-ejemplo')")"
comprobar 'host interno que cierra la frase: MEDIA, 2'   2 "$(barrer_linea "la base vive en $HOST.")"
comprobar 'nombre de fichero con ese sufijo dentro: 0'   0 "$(barrer_linea "$(printf 'se lee de ajustes.%s.json' local)")"
# Texto en UTF-16: con marca de orden se convierte y se barre; sin ella no se
# puede leer, y entonces se nombra. Un binario de verdad no detiene nada.
if command -v iconv >/dev/null 2>&1; then
    d="$(mktemp -d "$TMP/arbol.XXXXXX")"; printf 'nodo %s\n' "$IP" | iconv -f UTF-8 -t UTF-16 > "$d/nota.txt"
    comprobar 'IP en un UTF-16 con marca de orden: 1'    1  "$(barrer "$d" .)"
    printf 'nada que ver aquí\n' | iconv -f UTF-8 -t UTF-16 > "$d/nota.txt"
    comprobar 'UTF-16 con marca de orden, limpio: 0'     0  "$(barrer "$d" .)"
    comprobar '… y no cuenta como binario'               no "$(dice "$TMP/salida" 'BINARIO')"
    printf 'nodo %s\n' "$IP" | iconv -f UTF-8 -t UTF-32 > "$d/nota.txt"
    comprobar 'IP en un UTF-32 con marca de orden: 1'    1  "$(barrer "$d" .)"
    printf 'nodo %s\n' "$IP" | iconv -f UTF-8 -t UTF-16LE > "$d/nota.txt"
    comprobar 'UTF-16 sin marca: no se lee, sale 0'      0  "$(barrer "$d" .)"
    comprobar '… pero el barrido lo nombra'              sí "$(dice "$TMP/salida" 'BINARIO nota.txt')"
    comprobar '… y lo cuenta'                            sí "$(dice "$TMP/salida" 'binarios: 1')"
    r="$(repo_nuevo)"; printf 'nodo %s\n' "$IP" | iconv -f UTF-8 -t UTF-16 > "$r/u16.txt"; G -C "$r" add u16.txt
    comprobar 'UTF-16 con IP preparado: commit detenido' detenido "$(entregar "$r")"
fi
r="$(repo_nuevo)"; printf 'GIF89a\0\0\1\2 nodo %s\n' "$IP" > "$r/imagen.gif"; G -C "$r" add imagen.gif
comprobar 'un binario no detiene el commit'              hecho "$(entregar "$r")"
comprobar '… y la puerta dice que no lo ha leído'        sí    "$(dice "$TMP/salida" '1 fichero(s) binario(s)')"
comprobar '… y dice cuál'                                sí    "$(dice "$TMP/salida" 'imagen.gif')"
r="$(repo_nuevo)"; : > "$r/vacío.md"; G -C "$r" add .
comprobar 'un fichero vacío pasa'                        hecho "$(entregar "$r")"
comprobar '… y no cuenta como binario'                   no    "$(dice "$TMP/salida" 'binario')"
# Un fichero en Latin-1 leído desde un puesto en UTF-8 no es un binario.
d="$(mktemp -d "$TMP/arbol.XXXXXX")"; printf 'a\361o: host %s\n' "$IP" > "$d/nota.txt"
REGION="C.UTF-8"
comprobar 'IP en un fichero Latin-1, puesto en UTF-8: 1' 1 "$(barrer "$d" .)"
REGION=""
d="$(mktemp -d "$TMP/arbol.XXXXXX")"; printf 'cliente Zafiro Telecom\n' > "$d/nota.md"
printf 'Zafiro Telecom\r\n' > "$TMP/puesto/marcas.txt"; LOCAL="$TMP/puesto"
comprobar 'lista de marcas con finales CRLF: casa, 1'    1 "$(barrer "$d" .)"
rm "$TMP/puesto/marcas.txt"; printf 'zafiro[\n' > "$TMP/puesto/clientes.conf"
comprobar 'expresión inválida en clientes.conf: error'   3 "$(barrer "$d" .)"
printf 'zafiro +tele\n' > "$TMP/puesto/clientes.conf"
comprobar 'la misma lista, bien escrita (control): 1'    1 "$(barrer "$d" .)"
LOCAL=""
if [ "$(id -u)" -ne 0 ]; then
    d="$(mktemp -d "$TMP/arbol.XXXXXX")"; printf 'host %s\n' "$IP" > "$d/nota.md"; chmod 000 "$d/nota.md"
    comprobar 'fichero candidato ilegible: error (3)'    3 "$(barrer "$d" .)"
fi

# --- La clave entre comillas y los otros separadores -------------------------------
# JSON, un diccionario, una tabla asociativa y `:=`. Lo que con la clave sin
# comillas se deja pasar —marcadores, variables, llamadas— pasa igual con ellas.
printf '\ncredenciales con la clave entre comillas, y con := y =>\n'
DOBLES="\"$OPACO\""; SIMPLES="'$OPACO'"
comprobar 'clave sin comillas (control): 1'              1 "$(barrer_linea "$(asignar password ': ' "$DOBLES")")"
comprobar 'JSON, clave entre comillas dobles: 1'         1 "$(barrer_linea "$(asignar '"password"' ': ' "$DOBLES")")"
comprobar 'diccionario, comillas simples: 1'             1 "$(barrer_linea "{$(asignar "'password'" ': ' "$SIMPLES")}")"
comprobar 'tabla asociativa, con =>: 1'                  1 "$(barrer_linea "$(asignar "'password'" ' => ' "$SIMPLES")")"
comprobar 'asignación con :=: 1'                         1 "$(barrer_linea "$(asignar password ' := ' "$DOBLES")")"
comprobar 'un config.json con la clave: detenido'        detenido "$(entregar_fichero config.json "{ $(asignar '"password"' ': ' "$DOBLES") }")"
comprobar 'el mismo config.json con un marcador: pasa'   hecho    "$(entregar_fichero config.json "{ $(asignar '"password"' ': ' '"<password>"') }")"
d="$(mktemp -d "$TMP/arbol.XXXXXX")"
{ asignar '"password"' ': ' "$DOBLES"; printf '\n'; asignar "'token'" ' => ' "'$VALOR'"; printf '\n'; } > "$d/config.json"
comprobar 'las dos formas, con --full: 1'                1  "$(barrer "$d" . --full)"
comprobar '… --full enseña el valor del JSON (control)'  sí "$(dice "$TMP/salida" "$OPACO")"
comprobar '… y el de la tabla (control)'                 sí "$(dice "$TMP/salida" "$VALOR")"
comprobar '… por defecto sale 1 igual'                   1  "$(barrer "$d" .)"
comprobar '… y no enseña el valor del JSON'              no "$(dice "$TMP/salida" "$OPACO")"
comprobar '… ni el de la tabla'                          no "$(dice "$TMP/salida" "$VALOR")"
comprobar 'JSON con un marcador por valor: 0'            0 "$(barrer_linea "$(asignar '"password"' ': ' '"<password>"')")"
comprobar 'JSON con una variable por valor: 0'           0 "$(barrer_linea "$(asignar '"token"' ': ' '"${TOKEN}"')")"
comprobar 'tabla que toma una variable: 0'               0 "$(barrer_linea "$(asignar "'password'" ' => ' '$clave_leida'),")"
comprobar 'diccionario que lee del entorno: 0'           0 "$(barrer_linea "$(asignar '"api_key"' ': ' 'os.environ["CLAVE_API"]'),")"
comprobar 'llamada asignada con :=: 0'                   0 "$(barrer_linea "$(asignar token ' := ' 'pedir_credencial(servicio)')")"
comprobar 'JSON, nombre acabado en _url: 0'              0 "$(barrer_linea "$(asignar '"token_url"' ': ' '"https://ejemplo.org/oauth/emision"')")"
comprobar 'JSON, nombre acabado en _type, valor que no es URL: 0' 0 "$(barrer_linea "$(asignar '"token_type"' ': ' '"Bearer12345"')")"
comprobar 'diccionario con el propio nombre por valor: 0' 0 "$(barrer_linea "{\"usuario\": usuario, $(asignar '"password"' ': ' password)}")"
comprobar 'función flecha con el propio nombre: 0'       0 "$(barrer_linea "vivos = lista.filter($(asignar token ' => ' 'token.caducidad') > hoy)")"

# --- El acceso remoto: la orden y su argumento --------------------------------------
# La orden es una palabra y el acceso, argumento suyo. Ni una frase que nombra
# la orden junto a un correo, ni una forja pública, ni un marcador son acceso.
printf '\nacceso remoto: la orden, y usuario@host como argumento suyo\n'
NODO="$(printf 'db01.acme.%s' example)"; FORJA="forja.${NODO#*.}"
comprobar 'ssh a un host: 1'                             1 "$(barrer_linea "ssh operador@$NODO")"
comprobar '… con opciones delante y una orden detrás: 1' 1 "$(barrer_linea "ssh -p 2222 -i ~/.ssh/id_prueba operador@$NODO uptime")"
comprobar 'scp a un host: 1'                             1 "$(barrer_linea "scp volcado.sql operador@$NODO:/tmp/")"
comprobar 'rsync a un host: 1'                           1 "$(barrer_linea "rsync -az salida/ operador@$NODO:/destino/")"
comprobar 'scp al directorio personal, la línea acaba en los dos puntos: 1' 1 "$(barrer_linea "scp copia.tgz operador@$NODO:")"
comprobar '… y con rsync, tras otra orden: 1'            1 "$(barrer_linea "echo ok; rsync -a dir operador@$NODO:")"
comprobar 'URL ssh:// con usuario y host: 1'             1 "$(barrer_linea "git clone ssh://operador@$NODO/repo.git")"
comprobar 'usuario git en una forja que no es pública: 1' 1 "$(barrer_linea "ssh -T git@$FORJA")"
comprobar 'un marcador con dominio detrás ya es host: 1' 1 "$(barrer_linea "ssh usuario@servidor${NODO#db01}")"
comprobar 'un acceso junto a un marcador: 1'             1 "$(barrer_linea "scp user@host:/a operador@$NODO:/b")"
comprobar 'ssh -T a una forja pública: 0'                0 "$(barrer_linea 'ssh -T git@github.com')"
comprobar 'las otras dos forjas públicas: 0'             0 "$(barrer_linea $'ssh -T git@gitlab.com\nssh -T git@bitbucket.org')"
comprobar 'clonar por ssh:// de una forja pública: 0'    0 "$(barrer_linea 'git clone ssh://git@github.com/org/repo.git')"
comprobar 'una frase con ssh y un correo: 0'             0 "$(barrer_linea 'Dudas sobre ssh o el despliegue: soporte@example.com')"
comprobar 'openssh-server y un correo: 0'                0 "$(barrer_linea 'Mantenedor de openssh-server <ana@example.org>')"
comprobar 'el marcador usuario@servidor: 0'              0 "$(barrer_linea 'entrar con `ssh usuario@servidor`.')"
comprobar 'el marcador user@host, en scp: 0'             0 "$(barrer_linea 'scp fichero user@host:/tmp/')"
comprobar 'una guía con ssh -T a la forja pasa la puerta' hecho   "$(entregar_fichero guia.md 'ssh -T git@github.com')"
comprobar 'la misma guía con un host: detenido'          detenido "$(entregar_fichero guia.md "ssh operador@$NODO")"

printf '\n%s casos, %s fallan\n' "$N" "$MAL"
[ "$MAL" -eq 0 ]
