#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# operacion_puesto.sh — Banco de pruebas de la skill operacion-puesto: el
# resolutor de alias, el identificador de capas de un proyecto, sus plantillas
# y lo que su SKILL.md promete de ellos.
#
# Fabrica en un HOME desechable una cartera con tres capas (proyecto, cliente y
# puesto) y ejecuta cada caso con `env -i`: nada lee ni escribe el puesto real.
# Los datos son sintéticos, con direcciones de los rangos de documentación.
#
# Cada rechazo va con su control: la entrada que tiene que rechazarse y la
# gemela que tiene que pasar. Un detector que solo se ha visto rechazar puede
# estar rechazándolo todo, y uno que solo se ha visto pasar, nada.
#
# Uso:
#   pruebas/operacion_puesto.sh [raíz del repositorio]     por defecto, la de este fichero
#
# Una línea `ok` o `FALLA` por caso. Si alguno falla, el HOME desechable se
# conserva y se dice dónde está.
#
# Salidas: 0 todos los casos pasan · 1 alguno falla · 2 no encuentra la skill en esa raíz
#
# Author       : Saul López
# Created Date : 2026-10-11

set -uo pipefail
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
unset -f grep sed awk cat cp rm mkdir wc tr head tail mktemp 2>/dev/null || true

RAIZ="$(cd "${1:-$(dirname "$0")/..}" 2>/dev/null && pwd)" || { echo "no existe la raíz: ${1:-}" >&2; exit 2; }
SKILL="$RAIZ/marco/skills/operacion-puesto"
RES="$SKILL/scripts/resolve_alias.sh"
CTX="$SKILL/scripts/contexto_proyecto.sh"
for f in "$RES" "$CTX" "$SKILL/SKILL.md"; do
    [ -r "$f" ] || { echo "no encuentro $f" >&2; exit 2; }
done

CASA="$(mktemp -d)"
ERRF="$CASA/.err"
N_OK=0; N_FALLA=0; NOTAS=""; SAL=""; ERR=""; RC=0

# --- Motor --------------------------------------------------------------------
# correr <dir> [VAR=valor ...] -- <orden> [args]: deja SAL, ERR y RC.
correr() {
    local dir="$1"; shift
    local -a entorno=()
    while [ "$1" != "--" ]; do entorno+=("$1"); shift; done
    shift
    SAL="$(cd "$dir" && env -i PATH="$PATH" HOME="$CASA" ${entorno[@]+"${entorno[@]}"} "$@" 2>"$ERRF")"
    RC=$?
    ERR="$(cat "$ERRF")"
}
nota()     { NOTAS="${NOTAS:+$NOTAS; }$1"; }
rc()       { [ "$RC" -eq "$1" ] || nota "rc=$RC, se esperaba $1"; }
sale()     { grep -qF -- "$1" <<< "$SAL" || nota "falta en la salida: «$1»"; }
no_sale()  { if grep -qF -- "$1" <<< "$SAL"; then nota "sobra en la salida: «$1»"; fi; }
avisa()    { grep -qF -- "$1" <<< "$ERR" || nota "falta en la salida de error: «$1»"; }
no_avisa() { if grep -qF -- "$1" <<< "$ERR"; then nota "sobra en la salida de error: «$1»"; fi; }
exacta()   { [ "$SAL" = "$1" ] || nota "salida «$(head -c 60 <<< "$SAL")», se esperaba «$1»"; }
callado()  { [ -z "$ERR" ] || nota "escribe en la salida de error y no debía"; }
veces()    { local n; n="$(grep -cE -- "$1" <<< "$SAL")"; [ "$n" -eq "$2" ] || nota "«$1» sale $n vez/veces, se esperaban $2"; }
cierto()   { local que="$1"; shift; "$@" >/dev/null 2>&1 || nota "$que"; }
falso()    { local que="$1"; shift; if "$@" >/dev/null 2>&1; then nota "$que"; fi; }
fin() {
    if [ -z "$NOTAS" ]; then N_OK=$((N_OK+1)); printf 'ok     %s\n' "$1"
    else N_FALLA=$((N_FALLA+1)); printf 'FALLA  %s — %s\n' "$1" "$NOTAS"; fi
    NOTAS=""
}

# --- Datos sintéticos ---------------------------------------------------------
# registro <alias> <ssh_host> <modo> <propósito> [legado_grep]: las diez claves.
registro() {
    cat <<Y
  - alias: $1
    ssh_host: $2
    cliente: cliente-a
    pais: xx
    entorno: pruebas
    so: linux
    proposito: "$4"
    criticidad: baja
    modo: $3
    legado_grep: ${5:-false}
Y
}
cabecera() { printf 'version: 1\n\nconexiones:\n'; }
# Direcciones de los rangos de documentación, compuestas al ejecutar: así este
# fichero no contiene ninguna y la búsqueda de IPv4 sobre el árbol sigue vacía.
IP_UNA="$(printf '%s.%s.%s.%s' 198 51 100 7)"
IP_DOS="$(printf '%s.%s.%s.%s' 203 0 113 9)"

CONF="$CASA/conf"                              # <conf> del puesto, declarado
CART="$CASA/Proyectos"                         # la cartera, en su sitio por defecto
CLI="$CART/cliente-a"
PROY="$CLI/proy-uno"
FUERA="$CASA/fuera"                            # un directorio que no es de la cartera
mkdir -p "$CONF/_local" "$CLI/_local" "$PROY/_local" "$FUERA"

# Capa del puesto: lo general. `compartido` está también en el proyecto.
{ cabecera
  registro compartido  h-general   solo-lectura "nodo general"
  registro solo-puesto h-puesto    solo-lectura "salto del puesto" true
} > "$CONF/_local/conexiones.yaml"
# Capa del cliente.
{ cabecera
  registro solo-cliente h-cliente  solo-lectura "bastion del cliente" true
} > "$CLI/_local/conexiones.yaml"
# Capa del proyecto: de `compartido` declara solo lo que cambia aquí.
{ cabecera
  printf '  - alias: compartido\n    ssh_host: h-uno\n    modo: escritura-con-aprobacion\n'
  registro solo-proyecto h-proyecto solo-lectura "nodo del proyecto"
} > "$PROY/_local/conexiones.yaml"
printf 'cliente: cliente-a\nresponsable: alguien\n' > "$CLI/_local/proyecto.yaml"
printf 'proyecto: proy-uno\ncliente: cliente-a\n'   > "$PROY/_local/proyecto.yaml"

E_CONF="ALAMBIQUE_CONF=$CONF"
F="$CASA/una.yaml"                             # fuente única para los casos de formato
con_una()  { correr "$FUERA" "CONEXIONES_YAML=$F" -- "$RES" "$@"; }
cascada()  { correr "$PROY" "$E_CONF" -- "$RES" "$@"; }

# ==============================================================================
echo "# Interfaz que no puede cambiar"
# ==============================================================================
cierto "resolve_alias.sh no pasa bash -n"     bash -n "$RES"
cierto "contexto_proyecto.sh no pasa bash -n" bash -n "$CTX"
fin "los dos scripts pasan bash -n"

cascada --list
rc 0; veces '^ALIAS +ENTORNO +MODO +PROPOSITO$' 1
exacta "$(printf '%s\n' "$SAL" | head -n 2)
$(printf '%-28s %-12s %-10s %s\n' compartido pruebas escritura-con-aprobacion "nodo general" \
                                   solo-proyecto pruebas solo-lectura "nodo del proyecto" \
                                   solo-cliente pruebas solo-lectura "bastion del cliente" \
                                   solo-puesto pruebas solo-lectura "salto del puesto")"
fin "--list: dos líneas de cabecera y una fila por alias, de lo específico a lo general"

# Así se consume desde un guard: la primera columna de las filas, y un --check por alias.
legados="$(cd "$PROY" && env -i PATH="$PATH" HOME="$CASA" "$E_CONF" "$RES" --list 2>/dev/null | tail -n +3 | awk '{print $1}' | \
    while read -r a; do
        [ -n "$a" ] || continue
        (cd "$PROY" && env -i PATH="$PATH" HOME="$CASA" "$E_CONF" "$RES" --check "$a" legado_grep true 2>/dev/null) && printf '%s ' "$a"
    done)"
[ "$legados" = "solo-cliente solo-puesto " ] || nota "destinos marcados: «$legados»"
fin "--list más --check, como los usa el guard: salen los alias con legado_grep true y ninguno más"

cascada solo-proyecto
rc 0; veces '^[a-z_]+=.+$' 10; veces '^alias=solo-proyecto$' 1; veces '^ssh_host=h-proyecto$' 1
[ "$(grep -cvE '^[a-z_]+=.+$' <<< "$SAL")" -eq 0 ] || nota "hay líneas que no son clave=valor"
fin "<alias>: la ficha son líneas clave=valor"

cascada solo-cliente proposito
rc 0; exacta "bastion del cliente"
fin "<alias> <campo>: imprime el valor y nada más"

cascada --check solo-puesto modo solo-lectura
rc 0; exacta ""
fin "--check: sale 0 si coincide"
cascada --check solo-puesto modo escritura-con-aprobacion
rc 1
fin "--check: sale 1 si no coincide (control)"

cascada --fuentes
rc 0
exacta "  1. $PROY/_local/conexiones.yaml
  2. $CLI/_local/conexiones.yaml
  3. $CONF/_local/conexiones.yaml"
fin "--fuentes: las capas leídas, numeradas, de la más específica a la general"

correr "$FUERA" "ALAMBIQUE_CONF=$CASA/vacio" -- "$RES" --fuentes
rc 0; sale "(ninguna fuente legible)"
fin "--fuentes: sin ninguna fuente es diagnóstico y sale 0"

cascada --validar
rc 0; sale "esquema: 4 alias, sin problemas"
fin "--validar: sale 0 con la cascada bien formada"

cascada no-existe
rc 1; avisa "alias no encontrado: no-existe"
fin "salida 1: alias no encontrado"
cascada solo-puesto no_existe
rc 2; avisa "campo no encontrado: no_existe"
fin "salida 2: campo no encontrado"
cascada --check solo-puesto modo
rc 2
fin "salida 2: uso incorrecto (--check sin el valor)"
correr "$FUERA" "ALAMBIQUE_CONF=$CASA/vacio" -- "$RES" --list
rc 3; avisa "ninguna fuente legible"
fin "salida 3: sin fuente"
{ cabecera; printf '  - alias: cojo\n    ssh_host: h-uno\n'; } > "$F"
con_una --validar
rc 4; sale "cojo: falta modo"
fin "salida 4: esquema inválido (faltan claves obligatorias)"
correr "$FUERA" "$E_CONF" -- "$RES" --help
rc 0
fin "--help: sale 0"

{ cabecera; registro en-fichero h-uno solo-lectura "nodo aislado"; } > "$F"
correr "$PROY" "$E_CONF" "CONEXIONES_YAML=$F" -- "$RES" --fuentes
rc 0; exacta "  1. $F"
correr "$PROY" "$E_CONF" "CONEXIONES_YAML=$F" -- "$RES" en-fichero ssh_host
rc 0; exacta "h-uno"
correr "$PROY" "$E_CONF" "CONEXIONES_YAML=$F" -- "$RES" solo-proyecto
rc 1
fin "CONEXIONES_YAML: fuente única, y la cascada deja de verse"

correr "$FUERA" "CONEXIONES_YAML=$SKILL/plantillas/conexiones.yaml.example" -- "$RES" app
rc 1
correr "$FUERA" "CONEXIONES_YAML=$SKILL/plantillas/conexiones.yaml.example" -- "$RES" cliente-a-prod-app modo
rc 0; exacta "solo-lectura"
correr "$FUERA" "CONEXIONES_YAML=$SKILL/plantillas/conexiones.yaml.example" -- "$RES" --validar
rc 0; sale "esquema: 2 alias, sin problemas"
fin "la plantilla conexiones.yaml.example se lee, valida, y un sufijo de alias no es un alias"

# ==============================================================================
echo "# La ficha sale resuelta por la cascada"
# ==============================================================================
cascada compartido
rc 0; veces '^alias=' 1; veces '^modo=' 1; veces '^ssh_host=' 1; veces '^[a-z_]+=' 10
sale "modo=escritura-con-aprobacion"; sale "ssh_host=h-uno"; no_sale "modo=solo-lectura"; no_sale "h-general"
sale "proposito=nodo general"
fin "alias en dos capas: cada clave una vez, con el valor de la más específica"
cascada compartido modo
rc 0; exacta "escritura-con-aprobacion"
cascada compartido proposito
rc 0; exacta "nodo general"
fin "por campo resuelve igual que la ficha (control)"
correr "$FUERA" "$E_CONF" -- "$RES" compartido modo
rc 0; exacta "solo-lectura"
fin "fuera del proyecto vale la capa general (control)"

# ==============================================================================
echo "# --validar no da por bueno lo que no entiende"
# ==============================================================================
: > "$F"
con_una --validar
rc 4; no_sale "sin problemas"
fin "fichero vacío: esquema inválido"
con_una --list
rc 0; veces '.' 2
fin "--list sobre fichero vacío: solo la cabecera, sin fila de guiones"

printf 'conexiones:\n' > "$F"
con_una --validar
rc 4; no_sale "sin problemas"
fin "sección conexiones sin registros: esquema inválido"

printf 'conexiones:\n  nombre:\n    ssh_host: h-uno\n    modo: solo-lectura\n' > "$F"
con_una --validar
rc 4; no_sale "sin problemas"; sale ":2:"
fin "mapa por nombre en vez de lista: esquema inválido, con el número de línea"
{ cabecera; registro nombre h-uno solo-lectura "el mismo dato, en lista"; } > "$F"
con_una --validar
rc 0; sale "esquema: 1 alias, sin problemas"
con_una --list
veces '.' 3
fin "el mismo dato escrito como lista pasa (control)"

{ cabecera; registro uno h-uno solo-lectura "nodo"; } | sed "s/ssh_host: h-uno/ssh_host: \"$IP_UNA\" /" > "$F"
con_una --validar
rc 4; sale "uno: ssh_host parece una coordenada"; no_sale "$IP_UNA"
fin "IP entre comillas con espacio final: coordenada, y el informe no la repite"
{ cabecera; registro uno h-uno solo-lectura "nodo"; } | sed "s/ssh_host: h-uno/ssh_host: $IP_UNA/" > "$F"
con_una --validar
rc 4; sale "uno: ssh_host parece una coordenada"
fin "IP sin comillas: coordenada (control del detector)"
{ cabecera; registro uno h-uno solo-lectura "nodo"; } | sed 's/ssh_host: h-uno/ssh_host: "h-uno" /' > "$F"
con_una --validar
rc 0
con_una uno ssh_host
exacta "h-uno"
fin "entrada Host entre comillas con espacio final: pasa, y el valor sale limpio (control)"
for coord in 'ops@h-uno' 'h-uno.example.org' '"h-uno:22"' "$IP_DOS"; do
    { cabecera; registro uno h-uno solo-lectura "nodo"; } | sed "s/ssh_host: h-uno/ssh_host: $coord/" > "$F"
    con_una --validar
    [ "$RC" -eq 4 ] || nota "no rechaza la forma $coord"
done
fin "usuario@host, FQDN, host:puerto e IP: las cuatro son coordenadas"

{ cabecera; registro uno h-uno '"solo-lectura"' "nodo"; } | sed 's/$/\r/' > "$F"
con_una uno modo
rc 0; exacta "solo-lectura"
con_una --validar
rc 0
fin "fichero con CRLF y valor entre comillas: el valor sale sin comilla ni retorno de carro"

# ==============================================================================
echo "# Ningún campo acaba en el alias equivocado"
# ==============================================================================
{ cabecera; registro uno h-uno solo-lectura "nodo uno"
  printf '  - ssh_host: h-dos\n    alias: dos\n    modo: escritura-con-aprobacion\n'; } > "$F"
con_una dos
rc 0; sale "ssh_host=h-dos"; sale "modo=escritura-con-aprobacion"
con_una uno
rc 0; veces '^modo=' 1; sale "modo=solo-lectura"; no_sale "h-dos"; no_sale "escritura-con-aprobacion"
fin "alias que no es la primera clave: se encuentra, y el anterior no hereda sus campos"
{ cabecera; registro uno h-uno solo-lectura "nodo uno"
  printf '  - alias: dos\n    ssh_host: h-dos\n    modo: escritura-con-aprobacion\n'; } > "$F"
con_una dos
rc 0; sale "ssh_host=h-dos"
con_una uno
veces '^modo=' 1
fin "el mismo fichero con alias en primer lugar da lo mismo (control)"

{ cabecera; registro uno h-uno solo-lectura "nodo uno"
  printf 'grupos:\n  prod:\n    modo: escritura-con-aprobacion\n    extra: si\n'; } > "$F"
con_una uno
rc 0; veces '^[a-z_]+=' 10; sale "modo=solo-lectura"; no_sale "extra="; no_sale "prod="; no_sale "escritura-con-aprobacion"
avisa "--validar"
con_una --validar
rc 4; sale ":14:"
fin "sección posterior con sangría: no contamina al último alias, y --validar la señala"
{ cabecera; registro uno h-uno solo-lectura "nodo uno"; } > "$F"
con_una uno
rc 0; veces '^[a-z_]+=' 10; callado
con_una --validar
rc 0
fin "sin la sección ajena, la misma ficha y esquema válido (control)"

{ cabecera; registro uno h-uno solo-lectura "nodo #2 de app"; } > "$F"
con_una uno proposito
rc 0; exacta "nodo #2 de app"
fin "almohadilla entre comillas: es texto, no comentario"
{ cabecera; registro uno h-uno solo-lectura "nodo"; } | sed 's/proposito: .*/proposito: nodo de app   # el segundo/' > "$F"
con_una uno proposito
rc 0; exacta "nodo de app"
fin "almohadilla fuera de comillas, tras un espacio: es comentario (control)"

{ cabecera; registro uno h-uno solo-lectura "el primero"; registro uno h-otro escritura-con-aprobacion "el segundo"; } > "$F"
con_una --validar
rc 4; sale "alias repetido"
con_una uno
veces '^modo=' 1; sale "modo=solo-lectura"; sale "proposito=el primero"; no_sale "h-otro"
fin "alias repetido en el mismo fichero: --validar lo dice y no se fusionan"
cascada --validar
rc 0; no_sale "repetido"
fin "el mismo alias en dos capas distintas no es un problema: es la cascada (control)"

{ cabecera; printf '  - alias: uno\n      modo: torcido\n    ssh_host: h-uno\n    puertos:\n      - 22\n    so: linux\n'; } > "$F"
con_una uno
rc 0; no_sale "modo="; no_sale "puertos"; sale "so=linux"
con_una --validar
rc 4; sale ":5:"; sale ":8:"
fin "sangría torcida y lista anidada: no se leen a medias, y --validar dice la línea"

# ==============================================================================
echo "# contexto_proyecto.sh no da por declarado lo que nadie ha escrito"
# ==============================================================================
B="$CART/cliente-b"; BP="$B/proy-dos"
mkdir -p "$B/_local" "$BP/_local"
ctx() { correr "$1" "$E_CONF" -- "$CTX" "${@:2}"; }

cp "$SKILL/plantillas/proyecto.yaml.example" "$B/_local/proyecto.yaml"
ctx "$BP"
rc 1; sale "FALTA DECLARAR EL CLIENTE"; no_sale "Cliente    :"; no_sale "[cliente: <"
fin "plantilla proyecto.yaml.example sin rellenar: cliente sin declarar"
printf 'cliente: <PREGUNTAR>\n' > "$B/_local/proyecto.yaml"
ctx "$BP"
rc 1; sale "FALTA DECLARAR EL CLIENTE"
fin "el literal <PREGUNTAR>: sin declarar (control)"
printf 'cliente: cliente-b\n' > "$B/_local/proyecto.yaml"
ctx "$BP"
rc 0; sale "Cliente    : cliente-b"; sale "Nivel del cliente : Proyectos/cliente-b"
fin "cliente escrito en un ancestro: identificado (control)"

printf 'cliente: "cliente-b"   # con comillas\r\n' > "$B/_local/proyecto.yaml"
ctx "$BP"
rc 0; sale "Cliente    : cliente-b"; sale "[cliente: cliente-b]"; no_sale '"cliente-b"'
[ "$(grep -c $'\r' <<< "$SAL")" -eq 0 ] || nota "la salida arrastra un retorno de carro"
fin "valor entre comillas, con comentario y CRLF: sale limpio"

printf 'cliente: cliente-b\n' > "$B/_local/proyecto.yaml"
printf 'proyecto: proy-dos\ncliente: cliente-a\n' > "$BP/_local/proyecto.yaml"
ctx "$BP"
rc 1; sale "CONFLICTO"; no_sale "Cliente    :"
sale "cliente-b/proy-dos/_local/proyecto.yaml  dice  cliente-a"; sale "cliente-b/_local/proyecto.yaml  dice  cliente-b"
fin "el proyecto dice un cliente y su ancestro otro: avisa, y nombra los dos ficheros que discrepan"
printf 'proyecto: proy-dos\ncliente: cliente-b\n' > "$BP/_local/proyecto.yaml"
ctx "$BP"
rc 0; no_sale "CONFLICTO"; sale "Cliente    : cliente-b"; sale "Proyecto   : proy-dos"
fin "las dos declaraciones nombran al mismo cliente: sin conflicto (control)"

printf 'proyecto: proy-dos\n' > "$BP/_local/proyecto.yaml"
printf 'servidores:\n  - alias: uno\n    cliente: cliente-a\n' > "$B/_local/proyecto.yaml"
ctx "$BP"
rc 1; sale "FALTA DECLARAR EL CLIENTE"
fin "una clave cliente anidada en otra estructura no declara al dueño"
printf 'cliente: cliente-b\n' > "$B/_local/proyecto.yaml"

# ==============================================================================
echo "# contexto_proyecto.sh responde lo mismo desde la raíz del proyecto que desde dentro"
# ==============================================================================
# El diagnóstico: la salida sin la línea que nombra el directorio desde el que se pregunta.
diagnostico() { grep -v '^  Directorio :' <<< "$SAL"; }
igual_que()   { [ "$(diagnostico)" = "$1" ] || nota "el diagnóstico cambia con el directorio desde el que se pregunta"; }
C="$CART/cliente-c"; CP="$C/proy-tres"
mkdir -p "$CP/_local" "$CP/src/lib" "$C/notas"

printf 'proyecto: proy-tres\ncliente: cliente-c\n' > "$CP/_local/proyecto.yaml"
ctx "$CP"
rc 1; sale "El cliente solo está declarado"; sale "PREGUNTAR"; desde_raiz="$(diagnostico)"
ctx "$CP/src/lib"
rc 1; igual_que "$desde_raiz"
fin "al cliente solo lo nombra la declaración del proyecto: hay que preguntar, igual desde su raíz que desde un subdirectorio"

mkdir -p "$C/_local"
printf 'cliente: cliente-c\n' > "$C/_local/proyecto.yaml"
ctx "$CP"
rc 0; sale "Nivel del cliente : Proyectos/cliente-c"; desde_raiz="$(diagnostico)"
ctx "$CP/src/lib"
rc 0; igual_que "$desde_raiz"
fin "con el nivel del cliente declarado encima: identificado desde los dos sitios (control)"

ctx "$C"
rc 0; sale "Nivel del cliente : Proyectos/cliente-c"; desde_raiz="$(diagnostico)"
ctx "$C/notas"
rc 0; igual_que "$desde_raiz"
fin "el nivel del cliente es la declaración sin proyecto: se reconoce igual desde su propio directorio"

printf 'proyecto: <nombre corto>\ncliente: cliente-c\n' > "$C/_local/proyecto.yaml"
ctx "$CP/src/lib"
rc 1; sale "El cliente solo está declarado"; no_sale "Nivel del cliente"
fin "un proyecto: con el marcador sin rellenar no hace de nivel del cliente"
printf 'cliente: cliente-c\n' > "$C/_local/proyecto.yaml"

SC="$CART/propio"
mkdir -p "$SC/_local" "$SC/src"
printf 'proyecto: propio\ncliente: ninguno\n' > "$SC/_local/proyecto.yaml"
ctx "$SC"
rc 0; sale "Cliente    : ninguno"; sale "Proyecto   : propio"; no_sale "PREGUNTAR"; no_sale "Nivel del cliente"
desde_raiz="$(diagnostico)"
ctx "$SC/src"
rc 0; igual_que "$desde_raiz"
fin "cliente: ninguno declara un proyecto sin cliente: identificado, sin preguntar por el nivel del cliente"
printf 'proyecto: propio\n' > "$SC/_local/proyecto.yaml"
ctx "$SC"
rc 1; sale "FALTA DECLARAR EL CLIENTE"
fin "sin la clave cliente no se da por sin cliente: hay que preguntar (control)"
printf 'proyecto: proy-tres\ncliente: ninguno\n' > "$CP/_local/proyecto.yaml"
ctx "$CP"
rc 1; sale "CONFLICTO"; no_sale "Cliente    :"
fin "cliente: ninguno bajo un nivel que nombra a un cliente: conflicto, no se elige (control)"
printf 'proyecto: proy-tres\ncliente: cliente-c\n' > "$CP/_local/proyecto.yaml"

# ==============================================================================
echo "# <conf> se resuelve por la ubicación de la copia que se ejecuta"
# ==============================================================================
H1="$CASA/.h1"; H2="$CASA/.h2"
mkdir -p "$H1/skills" "$H2/skills" "$H1/_local" "$CASA/suelto" "$CASA/.alambique/_local"
cp -R "$SKILL" "$H1/skills/operacion-puesto"
cp -R "$SKILL" "$H2/skills/operacion-puesto"
cp "$RES" "$CASA/suelto/resolve_alias.sh"
{ cabecera; registro del-h1 h-uno solo-lectura "capa del harness principal"; } > "$H1/_local/conexiones.yaml"
{ cabecera; registro neutral h-uno solo-lectura "capa neutral"; } > "$CASA/.alambique/_local/conexiones.yaml"
R1="$H1/skills/operacion-puesto/scripts/resolve_alias.sh"
R2="$H2/skills/operacion-puesto/scripts/resolve_alias.sh"

correr "$FUERA" -- "$R1" --fuentes
rc 0; exacta "  1. $H1/_local/conexiones.yaml"
fin "copia instalada: lee la capa de su propio <conf>"
correr "$PROY" -- "$R2" --fuentes
rc 0; no_sale "$H1/_local"; avisa "$H2/_local/conexiones.yaml"; avisa "ALAMBIQUE_LOCAL"
fin "copia de otro harness: no ve la capa del principal, y nombra la que consulta"
correr "$PROY" "ALAMBIQUE_LOCAL=$H1/_local" -- "$R2" del-h1 ssh_host
rc 0; exacta "h-uno"
fin "con ALAMBIQUE_LOCAL la copia de otro harness ve la capa del puesto"
correr "$PROY" "ALAMBIQUE_CONF=$H1" -- "$R2" del-h1 ssh_host
rc 0; exacta "h-uno"
fin "con ALAMBIQUE_CONF también"
correr "$FUERA" -- "$CASA/suelto/resolve_alias.sh" --fuentes
rc 0; exacta "  1. $CASA/.alambique/_local/conexiones.yaml"
fin "copiado suelto a otro sitio: cae en ~/.alambique"
correr "$CART" -- "$H2/skills/operacion-puesto/scripts/contexto_proyecto.sh"
sale "$(basename "$H2")/_local"; sale "NO EXISTE"; sale "ALAMBIQUE_LOCAL"
fin "contexto_proyecto.sh nombra la raíz del puesto que consulta aunque no exista"
cierto "SKILL.md no habla de «varios harness»" grep -q 'varios harness' "$SKILL/SKILL.md"
cierto "SKILL.md no nombra ALAMBIQUE_LOCAL como salida" grep -q 'ALAMBIQUE_LOCAL=' "$SKILL/SKILL.md"
cierto "SKILL.md no cuenta los cuatro pasos" grep -q 'cuatro pasos' "$SKILL/SKILL.md"
fin "la SKILL.md cuenta los cuatro pasos y qué hacer con varios harness"

# ==============================================================================
echo "# contexto_proyecto.sh: ayuda, cartera y raíz del puesto"
# ==============================================================================
correr "$FUERA" -- "$CTX" --help
rc 0; no_avisa "crea las capas que falten"; avisa "cartera si falta"; avisa "fuera de la cartera"
fin "la ayuda dice lo que --crear crea, y el código 2 incluye «fuera de la cartera»"
cierto "la cabecera promete crear «las capas que falten»" \
    awk '/crea las capas que falten/ { mal = 1 } END { exit mal }' "$CTX"
fin "la cabecera del script no promete crear más capa que la de la cartera"

correr "$FUERA" "$E_CONF" -- "$CTX"
rc 2; avisa "está fuera de"
fin "fuera de la cartera: sale 2 (control)"
correr "$BP" "$E_CONF" "ALAMBIQUE_PROYECTOS=$CART/" -- "$CTX"
rc 0; sale "Cliente    : cliente-b"; no_avisa "está fuera de"
fin "ALAMBIQUE_PROYECTOS con barra final: la cartera es la misma"

AJENA="$CASA/ajena"
mkdir -p "$AJENA/cliente-d/_local" "$AJENA/cliente-d/proy"
printf 'cliente: cliente-d\n' > "$AJENA/cliente-d/_local/proyecto.yaml"
correr "$AJENA/cliente-d/proy" "$E_CONF" -- "$CTX"
rc 2; avisa "está fuera de"; avisa "ALAMBIQUE_PROYECTOS"; avisa "valor por defecto"; avisa "$CART"
fin "fuera de la cartera: el mensaje nombra ALAMBIQUE_PROYECTOS y dice que vale su valor por defecto"
correr "$AJENA/cliente-d/proy" "$E_CONF" "ALAMBIQUE_PROYECTOS=$CART" -- "$CTX"
rc 2; avisa "ALAMBIQUE_PROYECTOS, que ahora vale: $CART"; no_avisa "valor por defecto"
fin "fuera de la cartera con la variable definida: el mensaje dice el valor que tiene"
correr "$AJENA/cliente-d/proy" "$E_CONF" "ALAMBIQUE_PROYECTOS=$AJENA" -- "$CTX"
rc 0; sale "Cliente    : cliente-d"; no_avisa "está fuera de"
fin "con ALAMBIQUE_PROYECTOS apuntando a esa cartera, identifica (control)"

# Con `env -i` el script no hereda PWD y ve la ruta física. Quien llega por un
# enlace trae la lógica: se le pasa, como hace la shell desde la que se trabaja.
ln -s "$PROY" "$CASA/atajo"
correr "$CASA/atajo" "$E_CONF" "PWD=$CASA/atajo" -- "$CTX"
rc 0; sale "Cliente    : cliente-a"; sale "Proyecto   : proy-uno"; no_avisa "está fuera de"
fin "enlace simbólico hacia un proyecto de la cartera: no queda fuera"
# El resolutor lee por ese enlace las mismas capas que por la ruta del proyecto.
correr "$PROY" "$E_CONF" "ALAMBIQUE_PROYECTOS=$CART" -- "$RES" --fuentes
_por_ruta="$SAL"
correr "$CASA/atajo" "$E_CONF" "ALAMBIQUE_PROYECTOS=$CART" "PWD=$CASA/atajo" -- "$RES" --fuentes
rc 0; exacta "$_por_ruta"; sale "$PROY/_local/conexiones.yaml"
fin "enlace simbólico hacia un proyecto: el resolutor lee las mismas capas que por su ruta"
correr "$CASA/atajo" "$E_CONF" "ALAMBIQUE_PROYECTOS=$CART" "PWD=$CASA/atajo" -- "$RES" solo-cliente proposito
rc 0; exacta "bastion del cliente"
fin "… y resuelve el alias que solo declara el cliente, que por el enlace no es su ancestro"
ln -s "$FUERA" "$CASA/atajo-fuera"
correr "$CASA/atajo-fuera" "$E_CONF" "PWD=$CASA/atajo-fuera" -- "$CTX"
rc 2; avisa "está fuera de"
fin "enlace hacia un directorio que no es de la cartera: sigue fuera (control)"
ln -s "$CART" "$CASA/cartera-enlazada"
correr "$PROY" "$E_CONF" "ALAMBIQUE_PROYECTOS=$CASA/cartera-enlazada" -- "$CTX"
rc 0; sale "Cliente    : cliente-a"; no_avisa "está fuera de"
fin "la cartera es ella misma un enlace: sus directorios siguen dentro"
mkdir -p "$CASA/disco/proy-enlazado"
ln -s "$CASA/disco/proy-enlazado" "$CLI/proy-enlazado"
correr "$CLI/proy-enlazado" "$E_CONF" "PWD=$CLI/proy-enlazado" -- "$CTX"
rc 0; sale "Cliente    : cliente-a"; no_avisa "está fuera de"
fin "proyecto enlazado desde la cartera: sigue dentro por su ruta lógica (control)"
correr "$FUERA" "$E_CONF" -- "$CTX" --nope
rc 2
fin "opción desconocida: sale 2"

mkdir -p "$CART/sin-capas"
correr "$CART/sin-capas" "ALAMBIQUE_CONF=$CASA/vacio" -- "$CTX"
rc 1; no_sale "solo la raíz del puesto"; sale "NO EXISTE"
fin "sin capa propia ni raíz del puesto: no dice que la raíz está"
correr "$CART/sin-capas" "$E_CONF" -- "$CTX"
rc 1; sale "raíz del puesto"; no_sale "NO EXISTE"
fin "con la raíz del puesto presente, la nombra (control)"

OTRA="$CASA/otra-cartera"; mkdir -p "$OTRA/x"
falso "la cartera de prueba ya tenía _local" test -d "$OTRA/_local"
correr "$OTRA/x" "$E_CONF" "ALAMBIQUE_PROYECTOS=$OTRA" -- "$CTX" --crear
cierto "--crear no crea la _local de la cartera" test -d "$OTRA/_local"
falso  "--crear crea una capa en el directorio actual" test -d "$OTRA/x/_local"
fin "--crear crea la _local/ de la cartera y ninguna otra"

# ==============================================================================
echo "# resolve_alias.sh: --check, --fuentes y opciones"
# ==============================================================================
cascada --check no-existe modo solo-lectura
rc 2; avisa "alias no encontrado: no-existe"
fin "--check con un alias que no existe: sale 2 y lo dice"
cascada --check solo-puesto no_existe x
rc 2; avisa "campo no encontrado: no_existe"
fin "--check con un campo que no existe: sale 2 y lo dice"
cascada --check solo-puesto modo otro-valor
rc 1; callado
fin "--check que no coincide: sale 1, sin mensaje (control)"

correr "$PROY" "$E_CONF" "CONEXIONES_YAML=/no/existe" -- "$RES" --fuentes
rc 0; sale "(ninguna fuente legible)"; sale "CONEXIONES_YAML"; no_sale "hacia arriba"
fin "--fuentes con CONEXIONES_YAML ilegible: no dice que buscó en la cascada"
correr "$FUERA" "ALAMBIQUE_CONF=$CASA/vacio" -- "$RES" --fuentes
rc 0; sale "hacia arriba"
fin "--fuentes sin la variable: dice por dónde buscó (control)"

cascada --nope
rc 2; avisa "opción desconocida: --nope"; no_avisa "alias no encontrado: --nope"
fin "opción desconocida: uso incorrecto (2), no «alias no encontrado»"

# ==============================================================================
echo "# SKILL.md y plantillas"
# ==============================================================================
MD="$SKILL/SKILL.md"
claves="$(awk 'NR == 1 && $0 == "---" { en = 1; next } en && $0 == "---" { exit } en { sub(/:.*/, ""); print }' "$MD" | tr '\n' ' ')"
[ "$claves" = "name description " ] || nota "claves del frontmatter: «$claves»"
n_car="$(sed -n 's/^description: *//p' "$MD" | tr -d '\n' | LC_ALL=C.UTF-8 wc -m)"
n_oct="$(sed -n 's/^description: *//p' "$MD" | tr -d '\n' | wc -c)"
[ "$n_car" -gt 0 ] && [ "$n_car" -le 1024 ] || nota "description: $n_car caracteres"
[ "$n_oct" -le 1024 ] || nota "description: $n_oct bytes"
fin "frontmatter: solo name y description, y description dentro de 1024 caracteres y bytes"

falso  "dice que las coordenadas viven en conexiones.yaml" grep -q 'coordenadas viven en `conexiones.yaml`' "$MD"
cierto "no dice que la coordenada vive en ~/.ssh/config"   grep -q 'coordenada vive' "$MD"
fin "dónde vive la coordenada: una sola respuesta"
cierto "no cita R-04" grep -q 'R-04' "$MD"
fin "R-04 se cita"
[ "$(grep -c '^estado: abierto$' "$MD")" -eq 1 ] || nota "hay más de una cabecera de item, o ninguna"
cierto "la cabecera de item no lleva responsable" \
    awk '/^estado: abierto$/ { en = 1 } en && /^responsable:/ { ok = 1 } en && /^---$/ { en = 0 } END { exit !ok }' "$MD"
fin "los cinco directorios de estado comparten una cabecera, con responsable"
falso "promete un mensaje de error de un lector que el repositorio no trae" grep -q 'mapping values are not allowed here' "$MD"
fin "la regla de la cabecera no presupone un lector de YAML"
cierto "la receta manual no pone el bloque de ignore" grep -q 'marco/plantillas/gitignore' "$MD"
fin "la receta manual del esqueleto pone el bloque de ignore"
if sed -n 's/^description: *//p' "$MD" | grep -q 'logs'; then
    cierto "la description promete logs y el cuerpo no dice dónde van" grep -q '^| \*\*Logs\*\*' "$MD"
fi
fin "lo que la description promete tiene sitio en el cuerpo (logs)"
cierto "la fila de configuración real omite marcas.txt" grep -q 'Configuración real.*marcas\.txt' "$MD"
fin "la fila «Configuración real» nombra marcas.txt"
cierto "no explica <PREGUNTAR>" grep -q 'cliente: <PREGUNTAR>' "$MD"
fin "<PREGUNTAR> se explica en la SKILL.md"
cierto "la tabla de salidas no distingue --check" grep -q 'no hay con qué comparar' "$MD"
fin "la tabla de salidas dice qué significa cada código en --check"

cierto "no dice que describe una forma de organizar el puesto, cerca del principio" \
    awk 'NR <= 15 && /UNA forma de organizar el puesto/ { ok = 1 } END { exit !ok }' "$MD"
cierto "no dice que el esquema es una convención" grep -q 'son una convención' "$MD"
fin "la SKILL.md declara al principio que describe una forma de organizar el puesto, no un esquema universal"
cierto "no dice que ~/Proyectos es solo el valor por defecto" grep -q 'valor por defecto, no un requisito' "$MD"
cierto "no dice dónde se fijan las variables"                 grep -q 'entorno desde el que se lanza el harness' "$MD"
falso  "la cascada sigue escrita con ~/Proyectos como ruta fija" grep -q '^~/Proyectos/_local' "$MD"
fin "la SKILL.md dice que ~/Proyectos es el valor por defecto de la cartera y dónde se fija la variable"
cierto "la SKILL.md no documenta el valor sin cliente"  grep -q 'cliente: ninguno' "$MD"
cierto "la plantilla no documenta el valor sin cliente" grep -q 'ninguno' "$SKILL/plantillas/proyecto.yaml.example"
falso  "la SKILL.md sigue decidiendo por «declarado aquí»" grep -q 'solo está declarado aquí' "$MD"
fin "el nivel del cliente y el proyecto sin cliente están documentados en la SKILL.md y en la plantilla"
cierto "no dice dónde está la ruta del clon" grep -q '\.alambique-origen' "$MD"
fin "la SKILL.md dice dónde está la ruta del clon del marco"

# Lo que la SKILL.md declara que --validar NO hace, medido: si el validador
# cambia, este caso avisa de que el texto ya no dice la verdad.
{ cabecera; registro uno h-uno inventado "nodo"
  printf '    ip: no-es-una\n    usuario: alguien\n    clave_acceso: inventada\n'; } > "$F"
con_una --validar
rc 0; sale "esquema: 1 alias, sin problemas"
cierto "la SKILL.md no declara ese límite de --validar" grep -q 'no valida valores enumerados ni rechaza claves fuera del esquema' "$MD"
fin "--validar no mira valores enumerados ni claves de más, y la SKILL.md lo declara"

CON="$SKILL/plantillas/conexiones.yaml.example"
falso  "sigue diciendo que son obligatorias en todas las entradas" grep -q 'OBLIGATORIAS en todas las entradas' "$CON"
cierto "no dice que lo son en la ficha resuelta"                   grep -q 'ficha RESUELTA' "$CON"
fin "conexiones.yaml.example: las diez claves son obligatorias en la ficha resuelta, no en cada capa"

# El ejemplo de variantes de clientes.conf.example, byte a byte: sin
# configuración regional que iguale las letras con tilde.
variantes="$(grep -v '^[[:space:]]*#' "$SKILL/plantillas/clientes.conf.example" | grep -v '^[[:space:]]*$' | tail -n 1)"
for texto in 'compania ejemplo' 'compañía ejemplo' 'COMPAÑÍA EJEMPLO'; do
    printf '%s\n' "$texto" | LC_ALL=C grep -qiE -- "$variantes" || nota "no casa «$texto»"
done
if printf 'compañera ejemplo\n' | LC_ALL=C grep -qiE -- "$variantes"; then nota "casa «compañera ejemplo»"; fi
fin "clientes.conf.example: el ejemplo de variantes casa con y sin tilde byte a byte, y no lo que no es"

NEG="$SKILL/plantillas/negocio.conf.example"
for k in autor_empresa git_nombre git_correo; do
    cierto "$k no va marcada como informativa" \
        awk -v k="$k" '/INFORMATIVA/ { marca = 1 } /^$/ { marca = 0 } index($0, k "=") == 1 { hay = marca } END { exit !hay }' "$NEG"
done
for k in autor_nombre autor_correo firma_doc; do
    falso "$k, que sí lee el guard, va marcada como informativa" \
        awk -v k="$k" '/INFORMATIVA/ { marca = 1 } /^$/ { marca = 0 } index($0, k "=") == 1 { hay = marca } END { exit !hay }' "$NEG"
done
fin "negocio.conf.example: las claves que nadie lee van marcadas como informativas, y solo esas"

# ==============================================================================
echo "# Las diez claves, y las cinco capas"
# --validar echa en falta CADA una de las nueve que acompañan al alias.
for k in ssh_host cliente pais entorno so proposito criticidad modo legado_grep; do
    { cabecera; registro uno h-uno solo-lectura "nodo de prueba" | grep -v "^    $k:"; } > "$F"
    con_una --validar
    rc 4; sale "uno: falta $k"; sale "esquema: 1 problema(s); 1 alias leídos"
done
fin "--validar: echa en falta cada una de las nueve claves que acompañan al alias"
{ cabecera; registro uno h-uno solo-lectura "nodo de prueba"; } > "$F"
con_una --validar
rc 0
fin "… y con las diez no echa nada en falta (control)"

# Cinco niveles: proyecto, operación, cliente, cartera y puesto. Cada capa
# declara de `capas` una clave más que la anterior, con su propio valor.
C5="$CASA/cinco"; CART5="$C5/cartera"; CLI5="$CART5/cliente-5"; OP5="$CLI5/op-5"; PROY5="$OP5/proy-5"
mkdir -p "$C5/conf/_local" "$CART5/_local" "$CLI5/_local" "$OP5/_local" "$PROY5/_local" "$PROY5/src"
{ cabecera; registro capas h-puesto solo-lectura "del puesto"; } > "$C5/conf/_local/conexiones.yaml"
{ cabecera; printf '  - alias: capas\n    ssh_host: h-cartera\n    cliente: c-cartera\n    pais: p-cartera\n    entorno: e-cartera\n'; } > "$CART5/_local/conexiones.yaml"
{ cabecera; printf '  - alias: capas\n    ssh_host: h-cliente\n    cliente: c-cliente\n    pais: p-cliente\n'; } > "$CLI5/_local/conexiones.yaml"
{ cabecera; printf '  - alias: capas\n    ssh_host: h-operacion\n    cliente: c-operacion\n'; } > "$OP5/_local/conexiones.yaml"
{ cabecera; printf '  - alias: capas\n    ssh_host: h-proyecto\n'; } > "$PROY5/_local/conexiones.yaml"
printf 'cliente: cliente-5\nresponsable: alguien\n'    > "$CLI5/_local/proyecto.yaml"
printf 'cliente: cliente-5\noperacion: op-5\n'         > "$OP5/_local/proyecto.yaml"
printf 'proyecto: proy-5\ncliente: cliente-5\n'        > "$PROY5/_local/proyecto.yaml"
cinco() { correr "$PROY5/src" "ALAMBIQUE_CONF=$C5/conf" "ALAMBIQUE_PROYECTOS=$CART5" -- "$@"; }
cinco "$RES" --fuentes
rc 0
exacta "  1. $PROY5/_local/conexiones.yaml
  2. $OP5/_local/conexiones.yaml
  3. $CLI5/_local/conexiones.yaml
  4. $CART5/_local/conexiones.yaml
  5. $C5/conf/_local/conexiones.yaml"
fin "cinco capas: --fuentes las lista en orden, de la del proyecto a la del puesto"
cinco "$RES" capas
rc 0
veces '^ssh_host=h-proyecto$' 1; veces '^cliente=c-operacion$' 1; veces '^pais=p-cliente$' 1
veces '^entorno=e-cartera$' 1; veces '^proposito=del puesto$' 1; veces '^[a-z_]+=.+$' 10
fin "cinco capas: cada clave sale una vez, de la capa más específica que la declara"
cinco "$CTX"
rc 0; sale "Cliente    : cliente-5"; sale "Operación  : op-5"; sale "Proyecto   : proy-5"
sale "Nivel del cliente : ${CLI5#"$CASA"/}"; no_sale "Nivel del cliente : ${OP5#"$CASA"/}"
fin "cinco niveles: la operación sale de su capa, y el nivel del cliente es la declaración más alta"

# ==============================================================================
printf '\n%d casos: %d ok, %d FALLA\n' "$((N_OK + N_FALLA))" "$N_OK" "$N_FALLA"
if [ "$N_FALLA" -gt 0 ]; then
    printf 'HOME de la prueba, conservado para mirar: %s\n' "$CASA"
    exit 1
fi
rm -rf "${CASA:?}"
exit 0
