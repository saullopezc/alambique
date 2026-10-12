---
id: clasificacion
titulo: Clasificación
tipo: referencia
clasificacion: C0
responsable: Saul López
---

# Clasificación

Escala: **C0** público · **C1** interno (criterio y método, sin datos) · **C2**
infraestructura de cliente (IP, host, ruta de servidor, usuario de sistema, nombre real
de cliente, salidas reales) · **C3** credenciales y datos reales. Ante duda entre dos
clases, la más alta.

**Este repositorio es público: todo lo versionado aquí es C0.** Lo que entra es criterio
y método; un dato C1 de una organización tampoco entra. La `SKILL.md` y los demás ficheros
que no llevan cabecera propia —la lista está en `AGENTS.md`— quedan cubiertos por esta
declaración, y de ellos responde Saul López.

## Procedimiento

**El barrido por patrón no basta.** Devuelve cero sobre material que no contiene ninguno
de los tokens buscados, y un cero sin control positivo puede ser una sintaxis que no
corrió. Por eso:

1. El patrón decide **dónde mirar**; no decide la clase de lo que encuentra.
2. Toda afirmación negativa lleva **control positivo**: el mismo detector, contra una
   copia que sí tiene el dato, tiene que encontrarlo.
3. Lo que el patrón no alcanza se busca **leyendo**: lo demasiado específico para ser
   inventado —una cifra medida, una duración, un conteo, un identificador arbitrario— y
   la prosa que describe un sistema ajeno sin nombrarlo.
4. Una cifra medida en un sistema que no es tuyo es C2 **aunque no venga con ningún
   nombre al lado**.
5. Los dominios y rutas de ejemplo usan marcadores (`<producto>`) o dominios reservados
   (`example.com`): un fichero que enseña a no escribir coordenadas no puede contener una.

## Cómo re-verificar

```sh
ALAMBIQUE_CONF=$(mktemp -d) ALAMBIQUE_LOCAL=$(mktemp -d) marco/mecanismos/barrido.sh .   # solo patrones generales; sale 0
marco/mecanismos/barrido.sh .                                  # + marcas del puesto; cada ALTA se lee y se clasifica
git grep -nIiE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' -- .          # IPv4
git grep -nI  '/home/' -- .                                    # rutas absolutas locales
git grep -nIiE 'password|passwd|token *=|secret *=|api[_-]?key' -- .
git grep -nIE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' -- .   # correos
```

Control positivo antes de dar por bueno un cero: `d=$(mktemp -d); printf 'host 10.0.0.%s\n'
7 > "$d/control.md"; marco/mecanismos/barrido.sh "$d"` tiene que dar ALTA. La IP se compone
al ejecutar, para que este fichero no la contenga y pase su propio barrido.

Cualquier coincidencia se clasifica antes de commitear. Un resultado vacío solo vale si
antes se ha comprobado que el patrón detecta algo real. Los falsos positivos conocidos de
los detectores están en la tabla de trampas de `AGENTS.md`.
