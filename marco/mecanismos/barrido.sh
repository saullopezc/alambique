#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# barrido.sh — Datos C2/C3 fuera de la capa local (R-02, R-03).
#
# Uso:
#   barrido.sh [ruta]     barre lo versionable de un árbol (por defecto: .)
#   barrido.sh --staged   solo lo preparado para commit, en el repositorio actual
#   barrido.sh --full     no enmascara los valores encontrados
#   barrido.sh --help     esta ayuda
#
# Salidas: 0 limpio · 1 hallazgos ALTA · 2 solo MEDIA
#          3 el barrido no pudo hacerse o quedó incompleto: opción desconocida,
#            ruta inexistente, fichero ilegible, fallo de git, o una
#            autocomprobación que no detecta: antes de barrer se da a sí mismo
#            una IP, una clave privada, un acceso y una credencial de prueba, y
#            si `awk`, `grep` o `sed` no los ven no hay veredicto.
#
# SOLO LECTURA. Reporta, nunca corrige.
#
# Barre lo que PUEDE acabar en el repositorio: seguimiento + sin seguir, menos
# lo ignorado. Por eso `_local/` no se barre —ignorada, no entra en un commit
# corriente— y por eso el barrido no sustituye a la regla de ignore, la
# complementa.
#
# MARCAS DEL PUESTO: además de los patrones generales lee `marcas.txt`
# (literales) y `clientes.conf` (regex) de <ruta>/_local/ —la ruta que se
# barre: la raíz del proyecto cuando se barre entero; al barrer un
# subdirectorio no se sube a buscarla— y de la capa local del puesto
# (<conf>/_local/; $ALAMBIQUE_LOCAL la cambia). Sin ninguna, lo dice.
#
# Enmascara por defecto: el informe se archiva, y no debe convertirse él mismo
# en el artefacto C2 que denuncia. De cada línea se sustituye lo que casó
# —[ip], [usuario@host], [host], [ruta], [valor], [marca]— y se deja la frase.
#
# Un fichero puede declararse exento con una línea de comentario que diga solo
# `alambique: exento`, en sus primeras 30 líneas. El comentario se reconoce
# por su signo —`#`, `;`, `//`, `--`, `/* … */`, `<!-- … -->`, o el `*` que
# abre una línea de un comentario de bloque—, con la frase en esa misma línea:
# suelta, con otro signo (`%`, `"`, `rem`) o con una viñeta de guion delante,
# no exime. Los exentos SE CUENTAN y se
# dicen, uno por línea (`EXENTO <fichero>`): una exención silenciosa es un
# agujero, una contada es una decisión.
# Mencionar la marca en prosa (como aquí) no exime: tiene que ir sola en su
# línea, para que este fichero no se exima a sí mismo por describirla.
#
# Lo que lleva bytes nulos se toma por binario y NO SE LEE: no es un hallazgo,
# pero tampoco está mirado, así que se cuenta y se nombra (`BINARIO <fichero>`).
# Un texto en UTF-16 o UTF-32 lleva bytes nulos sin ser binario: si empieza por
# su marca de orden (BOM) se convierte con `iconv` y se barre como los demás; sin
# marca, o sin `iconv`, queda nombrado como binario.
#
# LO QUE NO VE. Los patrones son un punto de partida: cubren las formas más
# corrientes, pueden no ser completos y cada puesto los ajusta a su caso. Un
# «0» dice que ninguno casó, no que el árbol esté limpio. Quedan fuera:
#   - Las credenciales cuya clave no se llama como el patrón espera. Se
#     reconocen por el NOMBRE (password, passwd, contraseña, secret, token,
#     api_key), no por la forma del valor: no ve `DB_PASS=`, `pwd=`, `clave=`,
#     `passphrase:`, `Authorization: Bearer …`, `--password X`, `mysql -pX` ni
#     `curl -u u:X`; ni un token suelto por su prefijo (`ghp_`, `AKIA`, `xoxb-`,
#     un JWT); ni una URL con el token delante de la arroba y sin `:`.
#   - Una credencial de MENOS DE OCHO caracteres, se llame como se llame la
#     clave: una `password` o una `passwd` con un valor de siete, como
#     `admin12`, pasa. El umbral evita el ruido de la prosa que nombra la
#     clave y cuesta las claves cortas, que son también las más débiles. Sin
#     comillas el valor se corta además en `&`, `;` y `,`: si antes del octavo
#     carácter hay uno, tampoco casa. Cuenta lo que vaya pegado al valor: un
#     acento grave o un paréntesis de cierre suman.
#   - Un valor entre comillas con un espacio dentro, si su primer tramo no
#     llega a ocho caracteres (`"mi clave larga"`).
#   - Una credencial real en una línea donde otra asignación recibe una
#     llamada, una lectura del entorno o su propio nombre: ese descarte mira la
#     línea entera, y la asignación que es código tapa a la real si esta va
#     sin comillas.
#   - La credencial que no va en una asignación: como contenido de un
#     elemento XML, tras un espacio y sin separador (la forma de un `.netrc`)
#     o en la celda de una tabla.
#   - Las coordenadas que no son IPv4: ni IPv6, ni un rango escrito
#     `192.0.2.7-9`, ni la IP dentro de un nombre (`app.192.0.2.7.nip.io`).
#   - Una IPv4 real con aspecto de versión: con una `v` pegada delante, con un
#     guion y un sufijo detrás, o tras la palabra «versión» o «release». Es el
#     precio de no gritar en cada fichero de dependencias.
#   - Un `usuario@host` que no es el destino de una orden de acceso: en prosa,
#     suelto, o repartido como en `ssh -l usuario host`; dentro del valor de
#     una opción con `=` (`-o ProxyJump=usuario@host`) o detrás del destino
#     (`ssh host -J usuario@host`); tras una opción cuyo valor es `-` o lleva un
#     espacio escapado; como elemento de una lista (`["ssh", "usuario@host"]`);
#     o en el comentario que cierra una clave pública.
#   - Casi todos los hosts y las rutas de servidor. El aviso MEDIA es una
#     lista corta, no un reconocedor: de hosts, solo los nombres que acaban en
#     `.local`, `.lan`, `.corp`, `.internal`, `.intranet` o `.prod`; de rutas,
#     solo las que cuelgan de `/opt`, `/srv`, `/u01`, `/u02`, `/app`, `/app<N>`
#     o `/export`. Un host con dominio real (`db01.example.com`) o una ruta
#     bajo `/var`, `/home` o `/data` no avisan: un nombre propio del puesto
#     solo lo ve la lista de marcas.
#   - Los nombres de fichero y de directorio, y el mensaje del commit: solo lee
#     contenido.
# El enmascarado tapa lo que casó, no el resto de la línea: un secreto que
# ningún patrón reconoce sale tal cual en el informe.
#
# FALSOS POSITIVOS conocidos, que hay que leer y clasificar: una versión de
# cuatro números sin nada que la delate (`paquete==N.N.N.N`), un título
# numerado a cuatro niveles (`### N.N.N.N Título`) y, bajo un nombre de
# credencial, un valor que es palabra reservada o identificador (`undefined`,
# `var.db_password`), o un literal entre comillas que no es un secreto: un
# texto de interfaz, una regla de validación (`'required|min:8'`). También la
# prosa que describe un campo: el nombre de la clave, dos puntos y una palabra
# de ocho letras o más. Una máscara de red escrita con sus cuatro números
# cuenta como IP. Y los ejemplos de acceso con un nombre de máquina: la orden
# `ssh` hacia un usuario en un dominio reservado para ejemplos, o en la propia
# máquina, da ALTA; solo se descartan las forjas públicas y los marcadores
# `usuario@servidor` y `user@host`.
# De MEDIA, que avisa y no detiene: un nombre de fichero que acaba en uno de
# esos sufijos (el `.env` de desarrollo en la propia máquina) y una ruta de
# aplicación que empieza como una de servidor (`/app/` en una imagen de
# contenedor, en una importación o en un enlace relativo a la raíz del sitio).
#
# Author       : Saul López
# Created Date : 2026-08-31

set -uo pipefail
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
unset -f grep sed awk find head cut sort tr wc date cat 2>/dev/null || true
unset CDPATH

# Un barrido que no puede barrer no dice «limpio»: sale con su propio código,
# para que quien lo llama —la puerta— no confunda un error con un veredicto.
fallo() { printf 'barrido: %s\n' "$*" >&2; exit 3; }

MODO="arbol"; FULL=0; RUTA=""
for a in "$@"; do
    case "$a" in
        --staged) MODO="staged" ;;
        --full)   FULL=1 ;;
        -h|--help) grep '^#' "$0" | sed -n '3,17p' | cut -c3-; exit 0 ;;
        -*) fallo "opción desconocida: $a (--help las lista)" ;;
        *)  [ -z "$RUTA" ] || fallo "solo se barre una ruta por llamada: sobra $a"
            RUTA="$a" ;;
    esac
done

if [ "$MODO" = "staged" ]; then
    [ -z "$RUTA" ] || fallo "--staged barre el índice del repositorio actual: no admite ruta"
    RUTA="$(git rev-parse --show-toplevel 2>/dev/null)" && [ -n "$RUTA" ] \
        || fallo "--staged necesita un repositorio git con árbol de trabajo"
    # Desde la raíz, los nombres del índice y los del listado son los mismos.
    cd -- "$RUTA" || fallo "no puedo entrar en $RUTA"
else
    RUTA="${RUTA:-.}"
    [ -e "$RUTA" ] || fallo "no existe: $RUTA"
    if [ -d "$RUTA" ]; then
        RUTA="$(cd -- "$RUTA" && pwd)" || fallo "no puedo entrar en el directorio indicado"
    fi
fi
ALTA=0; MEDIA=0; EXENTOS=0; BINARIOS=0; SIN_LEER=0

# Marcas propias del puesto: nombres de cliente, dominios, lo que sea que no
# deba salir. Una por línea. Si no existe, se barre igual con los patrones
# generales — pero las marcas son lo que convierte esto en útil de verdad.
# Dos formatos, y el NOMBRE del fichero dice cuál:
#   marcas.txt     texto literal, una marca por línea (`grep -F`)
#   clientes.conf  una expresión regular extendida por línea (`grep -E`), para
#                  cuando el nombre del cliente es una palabra corriente y hace
#                  falta un discriminante
# Tratar una regex como literal no falla: simplemente no casa nunca, y un
# control que no casa nunca es un control apagado que nadie ve.
# Se leen TODOS los que existan, del proyecto y del puesto: lo que el proyecto
# añade no apaga lo que el puesto ya vigila.
# <conf> es el directorio de configuración del harness, sin asumir cuál.
if [ -r "$(dirname "$0")/lib/harness.sh" ]; then
    . "$(dirname "$0")/lib/harness.sh"
    CONF="$(conf_puesto)"
else
    CONF="${ALAMBIQUE_CONF:-$HOME/.alambique}"
fi
# Cada lista se pasa a `grep -f`, y ahí UNA LÍNEA VACÍA CASA CON TODO: cada
# línea del árbol sale como ALTA, la puerta bloquea siempre, y un control que
# salta siempre es un control apagado. Se filtran vacías y comentarios ANTES,
# en un fichero temporal; si no queda nada, es como no tener lista.
# El retorno de carro también se quita: una lista guardada con finales CRLF
# deja cada marca con un carácter de más y no casa con nada.
BLOB="$(mktemp)" && TEXTO="$(mktemp)" && LISTA="$(mktemp)" && LINEA="$(mktemp)" \
    && MARCAS_F="$(mktemp)" && MARCAS_E="$(mktemp)" \
    || fallo "no puedo crear ficheros temporales"
trap 'rm -f "$BLOB" "$TEXTO" "$LISTA" "$LINEA" "$MARCAS_F" "$MARCAS_E"' EXIT
limpiar() { tr -d '\r' < "$1" 2>/dev/null | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$'; }
for d in "$RUTA/_local" "${ALAMBIQUE_LOCAL:-$CONF/_local}"; do
    [ -r "$d/marcas.txt" ]    && limpiar "$d/marcas.txt"    >> "$MARCAS_F"
    [ -r "$d/clientes.conf" ] && limpiar "$d/clientes.conf" >> "$MARCAS_E"
done
[ -s "$MARCAS_F" ] || { rm -f "$MARCAS_F"; MARCAS_F=""; }
[ -s "$MARCAS_E" ] || { rm -f "$MARCAS_E"; MARCAS_E=""; }
MARCAS="${MARCAS_F}${MARCAS_E}"     # no vacío si hay alguna lista
# Una expresión mal escrita hace fallar a grep en cada fichero, y con el error
# descartado la lista entera queda apagada sin que nadie lo vea.
if [ -n "$MARCAS_E" ]; then
    grep -E -f "$MARCAS_E" /dev/null >/dev/null 2>&1
    [ $? -le 1 ] || fallo "clientes.conf tiene una expresión regular que grep -E no acepta"
fi

# Los patrones generales se aplican byte a byte (LC_ALL=C) y como texto (-a):
# un fichero en una codificación de un byte por carácter distinta de la del
# puesto (Latin-1, Windows-1252) no es binario, y sus líneas se leen igual.
# Las marcas sí usan la configuración regional del puesto, porque comparan sin
# distinguir mayúsculas también en ñ y vocales con tilde.
buscar() { LC_ALL=C grep -a "$@"; }
casar_marcas() {  # <opción de grep: -n | -o> <fichero>
    [ -n "$MARCAS_F" ] && grep -a -i -F "$1" -f "$MARCAS_F" -- "$2" 2>/dev/null
    [ -n "$MARCAS_E" ] && grep -a -i -E "$1" -f "$MARCAS_E" -- "$2" 2>/dev/null
    return 0
}

# --- Ficheros candidatos -----------------------------------------------------
# Los nombres salen separados por NUL (-z, -print0): así git no entrecomilla
# los que llevan ñ, tildes o espacios, y un salto de línea dentro de un nombre
# no lo parte en dos.
if [ "$MODO" = "staged" ]; then
    ORIGEN="indice"
elif git -C "$RUTA" rev-parse --git-dir >/dev/null 2>&1; then
    ORIGEN="git"
else
    ORIGEN="find"
fi
listar() {
    case "$ORIGEN" in
        indice)
            # Todo lo que entra al commit salvo los borrados. Sin detección de
            # renombrados, un fichero movido es un alta con su contenido entero.
            git diff --cached --name-only -z --no-renames --diff-filter=d ;;
        git)
            # Seguidos + sin seguir, EXCLUYENDO lo ignorado: exactamente lo que
            # puede acabar en un commit.
            git -C "$RUTA" ls-files -z -co --exclude-standard | sort -zu ;;
        find)
            find "$RUTA" -type f \
                 ! -path '*/.git/*' ! -path '*/_local/*' ! -path '*/__restriccion/*' \
                 ! -path '*/node_modules/*' ! -path '*/.venv/*' -print0 ;;
    esac
}

# Un nombre de fichero ocupa siempre una línea del informe.
visible() { printf '%s' "${1//[[:cntrl:]]/?}"; }

# Enmascara SOLO lo sensible, no la frase. Un informe ilegible no se lee, y uno
# que no se lee no remedia nada.
# Las marcas van primero y por el texto exacto que casó. Después, el acceso
# `usuario@host` entero (los corchetes entran en su patrón para que una marca
# ya sustituida no lo parta; en una URL, desde `://`, para que se vaya también
# la clave), y solo entonces las IP sueltas: al revés, la IP sustituida deja
# el usuario a la vista. Se enmascara ANTES de recortar: una
# IP partida por el recorte ya no casa con su patrón.
enmascarar() {  # texto
    local t="$1" m
    [ "$FULL" -eq 1 ] && { printf '%s' "$t"; return; }
    if [ -n "$MARCAS" ]; then
        # De la más larga a la más corta: una marca contenida en otra no deja
        # a la vista el resto de la larga. La línea va a un fichero porque la
        # leen las dos listas, y una tubería solo se lee una vez.
        printf '%s\n' "$t" > "$LINEA"
        while IFS= read -r m; do
            [ -n "$m" ] && t="${t//"$m"/[marca]}"
        done <<EOF
$(casar_marcas -o "$LINEA" | awk '{ print length($0) " " $0 }' | sort -rn | cut -d' ' -f2-)
EOF
    fi
    printf '%s' "$t" | LC_ALL=C sed -E \
        -e 's#(://)[^/[:space:]@"'"'"']*@[][A-Za-z0-9.-]+#\1[usuario@host]#g' \
        -e 's/[][A-Za-z0-9._-]+@[][A-Za-z0-9.-]+/[usuario@host]/g' \
        -e 's/([0-9]{1,3}\.){3}[0-9]{1,3}/[ip]/g' \
        -e 's/([A-Za-z0-9-]+\.)+(local|lan|corp|internal|intranet|prod)(\.?([^A-Za-z0-9.]|$))/[host]\3/g' \
        -e 's#(^|[^A-Za-z0-9_])/(opt|srv|u01|u02|app[0-9]*|export)/[^[:space:]"'"'"'`]*#\1[ruta]#g' \
        -e 's/('"$P_NOMBRE"'["'"'"']?)[^[:space:]"'"'"']+/\1[valor]/Ig' \
        -e 's/([:=][[:space:]]*["'"'"']?)[A-Za-z0-9\/+_.-]{8,}/\1[valor]/g'
}

reportar() {  # nivel fichero linea texto
    printf '  %-5s %s:%s\n' "$1" "$(visible "$2")" "$3"
    printf '        %s\n' "$(enmascarar "$4" | cut -c1-120)"
}

# --- Patrones ----------------------------------------------------------------
# ALTA: detiene el commit. No siempre es un dato real: los falsos positivos
# conocidos están en la cabecera.
#   - bloque de clave privada, con cualquier prefijo (RSA, OPENSSH, PGP…)
#   - IPv4 literal (se excluyen loopback, cualquiera, broadcast y los rangos
#     de documentación RFC 5737, que existen justo para poder escribirlos)
#   - usuario@host como argumento de una orden de acceso remoto. La orden es
#     una palabra entera (`openssh-server` no lo es) y el acceso, argumento
#     SUYO: tras `ssh`, `sftp`, `ssh-copy-id` o `autossh`, con solo opciones y
#     variables entre medias; tras `scp`, `rsync` o `sshfs`, en cualquier
#     argumento y seguido de `:`; o dentro de una URL de esos esquemas. Una
#     dirección de correo en una frase que nombra la orden no es su argumento
#   - asignación de contraseña/token con valor real. El nombre puede llevar
#     algo delante y tramos `_palabra` detrás, que es la forma de una variable
#     de entorno (`AWS_SECRET_ACCESS_KEY`, `db_password`, `API_TOKEN_PROD`), e
#     ir entre comillas; el separador es `:`, `=`, `:=` o `=>`, que son las
#     formas de JSON, de un diccionario y de una tabla asociativa.
#     El valor empieza por letra, cifra o `/+_.-` (un marcador como `<token>`
#     o `$VAR` no) y lleva los símbolos que lleve. Entre comillas llega hasta
#     la comilla o hasta el primer espacio; sin ellas, hasta el espacio o el
#     separador (`&`, `;`, `,`), para que `token=abc&otro=valor` no cuente
#     como un valor largo
#   - URL con usuario y clave dentro, entre `://` y la arroba del host, se
#     llame como se llame la clave que la guarda. Una clave que empieza por
#     `<`, `$` o `{` es un marcador y no cuenta: `esquema://<usuario>:<clave>@host`
P_CLAVE='-----BEGIN[A-Z ]*PRIVATE KEY( BLOCK)?-----'
P_ARROBA='[A-Za-z0-9._-]+@[A-Za-z0-9.-]+'
# Lo que puede ir entre la orden y su destino: una opción con su valor, o una
# variable. Una palabra corriente ahí dice que la línea es prosa.
P_SSH_OPCION="(-[^[:space:]]+([[:space:]]+(\"[^\"]*\"|'[^']*'|[^-[:space:]][^[:space:]]*))?|[\"']?[\$][^[:space:]]+)"
P_SSH="(^|[^A-Za-z0-9_.-])((ssh|ssh-copy-id|autossh|sftp)([[:space:]]+${P_SSH_OPCION})*[[:space:]]+[\"']?${P_ARROBA}"
P_SSH="${P_SSH}|(scp|rsync|sshfs)[[:space:]]+([^|;&]*[[:space:]])?[\"']?${P_ARROBA}:)|(ssh|sftp|scp|rsync)://${P_ARROBA}"
# Accesos que no son coordenadas de nadie: las forjas públicas, donde el
# usuario es siempre `git`, y los marcadores con que se escribe un ejemplo. El
# nombre va entero: `usuario@servidor.example.com` ya es un host.
P_NO_ACCESO='(^|[^A-Za-z0-9._-])(git@(github[.]com|gitlab[.]com|bitbucket[.]org)|(usuario|user)@(servidor|host))([^A-Za-z0-9.-]|[.]*$|[.]+[^A-Za-z0-9.-])'
P_URL_CRED='[A-Za-z][A-Za-z0-9+.-]*://[^/[:space:]:@"'"'"']*:[A-Za-z0-9+_.-][^/[:space:]@"'"'"']*@'
# Los patrones se comparan byte a byte, y ahí la ñ minúscula y la mayúscula no
# son la misma letra con otra caja: van las dos.
P_PALABRA='(password|passwd|contrase(n|ñ|Ñ)a|secret|token|api[_-]?key)'
P_NOMBRE="${P_PALABRA}"'(_[A-Za-z0-9]+)*["'"'"']?[[:space:]]*(:=|=>|[:=])[[:space:]]*'
P_CRED="${P_NOMBRE}"'(["'"'"'][A-Za-z0-9/+_.-][^[:space:]"'"'"']{7,}|[A-Za-z0-9/+_.-][^[:space:]"'"'"'&;,]{7,})'
# Sufijos del nombre que dicen que el valor NO es el secreto, sino dónde está,
# cómo se llama o cuánto dura: `token_url`, `password_file`, `secret_name`,
# `api_key_header`, `token_ttl`, `password_min_length`. Son claves corrientes
# en cualquier configuración, y una puerta que se cierra con cada una enseña a
# saltársela.
P_NO_SECRETO='url|uri|endpoint|file|filename|path|dir|name|header|field|param|type|format|algorithm|prefix|scope|version|ref|arn|ttl|timeout|lifetime|duration|expiry|expires|expires_in|expires_at|expiration|length|policy|hint|label|placeholder|command|env|var'
# MEDIA: sospechoso, pide una mirada.
# Un punto DESPUÉS del sufijo, con algo detrás, lo descarta: `settings.local.json`
# es un nombre de fichero, no un host. Cuesta los FQDN de tres tramos
# (`srv.corp.example.com`) y a cambio evita que el barrido grite en cada
# plantilla — que es como se acaba ignorando su salida. El punto que cierra la
# frase no cuenta: detrás no lleva nombre.
P_HOST='[A-Za-z0-9-]+\.(local|lan|corp|internal|intranet|prod)\.?([^A-Za-z0-9.]|$)'
P_RUTA='(^|[^A-Za-z0-9_])/(opt|srv|u01|u02|app[0-9]*|export)/[A-Za-z0-9]'

# Descarta lo que parece credencial y es código que la MANEJA. El patrón ve un
# nombre, un `=` y ocho caracteres; no distingue un valor de una variable. Se
# descarta cuando, sin comillas, lo asignado es:
#   - una llamada, un miembro o un índice:  token = cabecera.substring(7)
#   - una lectura del entorno:              api_key=os.environ["CLAVE"]
#   - el propio nombre, pasado tal cual:    password=password
#     (también como `"password": password` y `password => password.length`)
# Un literal entre comillas no se descarta nunca por esta vía. Mismo compromiso
# que con las versiones: calla ante el código que lee un secreto para no gritar
# en cada ejemplo. Este descarte (`cred_falsa`) mira la LÍNEA ENTERA: si una
# asignación de la línea es código, se calla la línea aunque otra lleve un
# valor real.
#
# ¿Lleva la línea alguna asignación cuyo valor sea el secreto? Aquí cada
# asignación se juzga por separado: una que no lo es por su nombre o por su
# valor no tapa a la que sí, en la misma línea. No lo es cuando:
#   - el nombre acaba en uno de los sufijos de arriba
#   - el valor es una ruta de fichero (`/…`, `./…`, `../…`): dice dónde está
#     el secreto, y si es una ruta de servidor ya la avisa su propio patrón
#   - el valor es una URL http(s): si lleva usuario y clave dentro, la ve el
#     patrón de las URL con credenciales
cred_real() {  # línea
    local m
    while IFS= read -r m; do
        [ -n "$m" ] || continue
        printf '%s' "$m" | buscar -qiE "^${P_PALABRA}(_[A-Za-z0-9]+)*_(${P_NO_SECRETO})[\"']?[[:space:]]*[:=]" && continue
        printf '%s' "$m" | buscar -qiE "^${P_NOMBRE}[\"']?([.][.]?)?/[A-Za-z0-9._/~-]*\$" && continue
        printf '%s' "$m" | buscar -qiE "^${P_NOMBRE}[\"']?https?://" && continue
        return 0
    done <<EOF
$(printf '%s' "$1" | buscar -oiE -e "$P_CRED")
EOF
    return 1
}

cred_falsa() {
    printf '%s' "$1" | buscar -qiE "${P_NOMBRE}[\"']" && return 1
    printf '%s' "$1" | buscar -qiE "${P_NOMBRE}[A-Za-z_][A-Za-z0-9_]*([.][A-Za-z_][A-Za-z0-9_]*)*[[:space:]]*[(\\[]" && return 0
    printf '%s' "$1" | buscar -qiE "${P_NOMBRE}(os[.]environ|os[.]getenv|getenv|process[.]env|System[.]getenv|[\$]ENV|[\$][{(])" && return 0
    for _k in password passwd contrasena contraseña secret token api_key apikey api-key; do
        printf '%s' "$1" | buscar -qiE "(^|[^A-Za-z0-9_])(${_k}[[:space:]]*=>?|[\"']${_k}[\"'][[:space:]]*(:|=>?))[[:space:]]*${_k}([^A-Za-z0-9_]|\$)" && return 0
    done
    return 1
}

# ¿Queda en la línea algún acceso remoto que no sea una forja pública ni un
# marcador? Se quitan esos y se vuelve a mirar: así el que sí es real no queda
# tapado por un ejemplo en la misma línea. La sustitución va dos veces porque
# cada una se lleva el separador de los lados, y dos seguidos lo comparten.
acceso_real() {  # línea
    printf '%s\n' "$1" | LC_ALL=C sed -E -e "s/${P_NO_ACCESO}/\\1_\\6/Ig" -e "s/${P_NO_ACCESO}/\\1_\\6/Ig" \
        | buscar -qiE -e "$P_SSH"
}

# Líneas con al menos una IPv4 real, como `n:texto`.
# Cada IP de la línea se juzga POR SEPARADO y entera: basta una real para que
# la línea sea hallazgo, aunque al lado haya un loopback o un número de versión.
# Una IP es el tramo completo de cifras y puntos: `1.2.3.4.5` no lo es, y la
# que cierra una frase («está en 192.0.2.7.») sí, sin su punto final.
# No cuentan:
#   - 0.0.0.0, 255.255.255.255, el loopback 127.0.0.0/8 y los tres rangos de
#     documentación
#   - los números de versión. Uno de cuatro partes es indistinguible de una IP
#     mirando solo el número, así que se mira lo que lo TOCA: una `v` pegada
#     delante, un guion y un sufijo detrás (`1.2.3.4-beta`), o la palabra
#     «versión» o «release» justo antes, sin más que signos entre medias.
#     Es un compromiso consciente: prefiere callar ante una versión a gritar
#     en cada fichero de dependencias, porque un barrido que grita se acaba
#     ignorando.
# Sin intervalos `{n}` ni clases POSIX: mawk no los tiene en todas sus versiones.
ips_reales() {  # fichero
    LC_ALL=C awk '
    function es_version(antes, despues,    a) {
        a = tolower(antes)
        if (a ~ /(^|[^a-z0-9])v$/) return 1
        if (a ~ /(version|versi(ó|Ó)n|release)(e?s)?[^a-z0-9]*$/) return 1
        return (despues ~ /^-[A-Za-z0-9]/)
    }
    function real(ip, antes, despues,    o) {
        split(ip, o, ".")
        if (o[1] + o[2] + o[3] + o[4] == 0) return 0
        if (o[1] == 255 && o[2] == 255 && o[3] == 255 && o[4] == 255) return 0
        if (o[1] == 127) return 0
        if (o[1] == 192 && o[2] == 0  && o[3] == 2)   return 0
        if (o[1] == 198 && o[2] == 51 && o[3] == 100) return 0
        if (o[1] == 203 && o[2] == 0  && o[3] == 113) return 0
        return !es_version(antes, despues)
    }
    {
        resto = $0; antes = ""
        while (match(resto, /[0-9.]+/)) {
            tramo = substr(resto, RSTART, RLENGTH)
            previo = antes substr(resto, 1, RSTART - 1)
            resto = substr(resto, RSTART + RLENGTH)
            antes = previo tramo
            ip = tramo
            # El punto final es de la frase salvo que siga un nombre:
            # `1.2.3.4.tar` es un fichero, no una IP y un punto.
            if (ip ~ /\.$/ && substr(resto, 1, 1) !~ /[A-Za-z_]/) sub(/\.+$/, "", ip)
            if (ip !~ /^[0-9][0-9]?[0-9]?\.[0-9][0-9]?[0-9]?\.[0-9][0-9]?[0-9]?\.[0-9][0-9]?[0-9]?$/) continue
            if (real(ip, previo, substr(tramo, length(ip) + 1) resto)) { print NR ":" $0; next }
        }
    }' < "$1"
}

# Autocomprobación. Un barrido que no detecta dice «ALTA: 0» igual que uno que
# no encuentra nada: antes de barrer se le da una IP, una clave privada, una
# credencial y un acceso compuestos aquí mismo, y si no los ve —falta una
# utilidad, o la de este sistema no entiende el patrón— no hay veredicto.
printf 'host %s\n%s\n%s\n' "$(printf '10.20.30.%s' 40)" \
    "$(printf -- '-----BEGIN RSA %s KEY-----' PRIVATE)" \
    "$(printf 'pass%s: %s' word Xk29LmQ8pZ7w)" > "$TEXTO" 2>/dev/null
[ -n "$(ips_reales "$TEXTO" 2>/dev/null)" ] \
    && buscar -qE -e "$P_CLAVE" -- "$TEXTO" 2>/dev/null \
    && buscar -qEi -e "$P_CRED" -- "$TEXTO" 2>/dev/null \
    && acceso_real "$(printf '%s operador@%s' ssh nodo-de-prueba)" 2>/dev/null \
    || fallo "la autocomprobación no detecta una IP, una clave privada, una credencial o un acceso de prueba: falta awk, grep o sed, o no entienden los patrones. Sin eso no hay veredicto"

printf '\nbarrido — %s\n\n' "$([ "$MODO" = staged ] && echo 'ficheros preparados' || echo "$RUTA")"

listar > "$LISTA" || fallo "no puedo listar los ficheros candidatos"

while IFS= read -r -d '' f; do
    [ -n "$f" ] || continue
    # `src` es lo que se lee; `f`, el nombre que se reporta. Con --staged se lee
    # el CONTENIDO PREPARADO, no el fichero de trabajo: tras un `git add -p` son
    # distintos, y lo que entra al commit es lo primero.
    case "$ORIGEN" in
        indice)
            # Modo y blob salen del índice, y el blob se pide por su
            # identificador: así el nombre no se interpreta en ningún momento.
            meta="$(git --literal-pathspecs ls-files -s -- "$f")" \
                || fallo "no puedo consultar el índice: $(visible "$f")"
            read -r modo blob _ <<EOF
$meta
EOF
            # Un submódulo es un puntero a otro repositorio: aquí no hay
            # contenido suyo que leer.
            [ "${modo:-}" = "160000" ] && continue
            # Lo que está en el listado y no se puede leer no se da por limpio.
            [ -n "${blob:-}" ] && git cat-file blob "$blob" > "$BLOB" 2>/dev/null \
                || fallo "no puedo leer del índice: $(visible "$f")"
            src="$BLOB" ;;
        git)  src="$RUTA/$f" ;;
        find) src="$f"; f="${f#"$RUTA"/}" ;;
    esac
    [ -f "$src" ] || continue
    if [ ! -r "$src" ]; then
        printf 'barrido: no puedo leer %s\n' "$(visible "$f")" >&2
        SIN_LEER=$((SIN_LEER+1)); continue
    fi
    [ -s "$src" ] || continue
    # Un texto en UTF-16 o UTF-32 se reconoce por su marca de orden; convertido,
    # se lee como cualquier otro. iconv deduce el orden de bytes de la marca.
    case "$(head -c 4 "$src" | od -An -tx1 | tr -d ' \n')" in
        fffe0000|0000feff) cod="UTF-32" ;;
        fffe*|feff*)       cod="UTF-16" ;;
        *)                 cod="" ;;
    esac
    if [ -n "$cod" ] && iconv -f "$cod" -t UTF-8 < "$src" > "$TEXTO" 2>/dev/null; then
        src="$TEXTO"
    fi
    # Lo que aún lleva bytes nulos no se puede leer por líneas. No bloquea
    # —una imagen no es una fuga—, pero se dice: no está mirado.
    if ! buscar -Iq '' "$src" 2>/dev/null; then
        printf '  BINARIO %s\n' "$(visible "$f")"
        BINARIOS=$((BINARIOS+1)); continue
    fi
    # Exención declarada. grep lee la entrada entera (sin -q): si cortara al
    # primer acierto, `head` moriría por la tubería rota y, con pipefail, la
    # exención dependería del tamaño de las líneas.
    if head -n 30 "$src" 2>/dev/null | buscar -E '^[[:space:]]*(#+|;+|//+|--|/[*]+|<!--|[*])[[:space:]]*alambique: exento[[:space:]]*(-->|[*]+/)?[[:space:]]*$' >/dev/null; then
        printf '  EXENTO %s\n' "$(visible "$f")"
        EXENTOS=$((EXENTOS+1)); continue
    fi

    # `-e` delante del patrón: el de la clave empieza por guiones y, sin él,
    # grep lo toma por una opción.
    while IFS=: read -r n texto; do
        [ -n "${n:-}" ] || continue
        reportar ALTA "$f" "$n" "$texto"; ALTA=$((ALTA+1))
    done <<EOF
$(buscar -nE -e "$P_CLAVE" -- "$src" 2>/dev/null)
EOF

    while IFS=: read -r n texto; do
        [ -n "${n:-}" ] || continue
        reportar ALTA "$f" "$n" "$texto"; ALTA=$((ALTA+1))
    done <<EOF
$(ips_reales "$src" 2>/dev/null)
EOF

    # La línea se parte a mano: `read` con `IFS=:` se lleva los dos puntos
    # del final, y son los que dicen que `usuario@host:` es un destino.
    while IFS= read -r hallada; do
        n="${hallada%%:*}"; texto="${hallada#*:}"
        [ -n "${n:-}" ] || continue
        acceso_real "$texto" || continue
        reportar ALTA "$f" "$n" "$texto"; ALTA=$((ALTA+1))
    done <<EOF
$(buscar -nEi -e "$P_SSH" -- "$src" 2>/dev/null)
EOF

    while IFS=: read -r n texto; do
        [ -n "${n:-}" ] || continue
        cred_real "$texto" || continue
        cred_falsa "$texto" && continue
        reportar ALTA "$f" "$n" "$texto"; ALTA=$((ALTA+1))
    done <<EOF
$(buscar -nEi -e "$P_CRED" -- "$src" 2>/dev/null)
EOF

    while IFS=: read -r n texto; do
        [ -n "${n:-}" ] || continue
        reportar ALTA "$f" "$n" "$texto"; ALTA=$((ALTA+1))
    done <<EOF
$(buscar -nE -e "$P_URL_CRED" -- "$src" 2>/dev/null)
EOF

    for p in "$P_HOST" "$P_RUTA"; do
        while IFS=: read -r n texto; do
            [ -n "${n:-}" ] || continue
            reportar MEDIA "$f" "$n" "$texto"; MEDIA=$((MEDIA+1))
        done <<EOF
$(buscar -nE -e "$p" -- "$src" 2>/dev/null)
EOF
    done

    if [ -n "$MARCAS" ]; then
        # Una línea que casa en las dos listas se cuenta una vez.
        while IFS=: read -r n texto; do
            [ -n "${n:-}" ] || continue
            reportar ALTA "$f" "$n" "$texto"; ALTA=$((ALTA+1))
        done <<EOF
$(casar_marcas -n "$src" | sort -t: -k1,1n -u)
EOF
    fi
done < "$LISTA"

printf '\nALTA: %s  MEDIA: %s  exentos: %s  binarios: %s\n' "$ALTA" "$MEDIA" "$EXENTOS" "$BINARIOS"
[ -n "$MARCAS" ] || printf 'sin lista de marcas propias — solo patrones generales\n'
printf '\n'

# Un fichero sin leer deja el barrido a medias, y a medias no hay veredicto.
[ "$SIN_LEER" -gt 0 ] && fallo "incompleto: $SIN_LEER fichero(s) sin leer"
[ "$ALTA"  -gt 0 ] && exit 1
[ "$MEDIA" -gt 0 ] && exit 2
exit 0
