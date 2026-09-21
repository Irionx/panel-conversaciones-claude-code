---
name: save
description: Guarda la conversación actual en el panel de conversaciones de Claude Code, o borra una existente. Usar cuando el usuario diga "guardá esta conversación", "agregala al panel", "anotá esta charla", "borrá la conversación X del panel", o invoque /save.
---

# Guardar la conversación en el panel

Toda la mecánica (UUID de la sesión, carpeta, rama, fecha, slug, upsert) la
resuelve `guardar.ps1`. Vos sólo aportás el criterio: **recap, notas, título y tags**.

## Guardar — camino rápido (el de siempre)

**Una sola llamada, sin escribir ningún archivo intermedio.** El título sale del
nombre de la sesión y las notas las ponés vos en el mismo comando:

```
guardar -Recap "Estamos con X. Falta Y." -Notas "Qué se decidió y qué quedó pendiente"
```

No lleva ruta a propósito: `guardar` sale del PATH, y el instalador lo apunta al
`bin\` de donde se instaló el proyecto — Escritorio, Documentos o donde sea. Si
responde "command not found", la instalación es nueva y esta terminal quedó con
el PATH viejo: abrí otra.

### El recap: lo que se ve en la tarjeta

Es lo **único** que la persona lee en el panel sin abrir nada, así que va
**siempre** que guardes. Reglas:

- **2 o 3 líneas.** La tarjeta corta a las tres; más es desperdicio.
- **Primera persona del plural, en presente:** "Estamos armando X…", no "Se
  implementó X". Tiene que leerse como un estado, no como un changelog.
- **Qué se está haciendo y qué falta.** Lo que falta es lo que más sirve al
  volver a la conversación días después.
- **Nada sensible**: sin IPs, tokens, contraseñas ni nombres de servidores. El
  recap se ve en pantalla y sale en cualquier captura; lo sensible va en las
  notas, que no se muestran.

Se **reescribe** en cada `/save`: es un estado, no un historial. Si guardás sin
`-Recap`, el anterior se conserva.

Se ejecuta **desde la carpeta del proyecto**. Si estás en otra, agregá
`-Cwd "C:\ruta\al\proyecto"`.

No verifiques nada después: el script ya relee el archivo y falla ruidosamente si
algo salió mal. Reportá en una línea el título y el id que imprimió, y listo.

### Cuándo hace falta más

- **Título explícito:** sólo si la sesión no tiene nombre de `/rename` *y* el
  usuario no pidió uno. Va como primer argumento posicional.
- **Tags:** `-Tags git,ci`. Opcional, no te esfuerces si no aportan.
- **Acentos en el recap o las notas:** si el texto lleva tildes o `ñ`, pasar el comando por
  la cadena bash→PowerShell puede romperlos. Ahí sí conviene escribir un `.ps1`
  temporal con Write, ponerle BOM UTF-8 y ejecutarlo. **Sólo en ese caso** — si
  las notas son ASCII, una llamada directa alcanza.

### Si el usuario quiere que sea instantáneo

Decile que puede saltearte del todo, escribiendo en Claude Code:

```
! guardar
```

Guarda con el nombre de `/rename`, sin recap, sin notas y sin IA en el medio. `/save` sólo
vale la pena cuando quiere que las notas las escriba yo.

**Es upsert por SESIÓN: una sesión, una entrada.** Volver a guardar la misma
conversación la actualiza, nunca la duplica — no importa qué título le pongas.
Dos entradas del mismo UUID reabrirían exactamente la misma charla, así que
serían duplicados disfrazados.

**El nombre que se ve es el de `/rename`.** Si el usuario renombró la sesión en
Claude Code, el panel muestra ese nombre y se actualiza solo en cada refresco;
el título guardado queda de respaldo para las sesiones sin renombrar.

Por eso, si la conversación **ya tiene nombre real**, no hace falta que inventes
un título: llamá al script sin el primer argumento y toma el nombre de la sesión.
Y si no lo tiene, sugerile al usuario que use `/rename` — es la forma de que el
nombre quede bien en todos lados de una sola vez.

## Ver qué sesiones hay

```powershell
guardar -Listar
```

Lista los UUID de esa carpeta con fecha y % de contexto, el más reciente primero.
Úsalo cuando el usuario quiera guardar una conversación que **no** es la actual:
mostrale la lista, que elija, y pasá `-Sesion <uuid>`.

## Borrar

Hay **dos borrados distintos** y confundirlos es grave. Este skill hace el
primero:

| | Qué se lleva | Reversible |
|---|---|---|
| **Quitar del panel** (esto) | sólo la entrada | sí: el transcript sigue en disco |
| `borrar-conversacion <id>` | la entrada **y el transcript** | **no**: sin el `.jsonl` no hay `--resume` |

Confirmá el id exacto contra la lista antes de tocar nada:

```powershell
$raiz = Split-Path (Split-Path (Get-Command guardar.cmd).Source) -Parent
. "$raiz\app\lib-conversaciones.ps1"
Remove-Conversacion -Id '<el-id>'
```

**Devuelve `$true` si lo borró y `$false` si ese id no existía** — no tira error.
Si te da `$false`, es que erraste el id: no le digas al usuario que borraste algo
que sigue ahí.

Antes de borrar se respalda sola la base en `datos\conversaciones.db.bak`, así
que un borrado equivocado se puede deshacer copiando ese archivo encima de
`datos\conversaciones.db`.

Si el usuario nombra la conversación por el título, decile qué id vas a borrar
antes de hacerlo.

## Una sola trampa

Los datos viven en una base SQLite (`datos/conversaciones.db`), no en un archivo
de texto: **no se edita a mano.** Se usa el script, o la capa de datos
(`lib/Datos`) si hace falta algo puntual. Ahí las rutas de Windows se guardan
tal cual, sin escapar nada.
