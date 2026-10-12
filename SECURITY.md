# Seguridad

Este repositorio existe para evitar fugas de datos ajenos al trabajar con agentes de
IA. Que algo se le escape es, por tanto, un fallo de seguridad y se trata como tal.

## Qué cuenta como vulnerabilidad aquí

- **Un mecanismo que deja pasar lo que debía parar**: la puerta de commit, el barrido, un
  guard o las reglas de lectura admiten algo que su cabecera dice que bloquean (una IP, una
  credencial, un fichero de la capa local, una orden destructiva sin confirmar).
- **Un dato de un tercero dentro del repositorio**: una coordenada, una credencial, un
  nombre real de cliente o una salida de un sistema ajeno, en cualquier fichero o commit.
- **Un instalador que escribe fuera de lo declarado**, o que pisa configuración de la
  persona sin dejar copia previa.

Lo que un mecanismo **declara no ver** —en su cabecera y en «Límites declarados» del
`README.md`— es un límite conocido, no una vulnerabilidad: los patrones cubren las formas
más corrientes y cada puesto los ajusta. Una forma nueva que convenga cubrir va como
incidencia o como propuesta.

Un error de redacción, una incoherencia entre documentos o una guía desactualizada tampoco
es una vulnerabilidad: va como incidencia normal.

## Cómo reportarla

Por el canal privado del repositorio en GitHub: pestaña **Security**, "Report a
vulnerability". No abras una incidencia pública con el detalle. Si la pestaña no ofrece
ese botón, abre una incidencia que diga solo que quieres reportar una vulnerabilidad, sin
el detalle, y se te dará un canal privado.

Si lo que has encontrado es un **dato filtrado**, no lo pegues en el reporte: indica el
fichero, la línea y el commit donde está. Repetirlo lo propaga.

Si lo que falla es un mecanismo, el reporte más útil trae el síntoma literal y cómo
reproducirlo: la orden o el fichero que debió pararse, qué hizo el mecanismo y qué esperabas.

## Qué puedes esperar

- Acuse de recibo en siete días.
- Un dato filtrado se retira del historial, no solo del árbol. Reescribir `main` no basta:
  el commit retirado sigue accesible por su identificador hasta que la plataforma lo
  purga, así que se pide esa purga o se publica el repositorio de nuevo. Se avisará de
  ello en el repositorio.
- Un mecanismo que falló se corrige y, por la regla R-12 del marco, el fallo se convierte
  en control: la prueba que lo detecta queda en el repositorio, como control positivo en
  `CLASIFICACION.md` o como caso, con su control, en el banco de `pruebas/`.
- Mención en el arreglo, si la quieres.

## Alcance

Solo este repositorio y lo que sus instaladores escriben. Los harness (Claude Code, Codex
CLI, Gemini CLI y los demás) tienen su propio canal: un fallo en cómo un harness ejecuta
un hook o aplica una regla de lectura se reporta allí.

Solo se mantiene `main`. No hay versiones anteriores con soporte.

---

Saul López — github.com/saullopezc
