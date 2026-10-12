# AGENTS.md — alambique

Un marco de doce reglas para trabajar con agentes de IA sobre datos ajenos, sus
mecanismos, y la skill que le dice al agente dónde vive cada cosa, en formato abierto Agent Skills:
**método y criterio, cero datos de cliente**. Este fichero es la
**única** puerta de entrada para cualquier agente; `CLAUDE.md` y `GEMINI.md`
solo lo importan.

## Qué cargar y cuándo

| Cargar | Cuándo |
|---|---|
| `marco/skills/operacion-puesto/SKILL.md` | Al clasificar, decidir dónde va algo o resolver un alias. Instalada, la pide el hook de arranque |
| [`marco/NORMA.md`](marco/NORMA.md) | Siempre que la tarea toque datos de cliente o un servidor ajeno. Son doce reglas: cabe en la cabeza |
| [`CLASIFICACION.md`](CLASIFICACION.md) | Antes de añadir contenido: la escala, el procedimiento y cómo re-verificar |

## Reglas de este repositorio

- **Clase C0: es público.** Aquí entra criterio, nunca un dato de un tercero: ni
  coordenada, ni nombre real de cliente, ni cifra medida en un sistema ajeno (R-01, R-03).
  Ante duda, no entra. Cómo re-verificar: sección «Cómo re-verificar» de `CLASIFICACION.md`.
- **Agnóstico al harness.** Ningún texto nombra `~/.claude` ni `CLAUDE.md` como
  único camino: se escribe `<conf>` (directorio de configuración del harness) y
  "fichero de contexto" (`AGENTS.md`, o su shim). Lo que SOLO funciona en un
  harness vive en `marco/adaptadores/` y se declara como tal; lo que aún queda fuera
  —el contrato de hook y el registro de cada hook— lo dice la sección «Harness».
- **Una regla, un dueño.** Las reglas `R-01`..`R-12` viven en `marco/NORMA.md`;
  la skill las cita, no las reformula. Lo que se puede contar no se escribe a mano: el
  recuento de quién comprueba cada regla, el texto de las reglas en las plantillas de
  contexto y las cifras de guards, hooks y bancos salen de su fuente, y
  `pruebas/coherencia.sh` falla si la prosa dice otra cosa. Una regla no figura como
  mecanizada entera mientras su mecanismo declare algo que no ve.
- **Un mecanismo declara lo que no ve.** El barrido, la puerta y los guards llevan en su
  cabecera lo que prometen y lo que no ven; al tocar un patrón se actualizan las dos cosas
  con lo medido, y el resumen de «Límites declarados» del `README.md`. Los patrones son
  un punto de partida, no una lista completa: lo que no se cubre se declara, no se calla.
- **Firma una persona, sin atribución a IA** (R-11). Cada aporte lo firma quien lo hace,
  con su nombre. Commits convencionales, sin `Co-Authored-By` de una herramienta.
- **`description` de la `SKILL.md` ≤ 1024 caracteres** (límite de la
  especificación). Medir antes de commitear.
- **El frontmatter de una `SKILL.md` lleva solo `name` y `description`**: lo fija la
  especificación Agent Skills, y un campo extra es ruido para el harness. Su
  `clasificacion` y su `responsable` los declara `CLASIFICACION.md` por el conjunto.
- **Qué documentos no llevan cabecera.** "Todo documento declara `clasificacion` y
  `responsable`" se aplica a los que son documentos por sí mismos: `marco/NORMA.md`,
  `marco/README.md`, `CLASIFICACION.md` y las plantillas
  que un proyecto copia (los `.example` la llevan como comentario: clase y
  `Responsable:`). No la llevan —y `CLASIFICACION.md` responde por ellos en
  conjunto— la `SKILL.md` (el harness la lee como skill), los ficheros de portada y de harness (`README.md`, `AGENTS.md` y sus shims,
  `SECURITY.md`, `CONTRIBUTING.md`, las plantillas de contexto), los README de las
  capas locales, las dos plantillas `gitignore` (son bloques que se insertan en un
  fichero ajeno) y el texto de la licencia.

## Cómo se valida un cambio

No hay framework de test: cada mecanismo tiene su banco en `pruebas/`, un script
autosuficiente que monta sus repositorios y su HOME temporales y prueba cada caso con su
control. Antes de tocar un mecanismo se pasa su banco contra `HEAD`
(`git archive HEAD | tar -x -C <dir>`; `pruebas/<banco>.sh <dir>`); un caso nuevo tiene
que fallar ahí y pasar con el cambio. Además, salida y código de salida de:

```bash
for f in $(git ls-files '*.sh'); do bash -n "$f" || echo "FALLA $f"; done   # uno a uno: bash -n solo mira el primero
T=$(mktemp -d); mkdir -p "$T/.claude"; env -i PATH="$PATH" HOME="$T" ./instalar.sh </dev/null; echo $?   # 0; con la entrada cerrada no pregunta la identidad
T=$(mktemp -d); mkdir -p "$T/.codex";  env -i PATH="$PATH" HOME="$T" ./instalar.sh </dev/null; echo $?   # 3: hueco declarado
T=$(mktemp -d);                        env -i PATH="$PATH" HOME="$T" ./instalar.sh </dev/null; echo $?   # 1: sin ningún harness
# Identidad: en una terminal pregunta y escribe; `script` da la terminal a la prueba
T=$(mktemp -d); mkdir -p "$T/.claude"; printf 'Ana Ruiz\nana@example.org\nEjemplo SA\n' | script -qec "env -i PATH='$PATH' HOME='$T' ./instalar.sh" /dev/null >/dev/null; grep -c '^autor_correo=ana@example.org$' "$T/.claude/_local/negocio.conf"   # 1
sed -n 's/^description: *//p' marco/skills/operacion-puesto/SKILL.md | tr -d '\n' | wc -m   # <= 1024
ALAMBIQUE_CONF=$(mktemp -d) ALAMBIQUE_LOCAL=$(mktemp -d) marco/mecanismos/barrido.sh . ; echo $?   # 0 sin lista del puesto
marco/mecanismos/barrido.sh . ; echo $?                                                    # con la lista: cada ALTA se clasifica leyendo
# Guard de autoría, control positivo: una atribución tiene que salir. El proyecto va FUERA de <conf>
T=$(mktemp -d); mkdir -p "$T/conf/hooks" "$T/proy/docs"; cp -R marco/mecanismos/guard-autoria-docs.sh marco/mecanismos/lib "$T/conf/hooks/"
printf -- '---\nresponsable: Ana Ruiz\n---\nGenerado con Claude\n' > "$T/proy/docs/a.md"
printf '{"tool_input":{"file_path":"%s"}}' "$T/proy/docs/a.md" | env -i PATH="$PATH" ALAMBIQUE_CONF="$T/conf" "$T/conf/hooks/guard-autoria-docs.sh" | grep -c 'atribución a IA'   # 1
# Los bancos: puerta y barrido, guards, instaladores, la skill, el arranque y la coherencia de la prosa
for t in pruebas/*.sh; do "$t" >/dev/null 2>&1 || echo "FALLA $t"; done   # sin salida
# Resolutor: un sufijo de un alias no es un alias
S=marco/skills/operacion-puesto; CONEXIONES_YAML=$S/plantillas/conexiones.yaml.example $S/scripts/resolve_alias.sh app; echo $?   # 1
```

`env -i` importa: con el HOME del puesto se instalaría de verdad. El barrido se prueba
también con control positivo (comando en `CLASIFICACION.md`). Con la lista de marcas del
puesto cargada puede dar ALTA sobre prosa corriente: el patrón decide dónde mirar, no la
clase de lo que encuentra, y una marca que es palabra común casa con la palabra. Se lee la
línea y se decide; el cero incondicional solo se exige sin lista.

Un instalador se prueba viéndolo **poner y quitar** sobre una configuración que
ya tenga reglas y hooks del usuario: lo del usuario tiene que sobrevivir.

## Trampas conocidas

| Síntoma (literal) | Causa real | Qué hacer |
|---|---|---|
| `barrido.sh` devuelve miles de ALTA sobre prosa normal y la puerta bloquea todo commit | En un `clientes.conf` —el del puesto, `<conf>/_local/`, o el del proyecto— hay una expresión que casa con la cadena vacía (`x*`): casa con todas las líneas. Las líneas vacías y los comentarios de las dos listas ya se filtran; una expresión así, no | Mirar la lista, no el árbol: anclar o completar la expresión |
| Un ALTA que solo aparece con la lista del puesto, sobre una frase corriente | Una marca de la lista es una palabra común (o va dentro de otra), sin discriminante; el barrido no sabe si la frase habla de la empresa o de la palabra | Leer la línea y clasificarla: eso lo decide quien revisa, no el patrón. Si la marca casa siempre dentro de otra palabra, anclarla en la lista (`clientes.conf` admite regex) |
| El barrido marca ALTA un valor entre comillas asignado a `token` o `password` en un ejemplo de código | El patrón no distingue un valor de prueba de uno real, y no debe: un literal es un literal | En el ejemplo va un marcador (`"<token>"`); variables, llamadas y lecturas del entorno ya las deja pasar |
| Un guard no actúa y `settings.json` dice que está registrado | Falta `<conf>/hooks/lib/hook.sh`, o el guard se copió a mano sin su `lib/` | Repetir `./instalar.sh`; el guard avisa de la falta por `systemMessage` en vez de callar |
| Un patrón de un guard «detecta» al probarlo a mano y el guard calla, o al revés | El guard sanea el `PATH` y usa el `grep` del sistema; la shell puede tener otro delante (una función, un alias, otra implementación) y no leen igual la misma expresión: `[^\n]` es «ni barra invertida ni n» en GNU grep, no «sin salto de línea» | Probar el guard entero con `env -i`, no el patrón suelto. Entre la palabra clave y el nombre va `.` |
| Tras cambiar el patrón de un guard deja de ver una forma que veía | Un banco de prueba hecho solo con los casos del cambio no ve las regresiones | Pasar `pruebas/guards.sh` contra un árbol de `HEAD` y contra el nuevo: lo que `HEAD` veía tiene que seguir viéndose |
| El barrido marca ALTA una clave con nombre de credencial cuyo valor no es un secreto | El patrón casa por el nombre (`*_TOKEN`, `*_SECRET_*`, `contraseña`…) y no sabe qué significa el valor; excluye los sufijos y valores que no son secreto más corrientes, no todos | Leer la línea y clasificarla. Si el valor es público, renombrar la clave o declarar el fichero exento |
| La puerta dice «BLOQUEADO — el barrido no terminó (código 3)» | El barrido no pudo barrer: fichero ilegible, expresión inválida en `clientes.conf`, fallo de git, o su autocomprobación no detecta (falta `awk`, `grep` o `sed`, o no entienden los patrones). No es un hallazgo | Leer la línea `barrido: …` que va debajo y corregir la causa; el barrido sale 3 solo cuando no hay veredicto |
| El guard de autoría pide firma a todo `.md` de un proyecto, también fuera de `docs/` | El proyecto vive bajo un directorio llamado `docs`, `doc`, `qa` o `runbooks`: el alcance se decide sobre la ruta completa del fichero | Es un límite declarado en la cabecera del guard. Una prueba se monta bajo un directorio de nombre neutro |
| El guard de autoría calla ante todo en una prueba, también ante lo que debe detectar | El fichero de prueba está dentro de `<conf>`: el guard no mira la configuración del propio harness | Poner el proyecto de prueba fuera de `<conf>` (comando en «Cómo se valida un cambio») |

## Estructura

| Ruta | Qué es | Licencia |
|---|---|---|
| `CLASIFICACION.md` · `SECURITY.md` · `CONTRIBUTING.md` | Clasificación del contenido y cómo re-verificarla, canal de vulnerabilidades, cómo contribuir | MIT |
| `marco/` | Norma, mecanismos (puerta, barrido, tres guards, el arranque de skills y el contrato de hook en `lib/`), un adaptador (Claude Code), plantillas, instalador | MIT |
| `marco/skills/operacion-puesto/` | La skill del marco: `SKILL.md`, el resolutor de alias, el identificador de capas de un proyecto y sus plantillas | MIT |
| `instalar.sh` | Reparte la skill a cada harness detectado y llama a `marco/instalar.sh` | MIT |
| `pruebas/` | Un banco por área: `puerta_barrido.sh`, `guards.sh`, `instaladores.sh`, `operacion_puesto.sh`, `arranque.sh`, y `coherencia.sh`, que compara la prosa con su fuente. No se instala | MIT |

## Harness

La tabla de harness —directorio, fichero de contexto, directorio de skills,
adaptador— es **dato** en `marco/mecanismos/lib/harness.sh`; la prosa de README y
de la skill la cita, no la define, y es ahí donde se corrige. Los scripts no llevan copia:
guards y scripts resuelven `<conf>` por su propia ubicación. Añadir un harness es una
línea; darle reglas de lectura y guards son dos ficheros: el
adaptador en `marco/adaptadores/` y su versión de `marco/mecanismos/lib/hook.sh`
(la carga de entrada y la respuesta de hook; los guards no cambian). El evento y el
matcher con que se registra cada hook van todavía en `marco/instalar.sh`, en la gramática
de Claude Code: es lo que falta por llevar al adaptador. Hoy solo Claude Code los tiene,
y el instalador **lo dice** en los demás.

---

Saul López — github.com/saullopezc
