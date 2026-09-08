---
name: save
description: Guarda la conversación actual en el panel de CONVERSACIONES del Escritorio, o borra una existente. Usar cuando el usuario diga "guardá esta conversación", "agregala al panel", "anotá esta charla", "borrá la conversación X del panel", o invoque /save.
---

# Guardar la conversación en el panel

Toda la mecánica (UUID de la sesión, carpeta, rama, fecha, slug, escapado del
JSON, upsert) la resuelve `guardar.ps1`. Vos sólo aportás el criterio: **título,
notas y tags**.

## Guardar — camino rápido (el de siempre)

**Una sola llamada, sin escribir ningún archivo intermedio.** El título sale del
nombre de la sesión y las notas las ponés vos en el mismo comando:

```
cmd //c "%USERPROFILE%\Desktop\CONVERSACIONES\guardar.cmd" -Notas "Qué se decidió y qué quedó pendiente"
```

Se ejecuta **desde la carpeta del proyecto**. Si estás en otra, agregá
`-Cwd "C:\ruta\al\proyecto"`.

No verifiques nada después: el script ya relee el archivo y falla ruidosamente si
algo salió mal. Reportá en una línea el título y el id que imprimió, y listo.

### Cuándo hace falta más

- **Título explícito:** sólo si la sesión no tiene nombre de `/rename` *y* el
  usuario no pidió uno. Va como primer argumento posicional.
- **Tags:** `-Tags git,ci`. Opcional, no te esfuerces si no aportan.
- **Acentos en las notas:** si el texto lleva tildes o `ñ`, pasar el comando por
  la cadena bash→PowerShell puede romperlos. Ahí sí conviene escribir un `.ps1`
  temporal con Write, ponerle BOM UTF-8 y ejecutarlo. **Sólo en ese caso** — si
  las notas son ASCII, una llamada directa alcanza.

### Si el usuario quiere que sea instantáneo

Decile que puede saltearte del todo, escribiendo en Claude Code:

```
! %USERPROFILE%\Desktop\CONVERSACIONES\guardar.cmd
```

Guarda con el nombre de `/rename`, sin notas y sin IA en el medio. `/save` sólo
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
& "$env:USERPROFILE\Desktop\CONVERSACIONES\guardar.ps1" -Listar
```

Lista los UUID de esa carpeta con fecha y % de contexto, el más reciente primero.
Úsalo cuando el usuario quiera guardar una conversación que **no** es la actual:
mostrale la lista, que elija, y pasá `-Sesion <uuid>`.

## Borrar

Confirmá el id exacto contra la lista antes de tocar nada. Deja respaldo en
`conversaciones.js.bak`.

```powershell
cd "$env:USERPROFILE\Desktop\CONVERSACIONES"
. .\lib-conversaciones.ps1
Remove-Conversacion -Carpeta (Get-Location).Path -Id '<el-id>'
```

Si el usuario nombra la conversación por el título, decile qué id vas a borrar
antes de hacerlo.

## Una sola trampa

Si alguna vez editás `conversaciones.js` a mano, usá **Edit o Write, nunca
heredoc**: en este entorno los heredoc y `printf` de Bash colapsan `\\` en `\` y
rompen las rutas de Windows. Lo normal igual es no tocarlo: usá el script.
