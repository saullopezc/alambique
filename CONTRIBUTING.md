# Contribuir

Lo que aquí se acepta es **criterio y método**: una regla que faltaba, un mecanismo que
la hace cumplir, un defecto en uno que ya existe. Lo que nunca entra es un dato de un
tercero, por útil que parezca el ejemplo real. Antes de nada, lee [`AGENTS.md`](AGENTS.md):
es la puerta de entrada y dice cómo se valida un cambio.

## Antes de abrir una incidencia

Busca si ya existe. Si es un error, trae el **síntoma literal** (el mensaje tal cual, el
código de salida) y cómo reproducirlo; es la clave con la que otro lo encontrará. Si es
una propuesta, di qué problema resuelve y en qué regla o skill encaja. Una vulnerabilidad
o un dato filtrado no va aquí: va por [`SECURITY.md`](SECURITY.md).

## Antes de abrir un pull request

1. **Clasifica lo que añades** (R-01 del marco). Ni coordenadas, ni credenciales, ni
   nombres reales de clientes, ni cifras medidas en un sistema ajeno. Ante duda, no entra:
   se sintetiza hasta que no quede dato.
2. **Una regla, un dueño.** Si tocas una regla, cámbiala donde vive y no la repitas en
   otro sitio. Las doce reglas viven en `marco/NORMA.md`; la skill las cita.
3. **Agnóstico al harness.** Lo que solo funciona en uno va a `marco/adaptadores/` y se
   declara. Un hueco declarado vale más que un adaptador sin probar.
4. **Pasa la validación** de `AGENTS.md` con `env -i` y un HOME desechable: sintaxis,
   instaladores, `description` de la skill por debajo de 1024 caracteres, y el barrido
   del propio repositorio en cero.
5. **Prosa con tildes; identificadores, claves, rutas y opciones en ASCII.** El idioma del
   repositorio es el español.

## El commit

- Convencional (`feat:`, `fix:`, `docs:`), corto y en español: nombra qué cambia para
  quien lo usa, no cómo se implementó.
- Sin atribución a herramientas de IA, ni en el mensaje ni en el código: son
  instrumento, no autoría (R-11). Firma una persona.
- Un pull request, un asunto. Los cambios pequeños se revisan; los grandes se discuten
  antes en una incidencia.

## Lo que no se va a aceptar

- Más skills. Aquí va solo la del marco, la que dice dónde vive el dato; las de forma de
  trabajar, de ingeniería o de un dominio concreto van en su propio repositorio.
- Código de terceros sin licencia compatible. Con ella, el texto de su licencia viaja
  junto al código que la trae.
- Ejemplos con datos reales "anonimizados" a medias. Recortar un registro no lo
  desclasifica.

Al contribuir aceptas que tu aporte se publique bajo la licencia MIT del repositorio.

---

Saul López — github.com/saullopezc
