#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# pruebas/coherencia.sh — Banco de lo que la prosa afirma de la norma y de los
# mecanismos: lo que se puede contar, se cuenta aquí y no se escribe a mano.
#
# Uso:
#   pruebas/coherencia.sh [raíz del repositorio]     por defecto, la de este script
#
# La fuente es una sola por dato, y la prosa que lo repite se compara con ella:
#   - la tabla de `marco/NORMA.md` dice quién comprueba cada regla: de ahí sale
#     el recuento, y contra él van las frases que lo citan;
#   - el título de cada mecanismo dice qué reglas vigila: una regla cuyo
#     mecanismo declara lo que no ve no puede figurar como mecanizada entera, y
#     una que la tabla da a una máquina tiene que tener mecanismo que la cite;
#   - el texto de las reglas que viaja en las plantillas de contexto es el de
#     la norma, letra por letra;
#   - los guards, los hooks y los bancos que la prosa cuenta son los que hay.
# QUÉ NO DECIDE: si una regla está mecanizada entera o a medias lo juzga una
# persona; el banco solo impide que ese juicio contradiga lo que los propios
# mecanismos declaran. Una línea `ok` o `FALLA` por caso; termina 0 solo si
# todos pasan.
#
# Author       : Saul López
# Created Date : 2026-10-11

set -uo pipefail
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

RAIZ="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
NORMA="$RAIZ/marco/NORMA.md"; MEC="$RAIZ/marco/mecanismos"; PLA="$RAIZ/marco/plantillas"
[ -r "$NORMA" ] || { echo "no encuentro $NORMA" >&2; exit 2; }

CASOS=0; FALLAN=0
caso() {  # <descripción> <obtenido> <esperado>
    CASOS=$((CASOS+1))
    if [ "$2" = "$3" ]; then printf '  ok     %s\n' "$1"
    else printf '  FALLA  %s — esperado: %s · obtenido: %s\n' "$1" "$3" "$2"; FALLAN=$((FALLAN+1)); fi
}
numero() {  # una cifra o su nombre, en cifra
    case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
        ninguna|ninguno) echo 0 ;; un|una|uno) echo 1 ;; dos) echo 2 ;; tres) echo 3 ;; cuatro) echo 4 ;;
        cinco) echo 5 ;; seis) echo 6 ;; siete) echo 7 ;; ocho) echo 8 ;; nueve) echo 9 ;; diez) echo 10 ;;
        once) echo 11 ;; doce) echo 12 ;; *) echo "$1" ;;
    esac
}

# --- La tabla de la norma: regla, texto y quién la comprueba -----------------
# Una línea por regla: R-NN <tab> entera|parcial|nadie <tab> texto sin marcas.
TABLA="$(awk -F' [|] ' '/^[|] [*][*]R-[0-9][0-9][*][*] [|]/ {
        id = $1; gsub(/[^R0-9-]/, "", id)
        quien = "nadie"
        if ($3 ~ /^[*][*]Máquina[*][*]/) quien = "entera"; else if ($3 ~ /^[*][*]Máquina/) quien = "parcial"
        texto = $2; gsub(/[*]/, "", texto); gsub(/[ \t]+/, " ", texto); sub(/ $/, "", texto)
        print id "\t" quien "\t" texto }' "$NORMA")"
cuantas() { printf '%s\n' "$TABLA" | awk -F'\t' -v q="$1" '$2 == q { n++ } END { print n + 0 }'; }
quien()   { printf '%s\n' "$TABLA" | awk -F'\t' -v r="$1" '$1 == r { print $2 }'; }
ENTERAS="$(cuantas entera)"; PARCIALES="$(cuantas parcial)"; NADIE="$(cuantas nadie)"
TOTAL="$(printf '%s\n' "$TABLA" | awk 'NF { n++ } END { print n + 0 }')"

printf 'la tabla de la norma: %s reglas — %s enteras, %s a medias, %s de nadie\n' "$TOTAL" "$ENTERAS" "$PARCIALES" "$NADIE"
caso 'la tabla trae las reglas R-01 a R-12, una vez cada una' \
     "$(printf '%s\n' "$TABLA" | cut -f1 | tr '\n' ' ')" "R-01 R-02 R-03 R-04 R-05 R-06 R-07 R-08 R-09 R-10 R-11 R-12 "

# --- El recuento que la prosa cita --------------------------------------------
# «N mecanizada(s) entera(s) … N a medias … N que dependen»: las tres cifras, en
# ese orden, de la frase del fichero.
recuento() {  # <fichero>
    tr '\n' ' ' < "$1" | sed -E 's/[*]//g' | awk '{
        if (match($0, /[A-Za-z0-9]+ (reglas? )?(está |están )?mecanizadas? enteras?[.,] +[A-Za-z0-9]+ (lo están )?a medias[.]?( y)? +[A-Za-z0-9]+ /)) {
            f = substr($0, RSTART, RLENGTH); n = split(f, p, " "); a = p[1]
            for (i = 2; i <= n; i++) if (p[i] == "medias" || p[i] == "medias.") { c = p[i + 1] == "y" ? p[i + 2] : p[i + 1] }
            for (i = 2; i <= n; i++) if (p[i] ~ /^enteras?[.,]$/) b = p[i + 1]
            print a, b, c
        } }'
}
for f in "$NORMA" "$RAIZ/marco/README.md"; do
    set -- $(recuento "$f")
    caso "el recuento de ${f#"$RAIZ"/} es el de la tabla" \
         "$(numero "${1:-?}") $(numero "${2:-?}") $(numero "${3:-?}")" "$ENTERAS $PARCIALES $NADIE"
done
caso 'el bloque de contexto dice cuántas no comprueba nadie' \
     "$(numero "$(sed -n -E 's/.*[*][*] ([A-Za-z]+) no las comprueba nadie.*/\1/p' "$PLA/contexto-global.bloque.md")")" "$NADIE"
caso 'el resumen del marco dice cuántas no comprueba ninguna máquina' \
     "$(numero "$(tr '\n' ' ' < "$RAIZ/marco/README.md" | sed -n -E 's/.*Las ([a-z]+) reglas que ninguna máquina comprueba.*/\1/p')")" "$NADIE"

# --- Cada regla y su mecanismo ------------------------------------------------
# Las reglas que cita el primer párrafo de la cabecera de un script.
citadas() { awk 'NR > 3 && /^#[ \t]*$/ { exit } NR > 3' "$1" | grep -oE 'R-[0-9][0-9]' | sort -u; }
# ¿Declara lo que no ve? La puerta lo dice con otras palabras: por dónde se salta.
declara() { grep -qE 'LO QUE NO VE|Se salta con' "$1"; }
CON_MECANISMO=""; mal=""
for s in "$MEC"/*.sh "$RAIZ"/marco/adaptadores/*.sh; do
    for r in $(citadas "$s"); do
        CON_MECANISMO="$CON_MECANISMO $r"
        [ "$(quien "$r")" != nadie ] || mal="$mal ${s##*/}:$r"
    done
done
caso 'ninguna regla que cita un mecanismo figura como de nadie' "$mal" ""
mal=""
for r in $(printf '%s\n' "$TABLA" | awk -F'\t' '$2 != "nadie" { print $1 }'); do
    case " $CON_MECANISMO " in *" $r "*) ;; *) mal="$mal $r" ;; esac
done
caso 'toda regla que la tabla da a una máquina tiene mecanismo que la cite' "$mal" ""
mal=""
for s in "$MEC"/*.sh; do
    declara "$s" || continue
    for r in $(citadas "$s"); do [ "$(quien "$r")" != entera ] || mal="$mal ${s##*/}:$r"; done
done
caso 'ninguna regla es «entera» si su mecanismo declara lo que no ve' "$mal" ""
mal=""
for s in "$MEC"/barrido.sh "$MEC"/puerta.sh "$MEC"/guard-*.sh; do declara "$s" || mal="$mal ${s##*/}"; done
caso 'el barrido, la puerta y los guards declaran lo que no ven' "$mal" ""

# --- El texto de las reglas en las plantillas de contexto ---------------------
# Cada `- **R-NN · texto**…` de una plantilla, en una línea y sin marcas.
en_plantilla() {  # <fichero>
    awk 'function sale(   i, s) {
             s = " · "; sub(/^- /, "", r); gsub(/[*]/, "", r); gsub(/[ \t]+/, " ", r); sub(/ $/, "", r)
             i = index(r, s); print substr(r, 1, i - 1) "\t" substr(r, i + length(s)); r = "" }
         /^- [*][*]R-[0-9][0-9] · / { if (r != "") sale(); r = $0; next }
         r != "" && /^  [^ ]/ { r = r " " substr($0, 3); next }
         r != "" { sale() }
         END { if (r != "") sale() }' "$1"
}
mal=""; vistas=""
for p in "$PLA/contexto-global.bloque.md" "$PLA/contexto-global.sin-adaptador.md"; do
    while IFS="$(printf '\t')" read -r r texto; do
        [ -n "$r" ] || continue
        vistas="$vistas$r "
        [ "$texto" = "$(printf '%s\n' "$TABLA" | awk -F'\t' -v r="$r" '$1 == r { print $3 }')" ] || mal="$mal ${p##*/}:$r"
    done <<EOF
$(en_plantilla "$p")
EOF
done
caso 'el texto de cada regla en las plantillas es el de la norma' "$mal" ""
# R-02 no viaja al contexto: su mitad de criterio es clasificar, y eso es R-01.
caso 'entre las dos plantillas van todas las reglas menos R-02' \
     "$(printf '%s' "$vistas" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/^ //')" \
     "$(printf '%s\n' "$TABLA" | cut -f1 | grep -v '^R-02$' | tr '\n' ' ')"

# --- Lo que la prosa cuenta ---------------------------------------------------
GUARDS="$(ls "$MEC"/guard-*.sh 2>/dev/null | wc -l | tr -d ' ')"
HOOKS="$(sed -n -E 's/^FIRMAS="([^"]*)"$/\1/p' "$RAIZ/marco/adaptadores/claude.sh" | wc -w | tr -d ' ')"
for f in README.md AGENTS.md marco/README.md; do
    mal="$(grep -oiE '\b[a-z]+ guards\b' "$RAIZ/$f" | while read -r n _; do
               case "$(numero "$n")" in *[!0-9]*|"$GUARDS") ;; *) printf ' %s' "$n" ;; esac; done)"
    caso "$f cuenta los guards que hay ($GUARDS)" "$mal" ""
    mal="$(grep -oiE '\b[a-z]+ hooks\b' "$RAIZ/$f" | while read -r n _; do
               case "$(numero "$n")" in *[!0-9]*|"$HOOKS") ;; *) printf ' %s' "$n" ;; esac; done)"
    caso "$f cuenta los hooks que se registran ($HOOKS)" "$mal" ""
done
mal=""
for b in "$RAIZ"/pruebas/*.sh; do grep -qF "${b##*/}" "$RAIZ/AGENTS.md" || mal="$mal ${b##*/}"; done
caso 'AGENTS.md nombra cada banco de pruebas/' "$mal" ""

# --- Los shims cargan la puerta de entrada ------------------------------------
# Un enlace a `AGENTS.md` no lo trae al contexto: lo trae la línea que lo importa.
mal=""
for f in CLAUDE.md GEMINI.md; do grep -qx '@AGENTS.md' "$RAIZ/$f" || mal="$mal $f"; done
caso 'CLAUDE.md y GEMINI.md importan AGENTS.md, no solo lo enlazan' "$mal" ""

printf '\n%s casos, %s fallan\n' "$CASOS" "$FALLAN"
[ "$FALLAN" -eq 0 ]
