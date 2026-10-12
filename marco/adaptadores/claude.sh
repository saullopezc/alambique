#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# adaptadores/claude.sh — Lo que SOLO vale en Claude Code: reglas de lectura
# (R-04) y alta de los cuatro hooks del marco: los tres guards (R-03, R-06,
# R-07, R-11) y el arranque de skills.
#
# Es el único adaptador que hay. No es una carencia disimulada: en los demás
# harness el instalador DECLARA el hueco en vez de escribir aquí un fichero
# que nadie lee y dar la regla por activa. Un adaptador nuevo son dos ficheros:
# una copia de este contrato y una versión de `mecanismos/lib/hook.sh` (cómo le
# llega la orden a un guard y cómo responde); se registra en
# `mecanismos/lib/harness.sh`.
#
# Contrato:
#   claude.sh instalar <conf> [evento;matcher;ruta ...]   pone deny + hooks
#   claude.sh quitar   <conf> ver|aplicar <sello>         quita SOLO lo suyo
# Cada hook se describe como `evento;matcher;ruta` (separador `;` porque un
# matcher puede llevar `|`, p. ej. `Write|Edit`). <conf> llega como ruta
# absoluta.
# Salidas: 0 hecho · 1 error · 2 falta una dependencia del adaptador (aquí,
#          python3: sin él no se puede fusionar sin pisar) · 3 la configuración
#          existe y no se entiende (aquí, no es JSON válido, o una de sus
#          piezas no tiene la forma esperada): NO se toca.
#          En 2 y en 3 el adaptador DICE cuál y por qué; quien lo llama no
#          necesita saber cómo se llama el fichero ni con qué se lee.
#
# QUÉ ES DEL MARCO LO DICE LA ANOTACIÓN, NO EL PARECIDO. El alta escribe en
# <conf>/.alambique-alta.claude.json lo que AÑADIÓ de verdad: cada regla y cada
# hook por su valor exacto, si creó `settings.json`, qué piezas encontró
# vacías y qué copias previas dejó. La baja retira eso y nada más: una regla
# igual a una del marco que ya estaba antes del alta es de la persona, y se
# queda. Lo que el alta creó y la baja deja vacío se retira; si lo que queda es
# lo mismo que había antes del alta, se devuelve el fichero tal como estaba,
# byte a byte.
#   Sin anotación la baja es conservadora: retira los hooks cuya orden es
# exactamente un guard del marco en <conf>/hooks/, NO retira ninguna regla de
# lectura, y lo dice. Lo mismo si la anotación es parcial: cuando el alta
# encuentra hooks del marco ya registrados y ninguna anotación, hay en el
# puesto una instalación del marco sin anotar, y lo anota. De las reglas que
# entonces ya estaban no se puede saber quién las puso: la baja las deja, las
# lista para retirarlas a mano, y no afirma que fueran de la persona.
#
# NUNCA SE PISA LO QUE NO SE ENTIENDE. Si `settings.json` no se puede leer como
# JSON, fusionar es imposible y escribir encima borraría la configuración de la
# persona: se sale con 3 y el fichero queda como estaba. Antes de la primera
# escritura que lo cambie se deja copia `.previo.<sello>`. Se escribe a través
# de un enlace simbólico (sobre su destino) y se conserva el modo del fichero.
#
# Author       : Saul López
# Created Date : 2026-09-12

set -uo pipefail
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
unset -f grep sed awk cat cp mv date mkdir 2>/dev/null || true

ACCION="${1:-}"; CONF="${2:-}"
[ -n "$ACCION" ] && [ -n "$CONF" ] || { echo "uso: $0 instalar|quitar <conf> ..." >&2; exit 1; }
case "$ACCION" in instalar|quitar) ;; *) echo "acción desconocida: $ACCION" >&2; exit 1 ;; esac
SETTINGS="$CONF/settings.json"
ANOTACION="$CONF/.alambique-alta.claude.json"
command -v python3 >/dev/null 2>&1 || {
    echo "  AVISO claude.sh: falta python3 (hace falta para fusionar $SETTINGS sin pisarlo)"
    exit 2
}

# Las reglas viven en UN sitio: el alta las añade y la baja las usa para decir
# cuáles siguen puestas sin ser suyas.
#
# La forma importa: `./**` y `//<raíz>/*/` son las que el harness resuelve de
# verdad. Con `**/` a secas la regla se acepta y NO protege — una regla que se
# admite sin actuar es peor que ninguna. La forma está verificada por pares A/B
# sobre `//home/*/` (Linux); `//Users/*/` (macOS) es la misma forma con otra
# raíz y NO se ha verificado en una instalación real.
#
# NO VERIFICADO contra el harness, y por eso cada una se AÑADE a la forma que
# ya había en vez de sustituirla:
#   - `./**/__restriccion*/**`: la capa vedada a cualquier profundidad, como el
#     resto de reglas con `./**/`
#   - `./**/*.pfx` y `./**/*credentials*`: lo que la plantilla `gitignore` del
#     marco no deja versionar
#   - las tres derivadas (abajo): la forma `//<ruta absoluta>` sin comodín
#
# MÁS ANCHAS QUE EL IGNORE, A SABIENDAS: la plantilla `gitignore` deja versionar
# `.env.example` y `*credentials*.example`, y aquí `.env.*` y `*credentials*`
# los vetan. La gramática de estas reglas no tiene una excepción verificada, y
# entre vetar de más un ejemplo y dejar de vetar un `.env.produccion` se elige
# lo primero. El agente no lee esos ejemplos: los abre la persona.
reglas() {
    cat <<'R'
Read(./__restriccion*/**)
Read(./**/__restriccion*/**)
Read(//home/*/.claude/__restriccion*/**)
Read(//home/*/.ssh/**)
Read(//home/*/.claude/.credentials.json)
Read(//Users/*/.claude/__restriccion*/**)
Read(//Users/*/.ssh/**)
Read(//Users/*/.claude/.credentials.json)
Read(./**/*.pem)
Read(./**/*.key)
Read(./**/*.p12)
Read(./**/*.pfx)
Read(./**/*.jks)
Read(./**/id_rsa*)
Read(./**/id_ed25519*)
Read(./**/.env)
Read(./**/.env.*)
Read(./**/credentials*)
Read(./**/*credentials*)
R
    reglas_derivadas
}

# Lo que depende de DÓNDE está <conf> y de dónde está la casa de la persona:
# las reglas fijas de arriba solo aciertan si <conf> es `~/.claude` bajo
# `/home` o `/Users`. Una ruta con caracteres que en un patrón significan otra
# cosa no se convierte en regla: protegería algo distinto de lo que dice.
RAROS='*[][*?(){}!\\]*'
patron_de() { # <ruta absoluta> -> la ruta sin su barra inicial, o nada
    case "$1" in /?*) ;; *) return 1 ;; esac
    # shellcheck disable=SC2254
    case "$1" in $RAROS) return 1 ;; esac
    printf '%s' "${1#/}"
}
reglas_derivadas() {
    if _p="$(patron_de "$CONF")"; then
        printf 'Read(//%s/__restriccion*/**)\n' "$_p"
        printf 'Read(//%s/.credentials.json)\n' "$_p"
    fi
    if _p="$(patron_de "${HOME:-}")"; then
        printf 'Read(//%s/.ssh/**)\n' "$_p"
    fi
}

# Guards y hooks que este marco copia a <conf>/hooks/: sin anotación, la baja
# reconoce un registro suyo por la ruta exacta de uno de estos.
FIRMAS="guard-remoto guard-autoria-docs guard-legacy-grep arranque-skills"

if [ "$ACCION" = "instalar" ]; then
    shift 2
    mkdir -p "$CONF" 2>/dev/null
    for _r in "$CONF" "${HOME:-}"; do
        patron_de "$_r" >/dev/null || [ -z "$_r" ] \
            || echo "  AVISO claude.sh: $_r lleva caracteres de patrón o no es una ruta absoluta: sin reglas de lectura derivadas de esa ruta"
    done
    MODO="-"; SELLO="$(date +%Y%m%d_%H%M%S)"
    HOOKS="$(printf '%s\n' "$@")"
else
    MODO="${3:-ver}"; SELLO="${4:-$(date +%Y%m%d_%H%M%S)}"
    HOOKS=""
fi

# Por variable de entorno, no por tubería: la entrada estándar la ocupa el
# propio script (`python3 -`), y una tubería ahí llega vacía sin avisar.
# `-I`: el intérprete, aislado. Sin ella un `shlex.py` o un `json.py` del
# directorio desde el que se instala se cargaría en lugar del de Python.
REGLAS="$(reglas)" HOOKS="$HOOKS" FIRMAS="$FIRMAS" \
python3 -I - "$ACCION" "$CONF" "$SETTINGS" "$ANOTACION" "$MODO" "$SELLO" <<'PY'
import json, os, re, shlex, shutil, sys, tempfile

accion, conf, ruta, ruta_anot, modo, sello = sys.argv[1:7]
reglas = [l.strip() for l in os.environ.get("REGLAS", "").splitlines() if l.strip()]
firmas = os.environ.get("FIRMAS", "").split()
nombre = os.path.basename(ruta)


def leer(r):
    """Texto del fichero; None si no existe; False si no es texto."""
    try:
        with open(r, encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return None
    except ValueError:
        return False


def entender(texto):
    """La configuración como objeto; None si no se entiende. Vacío vale {}."""
    if texto is False:
        return None
    if texto is None or not texto.strip():
        return {}
    try:
        cfg = json.loads(texto)
    except ValueError:
        return None
    return cfg if isinstance(cfg, dict) else None


def escribir(r, texto):
    """Escribe entero o no escribe, sobre el destino real y con su modo.

    Un `settings.json` que es un enlace simbólico (configuración llevada en un
    repositorio aparte) sigue siendo un enlace, y uno de modo 600 sigue en 600.
    """
    real = os.path.realpath(r)
    carpeta = os.path.dirname(real)
    os.makedirs(carpeta, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=carpeta, prefix=".alambique-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(texto)
        if os.path.exists(real):
            shutil.copymode(real, tmp)
        else:
            mascara = os.umask(0)
            os.umask(mascara)
            os.chmod(tmp, 0o666 & ~mascara)
        os.replace(tmp, real)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def copia_previa(r):
    """Copia `.previo.<sello>` con nombre libre: nunca pisa una anterior."""
    destino, n = f"{r}.previo.{sello}", 1
    while os.path.lexists(destino):
        n += 1
        destino = f"{r}.previo.{sello}.{n}"
    shutil.copy2(r, destino)
    print(f"  copia previa: {os.path.basename(destino)}")
    return os.path.basename(destino)


def orden(guard):
    """La orden que ejecuta un guard: su ruta, entrecomillada si hace falta.

    El harness pasa la orden a una shell; una ruta con espacios sin comillas
    son dos palabras y el hook no arranca.
    """
    return guard if re.fullmatch(r"[\w@%+=:,./-]+", guard) else shlex.quote(guard)


def anotacion():
    """Lo que el alta dejó anotado; None si no hay anotación que se entienda."""
    texto = leer(ruta_anot)
    try:
        a = json.loads(texto) if texto else None
    except ValueError:
        a = None
    if not isinstance(a, dict):
        return None
    limpia = {"creo_fichero": a.get("creo_fichero") is True,
              "previa_sin_anotar": a.get("previa_sin_anotar") is True}
    for clave in ("deny", "vacias", "previos"):
        v = a.get(clave)
        limpia[clave] = [x for x in v if isinstance(x, str)] if isinstance(v, list) else []
    hs = a.get("hooks")
    limpia["hooks"] = [h for h in hs if isinstance(h, dict)
                       and isinstance(h.get("evento"), str)
                       and isinstance(h.get("command"), str)] if isinstance(hs, list) else []
    return limpia


def no_entiendo(que):
    print(f"  AVISO claude.sh: en {ruta}, {que}: NO se toca")
    sys.exit(3)


def instalar():
    texto = leer(ruta)
    cfg = entender(texto)
    if cfg is None:
        print(f"  AVISO claude.sh: {ruta} existe y no es un objeto JSON válido "
              "(suele ser un comentario o una coma final): NO se toca")
        sys.exit(3)
    if not reglas:
        sys.exit(1)
    anot = anotacion()
    sin_anotar = anot is None
    anot = anot or {"creo_fichero": False, "previa_sin_anotar": False, "deny": [],
                    "hooks": [], "vacias": [], "previos": []}
    nuevas_deny, nuevos_hooks, vacias = [], [], []

    def pieza(padre, clave, tipo, donde):
        """La pieza donde se va a escribir, creada si falta.

        Una que ya estaba y estaba vacía se anota: la baja la deja vacía en vez
        de retirarla, porque no la creó el alta.
        """
        if padre.get(clave) is None:
            padre[clave] = tipo()
        elif not padre[clave]:
            vacias.append(donde)
        return padre[clave]

    def comprobar(valor, tipo, donde):
        if valor is not None and not isinstance(valor, tipo):
            no_entiendo(f"`{donde}` no es {'una lista' if tipo is list else 'un objeto'}")

    # Antes de escribir nada se comprueba la forma de todo lo que se va a tocar.
    perms = cfg.get("permissions")
    comprobar(perms, dict, "permissions")
    comprobar((perms or {}).get("deny"), list, "permissions.deny")
    hooks = cfg.get("hooks")
    comprobar(hooks, dict, "hooks")
    specs = []
    for spec in os.environ.get("HOOKS", "").splitlines():
        if not spec.strip():
            continue
        evento, matcher, guard = spec.split(";", 2)
        comprobar((hooks or {}).get(evento), list, f"hooks.{evento}")
        specs.append((evento, matcher, orden(guard)))

    ya = (perms or {}).get("deny") or []
    faltan = [r for r in reglas if r not in ya]
    if faltan:
        deny = pieza(pieza(cfg, "permissions", dict, "permissions"), "deny", list, "permissions.deny")
        deny.extend(faltan)
        nuevas_deny = faltan

    for evento, matcher, cmd in specs:
        entradas = (cfg.get("hooks") or {}).get(evento) or []
        # «Ya está» es el campo `command` exacto, en cualquier matcher del evento.
        if any(isinstance(h, dict) and h.get("command") == cmd
               for e in entradas if isinstance(e, dict)
               for h in (e.get("hooks") if isinstance(e.get("hooks"), list) else [])):
            # Un hook del marco registrado y ninguna anotación: en el puesto hay
            # una instalación del marco sin anotar. De lo que ya está no se
            # puede decir quién lo puso, y la baja tiene que saberlo.
            if sin_anotar:
                anot["previa_sin_anotar"] = True
            continue
        entradas = pieza(pieza(cfg, "hooks", dict, "hooks"), evento, list, f"hooks.{evento}")
        # Se comparte entrada con otros hooks del mismo matcher; una entrada
        # vacía no se reutiliza: al retirar no se sabría de quién era.
        destino = next((e for e in entradas if isinstance(e, dict) and e.get("matcher") == matcher
                        and isinstance(e.get("hooks"), list) and e["hooks"]), None)
        if destino is None:
            destino = {"matcher": matcher, "hooks": []}
            entradas.append(destino)
        destino["hooks"].append({"type": "command", "command": cmd})
        nuevos_hooks.append({"evento": evento, "matcher": matcher, "command": cmd})

    if not nuevas_deny and not nuevos_hooks:
        return               # ya estaba todo: ni escritura, ni copia, ni anotación

    if texto is None:
        anot["creo_fichero"] = True
    else:
        anot["previos"].append(copia_previa(ruta))
    anot["deny"] += [r for r in nuevas_deny if r not in anot["deny"]]
    anot["hooks"] += [h for h in nuevos_hooks if h not in anot["hooks"]]
    anot["vacias"] += [v for v in vacias if v not in anot["vacias"]]
    anot = {"que_es": f"Lo que el alta de alambique añadió a {nombre}. "
                      "La baja (marco/desinstalar.sh) retira esto y nada más.", **anot}
    # La anotación va primero: si la configuración no se llega a escribir, una
    # anotación de más no retira nada; una configuración sin anotar deja reglas
    # que la baja no sabe de quién son.
    anterior = leer(ruta_anot)
    escribir(ruta_anot, json.dumps(anot, indent=2, ensure_ascii=False) + "\n")
    try:
        escribir(ruta, json.dumps(cfg, indent=2, ensure_ascii=False) + "\n")
    except BaseException:
        if isinstance(anterior, str):
            escribir(ruta_anot, anterior)
        else:
            os.unlink(ruta_anot)
        raise


def quitar():
    anot = anotacion()
    texto = leer(ruta)
    if texto is None:
        print(f"  (no hay {ruta})")
        if anot is not None and modo == "aplicar":
            os.unlink(ruta_anot)
        return
    cfg = entender(texto)
    if cfg is None:
        print(f"  AVISO claude.sh: {ruta} no es un objeto JSON válido: NO se toca")
        sys.exit(3)
    a_deny = set(anot["deny"]) if anot else set()
    a_hooks = {(h["evento"], h["command"]) for h in anot["hooks"]} if anot else set()
    vacias = set(anot["vacias"]) if anot else set()

    # Sin anotación (o con un registro que el alta no añadió): un hook es del
    # marco si su orden es EXACTAMENTE la ruta de un guard del marco en
    # <conf>/hooks/ y ese fichero es el del marco, o ya no existe. El del marco
    # se reconoce por su cabecera, en posición fija —las tres primeras líneas
    # y el título `# <nombre>.sh — `—: que un fichero nombre al marco no dice
    # de quién es, y un hook de la persona que se llame igual se queda.
    cabecera = ["#!/usr/bin/env bash", "# SPDX-License-Identifier: MIT", "#"]
    guards = {}
    for fm in firmas:
        p = f"{conf}/hooks/{fm}.sh"
        guards[p] = guards[orden(p)] = guards[shlex.quote(p)] = p

    def guard_del_marco(cmd):
        p = guards.get(cmd)
        if p is None:
            return False
        try:
            with open(p, encoding="utf-8", errors="replace") as f:
                lineas = [f.readline().rstrip("\n") for _ in range(4)]
        except FileNotFoundError:
            return True
        except OSError:
            return False
        return lineas[:3] == cabecera and lineas[3].startswith(f"# {os.path.basename(p)} — ")

    q_hooks, q_deny, se_quedan = [], [], []
    hooks = cfg.get("hooks")
    if isinstance(hooks, dict):
        for evento in list(hooks):
            entradas = hooks[evento]
            if not isinstance(entradas, list):
                continue
            quedan, tocado = [], False
            for e in entradas:
                hs = e.get("hooks") if isinstance(e, dict) else None
                if not isinstance(hs, list):
                    quedan.append(e)
                    continue
                # Hook a hook, no la entrada entera: uno ajeno que comparta
                # matcher con uno del marco sobrevive.
                propios = [h for h in hs if isinstance(h, dict) and isinstance(h.get("command"), str)
                           and ((evento, h["command"]) in a_hooks or guard_del_marco(h["command"]))]
                if not propios:
                    quedan.append(e)
                    continue
                tocado = True
                q_hooks += [f"{evento}/{e.get('matcher')}: {h['command']}" for h in propios]
                ajenos = [h for h in hs if not any(h is p for p in propios)]
                if ajenos:
                    e["hooks"] = ajenos
                    quedan.append(e)
            if tocado:
                if quedan or f"hooks.{evento}" in vacias:
                    hooks[evento] = quedan
                else:
                    del hooks[evento]
        if q_hooks and not hooks and "hooks" not in vacias:
            del cfg["hooks"]

    perms = cfg.get("permissions")
    deny = perms.get("deny") if isinstance(perms, dict) else None
    if isinstance(deny, list):
        suya = lambda r: isinstance(r, str) and r in a_deny
        q_deny = [r for r in deny if suya(r)]
        se_quedan = [r for r in deny if r in reglas and not suya(r)]
        if q_deny:
            resto = [r for r in deny if not suya(r)]
            if resto or "permissions.deny" in vacias:
                perms["deny"] = resto
            else:
                del perms["deny"]
                if not perms and "permissions" not in vacias:
                    del cfg["permissions"]

    for x in q_hooks:
        print("  hook  -", x)
    for x in q_deny:
        print("  deny  -", x)
    if se_quedan:
        if anot is None:
            print(f"  AVISO no hay anotación del alta ({os.path.basename(ruta_anot)}): no consta qué reglas de")
            print("    lectura añadió el marco y cuáles eran tuyas. NO se retira ninguna. Estas")
            print(f"    coinciden con las del marco; si no son tuyas, se quitan a mano de {nombre}:")
        elif anot["previa_sin_anotar"]:
            print("  AVISO el alta encontró en este puesto una instalación del marco sin anotar: de estas")
            print("    reglas, iguales a las del marco, no consta quién las puso. Se quedan; si no son")
            print(f"    tuyas, se quitan a mano de {nombre}:")
        else:
            print("  reglas iguales a las del marco que ya estaban antes del alta: son tuyas, se quedan")
        for x in se_quedan:
            print("  deny  =", x)
    if not q_hooks and not q_deny:
        print("  (nada que retirar de la configuración)")
    if modo != "aplicar":
        return
    if q_hooks or q_deny:
        copia_previa(ruta)
        # Si lo que queda es lo que había antes del alta, vuelve el fichero de
        # entonces, byte a byte; si la persona lo cambió después, se conserva
        # su contenido de ahora y solo cambia el formato.
        devuelto = None
        for previo in reversed(anot["previos"] if anot else []):
            t = leer(os.path.join(os.path.dirname(ruta), previo))
            if isinstance(t, str) and entender(t) == cfg:
                devuelto = t
                break
        if devuelto is None and anot and anot["creo_fichero"] and not cfg:
            os.unlink(os.path.realpath(ruta))
            print(f"  {nombre} lo creó el alta y queda vacío: se retira")
        else:
            escribir(ruta, devuelto if devuelto is not None
                     else json.dumps(cfg, indent=2, ensure_ascii=False) + "\n")
    if anot is not None or os.path.lexists(ruta_anot):
        os.unlink(ruta_anot)


try:
    instalar() if accion == "instalar" else quitar()
except OSError as e:
    print(f"  AVISO claude.sh: {e}")
    sys.exit(1)
PY
