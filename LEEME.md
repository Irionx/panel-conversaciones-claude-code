# Conversaciones · Claude Code

Retomá cualquier sesión de Claude Code en su carpeta, de un click, desde un
**gadget de escritorio** translúcido que además te muestra en vivo cuánto
contexto le queda a cada charla y cuál está trabajando.

---

## Puesta en marcha

**Abrí `Gadget de conversaciones.lnk` y listo.** El gadget verifica su propia
instalación cada vez que arranca. Si falta algo, te lo ofrece en un diálogo; si
está todo, no dice nada.

Son cinco piezas, todas en tu usuario (`HKCU` y PATH de usuario). Ninguna pide admin:

| Pieza | Para qué |
|---|---|
| protocolo `claudeconv://` | que los enlaces `claudeconv://` abran la conversación |
| esta carpeta en el PATH | que existan los comandos `guardar` y `borrar-conversacion` |
| junction del skill | que exista `/save` dentro de Claude Code |
| shims para bash | que esos comandos anden desde el prompt `!` de Claude Code |
| volcado de la cuota | que el gadget sepa cuánta cuota te queda (la escribe tu statusline) |

No hay ningún marcador de "ya instalado": se **mide el estado real** en cada
arranque. Por eso podés **mover la carpeta** —u otra máquina, otro usuario— y en
el próximo arranque se re-apunta sola.

Si decís *Cancelar*, no vuelve a preguntar mientras falte exactamente lo mismo
(queda anotado en `setup-omitido.json`). Si aparece algo nuevo roto, vuelve a
ofrecer.

Para verlo o forzarlo desde una terminal:

```powershell
.\setup.ps1                 # muestra el estado de las cinco piezas
.\setup.ps1 -Instalar       # repara lo que falte
```

> **El PATH sólo lo ven los procesos que arrancan después.** Si acabás de
> instalar, abrí una terminal nueva —y reiniciá Claude Code— para tener los
> comandos. Los procesos ya abiertos siguen con el PATH viejo, sin excepción.

---

## Qué hace cada archivo

### Los que usás todos los días

| Archivo | Para qué sirve |
|---|---|
| **`datos/conversaciones.db`** | **Los datos.** Una base SQLite con la lista de conversaciones. Si la borrás, perdés la lista (pero no las sesiones). El backup es copiar ese archivo. |
| **`guardar.cmd`** | **La forma rápida de guardar.** Atajo de `guardar.ps1`: `guardar "Título"`. |
| **`guardar.ps1`** | Guarda una conversación con un comando. Deduce solo el UUID, la carpeta, la rama, la fecha y el slug. |
| **`Gadget de conversaciones.lnk`** | Abre el gadget de escritorio. Es sólo un acceso directo: si lo borrás, ejecutás `gadget.ps1` a mano. |
| **`borrar-conversacion.cmd`** | **Borra de verdad**, no sólo quita del panel: se lleva el transcript. `borrar-conversacion <id>`, con `-Listar`, `-DryRun` y `-y`. |
| **`borrar.ps1`** | El script detrás. Irreversible: sin el `.jsonl` no hay `--resume`, y `Remove-Item` no manda nada a la papelera. |
| **`datos.ps1`** | **Ver lo que hay guardado.** `.\datos.ps1` lista todo, `.\datos.ps1 <id>` muestra una entera **con sus notas** (el gadget no las muestra), `-Buscar texto` busca, `-Respaldar` copia la base con la fecha. |
| **`cerrar-gadget.cmd`** | **Cierra el gadget aunque esté trabado.** Existe porque el gadget no sale en la barra de tareas ni en Alt+Tab, y en el Administrador de tareas es un `powershell.exe` más. `-Listar` muestra sin cerrar. Es cierre forzado: no guarda la posición. |
| **`guardar`** y **`borrar-conversacion`** *(sin extensión)* | Los shims para bash. **Los genera `setup`, no los edites a mano.** Existen porque Git Bash no resuelve `.cmd` desde el PATH: sólo el nombre exacto y `.exe`. |

### El motor

| Archivo | Para qué sirve |
|---|---|
| **`gadget.ps1`** | El arranque y el cableado del gadget: crea la ventana, engancha los botones y los timers. Si lo borrás, no hay gadget. |
| **`gadget/`** | Las piezas de la interfaz: `Xaml.ps1` (la ventana), `Apariencia.ps1` (colores y modo bloqueado), `Tarjeta.ps1` (una conversación), `Confirmacion.ps1` y `Cuota.ps1`. |
| **`lib-conversaciones.ps1`** | Calcula el contexto, lee los transcripts y lanza las terminales. Lo usan el gadget y el protocolo. Si lo borrás, se rompen los dos. |
| **`lib/Datos/`** | **El corazón de los datos.** La única capa que sabe dónde y cómo se guardan las conversaciones. Ver `ARQUITECTURA.md`. |
| **`abrir-conversacion.ps1`** | Lo que se ejecuta cuando hacés click en un link `claudeconv://`. Valida el id y delega en la librería. |
| **`lib-setup.ps1`** | Verifica y repara las cinco piezas de la instalación. Lo usan `setup.ps1` y el gadget al arrancar. Genera los shims de bash. |
| **`probar.ps1`** | **Corre todos los tests.** Lo primero después de tocar algo, y lo primero al instalar en una máquina nueva. No toca tus datos. |
| **`setup.ps1`** | El CLI de la instalación: `.\setup.ps1` para ver el estado, `-Instalar` para reparar. **No tiene wrapper `.cmd` a propósito**: `setup` es un nombre demasiado genérico para dejarlo suelto en el PATH. |

### El protocolo

| Archivo | Para qué sirve |
|---|---|
| **`instalar-protocolo.reg`** | Alternativa manual, de antes del setup. **Tiene la ruta hardcodeada**: si movés la carpeta queda apuntando al lugar viejo. El setup del gadget escribe la misma clave con la ruta real, así que normalmente no hace falta tocarlo. |
| **`desinstalar-protocolo.reg`** | Saca `claudeconv://` del registro. Para revertir. Ojo: el gadget te va a ofrecer reinstalarlo en el próximo arranque. |

### El comando `/save`

| Archivo | Para qué sirve |
|---|---|
| **`skill\SKILL.md`** | Las instrucciones del comando `/save` de Claude Code. **Este archivo es el original**: `~\.claude\skills\save` es una *junction* que apunta acá. Si borrás la carpeta `skill`, `/save` deja de existir. |

### Se generan solos

| Archivo | Para qué sirve |
|---|---|
| `gadget-posicion.json` | Dónde dejaste el gadget y con qué transparencia. Borralo para resetear la posición. |
| `datos/conversaciones.db.bak` | Respaldo automático que se hace justo antes de cada borrado. Es tu red si borrás algo sin querer — **pero sólo de la lista**, no del transcript. |
| `setup-omitido.json` | Qué le dijiste *Cancelar* al setup, para no volver a preguntar por lo mismo. Borralo para que vuelva a ofrecer. |

---

## Agregar una conversación

**Con el script (lo más rápido).** Parado en la carpeta del proyecto:

```
guardar "Nivelar dev con test"
guardar "Refactor del toolbar" -Tags ui,scss -Notas "Quedó pendiente el responsive"
guardar -Listar
```

Deduce solo el UUID de la sesión, la carpeta, la rama de git, el proyecto, la
fecha y el slug. Vos ponés el título; las notas y los tags son opcionales.

**Una sesión, una entrada.** Volver a guardar la misma conversación la
**actualiza**, nunca la duplica — le pongas el título que le pongas. Dos entradas
del mismo UUID reabrirían la misma charla: son duplicados disfrazados.

Si el título cambia, el script te avisa qué nombre tenía antes.

### El nombre lo manda `/rename`

Si renombrás la sesión dentro de Claude Code:

```
/rename charla sencilla
```

**el panel pasa a mostrar ese nombre y se actualiza solo**, sin que tengas que
volver a guardar nada. El `titulo` del archivo queda como respaldo para las
sesiones que todavía no renombraste.

Por eso conviene renombrar y no pelear con el título: es un solo nombre, el mismo
en Claude Code y en el panel, siempre sincronizado.

Si estás en otra carpeta: `-Cwd "C:\ruta\al\proyecto"`.
Para guardar una sesión vieja: `-Listar` y después `-Sesion <uuid>`.

La carpeta **ya está en tu PATH de usuario**, así que `guardar` funciona desde
cualquier terminal. Para sacarlo algún día:

```powershell
$p = [Environment]::GetEnvironmentVariable('Path','User') -split ';' |
     Where-Object { $_ -notlike '*Desktop\CONVERSACIONES*' }
[Environment]::SetEnvironmentVariable('Path', ($p -join ';'), 'User')
```

> Nunca uses `setx PATH "%PATH%;..."` para esto: `%PATH%` ya viene con el PATH del
> sistema mezclado, así que te duplica todas esas entradas dentro del de usuario
> (y `setx` además trunca a 1024 caracteres). La API de .NET con scope `User`
> escribe sólo el tuyo.

### Qué usar y cuándo

| Querés… | Usá | Tarda |
|---|---|---|
| Guardar y seguir | `! guardar` en Claude Code | ~1 s, sin IA |
| Guardar con notas escritas por Claude | `/save` | lo que tarde el modelo |
| Guardar desde una terminal cualquiera | `guardar -Notas "..."` | ~1 s |

`/save` **no puede ser instantáneo**: un skill son instrucciones para el modelo,
así que invocarlo es invocarlo a él. El script tarda 1 segundo; el resto es el
modelo pensando. Si no necesitás que escriba las notas, salteátelo.

**Con `/save`.** En Claude Code, dentro del proyecto. Hace lo mismo, pero además
te propone el título y las notas según de qué se trató la charla. Y sabe borrar:
*"borrá la conversación X del panel"*.

**A mano.** Ya no hace falta editar un archivo: es una llamada a la capa de
datos.

```powershell
Import-Module .\lib\Datos\Datos.psd1
Initialize-Datos -Ruta .\datos\conversaciones.db
Add-Conversacion -Id 'slug-unico' -Titulo 'Lo que quieras leer en la tarjeta' `
    -Cwd 'C:\ruta\al\proyecto' `
    -Sesion '8106d6bc-ff38-4601-a500-e6778895fa14' `
    -Proyecto 'DespachoViewer' -Rama 'fix/1168' -Fecha '2026-08-31' `
    -Tags 'git', 'ci' -Notas 'Para acordarte de qué se trataba.'
```

Obligatorios: `-Id`, `-Titulo`, `-Cwd`, `-Sesion`. Las rutas van con **una sola
barra**: se guardan tal cual, sin escapar nada.

### Sacar el UUID de una sesión

- En la carpeta del proyecto: `claude --resume` y mirás la lista, **o**
- el `.jsonl` más reciente en `C:\Users\skozak\.claude\projects\<carpeta-codificada>\`
  (el nombre del archivo *es* el UUID).

---

## Borrar una conversación

Ninguna de las dos formas toca la sesión de Claude Code: sólo sacan la entrada
del panel. Y siempre queda `datos/conversaciones.db.bak`.

- **En el gadget:** el **✕** de la tarjeta. Pide confirmación y **borra de verdad**.
- **En el panel HTML:** el botón **Quitar**. Pide confirmación y te entrega el
  archivo ya actualizado para pegar.

¿Por qué la diferencia? Una página abierta con `file://` **no tiene permiso para
escribir en disco**. PowerShell sí.

---

## El gadget de escritorio

- **Arrastralo** del encabezado. Recuerda dónde lo dejaste.
- **◐** cicla la transparencia: opaco → medio → fantasma.
- **↻** refresca a mano (igual se refresca solo cada 30 s).
- **Click en la tarjeta** abre la conversación. **✕** la quita.

Los gadgets nativos de Windows murieron en Windows 8. Esto es una ventana **WPF**
hosteada por PowerShell: transparencia real, cero instalación.

### El % de contexto

**Tokens usados:** suma `input + cache_creation + cache_read + output` del último
mensaje del assistant en el `.jsonl`, ignorando los turnos de subagentes.

**Tamaño de la ventana:** el transcript *no* lo guarda. Se resuelve por orden de
confianza:

1. `contextoMax` si lo fijaste en la entrada
2. **el `context_window_size` real** que Claude Code le pasa al statusline y el
   plugin `claude-hud` cachea en `~\.claude\plugins\claude-hud\context-cache\`
   (indexado por el sha256 de la ruta del transcript) ← lo normal
3. la ventana más frecuente entre tus otras sesiones
4. último recurso: el tier más chico que entre

Verde <60 % · ámbar 60-85 % · rojo >85 %.

> **Por qué importa el paso 2.** Antes se adivinaba el límite y una conversación
> de 171k tokens se mostraba **85 % en rojo** asumiendo una ventana de 200k,
> cuando en realidad era **17 %** de 1M. 68 puntos de error. Verificado contra el
> statusline: ahora da 34,2 % donde Claude Code muestra 34 %.

Si desinstalás `claude-hud`, se cae al paso 3 y sigue andando bien mientras tus
sesiones tengan todas la misma ventana.

---

## Por qué está armado así

- **SQLite y no un archivo de texto:** el backup es copiar un archivo, hay
  locking de verdad (antes el gadget y `guardar` se pisaban en silencio) y las
  rutas de Windows se guardan sin escapar. Sale gratis: usa el `winsqlite3.dll`
  que ya trae Windows, sin instalar nada. Ver `ARQUITECTURA.md`.
- **Protocolo custom y no un link directo:** ningún navegador deja que una página
  ejecute un programa local. Un protocolo registrado es la vía soportada.
- **Los `.ps1` van con BOM UTF-8:** PowerShell 5.1 los lee como ANSI si no lo
  tienen, y los acentos y el `·` salen rotos.

## Seguridad

La URL `claudeconv://` **sólo transporta un `id`** validado contra
`^[A-Za-z0-9._-]{1,64}$`. La carpeta, el UUID y el comando salen de
`datos/conversaciones.db`, que es local y tuya. El comando está fijo en la librería:
`claude --resume <uuid>`. Una página web no puede inyectar rutas ni comandos.

Verificado: `../../windows/system32` y `x"; calc.exe ;"` como `id` son rechazados
antes de tocar nada.

Para revertir todo: `desinstalar-protocolo.reg` y borrar la carpeta.

## Diagnóstico

Si algo falla, corré esto y mirá qué dice:

```powershell
cd "$env:USERPROFILE\Desktop\CONVERSACIONES"
.\abrir-conversacion.ps1 -Url "claudeconv://abrir?id=dev-test-nivelacion" -DryRun
```

`-DryRun` muestra el `exe`, los `args` y el % de contexto sin abrir nada.

Para ver la lista tal como la leen los scripts:

```powershell
. .\lib-conversaciones.ps1
Get-Conversaciones -Carpeta (Get-Location).Path | Select-Object id, titulo, cwd
```
