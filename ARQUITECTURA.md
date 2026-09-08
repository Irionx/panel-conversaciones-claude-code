# Arquitectura

Este documento no explica **cómo se usa** la app — para eso está `LEEME.md`.
Explica **por qué está armada así**, qué se decidió, qué se descartó y con qué
argumento. Si vas a agregar una funcionalidad, leelo antes: la mitad de las
decisiones de abajo existen para que agregar cosas no cueste cada vez más.

---

## 1. Qué es la app

Un lanzador y monitor de sesiones de Claude Code. Lista conversaciones de
cualquier proyecto, las reabre con `claude --resume <uuid>`, y muestra en vivo
el contexto de cada una, si está pensando, y la cuota de la cuenta.

La interfaz es una sola: **`gadget.ps1`**, un gadget de escritorio WPF siempre
a la vista. Hubo un panel en el navegador (`index.html`) que se retiró en el
paso 2; el porqué está en §7.

---

## 2. Estado actual, medido

```
CONVERSACIONES/
  setup.ps1  probar.ps1  datos.ps1        entradas de mantenimiento
  bin/     los comandos de terminal       <- LO UNICO en el PATH
  app/     gadget.ps1            547 l.   <- arranque y cableado, nada mas
           gadget/Tarjeta.ps1    491 l.   <- la mas grande, la que mas se toca
           gadget/Xaml.ps1       223 l.
           gadget/Confirmacion   217 l.
           gadget/Apariencia     143 l.
           gadget/Cuota.ps1      135 l.
           lib-conversaciones    835 l.   <- lo proximo: 4 responsabilidades
           lib/Datos/           ~700 l.   <- modulo + motor SQLite + 33 tests
           lib-setup.ps1        ~560 l.   <- las 7 piezas + desinstalacion
  skill/   el /save
  datos/   TUS datos, fuera de app/
  dev/     build.ps1, instalador.iss, hacer-icono.ps1
```

**Por qué `app/` y `datos/` están separados:** actualizar la app es reemplazar
`app/` sin acercarse a las conversaciones, y el paquete distribuible excluye los
datos sin tener que pensar (ver §9).

**Hecho en los cuatro pasos:** la capa de datos salió a un módulo con exports
explícitos, el motor pasó de `.js` a SQLite tocando sólo ese módulo y una línea,
`gadget.ps1` bajó de 1703 a 547 líneas, y el instalador tiene las cinco piezas.
Lo que sigue enredado es `lib-conversaciones.ps1`.

`lib-conversaciones.ps1` todavía mezcla, en un solo archivo y sin fronteras:

1. **Transcripts de Claude Code** — rutas, contexto, nombres de sesión, títulos
2. **Sesiones vivas** — estados, actividad
3. **Ventanas Win32** — lanzar, enfocar, seleccionar pestaña
4. **Formato** — `Format-Tokens`, `Format-Bytes`

Eran cinco responsabilidades; el acceso a datos ya salió. Las que quedan siguen
siendo visibles para todas, y **eso** es lo que se enreda cuando la app crece —
no el archivo de datos.

---

## 3. Las capas, y la regla que las sostiene

```
        gadget.ps1  /  scripts de linea de comandos       <- interfaz
                          |
        +-----------------+------------------+
        |                 |                  |
     Datos            Claude             Sistema           <- capas
   (§4, §5)      (transcripts,        (ventanas,
                  contexto)            procesos)
        |
   la base SQLite
```

**La regla:** *sólo la capa de Datos sabe dónde y cómo se guarda la
información.* Nadie más ve un path de archivo, un `ConvertFrom-Json` ni una
sentencia SQL.

Es lo que hizo que cambiar de motor (paso 2) tocara **un archivo** en vez de
ocho — medido, no prometido. Y no queda como buena intención: cada capa es un **módulo de PowerShell**
(`.psd1` + `.psm1`) con `FunctionsToExport` explícito, así los helpers internos
son *inalcanzables* desde la interfaz. Una carpeta con archivos sueltos se cruza
sin querer; un módulo con exports, no.

---

## 4. API de la capa de Datos

Este es el contrato. Lo de abajo puede cambiar de motor; esto no.

```powershell
# --- lectura ---
Get-Conversacion                  # todas, o -Id / -Sesion
Find-Conversacion   -Texto        # busca en titulo, proyecto, rama, notas, tags
Get-Nota            -Id
Get-Tag             -Id

# --- escritura ---
Add-Conversacion    -Id -Titulo -Cwd -Sesion [-Proyecto -Rama -Fecha
                                             -Notas -Tags -ContextoMax]
Set-Conversacion    -Id [-Titulo ...]      # actualiza solo lo que se le pasa
Remove-Conversacion -Id
Set-Nota            -Id -Texto
Set-Tag             -Id -Tags

# --- infraestructura: lo UNICO que sabe donde/como se guarda ---
Initialize-Datos    [-Ruta]                # crea el almacen si no existe, migra
Backup-Datos        -Destino
```

---

## 5. El modelo de datos

```
conversacion
  id           TEXT PK      slug unico (a-z 0-9 . _ -)
  titulo       TEXT NOT NULL
  cwd          TEXT NOT NULL
  sesion       TEXT NOT NULL   UUID de la sesion de Claude Code
  proyecto     TEXT
  rama         TEXT
  fecha        TEXT
  notas        TEXT            texto libre, es lo unico sensible del modelo
  contextoMax  INTEGER         pisa el tamano de ventana detectado; 0/ausente
                               = deducirlo. Lo escribe `guardar` y lo lee el
                               gadget para la barra de contexto

tag
  conversacion_id  TEXT     PK compuesta con tag
  tag              TEXT
```

**Sensibilidad.** El 99% del riesgo vive en `notas`: son apuntes de trabajo con
IPs de servidores, configuración de infraestructura, variables de entorno y
hallazgos de seguridad sin resolver. Medido: `notas` llega a 1823 caracteres, el
resto de los campos no pasa de 48. Por eso el almacén completo está en
`.gitignore` y nunca se versiona.

El transcript real (`~/.claude/projects/*.jsonl`) tiene todo el detalle sin
resumir y vive fuera de este proyecto. Las notas son un resumen derivado.

---

## 6. El plan

```
1. refactor/capa-de-datos    HECHO. Modulo Datos con el .js detras,
                             + escritura atomica y candado entre procesos.
2. feat/sqlite               HECHO. Swap del motor: toco Datos.psm1 y UNA
                             linea de lib-conversaciones.ps1, como estaba
                             previsto. Los 31 tests casi no cambiaron porque
                             estan escritos contra la API, no contra el
                             formato: eso fue el paso 1 pagando.
3. refactor/partir-gadget    HECHO. gadget.ps1 1703 -> 547 lineas, en cinco
                             piezas bajo gadget/. Hay un test de carga que
                             verifica el orden de dot-source y que todos los
                             x:Name que busca gadget.ps1 existan en el XAML.
4. feat/instalador           HECHO. El instalador tiene siete piezas. La del
                             volcado de la cuota ENVUELVE el statusline que
                             tengas en vez de reemplazarlo. La base no es una
                             pieza: la crea sola la capa de Datos.
5. refactor/layout-y-build   HECHO. bin/ app/ datos/ dev/ separados, y un
                             build.ps1 que arma el paquete. Ver §9.

Lo proximo, cuando haga falta:
6. partir lib-conversaciones.ps1 (835 lineas, 4 responsabilidades)
7. traer al gadget lo que solo tenia index.html: buscar texto libre y filtrar
   por tag (ver las notas ya lo cubre datos.ps1)
```

**El orden no es negociable, y esta es la razón:** si se cambia a SQLite antes
de tener la costura, el cambio de motor se mete en los 6 scripts y en el gadget
al mismo tiempo. Con la costura primero, el paso 2 es un archivo.

---

## 7. Decisiones tomadas, y las descartadas

### Almacén: SQLite, en `datos/conversaciones.db` al lado de la app

Verificado el 2026-09-08: Windows trae `winsqlite3.dll` en System32 (versión
3.51.1). Se maneja por P/Invoke directo desde PowerShell 5.1 — **cero
dependencias, cero instalación, ningún binario en el repo**.

Probado: round-trip de una nota de 1152 caracteres con acentos, ñ, comillas y
saltos de línea, idéntica byte por byte. Backslashes de rutas Windows guardados
tal cual, sin escapar.

Resuelve cuatro deudas concretas:

| antes | con SQLite |
|---|---|
| El gadget reescribía el archivo entero cada 30 s sin lock, y un `catch {}` se tragaba la falla en silencio | Locking real + `busy_timeout`. La carrera desaparece por elección de arquitectura |
| Backslashes escapados a mano, con una regex de rescate en la lectura | Se guardan tal cual |
| Buscar = leer todo y filtrar en memoria | `WHERE ... LIKE` |
| `tags` era un array dentro de un objeto | Tabla con relación |

**Al lado de la app y no en `%LOCALAPPDATA%`**: copiás la carpeta y te llevás
app + datos. Y para un compañero nuevo, el instalador crea la base vacía en vez
de que se descargue una con las notas de otro.

**No activar modo WAL.** El journal por defecto (`DELETE`) deja **un solo
archivo** en reposo, que es lo que hace que el backup sea copiar un archivo. WAL
agrega `-wal` y `-shm` al lado y rompe esa propiedad. Para copiar en caliente:
`VACUUM INTO 'respaldo.db'`, que da una copia consistente con la app corriendo.

### Descartado: ORM (Prisma, Entity Framework)

Prisma es Node/TypeScript: exigiría Node instalado, el engine binary (15-40 MB
por plataforma) y shell-out a un script de Node **por consulta**, en un gadget
que refresca cada 30 s. No es "demasiado", es otro runtime.

De las cuatro cosas que da un ORM, acá sirve una:

- **Migraciones de esquema** → sí, y hace falta. Se resuelve con
  `PRAGMA user_version` + una lista de migraciones, ~30 líneas. Es el idioma
  estándar de SQLite para esto, y es lo que evita que la base de un compañero
  quede en un esquema viejo.
- Mapear filas a objetos → `[pscustomobject]` ya lo hace.
- Query builder → son ~12 consultas en total.
- Tipos → PowerShell no tiene tipos; un ORM no puede dar lo que el lenguaje no
  tiene.

Si algún día se porta a C# (§8), ahí un micro-ORM tipo **Dapper** tiene sentido.
Entity Framework seguiría siendo desproporcionado para 4 tablas.

### Descartado: notas en archivos `.md`, una por conversación

Sería más lindo de leer y editar, pero `index.html` corre en `file://`, donde
Chrome bloquea `fetch()` de archivos locales — **es la razón por la que los
datos son `.js` y no `.json`**. Cargar N notas exigiría inyectar `<script>`
dinámicamente y rompería el buscador, que escanea todas las notas de una.

### Retirado: `index.html`

Borrado en el paso 2; queda en el historial de git. Un navegador no puede leer
un `.db` desde `file://` (misma razón que arriba), y el gadget ya cubre el uso
diario.

El protocolo `claudeconv://` **se queda**: lo sigue usando
`abrir-conversacion.ps1` desde la línea de comandos y desde cualquier enlace, y
desregistrarlo no le ahorra nada a nadie.

**Queda pendiente**, porque hoy sólo existe en el navegador y el gadget nunca lo
tuvo: **mostrar las notas, buscar texto libre y filtrar por tag.** No es una
pérdida silenciosa, es backlog.

### El statusline es una dependencia del instalador

La cuota real de la cuenta (`rate_limits`) llega **por el stdin del comando del
statusline** y no existe en ningún archivo. El instalador tiene que volcarla a
`~/.claude/statusline-ultimo.json`.

**Envolviendo, no reemplazando.** El parche que hay hoy reescribe el comando
concreto de esta máquina (claude-hud); a otra persona le rompería el suyo. Lo
correcto: leer el `statusLine.command` actual, dejarlo intacto y meterle el
volcado adelante. Idempotente, y si no hay statusline configurado, instalar sólo
el volcado.

---

## 8. El techo de PowerShell, y cuándo reevaluar

**La estética es de WPF, no de PowerShell.** El XAML se muda verbatim a C#, así
que la pregunta nunca fue "¿pierdo el diseño?" sino "¿quién ejecuta ese XAML?".

Techos reales, no teóricos:

- **El icono al pinear a la barra de tareas no se puede arreglar.** Se probó
  `SetCurrentProcessExplicitAppUserModelID` (funciona para la ventana en
  ejecución, verificado en píxeles) y se le escribió el AppUserModelID al `.lnk`
  por IPropertyStore. Explorer **regenera el pin** desde su propio modelo, que
  dice "la app de esa ventana" = `powershell.exe`. Con un `.exe` propio el
  problema no existe.
- 1703 líneas en un archivo, sin tipos ni tests.
- `XamlReader` en runtime: sin chequeo en compilación, sin binding a viewmodels.
  Todo es `FindName` + imperativo.
- PS 5.1 es de 2016 y está en mantenimiento.

**Se queda en PowerShell por ahora**, porque: no hay .NET SDK en la máquina (el
port arranca instalando el SDK y termina peleando con Defender por un exe sin
firma), la costura de §3 es *exactamente* el diseño que tendría la versión en C#
y no se tira nada, y hay fixes pendientes que un port congelaría.

**Cuándo reevaluar:** cuando otra persona la esté usando. Ahí se sabe de verdad
si el icono pineado y el "no requiere instalar nada" pesan más que los tipos.

**Ojo con una confusión fácil:** el instalador `.exe` de Inno Setup y portar a
C# **no son lo mismo**, aunque los dos terminen en un `.exe`. Inno produce el
*camión de mudanza*: un programa que copia archivos y se va; lo que queda
instalado siguen siendo estos `.ps1`. Portar a C# produce *la app*. Son ejes
distintos y se pueden combinar. Y sólo el segundo arregla el icono al pinear.

---

## 9. El paquete distribuible

```powershell
.\dev\build.ps1            zip
.\dev\build.ps1 -Exe       zip + instalador .exe (necesita Inno Setup 6)
```

**Los archivos que entran salen de `git ls-files`, no de una lista a mano.** Esa
es la decisión que importa: una lista a mano se desactualiza el día que alguien
agrega un archivo y se olvida de venir al build. El índice de git ya sabe
exactamente qué es código y qué son datos, porque es justo lo que encodea el
`.gitignore`. Sale gratis y no puede quedar viejo.

Consecuencia buena: `datos/conversaciones.db`, `conversaciones.js` y el `.lnk`
quedan afuera **solos**, porque están ignorados. Igual el build lo verifica al
final y aborta si encuentra algo personal adentro — un paquete que se manda a
otra máquina no es lugar para confiar.

El build **corre los tests primero y aborta si falla alguno**. Un paquete que no
pasó los tests no es un paquete.

**El `.iss` de Inno no reimplementa nada.** Copia los archivos e invoca
`setup.ps1 -Instalar -y`, que es el mismo instalador de siempre; al desinstalar
invoca `setup.ps1 -Desinstalar -y` **antes** de borrar los archivos, porque ese
script vive dentro de la carpeta que se va. Si algún día se cambia Inno por otra
cosa, no se reescribe lógica.

**`setup.ps1 -Desinstalar` nunca toca `datos/`.** Desinstalar la app no es tirar
las conversaciones: si el usuario las quiere borrar, las borra él. Y sólo
deshace lo que apunta a *esta* carpeta — si otro panel se quedó con el protocolo
o el skill, se los deja. Tampoco desarma el volcado del statusline: envuelve el
comando propio del usuario y desarmarlo a ciegas podría romperle el HUD.

### Descartado: `.exe` como método de distribución único

El `.exe` de Inno es cómodo pero **no es un requisito**: el zip alcanza y no
suma herramientas al medio. Inno hace falta sólo para *compilar*; el `.exe` que
sale no lo pide. Por eso `build.ps1` produce el zip siempre y el `.exe` sólo si
se lo pide con `-Exe` y encuentra Inno instalado.
