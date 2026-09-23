---
name: save
description: Guarda la conversación actual en Hilos de Claudio, el panel de conversaciones, o la actualiza. Usar cuando el usuario diga "guardá esta conversación", "agregala al panel", "anotá esta charla", o invoque /save.
---

# Guardar la conversación en el panel (Linux)

Toda la mecánica —el UUID de la sesión, la carpeta, la rama, la fecha, el slug y
el upsert— la resuelve el comando. Vos aportás el criterio: **recap, notas y
título**.

```bash
conversaciones guardar -- --recap "Estamos con X. Falta Y." --notas "Qué se decidió y qué quedó pendiente"
```

Se ejecuta **desde la carpeta del proyecto**, que es donde Claude Code tiene su
sesión: de ahí sale a qué conversación corresponde.

Con un título explícito, va primero:

```bash
conversaciones guardar "Migración a Postgres" --recap "..."
```

## El recap: lo único que se ve en la tarjeta

- **Dos o tres líneas.** La tarjeta corta ahí; más es desperdicio.
- **Primera persona del plural, en presente:** "Estamos armando X…", no "Se
  implementó X". Es un estado, no un changelog.
- **Qué se está haciendo y qué falta.** Lo que falta es lo que más sirve cuando
  se vuelve a la conversación días después.
- **Nada sensible:** sin IPs, tokens, contraseñas ni nombres de servidores. El
  recap se ve en pantalla y sale en cualquier captura. Eso va en las notas, que
  el panel no muestra.

Se reescribe en cada guardado. Si guardás sin `--recap`, el anterior se conserva.

## Una sola entrada por sesión

El upsert es **por sesión**, no por título: volver a guardar la misma
conversación la actualiza, nunca la duplica. Si la renombraste con `/rename`, el
título nuevo se toma solo.

## Qué NO hace todavía

Esta es la versión Linux del panel. Comparado con la de Windows, el comando aún
no tiene tags ni borrado; para eso, por ahora, se edita desde la otra. La base es
la misma, así que lo guardado acá se ve allá y al revés.

## Ver lo guardado

```bash
conversaciones --lista     # lo que hay, con su contexto
conversaciones             # abre el panel
```
