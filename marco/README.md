---
id: marco-readme
titulo: El marco — doce reglas y sus mecanismos
tipo: referencia
clasificacion: C0
responsable: Saul López
---

# El marco

La skill de este repositorio cita reglas `R-01`..`R-12`. Esto es lo que cita.

**Doce reglas. Es todo.** Si algo no está en [`NORMA.md`](NORMA.md), no es norma.

## Por qué es tan corto

Un marco de riesgo completo son cientos de requisitos, y ese es su problema: una norma
que no cabe en la cabeza se consulta **después** del error, no se logra auditar entera, y
cada caso que se le añade la vuelve un poco más inconsistente. Estas doce reglas son lo
que queda cuando se conserva solo lo que aplica a cualquier interacción y se fusiona lo
que se solapa.

La última columna de la tabla es **quién comprueba cada regla**. El recuento honesto es
ninguna mecanizada entera, 6 a medias y 6 que dependen de que una persona se acuerde. Un marco
que declara 100% de cobertura cuenta los requisitos que un control **cita**, no los que
**comprueba**; en cuanto alguien se lo cree, deja de proteger para pasar a tranquilizar.

## Qué hay aquí

| Pieza | Qué es |
|---|---|
| [`NORMA.md`](NORMA.md) | Las doce reglas, con quién comprueba cada una |
| `mecanismos/puerta.sh` | Puerta de commit: detiene el commit si lo preparado trae algo de la capa local o una forma de C2/C3 que el barrido conoce. Falla en cerrado: si el barrido no termina, no hay commit. Solo actúa donde git ejecuta `pre-commit`: lo que no pasa por ella lo lista su cabecera |
| `mecanismos/lib/hook.sh` | El contrato de hook del harness —cómo llega la orden, cómo se responde— en un solo fichero. Hoy, el de Claude Code; otro harness es otra versión de este fichero. Cada guard responde con un único objeto: el aviso a la persona viaja dentro de la decisión |
| `mecanismos/guard-remoto.sh` | Pide confirmación ante acciones destructivas, ante una escritura cuyo destino es una ruta de servidor declarada, y ante `scp`/`rsync` hacia un host o un `ssh` cuyo tramo remoto escribe (R-06, R-07) |
| `mecanismos/guard-legacy-grep.sh` | Sobre órdenes `ssh`: deniega extensiones de las utilidades en el tramo remoto hacia un destino marcado en la capa local como sin ellas (se compara el destino del `ssh` con el `alias` y con el `ssh_host`), y pide confirmación ante un `ssh` a una IP literal en vez de a un alias (R-03) |
| `mecanismos/guard-autoria-docs.sh` | Vigila que ninguna IA figure como autor en todo `.md` y en el código de las extensiones que mira (las lista su cabecera), la firma de los documentos de proyecto —la cabecera `responsable`, o la firma al pie con el correo de la capa local— y el sello del código cuya cabecera ya lleva fecha de modificación (R-11). La identidad se lee de la capa local |
| `mecanismos/arranque-skills.sh` | Al iniciar o reanudar la sesión pide al agente que cargue la skill del marco: declararla en el contexto no la carga. No es un guard. Pide además toda skill instalada que se declare de arranque con un fichero `.arranque`; `ALAMBIQUE_SKILLS_ARRANQUE` fija la lista entera |
| `mecanismos/barrido.sh` | Barrido por patrón del árbol o de lo preparado para commit, más las marcas del puesto (literales en `marcas.txt`, regex en `clientes.conf`); el informe enmascara lo que casó (`--full` lo enseña) y nombra los ficheros exentos |
| `mecanismos/lib/harness.sh` | La tabla de harness —directorio, fichero de contexto, skills, adaptador— como dato, la resolución de `<conf>`, y lo que alta y baja resuelven igual (ignore global de git, raíz de un repositorio, estado del bloque) |
| `adaptadores/claude.sh` | Lo que SOLO vale en Claude Code: reglas de lectura (R-04) y alta de los hooks en su configuración, con copia previa y sin tocar lo que no entiende. Es el único adaptador |
| `plantillas/` | Bloque para el contexto global y su añadido para harness sin adaptador, plantilla del contexto de proyecto, checklist de tarea, `gitignore` del proyecto y `gitignore-global` (mínimo), el README de cada capa local del proyecto, y los `.example` de lo que leen los guards (`rutas-cliente`, `modelos`) y el barrido (`marcas`) |
| `skills/operacion-puesto/` | La skill del marco: dónde vive cada cosa y cómo se clasifica (R-01, R-02, R-03). Trae el resolutor de alias que usa `guard-legacy-grep`, el script que dice de quién es un directorio y las plantillas de la capa local |
| `instalar.sh` · `desinstalar.sh` | Instalan y retiran el conjunto, y dicen lo que no han podido poner |

**Los mecanismos son una red, no un sustituto.** Si uno salta, se lee el motivo en vez
de aprobar por inercia; si calla, no ha dicho que esté limpio. Cada script declara en su
cabecera lo que no ve, y sus patrones —formas de credencial, verbos destructivos, nombres
de modelo— son las más corrientes: un punto de partida que puede no ser completo y que
cada puesto ajusta a su caso. El resumen está en «Límites declarados» del
[README](../README.md#límites-declarados). Las seis reglas que ninguna máquina comprueba, y el fondo de
R-11 (el hook vigila la firma, no que alguien responda), van al contexto global del
harness porque no hay otro sitio desde el que puedan actuar.

## Instalación

```sh
./instalar.sh                 # ignore global, bloque de reglas en el contexto global del
                              # harness, y —solo con adaptador— reglas de lectura y hooks
./instalar.sh /ruta/proyecto  # además: .gitignore, capa local y puerta de commit
./desinstalar.sh --ver        # qué quitaría; --aplicar lo quita, con copia .previo
```

Antes de ejecutarlos, léelos. Escriben en la configuración del puesto, y solo esto: un
bloque marcado en el ignore global de git (solo `_local/` y `__restriccion/`, en el fichero
que diga `core.excludesfile` o, si no dice ninguno, en el que git lee por defecto; ese
ajuste no se escribe nunca, y el instalador comprueba con git que `_local/` queda ignorado y,
si no, lo marca `NO ACTIVO`) y en el
fichero de contexto global del harness; el directorio `<conf>/_local/`, donde van los
datos del puesto, y en él `negocio.conf` con la identidad de quien firma, que el
instalador pregunta en una terminal si no existe ya; con adaptador, reglas de lectura y
cuatro hooks en la configuración del harness —tres guards y el arranque de skills—, con
copia `.previo.<sello>` antes del primer cambio de cada fichero de la persona que ya existía,
esos cuatro con su `lib/hook.sh` en `<conf>/hooks/` —lo que el marco copió se sustituye por
la versión del repositorio, sin copia previa—, y `<conf>/.alambique-alta` con la anotación del
adaptador, donde el alta apunta qué añadió y qué ficheros creó; con proyecto, su `.gitignore`, el esqueleto de la capa local y un `pre-commit` que llama a
este repositorio por su ruta. **El clon se queda donde se instaló**: si se mueve, se
repite el alta.

Requisitos y plataformas probadas: los del [README](../README.md) de la raíz, sección
«Instalación».

**No se asume ningún harness.** `<conf>` es `$ALAMBIQUE_CONF` o el primer directorio de
configuración que exista (`~/.claude`, `~/.codex`, `~/.gemini`, `~/.cursor`,
`~/.config/opencode`, `~/.aider`); si ninguno, `~/.alambique` (el `instalar.sh` de la raíz,
en cambio, se detiene y pide `$ALAMBIQUE_CONF`: sin harness no hay donde repartir skills). Las piezas que dependen de
cómo el harness expresa permisos y hooks las pone un adaptador, y **solo hay uno** (Claude
Code). En cualquier otro harness el instalador termina con salida `3` y marca R-04, R-06,
R-07 y R-11 —y el guard de R-03— como `NO SOPORTADO`: es un hueco declarado, no un fallo. El desinstalador
retira los bloques marcados, las reglas y hooks que el alta anotó haber añadido y los guards
copiados, y los renombra con `.previo.<sello>` en vez de borrarlos; las reglas, hooks y
líneas del usuario sobreviven. Sin anotación del alta, o si el alta encontró una instalación del marco sin anotar, no retira las reglas de lectura que ya estaban: no consta quién las puso, y las lista. La skill la instala el `instalar.sh` de la raíz y se retira a mano: es
el directorio `<conf>/skills/operacion-puesto`, si contiene `.alambique-origen`.

**Variables de entorno.** Todas opcionales; cada script documenta la suya en su cabecera.

| Variable | Qué fija | Si no está |
|---|---|---|
| `ALAMBIQUE_CONF` | `<conf>`: el directorio de configuración del harness. Si se declara y no existe, el instalador lo crea. El harness se reconoce por el último tramo de la ruta (`.claude`, `.codex`…): con otro nombre (`~/.claude-trabajo`) no se le asigna adaptador | el primero de la tabla que exista; si ninguno, `~/.alambique` |
| `ALAMBIQUE_LOCAL` | La capa local del puesto: la leen el barrido (y con él la puerta), `guard-remoto`, `guard-autoria-docs`, el instalador y los scripts de `operacion-puesto`. Las tres variables de fichero de abajo la pisan una a una | `<conf>/_local` |
| `ALAMBIQUE_PROYECTOS` | La cartera: raíz bajo la que cuelgan clientes y proyectos (cascada de alias) | `~/Proyectos` |
| `ALAMBIQUE_RUTAS` | Raíces de servidor que vigila `guard-remoto` | `<conf>/_local/rutas-cliente.conf` |
| `ALAMBIQUE_NEGOCIO` | Identidad de quien firma que comprueba `guard-autoria-docs`. Fijarla salta la cascada | el `_local/negocio.conf` más cercano al fichero escrito (proyecto o cliente); si no hay, `<conf>/_local/negocio.conf` |
| `ALAMBIQUE_MODELOS` | Nombres de IA añadidos a la lista del mismo guard | `<conf>/_local/modelos.conf` |
| `ALAMBIQUE_RESOLVER` | El resolutor de alias que usa `guard-legacy-grep` | el de la skill `operacion-puesto` instalada |
| `ALAMBIQUE_SKILLS_ARRANQUE` | Skills que `arranque-skills` pide cargar al abrir la sesión, separadas por espacios. Sustituye a la lista por defecto | `operacion-puesto` y toda skill instalada con un fichero `.arranque` en su directorio |

Fuera de esa familia hay una más: `CONEXIONES_YAML` hace de un fichero la única fuente del
resolutor de alias, sin cascada. Es para probar; definida en el entorno del harness, es
también la única que consulta `guard-legacy-grep`.

## Cómo crece

Casi nunca. Cuando una regla se queda corta manda **R-12**: un fallo repetido se convierte
en mecanismo, no en un requisito nuevo. Se añade código a `mecanismos/`, no una fila a la
tabla. La tabla solo crece si aparece una clase de riesgo que ninguna de las doce cubre.

Y un mecanismo tampoco crece para cubrir cada caso: se mantiene simple y declara su
alcance. Donde sí crecen los patrones de detección, las heurísticas y los procesos es en
cada empresa consultora, que los adapta a su realidad y los amplía en su propio puesto.

---

Saul López — github.com/saullopezc
