# alambique

**Un marco de doce reglas para trabajar con agentes de IA sobre datos ajenos**, con los
mecanismos que hacen cumplir las que una máquina puede comprobar: puerta de commit,
barrido, guards y reglas de lectura. Trae dentro una skill en formato abierto
[Agent Skills](https://agentskills.io), `operacion-puesto`, que le dice al agente dónde
vive cada cosa y cómo se clasifica.
**Método y criterio, cero datos de cliente.** Agnóstico al LLM y al harness: lo que solo
funciona en uno vive en un adaptador y se declara.

> El nombre: un alambique destila. Entra la experiencia operativa con datos reales
> dentro, sale el criterio sin ellos. Este repositorio es la salida, no la carga.

**Para quién:** quien desarrolla, opera o da soporte sobre sistemas y datos de terceros
con un agente de línea de órdenes, y necesita que lo ajeno no acabe en un repositorio ni
en una orden ejecutada sin preguntar. No es un producto de seguridad ni sustituye un
acuerdo de confidencialidad: es método, con los mecanismos que lo sostienen.

## Para qué sirve

Un agente sin marco versiona lo que estorba, escribe coordenadas en la documentación y
ejecuta sobre un servidor ajeno lo primero que parece razonable. Y una norma de cientos de
requisitos no lo evita: nadie la tiene en la cabeza en el momento en que hace falta.

**El marco** son doce reglas que caben en la cabeza, cada una con quién la comprueba.
Una máquina hace cumplir la regla de ignorar la capa local en todo puesto y la puerta de
commit en cada proyecto dado de alta;
las reglas de lectura y los guards, donde el harness tiene adaptador. Las siete que
dependen de criterio van al contexto del agente, porque no hay otro sitio desde el que
puedan actuar. Y el instalador termina diciendo qué ha quedado activo y qué no: un hueco
declarado vale más que una regla que nadie hace cumplir.

**La skill del marco**, `operacion-puesto`, es el manual del agente para las tres reglas
que tratan de dónde vive el dato (R-01, R-02, R-03): la escala de clasificación, la capa
local y su estructura, y el alias en vez de la coordenada, con un resolutor que lo
resuelve en cascada. La regla llega al agente por el contexto; el cómo, por la skill.

**Son herramientas simples, a propósito.** No pretenden cubrir todos los escenarios: nadie
puede comprobarlos todos, y un mecanismo que lo intenta crece hasta que nadie lo entiende.
Por eso cada pieza —script, documento, plantilla— dice su alcance: qué cubre y qué no, sin
prometer más. Lo que trae es un punto de partida: **cada empresa consultora lo adapta a su
realidad —lo tropicaliza— y lo amplía**. Los patrones de detección, las heurísticas y los
procesos se ajustan a sus clientes, a su tecnología y a su forma de trabajar; lo que aquí
no cabe se añade allí, no aquí.

## Qué hay dentro

| Carpeta | Qué aporta |
|---|---|
| [`marco/`](marco/) | Las doce reglas ([`NORMA.md`](marco/NORMA.md)), sus mecanismos (puerta de commit, barrido, tres guards, arranque de skills), un adaptador —Claude Code— y sus plantillas |
| [`marco/skills/operacion-puesto/`](marco/skills/operacion-puesto/) | La skill del marco: clasificación C0-C3, capas `_local/`, alias en vez de coordenadas, y el resolutor de la cascada de configuración |
| [`AGENTS.md`](AGENTS.md) | Puerta de entrada para el agente. `CLAUDE.md` y `GEMINI.md` son shims que lo importan |

## Vocabulario

Las palabras que el resto del texto da por sabidas:

| Término | Qué es aquí |
|---|---|
| **Harness** | El programa que ejecuta al agente y lee sus skills y su fichero de contexto: Claude Code, Codex CLI, Gemini CLI, opencode, Cursor, aider |
| **`<conf>`** | El directorio de configuración del harness en la máquina (`~/.claude`, `~/.codex`...). Se detecta; `$ALAMBIQUE_CONF` lo fija |
| **Puesto** | La máquina y la configuración desde la que una persona trabaja con el agente. Lo que es del puesto —identidad, raíces de servidor, marcas— no es de ningún proyecto |
| **Capa local** | `_local/`: lo que no se versiona porque lleva datos reales. Existe en el puesto (`<conf>/_local/`) y en cada proyecto |
| **Cartera** | La raíz bajo la que cuelgan los clientes y sus proyectos (`~/Proyectos` por defecto). Las capas locales se resuelven subiendo por ese árbol |
| **Alias** | El nombre con el que se nombra un servidor o un cliente en vez de su coordenada. La coordenada vive fuera de lo versionable —en `~/.ssh/config`—, lo que la describe en la capa local, y el alias puede escribirse en cualquier sitio |
| **Marca** | Un nombre real —cliente, empresa, sistema— cuya aparición en algo versionable es una fuga. La lista vive en la capa local del puesto |
| **C0 a C3** | La escala de clasificación: C0 público, C1 interno (criterio sin datos), C2 infraestructura de un tercero, C3 credenciales y datos reales. Ante duda, la más alta |
| **Capa vedada** | `__restriccion/`: lo que el agente además no debe **leer**, no solo no versionar. Las reglas de lectura la protegen donde hay adaptador |
| **Hook** | Un script que el harness ejecuta solo en un momento dado: antes de una orden, después de escribir un fichero, al abrir la sesión. El marco instala cuatro |
| **Guard** | Un hook que vigila una regla y pregunta o deniega: `guard-remoto` (R-06, R-07), `guard-legacy-grep` (R-03), `guard-autoria-docs` (R-11) |
| **Puerta de commit** | El `pre-commit` que el instalador pone en cada proyecto dado de alta: comprueba que nada de la capa local entra al índice, pasa el barrido sobre lo preparado —altas, cambios, renombrados y cambios de tipo—, detiene el commit si hay fuga o si el barrido no termina, nombra los ficheros que se declaran exentos y dice si el barrido no tenía lista de marcas. Solo actúa donde git ejecuta `pre-commit`: un merge sin conflictos, por ejemplo, no pasa por ella (la lista, en «Límites declarados») |
| **Barrido** | `marco/mecanismos/barrido.sh`: busca por patrón en lo versionable claves privadas, IPv4, credenciales —por el nombre de la clave—, accesos `usuario@host` y marcas del puesto, y avisa de hosts y rutas de servidor. Lo que no ve: «Límites declarados». Sale 0 limpio, 1 con ALTA, 2 solo MEDIA y 3 si no pudo barrer. Lo que no lee —binarios y ficheros exentos— lo cuenta y lo nombra. Solo lectura; lo usa la puerta |
| **Reglas de lectura** | Permisos `deny` de lectura sobre la capa vedada y las credenciales, en la gramática del harness (R-04). Solo con adaptador |
| **Adaptador** | Lo que traduce reglas de lectura y hooks a un harness concreto: `marco/adaptadores/<harness>.sh` más su versión de `lib/hook.sh`. Hoy solo Claude Code |
| **Skill de arranque** | La que el hook `arranque-skills` pide cargar al abrir la sesión: `operacion-puesto`, y toda skill instalada que traiga un fichero `.arranque` en su directorio. Las demás se cargan por su `description` |

## Instalación

Requisitos: `bash`, `git` y las utilidades habituales de línea de órdenes (`awk`, `sed`,
`grep`); `python3` solo para el adaptador de Claude Code. Se buscan en los directorios del
sistema, no en el `PATH` de la sesión (ver «Límites declarados»). Probado en Linux, con las
utilidades de GNU y `mawk`. En macOS no está verificado: ni las utilidades de BSD —los
guards leen la orden con `awk` y `RS="\0"`— ni la forma de las reglas de lectura.

```sh
git clone https://github.com/saullopezc/alambique.git
cd alambique
./instalar.sh                    # la skill en cada harness detectado + marco en el principal
./instalar.sh /ruta/proyecto     # además, alta del proyecto: capa local y puerta de commit
./instalar.sh --solo-skills      # solo la skill
```

**Para probarlo sin tocar tu máquina**, instálalo en un HOME desechable. `env -i` importa:
sin él se instalaría en tu configuración de verdad.

```sh
T=$(mktemp -d); mkdir -p "$T/.claude"
env -i PATH="$PATH" HOME="$T" ./instalar.sh    # todo queda bajo $T; se mira y se tira
```

En una terminal el instalador pregunta la identidad de quien firma; Enter la omite.

**Qué escribe en la máquina, y nada más:** la skill, copiada a `<conf>/skills/` con un
marcador de origen; un bloque marcado en el ignore global de git —solo `_local/` y
`__restriccion/`, en el fichero que diga `core.excludesfile` o, si no dice ninguno, en
el que git lee por defecto; ese ajuste no se escribe nunca, y el instalador comprueba con
git que `_local/` queda ignorado: si no, lo marca `NO ACTIVO`— y
otro en el fichero de contexto global del harness; el directorio `<conf>/_local/`,
donde van los datos del puesto, y en él `negocio.conf` con la identidad que pregunta al
instalar; con adaptador, reglas de lectura y
cuatro hooks en la configuración del harness —tres guards y el arranque de skills—, con
copia `.previo.<sello>` antes del primer cambio de cada fichero de la persona que ya
existía —el ignore global, el fichero de contexto, la configuración del harness y el
`.gitignore` del proyecto—, esos cuatro con su `lib/` en `<conf>/hooks/`, y la anotación de
qué añadió el alta, para que la baja retire solo eso. La configuración del harness se
reescribe entera al añadirle reglas y hooks: conserva sus claves y su orden, no su
sangría ni la forma de escribir un número o un carácter escapado, y la baja la devuelve
como estaba. Lo que el marco copió —los hooks y la
skill— se sustituye por la versión del repositorio, sin copia previa: no se edita en su
copia instalada; con proyecto, un bloque en su `.gitignore` —que además de las dos capas
y las credenciales deja de versionar `/datos/`, `/data/`, `/evidencia/`, `/evidence/`,
`/exports/`, `/capturas/`, `/context/`, `/qa/` y `/audit/` en la raíz, y los `*.dump` y
`*.sql.gz` de cualquier directorio: conviene leer
[`marco/plantillas/gitignore`](marco/plantillas/gitignore) antes del alta—,
el esqueleto de la capa local, un `pre-commit` —si el proyecto ya tiene uno propio no se
pisa: el instalador da la línea con la que encadenar la puerta, que va la primera, justo
después del `#!`, y al repetir la reconoce; en cualquier otro sitio no la da por activa,
porque detrás de otra orden puede no alcanzarse; la baja retira solo esa línea— y, si firma con otra identidad, su
`_local/negocio.conf`. **El clon se queda donde se instaló:**
el contexto global y el `pre-commit` de cada proyecto lo llaman por su ruta; si se mueve,
se repite la instalación. También tras actualizar el clon: los hooks y la skill son
copias, y siguen en la versión anterior hasta repetir `./instalar.sh`.

No hay que declarar el harness: se detecta. La skill va a **todos** los que lean
skills; el marco, **solo** al principal (`$ALAMBIQUE_CONF`, o el primero que exista): los
demás no reciben el bloque de reglas, y para llevárselo se repite la instalación con
`ALAMBIQUE_CONF=<su conf>` (sale con `3` si ese harness no tiene adaptador). Con varios
harness, la copia de la skill en los demás busca la capa local del puesto en su propio
`<conf>`: `ALAMBIQUE_LOCAL` o `ALAMBIQUE_CONF` la llevan a la del principal. La skill se
puede copiar a mano a `<conf>/skills/`. Las variables `ALAMBIQUE_*` que mueven cada pieza están todas en
la tabla de [`marco/README.md`](marco/README.md).

| Harness | `<conf>` | Skills | Reglas de criterio en el contexto global | Reglas de lectura y guards |
|---|---|---|---|---|
| Claude Code | `~/.claude` | sí | `CLAUDE.md`, una línea que importa el bloque del repo | **sí** — único adaptador |
| Codex CLI | `~/.codex` | sí | `AGENTS.md` | hueco declarado |
| Gemini CLI | `~/.gemini` | sí | `GEMINI.md`, dos líneas que importan el bloque del repo y su añadido para un harness sin adaptador | hueco declarado |
| Cursor | `~/.cursor` | sí | sin fichero global: el bloque se pega a mano en el `AGENTS.md` de cada proyecto (lo indica `marco/plantillas/contexto-proyecto.md`) | hueco declarado |
| opencode | `~/.config/opencode` | sí | `AGENTS.md` | hueco declarado |
| aider | `~/.aider` | no lee skills | — | hueco declarado |
| ninguno | el que declare `$ALAMBIQUE_CONF` (p. ej. `~/.alambique`); sin ella el instalador se detiene y lo dice | sí | no se escribe: ningún agente lo leería. El bloque se pega a mano en el `AGENTS.md` de cada proyecto | hueco declarado |

El orden de la tabla es el de detección: con varios en el puesto, el principal es el
primero de arriba abajo.

La tabla es dato, en `marco/mecanismos/lib/harness.sh`. Añadir un harness es una línea;
darle reglas de lectura y guards son dos ficheros: un adaptador en `marco/adaptadores/`
con el contrato de `claude.sh`, y una versión de `marco/mecanismos/lib/hook.sh` que hable
la carga y la respuesta de hook de ese harness —los guards no cambian—. Queda una tercera
pieza por sacar al adaptador: el evento y el matcher con que se registra cada hook van hoy
en `marco/instalar.sh`, en la gramática de Claude Code. Las rutas de los
harness distintos de Claude Code no están probadas contra una instalación real: se
corrigen en la tabla.

**El instalador dice lo que no ha puesto.** Un harness sin adaptador termina con salida
`3` y las reglas `R-04`, `R-06`, `R-07` y `R-11` —y el guard de `R-03`— marcadas
`NO SOPORTADO`: siguen siendo
norma, pero en ese puesto las cumple una persona, no una máquina. Marcarlas activas
escribiendo un fichero que nadie lee sería peor que no instalar nada.
En esos harness el bloque de contexto lleva además el texto de `R-03`,
`R-04`, `R-06` y `R-07`, porque ahí también dependen de criterio; sin fichero de contexto
global, el instalador dice que no llegan al agente.

## Después de instalar: la capa local del puesto

**La identidad de quien firma la pregunta el instalador**: nombre, correo institucional y
empresa u organización. Lo hace en una terminal y solo si `negocio.conf` no existe ya; con
Enter se omite. El resto de los datos del puesto los pone la persona, copiando cada
`.example` a `<conf>/_local/` sin el sufijo y rellenándolo. Ninguno se versiona.

**Una identidad o varias.** La del puesto es la de por defecto. Quien firma con más de una
—varias empresas, o marca blanca para un cliente— pone otro `negocio.conf` en el `_local/`
de ese proyecto o de ese cliente: el instalador lo pregunta, opcional, al dar de alta un
proyecto, y para todo un cliente se copia a mano a `<cliente>/_local/`. El guard usa el
más cercano al fichero que se escribe, igual que la cascada de alias.

| Copiar | A `<conf>/_local/` | Quién lo lee | Si falta |
|---|---|---|---|
| `marco/skills/operacion-puesto/plantillas/negocio.conf.example` (o lo escribe el instalador) | `negocio.conf` | `guard-autoria-docs` | el guard avisa, en **cada** documento que no declare `responsable` en su cabecera, de que no pudo comprobar la firma |
| `marco/plantillas/rutas-cliente.example.conf` | `rutas-cliente.conf` | `guard-remoto` | solo vigila las acciones destructivas genéricas, no las raíces de servidor |
| `marco/plantillas/modelos.example.conf` | `modelos.conf` | `guard-autoria-docs` | usa su lista interna de nombres de IA |
| `marco/plantillas/marcas.example.txt` | `marcas.txt` | barrido y puerta de commit | la puerta no conoce los nombres del puesto: solo IP, credenciales y capa local |
| `marco/skills/operacion-puesto/plantillas/clientes.conf.example` | `clientes.conf` | barrido y puerta (regex) | igual que `marcas.txt` |
| `marco/skills/operacion-puesto/plantillas/conexiones.yaml.example` | `conexiones.yaml` | `resolve_alias.sh`, `guard-legacy-grep` | no hay alias que resolver: el guard de `ssh` no tiene destinos marcados y deja pasar; solo avisa si falta el propio resolutor o si este falla |

El instalador crea `<conf>/_local/` y, si los hooks quedaron activos, termina diciendo
cuáles de estos seis faltan.

Hay un séptimo que no va en `<conf>/_local/` sino en la capa local de cada nivel de la
cartera —proyecto, cliente u operación—:
`marco/skills/operacion-puesto/plantillas/proyecto.yaml.example` se copia a
`<nivel>/_local/proyecto.yaml` y declara de quién es ese directorio —el cliente, por
alias— y qué skills cargar en él. El dueño lo lee `contexto_proyecto.sh`, para directorios
bajo la cartera; la lista de skills la lee el agente al abrir el proyecto, no un script.

**Qué da el guard por firma de un documento:** la cabecera `responsable` rellena, que es
la que piden la norma y las plantillas de documentación, o la firma al pie con el correo
del `negocio.conf` que aplique a ese fichero. Vale cualquiera de las dos.

## Desinstalación

```sh
marco/desinstalar.sh --ver              # qué quitaría, sin tocar nada
marco/desinstalar.sh --aplicar [proy]   # lo quita; lo retirado queda como .previo.<sello>
```

Retira los bloques marcados y las reglas y hooks que el alta anotó haber añadido, y deja
cada fichero como estaba: uno que el alta creó y queda vacío se retira. Si en el puesto hay
una instalación del marco sin anotar, las reglas de lectura que ya estaban se quedan —no
consta quién las puso— y la baja las lista para quitarlas a mano. Las reglas, hooks
y líneas del usuario sobreviven, y `<conf>/_local/` no se toca porque son datos del
puesto. **Las capas locales se quedan, y sin ignorar:** retirado el bloque del ignore
global, `_local/` y `__restriccion/` dejan de estar ignorados en todo repositorio que no
tenga su propio bloque —tampoco en el proyecto que se da de baja, que lo pierde—, y un
`git add` de todo el árbol los versionaría; la baja lo avisa.
**La baja actúa sobre el harness principal:** si el marco se llevó a otro con
`ALAMBIQUE_CONF=<su conf>`, se repite la baja con esa misma variable.
Sale con `1` si algo no se pudo retirar. La skill se retira a mano: es el directorio `<conf>/skills/operacion-puesto`, si contiene
`.alambique-origen`; el desinstalador dice dónde está.

La baja no guarda lista de los proyectos dados de alta: el `pre-commit` y el bloque del
`.gitignore` de cada uno se retiran nombrándolo en la misma baja (`--aplicar <proyecto>`,
que retira también lo del puesto); no hay baja de un solo proyecto. Hasta entonces su
`pre-commit` sigue llamando a la puerta por la ruta del clon, y si el clon ya no está, el
commit falla diciendo que no la encuentra.

## Cómo se usa

1. La skill del marco tiene que estar desde el primer mensaje: la pide el hook
   `arranque-skills` al abrir cada sesión. Donde no hay adaptador la carga el harness
   por su `description`, cuando la tarea encaja.
2. Al abrir una tarea que toque datos de cliente o un servidor ajeno, se rellena
   `marco/plantillas/tarea.md`: cuatro preguntas previas, puestas donde estorban.
3. Todo lo C2 y C3 —lo que describe la infraestructura ajena, salidas reales, evidencia,
   credenciales— va a `_local/` del proyecto, y a `__restriccion/` lo que el agente además
   no deba leer. El instalador deja las dos creadas y excluidas del versionador.
4. Antes de cada commit actúa la puerta sobre lo preparado: si entra algo de la capa
   local, o una IP, una credencial o una marca del puesto en una forma que el barrido
   conozca, el commit no ocurre y dice por qué; un host o una ruta de servidor sospechosos avisan sin bloquear.

## Límites declarados

Los mecanismos cubren las formas más corrientes de lo que vigilan. Sus patrones son un
punto de partida: pueden no ser completos, y cada empresa consultora los adapta a su caso
y los amplía —con sus marcas, sus raíces de servidor y sus nombres de modelo en la capa
local, o tocando el patrón—. La cabecera de cada script dice con exactitud lo que no ve; esto es el resumen.

- **El barrido busca por patrón.** Las credenciales las reconoce por el **nombre de la
  clave** (`password`, `passwd`, `contraseña`, `secret`, `token`, `api_key`, y sus
  variantes con prefijo o sufijo), no por el formato del valor: un token suelto o una
  clave con otro nombre no los ve, ni un valor de **menos de ocho caracteres**
  (una `password` de siete pasa). De coordenadas ve **IPv4**; no IPv6. Un `usuario@host`
  lo ve como argumento de una orden de acceso (`ssh`, `scp`, `rsync`), no en prosa. De
  hosts y rutas de servidor avisa solo ante una lista corta —nombres que acaban en
  `.local`, `.lan`, `.corp`, `.internal`, `.intranet` o `.prod`, y rutas bajo `/opt`,
  `/srv`, `/u01`, `/u02`, `/app` (o `/app1`, `/app2`…) o `/export`—: un host con dominio real o una ruta bajo
  `/var` o `/home` solo los ve la lista de marcas. No
  mira nombres de fichero ni el mensaje del commit. Y da ALTA sobre cosas que no lo son
  —una versión de cuatro números, un título numerado—: se lee la línea y se clasifica.
- **Un fichero se declara exento** con una línea de comentario que diga solo
  `alambique: exento` en sus primeras 30 líneas. El barrido no lo lee, y lo cuenta y lo
  nombra en cada pasada.
- **La puerta solo actúa donde git ejecuta `pre-commit`.** No pasan por ella
  `commit --no-verify`, un merge sin conflictos o fast-forward, `cherry-pick`, `rebase`,
  `revert` ni `git am`. Nada registra que se saltó. Y va donde git busca sus hooks: con
  `core.hooksPath` definido, la puerta se pone en ese directorio y actúa en todos los
  repositorios que lo usen, no solo en el dado de alta; el instalador lo avisa.
- **Los guards preguntan en los casos comunes.** `guard-remoto` conoce una lista cerrada de
  verbos que escriben, mueven, matan o reinician, y los transportes `ssh`, `scp` y
  `rsync`; no `sftp`, `kubectl`, `docker -H` ni `ansible`. `guard-legacy-grep` ve una IPv4
  literal como destino de `ssh`, no un nombre de host. `guard-autoria-docs` mira el
  fichero que el agente escribe con las herramientas de edición del harness: no el mensaje
  de un commit ni un fichero escrito por redirección; y su lista de formas de atribución
  es de ejemplo.
- **Las reglas de lectura cubren las herramientas y las órdenes que nombran el fichero.**
  En Claude Code paran la herramienta de lectura y, en Bash, `cat`, `mv` y similares,
  también con la ruta en una variable. No paran un subproceso que abre el fichero por su
  cuenta (`python3 -c`, `bash -c`, un script) ni lo que lee sin nombrarlo (`grep -r`): eso
  solo lo cierra el sandbox del harness, que el adaptador no activa.
- **La skill describe una forma de organizar el puesto**, la de quien la escribió: cartera,
  cliente, operación, proyecto, y diez claves por conexión. Es un ejemplo de uso; de esas
  claves los mecanismos solo leen `alias`, `ssh_host` y `legado_grep`; el resto informa.
- **Entorno.** Los scripts fijan su `PATH` a
  `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`: un `git` o un `python3`
  instalado fuera de ahí no se encuentra. Sin verificar: macOS, las utilidades de BSD y
  un `bash` anterior al 4.

Lo que un mecanismo promete en su cabecera y no cumple es un fallo y se reporta
([`SECURITY.md`](SECURITY.md)); lo que declara no ver es un límite.

## Cómo se verifica

- **Instaladores:** se prueban poniendo y quitando sobre una configuración que ya tenga
  reglas y hooks del usuario; lo del usuario tiene que sobrevivir. Un harness sin
  adaptador debe salir con `3`, y sin ningún harness, con `1`. Comandos en `AGENTS.md`.
- **Clasificación:** toda afirmación negativa lleva control positivo, y el patrón decide
  dónde mirar, no la clase de lo que encuentra. Procedimiento y comandos en
  [`CLASIFICACION.md`](CLASIFICACION.md).
- **`description` de la skill ≤ 1024 caracteres**, límite de la especificación.
- **Cada mecanismo tiene su banco en `pruebas/`**: la puerta y el barrido, los guards, los
  instaladores, la skill y el arranque. Cada caso va con su control —el que debe detenerse y el gemelo
  que debe pasar—, y el banco tiene que fallar contra la versión anterior al arreglo.
- **Lo que se puede contar no se escribe a mano.** `pruebas/coherencia.sh` saca de la
  tabla de la norma el recuento de quién comprueba cada regla y lo compara con las frases
  que lo citan; comprueba que el texto de las reglas en las plantillas es el de la norma, y
  que ninguna regla figura como mecanizada entera si su mecanismo declara algo que no ve.
- **El propio repositorio pasa su barrido** (`marco/mecanismos/barrido.sh .` sale 0 sin
  lista de marcas del puesto; con ella, cada coincidencia se lee y se clasifica) y los
  comandos de `AGENTS.md`.

## Acoplamiento declarado

- **Un solo adaptador y un solo contrato de hook.** Los tres guards (`guard-remoto`,
  `guard-legacy-grep`, `guard-autoria-docs`) detectan sin saber de harness; cómo les
  llega la orden y cómo responden lo dice `marco/mecanismos/lib/hook.sh`, hoy en la
  versión de Claude Code. Las reglas de lectura usan la gramática de permisos de ese
  harness. Es lo único atado a uno, y por eso lo da de alta `marco/adaptadores/claude.sh`
  y no otro. Un hueco declarado vale más que cinco adaptadores sin probar.
- **Un hook más al abrir la sesión.** `arranque-skills.sh` pide al agente que cargue la
  skill del marco, porque declararla en el contexto no la carga: solo actúa su resumen
  hasta que alguien la invoca. El adaptador lo registra en `SessionStart`, al iniciar o
  reanudar, junto a los tres guards.
- **Las referencias `R-01`..`R-12`** de la skill resuelven en [`marco/`](marco/). El
  texto que rodea cada cita explica la regla, así que la referencia es trazabilidad, no
  requisito.

## Clasificación, autoría y titularidad

- **Clasificación:** C0, público — criterio y método, sin datos de cliente. Procedimiento y cómo
  re-verificarla en [`CLASIFICACION.md`](CLASIFICACION.md).
- **Propietario:** Saul López — github.com/saullopezc. Problemas y propuestas: en las
  incidencias del repositorio, con el síntoma literal y cómo reproducirlo. Cómo contribuir:
  [`CONTRIBUTING.md`](CONTRIBUTING.md); vulnerabilidades: [`SECURITY.md`](SECURITY.md).
- **Licencia:** MIT (ver [LICENSE](LICENSE)).
- **Obra personal.** No está patrocinada ni respaldada por ninguna organización; las que
  aparezcan en ejemplos son ilustrativas.
- **Ninguna herramienta de IA figura como autor, editor ni revisor.** Son instrumento,
  no autoría: la misma tesis que sostiene `R-11`.
