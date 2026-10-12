# Plantilla — fichero de contexto de un proyecto

> Se llama `AGENTS.md` (especificación abierta). Claude Code lee `CLAUDE.md` y
> Gemini CLI `GEMINI.md`: en esos, una línea que diga solo `@AGENTS.md` —lo
> importa; un enlace no lo carga— y nada más, para que la norma tenga un solo
> dueño.

> Se carga en **cada** sesión de este proyecto, así que cada línea cuesta
> contexto siempre. Prueba para decidir si una línea entra: **si el agente no lo
> supiera, ¿rompería algo o perdería tiempo?** Si no, fuera.
>
> **No va aquí:** lo que el código ya dice (se lee) · lo que dice el marco
> global (se enlaza, no se copia) · la descripción comercial (eso es el README)
> · el historial (eso es `git log`).
>
> Objetivo: **menos de 60 líneas.** Si crece más, casi siempre está duplicando
> el README.

> **Harness sin fichero de contexto global** (en la tabla de `mecanismos/lib/harness.sh`,
> los que llevan `-` en esa columna): las reglas de criterio no llegan desde el puesto.
> Pegar al final de este fichero el contenido de `contexto-global.bloque.md` y, si el
> harness tampoco tiene adaptador, el de `contexto-global.sin-adaptador.md`, con las
> rutas de sus enlaces cambiadas a las del clon del marco. Se quita a mano: el
> desinstalador no toca el fichero de contexto de un proyecto.

Copiar desde la línea siguiente.

---

# <nombre-del-proyecto>

<!-- UNA frase: qué es y cuál es su papel. -->

## Stack

<!-- Lo que condiciona CÓMO se escribe el código. La versión del DESTINO real,
     no la del puesto: es la diferencia entre compilar y funcionar. -->

- **Lenguaje / runtime:** <versión>
- **Destino de ejecución:** <SO y versión reales>
- **Restricciones del destino:** <lo que NO se puede usar, y por qué>

## Cómo se valida un cambio

<!-- LA SECCIÓN MÁS IMPORTANTE. Sin ella, cada sesión vuelve a preguntar o,
     peor, da por bueno lo que no ha probado. Comando exacto. -->

```bash
<el comando>
```

## Clase de dato que se maneja aquí

<!-- R-01. Si este proyecto toca datos de cliente, decirlo aquí ahorra tener
     que deducirlo cada vez. -->

- **Clase por defecto:** <C0 | C1 | C2 | C3>
- **Lo que nunca sale de `_local/`:** <qué>

## Trampas conocidas

<!-- Lo que ya rompió una vez. Una línea por trampa. Esto es R-12 en su forma
     más barata: si la trampa vuelve, deja de ser una línea y pasa a ser un
     mecanismo. -->

-
