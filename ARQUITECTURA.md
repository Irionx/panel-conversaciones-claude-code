# Arquitectura

Este documento no explica **cómo se usa** la app — para eso está `LEEME.md`.
Explica **por qué está armada así**, qué se decidió, qué se descartó y con qué
argumento. Si vas a agregar una funcionalidad, leelo antes: la mitad de las
decisiones de abajo existen para que agregar cosas no cueste cada vez más.

---

## 1. Qué es la app

**Hilos de Claudio**: un lanzador y monitor de sesiones de Claude Code. Lista conversaciones de
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
  app/     gadget.ps1            582 l.   <- arranque y cableado, nada mas
           gadget/Tarjeta.ps1    712 l.   <- la mas grande, la que mas se toca
           gadget/Etiquetas.ps1  446 l.   <- las etiquetas y su popup
           gadget/Xaml.ps1       294 l.
           gadget/Apariencia     272 l.   <- bloqueado, colapsado y animaciones
           gadget/Ayuda.ps1      268 l.   <- la ventana "Como funciona"
           gadget/Cuentas.ps1    274 l.   <- el selector de cuentas
           gadget/Confirmacion   217 l.
           gadget/Orden.ps1      200 l.   <- arrastrar para reordenar
           gadget/Cuota.ps1      137 l.
           gadget/GitHub.ps1     238 l.   <- la cuenta de gh, el selector y el login
           gadget/Cuenta.ps1     104 l.   <- el chip de la cuenta
           gadget/Instalacion     89 l.   <- "falta una pieza", al arrancar
           gadget/Posicion.ps1    57 l.   <- donde quedo la ventana, entre sesiones
           lib-conversaciones    922 l.   <- lo proximo: 4 responsabilidades
           lib/Datos/           ~790 l.   <- modulo + motor SQLite (43 tests aparte)
           lib-setup.ps1         896 l.   <- las 8 piezas + desinstalacion
           lib-cuentas.ps1       344 l.   <- cambiar de cuenta (27 tests aparte)
           lanzador.cs            85 l.   <- Conversaciones.exe: abre sin consola
           gadget.ico                     <- la marca; de aca sale el logo del header
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
Get-Conversacion  [-Estado]       # todas, o -Id / -Sesion
                                  # -Estado activas|archivadas|todas (default
                                  # todas). -Id y -Sesion NUNCA filtran: ver el
                                  # comentario del parametro
Find-Conversacion   -Texto        # busca en titulo, proyecto, rama, notas, tags
Get-Nota            -Id
Get-Tag             -Id
Get-Etiqueta                      # el catalogo: id, nombre, color, usos

# --- escritura ---
Add-Conversacion    -Id -Titulo -Cwd -Sesion [-Proyecto -Rama -Fecha
                                             -Notas -Tags -ContextoMax]
Set-Conversacion    -Id [-Titulo ...]      # actualiza solo lo que se le pasa
Remove-Conversacion -Id
Set-Nota            -Id -Texto
Set-Tag             -Id -Tags
Set-OrdenConversacion -Ids        # los ids EN EL ORDEN QUE SE QUIERE, en una
                                  # sola transaccion (lo usa el arrastre)
Set-ArchivadoConversacion -Id -Archivada   # esconder / recuperar. No borra
Add-Etiqueta        -Nombre -Color         # devuelve el id. Color = clave de la paleta
Set-Etiqueta        -Id [-Nombre -Color]
Remove-Etiqueta     -Id                    # la saca de todas; respalda antes
Set-EtiquetaConversacion -Id -Etiquetas    # reemplazo completo, en una transaccion
# Get-Conversacion trae .etiquetas (id, nombre, color) en cada objeto
# Add- y Set-Conversacion aceptan -Recap (el texto corto de la tarjeta)

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
  orden        INTEGER         posicion en el panel, 1..N. Es un dato del
                               USUARIO: lo escribe arrastrando tarjetas. Se
                               agrego en la migracion v2 con backfill desde
                               rowid, asi migrar no le movio el panel a nadie.
                               Una fila sin orden cae al final (COALESCE con
                               rowid), no al principio
  archivada    INTEGER         0/1, NOT NULL DEFAULT 0 (migracion v3).
                               Archivar es ESCONDER del panel: la fila queda
                               entera. El filtro NO esta en el default de
                               Get-Conversacion a proposito, porque el chequeo
                               de duplicados de guardar.ps1 tiene que seguir
                               viendo las archivadas o crearia una segunda
                               entrada para la misma sesion
  recap        TEXT            2-3 lineas que escribe /save (migracion v4). Se
                               MUESTRA en la tarjeta, asi que no lleva nada
                               sensible: eso va en notas, que no se muestran

tag
  conversacion_id  TEXT     PK compuesta con tag
  tag              TEXT

etiqueta                    migracion v5. Las crea la persona y SE VEN en la
  id      INTEGER PK        tarjeta; los tags los escribe /save para buscar y
  nombre  TEXT UNIQUE       no se muestran. Son cosas distintas. El nombre no
                            distingue mayusculas (COLLATE NOCASE)
  color   TEXT              la CLAVE de la paleta (verde, azul...), no el hex:
                            la paleta vive en gadget/Etiquetas.ps1 y se retoca
                            sin migrar

conversacion_etiqueta
  conversacion_id  TEXT     PK compuesta
  etiqueta_id      INTEGER
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

### Cambiar de cuenta: intercambiar archivos, no perfiles

Medido el 2026-09-14 sobre `claude.exe` 2.1.270. La sesión de Claude Code son
**dos archivos separados**: el par de tokens en `~/.claude/.credentials.json`
(501 bytes, un objeto `claudeAiOauth`) y la identidad —mail, organización,
plan— adentro de `~/.claude.json`, bajo `oauthAccount`. En Windows **no** está
en el Credential Manager: `cmdkey /list` no devuelve nada de Claude.

Cambiar de cuenta es intercambiar las dos cosas a la vez. Con una sola, o el
panel muestra el mail que no es, o Claude entra con la cuenta anterior.

**Descartado: un perfil por cuenta con `CLAUDE_CONFIG_DIR`.** La variable
funciona —verificado: apuntándola a una carpeta vacía, `claude -p` contesta
"Not logged in" y se arma ahí adentro su propio `.claude.json`, `projects/` y
`sessions/`— y es lo único que permite **dos cuentas a la vez**. Pero un perfil
nuevo arranca virgen: sin agentes, sin skills, sin los ~107 MB de plugins, sin
statusline, y con el panel ciego porque lee `~/.claude/projects`. Para el caso
real —saltar entre cuentas, no usarlas en paralelo— el costo no se paga.

**El archivo archivado guarda TEXTO CRUDO, no objetos.** Cada cuenta conocida
queda en `~/.claude/cuentas/<mail>.json` con el contenido literal de la
credencial y del bloque de identidad. Al restaurar se escriben tal cual: un
`ConvertTo-Json` de por medio podría cambiar una coma, y acá una coma es una
sesión rota.

**A `.claude.json` se le hace cirugía, no se lo reescribe.** Tiene 90 KB con el
estado de todos los proyectos, y en PowerShell 5.1 un round-trip por
`ConvertFrom-Json`/`ConvertTo-Json` colapsa arrays vacíos. Se ubica el tramo
exacto de `oauthAccount` y de `userID` contando llaves —respetando las que
viven adentro de strings— y se reemplaza sólo eso. Si la clave apareciera más
de una vez, **no se toca nada**: es la misma regla que el volcado del
statusline. Verificado contra el archivo real: el round-trip lo dejó idéntico
byte a byte, los 90.217.

**La cuenta viva se re-archiva antes de cada cambio.** El refresh token dura
~30 días pero **rota**: si guardáramos una foto y no la actualizáramos, al
volver a esa cuenta el token ya estaría vencido y habría que loguearse igual —
justo lo que esto viene a evitar.

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
  problema no existe. `Conversaciones.exe` (§9) **no** cuenta: es un lanzador
  que arranca PowerShell y termina, y la ventana sigue siendo de `powershell.exe`.
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

El build **corre los tests adentro del paquete ya armado**, no en el árbol de
trabajo, y aborta si falla alguno. Esa distinción no es de estilo: el paquete
lleva sólo lo versionado, así que un archivo sin trackear está presente en el
árbol —todo verde— y **ausente** en el zip. Pasó de verdad: cuatro piezas nuevas
del gadget sin commitear, 63 tests en verde, y el paquete moría al arrancar
porque `gadget.ps1` dot-sourcea las piezas con `ErrorActionPreference = 'Stop'`.
Si los tests fallan, el staging **no se borra**: es el único lugar donde el bug
se reproduce.

El build también deja un archivo **`VERSION`** en la raíz del paquete. Es el
único lugar de lo instalado que sabe qué versión es, y lo muestra la ⓘ del
panel: sin eso, un "no me anda" desde otra máquina no se puede ubicar. Y con
`-Exe` **exige una versión limpia** (`x.y.z`): un `1.1.0-4-gab12-dirty` quedaría
escrito como AppVersion en Programas y características.

**Un aviso no es un error.** Dos de las ocho piezas pueden no tener arreglo
posible —el plugin `claude-hud`, que no es nuestro, y el volcado de la cuota, que
necesita un `settings.json` que todavía puede no existir—. Van a `Avisos`, no a
`Errores`, y `setup.ps1` sale con código de error **sólo** si algo que intentó
arreglar falló. Antes se contaban juntos, así que en cualquier máquina sin el
plugin una instalación perfecta terminaba en rojo y con `exit 1` — y el `.exe`
corre justamente `setup.ps1 -Instalar -y`.

**Los accesos directos que crea Inno llevan el mismo `AppUserModelID`** que el
`.lnk` (`GIA.Conversaciones.Gadget`), que es el que el proceso se pone a sí mismo.
Sin eso, al pinear el acceso Windows no puede juntar la ventana con su ícono y
abre un **segundo** botón en la barra al lado del pineado.

**El panel se abre por un lanzador, no por `powershell.exe`.** `powershell.exe`
es de consola: abierto desde un acceso directo, Windows le crea la consola antes
de correr una línea, y en Windows 11 esa consola es una ventana de Windows
Terminal. `-WindowStyle Hidden` llega tarde, y `FreeConsole` la suelta pero no la
cierra: quedaba una terminal vacía al lado del panel. `Conversaciones.exe`
(`app/lanzador.cs`) es de subsistema de ventanas y arranca PowerShell con
`CREATE_NO_WINDOW`. Lo usan el acceso directo y el protocolo, y sólo sabe abrir
esos dos scripts: no es un "corré cualquier `.ps1` oculto".

Se compila con el C# que trae .NET Framework, sin SDK. El build lo mete en el
paquete, y en una carpeta de trabajo lo compila la pieza 6. El `.exe` lleva
adentro el hash de su fuente, así la pieza lo recompila si cambia el código. Los
tests verifican que el script arranque **sin ventana de consola** y que la URL
del protocolo llegue intacta.

Descartados: `conhost.exe --headless` (una línea, pero es un flag no documentado
y "conhost oculto + PowerShell con `Bypass`" es un patrón típico de malware que un
EDR corporativo puede marcar), y un `.vbs` con `wscript` (Windows está retirando
VBScript).

**El `.iss` de Inno no reimplementa nada.** Copia los archivos e invoca
`setup.ps1 -Instalar -y`, que es el mismo instalador de siempre; al desinstalar
invoca `setup.ps1 -Desinstalar -y` **antes** de borrar los archivos, porque ese
script vive dentro de la carpeta que se va. Si algún día se cambia Inno por otra
cosa, no se reescribe lógica.

**`setup.ps1 -Desinstalar` nunca toca `datos/`.** Desinstalar la app no es tirar
las conversaciones: si el usuario las quiere borrar, las borra él. Y sólo
deshace lo que apunta a *esta* carpeta — si otro panel se quedó con el protocolo
o el skill, se los deja.

**El volcado del statusline se deshace, pero sólo si es byte a byte el nuestro.**
`Get-AjustesSinVolcado` reconoce las dos formas que escribe el instalador —el
envoltorio sobre un statusline que ya estaba, y el bloque entero cuando no había
ninguno— y restaura lo de adentro. Cualquier otra cosa se deja intacta y se
explica qué borrar: el comando del statusline es de la persona, y en la práctica
aparece **editado a mano** (medido: uno que entretejía el volcado con el comando
de `claude-hud` en vez de envolverlo). Desarmar eso a ciegas le rompe el HUD. Un
test hace el viaje redondo y verifica que instalar y desinstalar deje el
`settings.json` idéntico al original, byte a byte.

### Descartado: `.exe` como método de distribución único

El `.exe` de Inno es cómodo pero **no es un requisito**: el zip alcanza y no
suma herramientas al medio. Inno hace falta sólo para *compilar*; el `.exe` que
sale no lo pide. Por eso `build.ps1` produce el zip siempre y el `.exe` sólo si
se lo pide con `-Exe` y encuentra Inno instalado.
