---
name: operacion-puesto
description: Dónde vive cada cosa en este puesto y cómo se clasifica. Activar al arrancar sesión, al reanudar sesión o al repetir una tarea programada (revisar seguimiento y pendientes), al preguntar "qué tengo pendiente", "en qué iba", "qué hay urgente"; al decidir dónde guardar algo ("dónde pongo esto", "esto se versiona?", "es C2?"), al crear evidencia, contexto, logs o notas; al abrir un proyecto nuevo o preguntar "qué skills uso aquí"; y con "_local", "__restriccion", "clasificar", "metadata del proyecto", "alias", "conexiones".
---

# Operación del puesto — dónde vive cada cosa

**Esta skill y sus plantillas describen UNA forma de organizar el puesto —la de quien la
escribió—, como ejemplo de uso.** Puede no ser completa, y cada puesto la ajusta a su
caso. La organización cliente → operación → proyecto, las diez claves del registro de
conexiones y campos como `pais` o `legado_grep` son una convención, no un esquema
universal: un destino que no sea SSH no cabe tal cual. Qué hace cumplir un mecanismo y qué
queda al criterio de quien escribe lo dice cada sección.

La clase de un dato decide dónde vive (R-01); ante la duda, **la más alta**.

| Clase | Qué es | Dónde vive |
|---|---|---|
| **C0** público | Nada del cliente ni del puesto | Árbol versionable |
| **C1** interno | Criterio, método, destilado sin datos | Árbol versionable |
| **C2** infraestructura del cliente | IP, host, ruta de servidor, nombre real del cliente, salidas reales | `_local/` — **nunca** un repositorio (R-02) |
| **C3** credenciales y datos reales | Contraseñas, llaves, registros de cliente | `_local/` — **nunca** un repositorio (R-02). Lo que el agente no deba leer va a `__restriccion/`: un dato C3 no cruza al proveedor del modelo (R-04) |

**Alias siempre, coordenadas nunca** (R-03). Los alias se resuelven con `conexiones.yaml`
—uno por capa `_local/`, en cascada— y `scripts/resolve_alias.sh`. **La coordenada vive
en `~/.ssh/config`.** Que una salida real la arrastre no le da otro sitio donde vivir:
hace C2 a esa salida.

**`<conf>` es el directorio de configuración del harness en el puesto.** Los scripts de
esta skill lo resuelven en cuatro pasos, y vale el primero que se cumpla:

1. `$ALAMBIQUE_CONF`, si está definido.
2. Ejecutados desde el repositorio del marco: el primer harness de su tabla que exista en
   el puesto (`~/.claude`, `~/.codex`...: la lista es dato del marco, en
   `marco/mecanismos/lib/harness.sh`, y no se copia aquí); si ninguno, `~/.alambique`.
3. Instalados: el `<conf>` de **la copia que se ejecuta**, tres niveles por encima de
   `scripts/`.
4. Copiados sueltos a otro sitio: `~/.alambique`.

La capa local del puesto es `<conf>/_local/`, salvo que `ALAMBIQUE_LOCAL` la fije en
otro sitio. **Con varios harness en el puesto** la skill está copiada en todos, pero esa
capa vive en uno solo: el principal, donde el instalador la crea. Por el paso 3, la
copia de otro harness la busca en su propio `<conf>` y no la encuentra. No se copia la
capa —serían dos verdades—: se declara en el entorno, con
`ALAMBIQUE_LOCAL=<conf principal>/_local` o con `ALAMBIQUE_CONF=<conf principal>`.
`resolve_alias.sh --fuentes` y `contexto_proyecto.sh` nombran la capa del puesto que
consultan, exista o no.

**Las `ALAMBIQUE_*` son variables de entorno, todas opcionales** (tabla en
`marco/README.md`). Se fijan en el entorno desde el que se lanza el harness —el perfil de
la shell—: de ahí las heredan a la vez el agente, los hooks y la puerta de commit. Puesta
solo delante de una orden, la ve esa orden y nadie más.

Las rutas `marco/...` de este texto son del repositorio del marco —el clon desde el que
se instaló—, no de la copia instalada de la skill. La ruta de ese clon está en el fichero
`.alambique-origen` de la raíz de la skill instalada, en su línea `origen:`.

**Se versiona código y contrato; no datos ni evidencia.** Un repositorio tiene que
poder clonarse en una máquina limpia, sin VPN, y seguir siendo útil.

## Estructura de `_local/`

```
_local/
├── entrada/          <- lo que aún no está clasificado (ver abajo)
├── operacion/        <- los cinco directorios de estado, un fichero por item
├── qa/               <- evidencia de validación, por YYYYMMDD_HHMMSS_<asunto>/
├── context/          <- memoria de sesión: comandos y salidas reales
├── respaldos/        <- copias previas antes de tocar algo (*.previo.<TS>)
├── retirados/        <- artefactos que se sacan de circulación, nunca se borran
└── <config real, exports y salidas del cliente>
```

### Qué va en `_local/` — usos recomendados

| Uso | Ejemplo | Por qué ahí |
|---|---|---|
| **Evidencia de validación** | `qa/YYYYMMDD_HHMMSS_<cambio>/REPORTE.md` + `salidas/` | Lleva salidas reales: C2 por construcción |
| **Memoria de sesión** | `context/`: puntos de retorno de sesión y bitácoras | Registra comandos, rutas y salidas reales |
| **Estado operativo** | `operacion/{urgencias,seguimiento,pendientes,planificacion,sugerencias}/<item>.md` | Nombra trabajo de cliente y arrastra salidas reales |
| **Configuración real** | `conexiones.yaml`, `negocio.conf`, `clientes.conf`, `marcas.txt`, `rutas-cliente.conf`, `modelos.conf` | Nombra al cliente, sus servidores y a quien firma: C2 (`modelos.conf` es C1 y va con ellos por ser del puesto) |
| **Logs** | de una validación, `qa/YYYYMMDD_HHMMSS_<cambio>/salidas/`; de una sesión, `context/`; traídos del cliente, con sus exports | No hay un `logs/` aparte: un log es evidencia, memoria o dato del cliente, y va con lo que explica |
| **Respaldo antes de tocar** | `respaldos/<fichero>.previo.<TS>` | Es el punto de restauración (R-07); si no está, no hay vuelta atrás |
| **Artefactos retirados** | `retirados/` — skills sustituidas, documentos que ya no encajan | **Nada se borra: se mueve** |
| **Retirado de una tarea viva** | `operacion/<TS>_<tema>/` junto a su tarea, con un `LEEME` | Fuera de su tarea no se entiende, y en `retirados/` nadie lo vuelve a leer |
| **Exports y salidas del cliente** | volcados, logs, ficheros de un feed | Datos reales, no se versionan jamás. Con registros de cliente o credenciales dentro son C3 |
| **Borradores con datos reales** | notas de diagnóstico con salidas reales pegadas | Hasta que se sinteticen, son C2 |

**Lo que NO va en `_local/`:** código, contrato, y el destilado sin datos de cliente
—ADR, runbook, `AGENTS.md`, memoria, criterio—. Eso se versiona.

**Retirar no es tirar, y el sitio depende de si la tarea sigue viva.** Un script que
se escribió para una operación concreta y se descartó a mitad sigue explicando por
qué esa operación acabó haciéndose de otra forma: va con ella, en
`operacion/<TS>_<tema>/`, con un `LEEME` que diga qué hacía, si llegó a ejecutarse y
por qué se retiró. `retirados/` es para lo que ya no pertenece a ninguna tarea.
Lo que nunca es una opción es `rm`: **ni siquiera con lo que uno mismo acaba de
escribir** —«es mío, no del usuario» es una distinción inventada, y el coste de
moverlo es cero. Si además no estaba commiteado, el `rm` es irreversible y lo único
que queda es reconstruirlo de memoria; entonces hay que **decir en el `LEEME` que
está reconstruido**, porque un fichero que no viene de git no se puede comparar con
nada.

### `_local/entrada/` — lo que aún no está clasificado

Todo lo que llega sin saber qué es —un adjunto, un volcado, un fichero que alguien
pasó, algo descargado para mirarlo después— entra aquí **antes** de tocarlo.

- **Se trata como C2 mientras esté ahí.** No es una excepción a R-01: es aplicarla
  —ante duda, la clase más alta— sin bloquear el trabajo. Nunca sale al árbol
  versionable desde aquí.
- Al abrirlo, se clasifica y se **mueve** a donde le toque. Si resulta tener
  credenciales o registros reales de cliente, sube a C3; lo que el agente no deba
  leer, a `__restriccion/`. Si es C0/C1, sale de `_local/` al sitio que le corresponda.
- **Es un estado transitorio, no un almacén.** Lo que lleva ahí más de una semana
  o se clasifica o se retira: un buzón que no se vacía deja de ser cuarentena y se
  convierte en el agujero por donde se escapa lo que R-01 debía atrapar.
- Se nombra `YYYYMMDD_HHMMSS_<lo que se sepa>`, aunque sea poco.

`__restriccion/` es aparte: lo que el agente **no debe leer**. Lo que lee viaja al
proveedor del modelo, y por eso importa para un dato C3 (R-04): las credenciales
—contraseñas, llaves, tokens— son el caso claro. Protegido por las reglas de lectura
del harness cuando este las ofrece (en Claude Code, reglas `deny`); si no las ofrece,
el control es procedimental y se declara. Nada entra ahí por costumbre; entra por
decisión. Un dato real que se queda en `_local/` porque la tarea lo necesita cumple
R-04 trabajándolo sin traer su contenido a la conversación: contar, filtrar, comparar;
no volcarlo.

Todo artefacto generado **sin patrón de nombre propio** (destilado, log, nota de
contexto, evidencia) se nombra `YYYYMMDD_HHMMSS_<tema>`, o solo `YYYYMMDD_HHMMSS`
si es transversal. Los que ya traen patrón propio conservan el suyo. **La hora se
saca con `date`, nunca se estima.**

## Los cinco directorios de estado — un fichero por item

Viven en `_local/operacion/`. **Un item, un fichero**: un fichero monolítico por
categoría crece hasta que nadie lo lee entero, y cerrar un item obliga a editar en
medio de los demás. Con un fichero por item, cerrar es mover.

| Directorio | Qué contiene | Se puede ejecutar desde ahí |
|---|---|---|
| `urgencias/` | Lo que **caduca o bloquea a alguien**: tiene fecha límite | Sí — y antes que nada |
| `seguimiento/` | Lo que se vigila **AHORA** y **cómo re-chequearlo**. Sobrevive a la compactación | Es vigilancia, no tarea |
| `pendientes/` | **Tareas pequeñas o medianas**: se pueden tomar y hacer. Si una espera una decisión, lo dice el propio item | Sí |
| `planificacion/` | **Tareas grandes y subdivisibles**, aprobadas o no. Al aprobarse se **trocean** en subtareas que van a `pendientes/`, una por fichero con `origen:` apuntando al plan, y el plan pasa a su histórico | **Nunca en bloque.** Un diseño bien escrito invita a ejecutarse; por eso no convive con la lista de lo que hay que hacer |
| `sugerencias/` | Ideas **sin diseñar**. Al decidirse pasan a `pendientes/`, a `planificacion/` o a su histórico | No |

**El criterio entre pendiente y planificación es el TAMAÑO, no la aprobación.**

Junto a una tarea viva puede aparecer además `operacion/<TS>_<tema>/` con lo retirado de
ella (ver «Retirar no es tirar»). No es un sexto directorio de items y el instalador no lo
crea: nace cuando hace falta y muere con su tarea.

**Orden de atención:** urgencias → seguimiento de lo que corre → pendientes.
Mientras se espera a que termine algo, se avanza en pendientes.

**Se revisan al arrancar la sesión Y al reanudar sesión o al repetir una tarea
programada**, no solo al inicio.

### Estructura interna

**Cabecera común a los cinco directorios.** De cada item responde una persona (R-11) y
cada uno declara su clase (R-01), sea una urgencia o una idea:

```markdown
---
estado: abierto
abierto: <YYYY-MM-DD>
actualizado: <YYYY-MM-DD>
clasificacion: <C0-C3>
responsable: <quien responde>
origen: <ruta del plan>        # solo en una subtarea troceada de un plan
---
```

Debajo de la cabecera, el cuerpo. `seguimiento/<asunto>.md` — lo único que de verdad se
pierde al compactar:

```markdown
# Seguimiento — <asunto>

## Qué se está haciendo        <- en una frase
## Estado por bloque           <- tabla: bloque | estado (hecho/en curso/pendiente)
## Cómo re-chequear            <- los comandos exactos, para no reconstruirlo de memoria
## Hallazgos abiertos          <- lo que apareció y no es parte de esta tarea
```

`urgencias/`, `pendientes/`, `planificacion/` y `sugerencias/` — un fichero por item:

```markdown
# <titulo>
- **Por qué**: <el motivo, no la tarea>
- **Dónde**: <fichero:linea, alias del servidor, proyecto>
- **Terminado cuando**: <condicion verificable>
- (urgencias) **Límite**: <YYYY-MM-DD> · **Bloquea a**: <quien>
```

**La cabecera se escribe para que la pueda leer una máquina:** una clave por
línea y un valor de una sola línea. Si el valor lleva `: ` (dos puntos y
espacio), va entre comillas. Lo que no cabe en una línea —el motivo de un
cierre, un resultado, una explicación— va al cuerpo del fichero, no a la
cabecera. Hoy la lee el agente, y el marco no trae ningún lector de YAML; la regla
previene al que venga: dos claves en la misma línea, o prosa con `: ` dentro de un
valor sin comillas, hacen que un lector de YAML rechace el fichero entero.

**Escribir el estado ANTES de que haga falta:** al cerrar cada bloque de una tarea
larga se actualiza el seguimiento — no al final, ni cuando lo pidan. La
compactación conserva el transcript en disco pero **no el hilo**; destilarlo exige
criterio, así que no lo salva ningún hook.

**Item COMPLETADO o descartado: se MUEVE a `<directorio>/historico/`** renombrado
`YYYYMMDD_HHMMSS_<nombre>.md` (hora del cierre, por `date`), con `estado: cerrado` y
`cerrado: <YYYY-MM-DD>` en su cabecera. Lo activo es lo que está en la raíz de cada
directorio; el histórico no se lee salvo para buscar. **Nunca se borra**: un item
cerrado es evidencia.

## Cascada de capas locales — un dato vive en el nivel más alto donde sigue siendo cierto

Las conexiones **no se repiten en cada proyecto**: se resuelven subiendo por el
árbol, de lo específico a lo general. Lo común a un cliente se escribe una vez en
su nivel; lo propio de una operación, en el suyo.

```
<proyecto>/_local/conexiones.yaml        lo que solo vale aquí
<operacion>/_local/conexiones.yaml       la filial o el país (p. ej. una operación nacional)
<cliente>/_local/conexiones.yaml         lo común a todos sus proyectos: bastión, salto
<cartera>/_local/conexiones.yaml         la cartera: `$ALAMBIQUE_PROYECTOS`; sin ella, `~/Proyectos`
<conf>/_local/conexiones.yaml            la raíz: lo transversal al puesto
```

**Gana la primera aparición, campo a campo**: lo específico pisa a lo general, nunca al
revés. La ficha de un alias que está en dos capas trae cada clave una vez, y de la
general solo las que la específica no declara. A un proyecto de la cartera al que se
llega por un enlace simbólico desde fuera de ella se le leen las capas de su ruta real,
hasta la cartera; una capa que cuelgue del directorio del enlace no cuenta.

```sh
resolve_alias.sh --fuentes                        # qué capas se están leyendo, en orden
resolve_alias.sh --list                           # qué alias hay visibles (entorno, modo, propósito)
resolve_alias.sh <alias>                          # ficha completa, ya resuelta por la cascada
resolve_alias.sh <alias> <campo>                  # un campo, apto para $( )
resolve_alias.sh --check <alias> <campo> <valor>  # salida 0 si coincide; para condicionar un script
resolve_alias.sh --validar                        # formato y esquema de toda la cascada de una vez
```

Salidas: 0 correcto · 1 alias no encontrado · 2 campo no encontrado o uso incorrecto · 3 sin
fuente (salvo `--fuentes`, que es diagnóstico: dice dónde buscó y sale 0) · 4 esquema
inválido (`--validar`). En `--check`: 0 coincide · 1 **no** coincide · 2 el alias o el
campo no existen —no hay con qué comparar, y lo dice por la salida de error—.

Implementación de referencia incluida en `scripts/resolve_alias.sh` (bash + awk, sin
dependencias; funciona copiado solo). **No lleva un parser de YAML:** admite el formato
de `plantillas/conexiones.yaml.example` —`version`, y `conexiones` como lista de
registros `- clave: valor`, un valor por línea— y ninguno más. Una línea que no encaja
no se atribuye a ningún alias: al resolver se avisa por la salida de error, y
`--validar` dice cuál, con fichero y número de línea.

El formato estándar de cada fichero de la capa local está en su plantilla. Cuatro viven
aquí, en `plantillas/`; las otras tres, en `marco/plantillas/`, junto al mecanismo que
lee cada una:

| Plantilla | Dónde | Clase | Se versiona |
|---|---|---|---|
| `conexiones.yaml.example` | `plantillas/` | C2 | el `.example` sí; el real **nunca** |
| `negocio.conf.example` | `plantillas/` | C2 (dato personal) | el `.example` sí; el real **nunca** |
| `clientes.conf.example` | `plantillas/` | C2 | el `.example` sí; el real **nunca** |
| `proyecto.yaml.example` | `plantillas/` | **C1** | el `.example` sí; el real **no** — es estado del puesto y vive en `_local/` |
| `rutas-cliente.example.conf` | `marco/plantillas/` | C2 | el `.example` sí; el real **nunca** |
| `marcas.example.txt` | `marco/plantillas/` | C2 | el `.example` sí; el real **nunca** |
| `modelos.example.conf` | `marco/plantillas/` | C1 | el `.example` sí; el real **no** — es configuración del puesto |

**`conexiones.yaml` está diseñado para ser insuficiente para conectarse.** No guarda
dirección, ni usuario, ni puerto, ni credencial: guarda cómo se llama cada destino y
cómo hay que tratarlo; `ssh_host` referencia una entrada `Host` de `~/.ssh/config`.
Por eso `resolve_alias.sh --validar` falla (salida 4) si
`ssh_host` se parece a una IP o a un FQDN —por su forma más corriente: cuatro números con
puntos, un nombre con puntos cuya última etiqueta son dos o más letras, o cualquier valor
con `@` o con `:`—: no es un formato más estricto, es la propiedad que hace que el
fichero se pueda tener sin que sea una llave. Sale 4 también con una fuente que existe
y no aporta ningún alias —vacía, o con `conexiones` escrito como mapa por nombre—, con
un alias repetido dentro del mismo fichero (vale el primero; en **otra** capa no es un
problema: es la cascada) y cuando a un alias le falta alguna de las diez claves.

**Qué hace cumplir un mecanismo, y qué no.** De las diez claves, `alias` es la de búsqueda
y solo otras dos las consume un mecanismo: `ssh_host` (su forma, `--validar`; el destino,
`guard-legacy-grep`) y `legado_grep` (ese mismo guard). El resto, incluida
`modo: solo-lectura`, es información para el agente y para quien revisa: ningún mecanismo
la hace cumplir. `--validar` comprueba que las claves están y que `ssh_host` no es una
coordenada; no valida valores enumerados ni rechaza claves fuera del esquema —un registro
con `ip:`, `usuario:` o `clave_acceso:` da «sin problemas»—. El criterio lo pone quien
escribe el fichero: R-03. Y la cascada completa es solo de `conexiones.yaml`: `marcas.txt`
y `clientes.conf` el barrido los lee del proyecto y del puesto, no de los niveles
intermedios.

**Un instrumento no vale hasta verlo detectar.** `--check` devolviendo cero sobre el
valor esperado no prueba nada: prueba el control positivo —pásale un valor que NO sea
el del fichero y comprueba que sale 1—, y antes de fiarte de que un alias "no está",
resuelve uno que sí está. Al resolver no se valida el esquema: si una clave obligatoria
falta, la ficha sale sin ella y es el consumidor quien lo nota (campo no encontrado,
salida 2).

`CONEXIONES_YAML=<fichero>` fuerza una fuente única, para probar sin tocar el puesto:
con ella definida la cascada no se mira. `ALAMBIQUE_PROYECTOS` fija la cartera:
`~/Proyectos` es su valor por defecto, no un requisito. La cartera no puede ser el propio
`$HOME`: el recorrido se detiene antes de llegar a él, y su `_local/` no se lee como capa.

## Metadata de proyecto

Cada nivel declara quién es en su `_local/proyecto.yaml` — **el proyecto, y
también el cliente y la operación**. Sin la declaración del nivel del cliente no
se sabe a qué altura del árbol vive lo común, y todo acaba repetido abajo.

**El dueño de un directorio no se deduce: se declara.** La estructura del árbol
no es uniforme —un nivel puede ser un país, un cliente o un proyecto suelto— así
que **ante la duda se PREGUNTA quién es el cliente**; nunca se infiere del nombre
del directorio ni de la ruta. Preguntar el alias, no inventarlo.

**Mientras no se sepa, se escribe `cliente: <PREGUNTAR>`.** Ese literal, y cualquier
valor con forma de marcador de plantilla (`<...>`), cuenta como sin declarar: una
plantilla copiada sin rellenar no identifica a nadie.

Para saber de quién es un directorio y qué capas hay: `scripts/contexto_proyecto.sh`
desde el directorio. Sale 0 si está identificado; 1 si hay que preguntar —falta declarar
el cliente, solo lo nombra la declaración de un proyecto, o dos niveles nombran clientes
distintos, y entonces dice qué dos ficheros—; 2 fuera de la cartera (lo dice, con el
valor de `ALAMBIQUE_PROYECTOS`) o uso incorrecto. **El nivel del cliente es la declaración
que lo nombra sin `proyecto:`**; la respuesta es la misma desde la raíz de un proyecto que
desde cualquier subdirectorio suyo, también si se llega por un enlace simbólico. Un
proyecto que no es de ningún cliente —propio, abierto— declara `cliente: ninguno`: sale 0
y no se pregunta por un nivel de cliente.
Lee las claves de primer nivel de `proyecto.yaml`, sin sangría delante, como las trae
la plantilla. A mano es lo mismo: leer `_local/proyecto.yaml` en el nivel actual y en
cada padre hasta la cartera, y `resolve_alias.sh --fuentes` para ver qué capas de
conexiones se están leyendo.
`contexto_proyecto.sh --crear` crea la `_local/` de la cartera si falta, y solo esa: la
del nivel del cliente existe por construcción, porque es donde está el `proyecto.yaml`
que lo declara, y no se crea sin saber a qué altura va —crearla en el sitio equivocado
es justo la repetición que la cascada evita—.

Para crear el esqueleto completo de un nivel, `marco/instalar.sh <ruta>`: pone el bloque
de ignore en su `.gitignore`, crea el árbol de `_local/` descrito arriba y
`__restriccion/` —con un `.gitkeep` en cada directorio, salvo en `operacion/`, que ya
tiene los cinco dentro, y un `README.md` en cada capa—, da de alta también el puesto si
faltaba y pone la puerta de commit (`<ruta>` tiene que ser un repositorio git: sin
`.git` la puerta cuenta como pieza sin poner y el instalador sale 1). A mano, crear los
directorios no basta: lo que sostiene R-02 es el bloque de ignore, y va primero. Con
`M` apuntando al clon del marco (su ruta, en `.alambique-origen`):

```sh
grep -q '^# >>> alambique' .gitignore 2>/dev/null || cat "$M/marco/plantillas/gitignore" >> .gitignore
mkdir -p _local/{entrada,operacion/{urgencias,seguimiento,pendientes,planificacion,sugerencias},qa,context,respaldos,retirados} __restriccion
find _local __restriccion -type d -exec touch {}/.gitkeep \;
git check-ignore -q _local/control.txt && echo "la capa local está ignorada"   # si no lo dice, no escribir nada dentro
```

Y aun así queda sin puerta de commit: el ignore evita el descuido, no un `git add -f`.

**Con alias, nunca coordenadas** (R-03) — así el fichero es C1 aunque viva en `_local/`
como estado del puesto (no se versiona). Sus alias los resuelve la cascada.

```yaml
proyecto:    <nombre corto>             # se omite en el nivel de cliente/operacion
cliente:     <ALIAS del cliente>        # PREGUNTADO, nunca deducido; `ninguno` si no lo hay
operacion:   <ALIAS de la filial/pais>  # si el cliente tiene varias
responsable: <quien responde>           # R-11
clasificacion: <C0|C1|C2|C3>            # la del nivel en conjunto

servidores:                             # SOLO alias; se resuelven con el resolutor
  - alias: <alias>
    rol:   <produccion | pruebas | salto>
accesos:                                # cómo se entra, no con qué se entra
  metodo: <ssh-por-salto | vpn-y-salto | local>
  nota:   <lo que hay que saber; ni coordenada ni credencial>

stack:       [<tecnologias principales>]
herramientas: [<lo que hace falta tener instalado>]

skills:                                 # qué cargar al abrir este proyecto
  - <skill>
  - <skill>
```

El campo `skills` es declarativo: lo lee el agente al abrir el proyecto (sección siguiente),
no un script. Es lo que hace que una skill específica —la de un dominio, un stack o un
producto concreto— se cargue **donde aplica** en vez de estar activa en todas partes.

## Al abrir un proyecto

1. `scripts/contexto_proyecto.sh` (o leer `_local/proyecto.yaml` a mano): si sale 0,
   de quién es; si sale 1, preguntar lo que pide y proponer la declaración cuando el
   proyecto lo amerite; si sale 2, el directorio no cuelga de la cartera.
2. Revisar `_local/operacion/` en el orden de atención.
3. Cargar las skills que declare su campo `skills`. Antes de cargar cada una: qué capas
   quedan activas, qué contradicciones hay entre ellas, **qué clase de dato entra y
   dónde acaba cada artefacto**.
