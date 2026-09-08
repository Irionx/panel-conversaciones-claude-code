# =============================================================================
#  Datos - la unica capa que sabe donde y como se guardan las conversaciones
# -----------------------------------------------------------------------------
#  Nadie fuera de este modulo ve una ruta de archivo ni una sentencia SQL. Esa es
#  toda la razon de que exista: cuando cambio el motor de un .js a SQLite, el
#  paso 2 toco ESTE archivo y una linea de lib-conversaciones.ps1. Nada mas.
#  Ver ARQUITECTURA.md secciones 3, 4 y 5.
#
#  QUE APORTA EL MOTOR SQLITE, ademas de ser un archivo solo para el backup:
#    - Locking de verdad. Antes el gadget reescribia el archivo entero en cada
#      refresco y si `guardar` corria a la vez desde una terminal, uno de los dos
#      se perdia en silencio.
#    - Los backslashes de las rutas Windows se guardan tal cual. Se fue la regex
#      de rescate que reparaba el escapeo a mano.
#    - Buscar es una consulta, no leer todo y filtrar en memoria.
#    - `tags` es una relacion y no un array dentro de un objeto.
#
#  Y no arrastra dependencias: usa el winsqlite3.dll que ya trae Windows.
#  Ver Sqlite.ps1.
# =============================================================================

. (Join-Path $PSScriptRoot 'Sqlite.ps1')

$script:Ruta = $null
$script:NOMBRE_MUTEX = 'Local\GiaConversacionesDatos'
$script:ESPERA_MUTEX_MS = 5000

# Columnas de la tabla, en el orden en que las devuelve Get-Conversacion. Una
# sola definicion: la usan el SELECT y el armado del objeto, asi no se
# desincronizan.
$script:COLUMNAS = @('id', 'titulo', 'proyecto', 'rama', 'cwd', 'sesion', 'fecha', 'notas', 'contextoMax')

# --- migraciones -------------------------------------------------------------
#  Una entrada por version del esquema. Se aplican en orden las que falten,
#  segun PRAGMA user_version. Es el mecanismo estandar de SQLite y es LO UNICO
#  que hacia falta de un ORM (ver ARQUITECTURA.md seccion 7).
#
#  REGLA: nunca editar una migracion ya publicada. Se agrega una nueva al final.
#  Si no, la base de un compañero que ya migro queda distinta de la tuya.
#
#  Cada migracion es un ARRAY de sentencias sueltas: sqlite3_prepare_v2 compila
#  UNA por llamada, asi que un string con varias separadas por ';' ejecutaria
#  solo la primera, en silencio.
$script:MIGRACIONES = @(
    # --- v1: el esquema inicial ---
    , @(
        @'
CREATE TABLE conversacion (
    id          TEXT PRIMARY KEY,
    titulo      TEXT NOT NULL,
    proyecto    TEXT,
    rama        TEXT,
    cwd         TEXT NOT NULL,
    sesion      TEXT NOT NULL,
    fecha       TEXT,
    notas       TEXT,
    contextoMax INTEGER
)
'@,
        @'
CREATE TABLE tag (
    conversacion_id TEXT NOT NULL,
    tag             TEXT NOT NULL,
    PRIMARY KEY (conversacion_id, tag)
)
'@,
        'CREATE INDEX ix_conversacion_sesion ON conversacion (sesion)'
    )
)

# --- infraestructura ---------------------------------------------------------

<#
.SYNOPSIS
  Fija donde vive la base, la crea si no existe y le aplica las migraciones.
#>
function Initialize-Datos {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Ruta)

    $carpeta = Split-Path -Parent $Ruta
    if ($carpeta -and -not (Test-Path -LiteralPath $carpeta)) {
        New-Item -ItemType Directory -Path $carpeta -Force | Out-Null
    }
    $script:Ruta = $Ruta

    $lock = Lock-Almacen
    try {
        $db = [SqliteNativo]::Abrir($Ruta)
        try {
            # DELETE y no WAL a proposito: WAL deja un -wal y un -shm al lado y
            # rompe la propiedad de "un solo archivo" que hace que el backup sea
            # copiar un archivo. Ver ARQUITECTURA.md seccion 7.
            [SqliteNativo]::Ejecutar($db, 'PRAGMA journal_mode=DELETE', $null)

            $version = [int]([SqliteNativo]::Consultar($db, 'PRAGMA user_version', $null))[0][0]
            for ($v = $version; $v -lt $script:MIGRACIONES.Count; $v++) {
                [SqliteNativo]::Ejecutar($db, 'BEGIN IMMEDIATE', $null)
                try {
                    foreach ($sql in $script:MIGRACIONES[$v]) {
                        [SqliteNativo]::Ejecutar($db, $sql, $null)
                    }
                    # user_version no acepta parametros: va interpolado. Es
                    # seguro porque el valor es el indice de nuestro propio array.
                    [SqliteNativo]::Ejecutar($db, "PRAGMA user_version = $($v + 1)", $null)
                    [SqliteNativo]::Ejecutar($db, 'COMMIT', $null)
                } catch {
                    [SqliteNativo]::Ejecutar($db, 'ROLLBACK', $null)
                    throw "Fallo la migracion a la version $($v + 1): $($_.Exception.Message)"
                }
            }
        } finally { [SqliteNativo]::Cerrar($db) }
    } finally { Unlock-Almacen $lock }
}

function Get-RutaAlmacen {
    if (-not $script:Ruta) {
        throw 'La capa de datos no esta inicializada. Llama a Initialize-Datos primero.'
    }
    $script:Ruta
}

# --- el candado --------------------------------------------------------------
#  SQLite ya sincroniza a nivel archivo, pero este candado sincroniza a nivel
#  OPERACION: una secuencia leer-decidir-escribir queda entera para un solo
#  proceso. Sale barato y ya esta probado.
#
#  POR QUE ESTO NO ES UN Invoke-ConBloqueo { ... } QUE ENVUELVE UN SCRIPTBLOCK:
#  en PowerShell los scriptblocks NO son closures. Al invocarlo con `& $bloque`,
#  el bloque corre en un scope hijo del scope de la funcion que hace el `&`, no
#  del scope donde se ESCRIBIO, asi que no ve las variables de quien lo armo.
#  Se puede tapar con .GetNewClosure(), pero hay que acordarse en cada lugar.
#  Esta capa es el cimiento de todo: mejor explicito y aburrido que ingenioso.
function Lock-Almacen {
    $mutex = New-Object System.Threading.Mutex($false, $script:NOMBRE_MUTEX)
    $tomado = $false
    try {
        $tomado = $mutex.WaitOne($script:ESPERA_MUTEX_MS)
    } catch [System.Threading.AbandonedMutexException] {
        # Otro proceso murio con el candado tomado. Igual queda nuestro.
        $tomado = $true
    }
    if (-not $tomado) {
        $mutex.Dispose()
        throw "El almacen de datos esta ocupado (mas de $($script:ESPERA_MUTEX_MS) ms). No se toco nada."
    }
    $mutex
}

function Unlock-Almacen {
    param($Mutex)
    if ($Mutex) {
        try { $Mutex.ReleaseMutex() } catch { }
        $Mutex.Dispose()
    }
}

# --- el motor ----------------------------------------------------------------

<#
.SYNOPSIS
  Corre una consulta y devuelve las filas como object[][].
#>
function Get-Filas {
    param([Parameter(Mandatory)][string]$Sql, [object[]]$Par)

    $lock = Lock-Almacen
    try {
        $db = [SqliteNativo]::Abrir((Get-RutaAlmacen))
        try { return , [SqliteNativo]::Consultar($db, $Sql, $Par) }
        finally { [SqliteNativo]::Cerrar($db) }
    } finally { Unlock-Almacen $lock }
}

<#
.SYNOPSIS
  Corre N sentencias en UNA transaccion. Devuelve las filas afectadas por la ultima.
.DESCRIPTION
  Recibe un array de hashtables @{ Sql = '...'; Par = @(...) }. Se pasan datos y
  no scriptblocks justamente por el problema de scoping que se explica arriba.
  O entran todas o no entra ninguna: sin esto, borrar los tags viejos y no poder
  escribir los nuevos dejaria la conversacion sin tags.
#>
function Invoke-Lote {
    param([Parameter(Mandatory)][array]$Sentencias)

    $lock = Lock-Almacen
    try {
        $db = [SqliteNativo]::Abrir((Get-RutaAlmacen))
        try {
            [SqliteNativo]::Ejecutar($db, 'BEGIN IMMEDIATE', $null)
            try {
                $cambios = 0
                foreach ($s in $Sentencias) {
                    [SqliteNativo]::Ejecutar($db, $s.Sql, $s.Par)
                    $cambios += [SqliteNativo]::Cambios($db)
                }
                [SqliteNativo]::Ejecutar($db, 'COMMIT', $null)
                return $cambios
            } catch {
                [SqliteNativo]::Ejecutar($db, 'ROLLBACK', $null)
                throw
            }
        } finally { [SqliteNativo]::Cerrar($db) }
    } finally { Unlock-Almacen $lock }
}

# Arma el objeto que ve el resto de la app a partir de una fila y sus tags.
# Los campos ausentes quedan en $null, igual que cuando faltaban en el .js.
function ConvertTo-Conversacion {
    param([object[]]$Fila, [string[]]$Tags)

    $o = [ordered]@{}
    for ($i = 0; $i -lt $script:COLUMNAS.Count; $i++) { $o[$script:COLUMNAS[$i]] = $Fila[$i] }
    $o['tags'] = @($Tags)
    [pscustomobject]$o
}

# --- lectura -----------------------------------------------------------------

<#
.SYNOPSIS
  Devuelve conversaciones: todas, o la que coincida con -Id o -Sesion.
#>
function Get-Conversacion {
    [CmdletBinding(DefaultParameterSetName = 'Todas')]
    param(
        [Parameter(ParameterSetName = 'PorId', Mandatory)][string]$Id,
        [Parameter(ParameterSetName = 'PorSesion', Mandatory)][string]$Sesion
    )

    $cols = $script:COLUMNAS -join ', '
    # ORDER BY rowid = el orden en que se fueron agregando, que es el que se ve
    # en el panel. Un UPDATE no cambia el rowid, asi que editar una entrada no
    # la manda al final de la lista.
    switch ($PSCmdlet.ParameterSetName) {
        'PorId' {
            $filas = Get-Filas "SELECT $cols FROM conversacion WHERE id = ?1" @($Id)
        }
        'PorSesion' {
            # El UUID se compara en minuscula: Claude Code lo escribe asi, pero a
            # mano se pega de cualquier forma.
            $filas = Get-Filas "SELECT $cols FROM conversacion WHERE lower(sesion) = lower(?1)" @($Sesion)
        }
        default {
            $filas = Get-Filas "SELECT $cols FROM conversacion ORDER BY rowid" $null
        }
    }
    if ($filas.Count -eq 0) { return }

    # Los tags de todas las filas en UNA consulta y no una por conversacion.
    $porId = @{}
    foreach ($t in (Get-Filas 'SELECT conversacion_id, tag FROM tag ORDER BY tag' $null)) {
        if (-not $porId.ContainsKey($t[0])) { $porId[$t[0]] = @() }
        $porId[$t[0]] += [string]$t[1]
    }
    foreach ($f in $filas) {
        ConvertTo-Conversacion -Fila $f -Tags @($porId[[string]$f[0]])
    }
}

<#
.SYNOPSIS
  Busca texto libre en titulo, proyecto, rama, cwd, notas y tags.
#>
function Find-Conversacion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Texto)

    $cols = ($script:COLUMNAS | ForEach-Object { "c.$_" }) -join ', '
    # El EXISTS sobre tag deja que la busqueda alcance los tags sin traerse
    # filas repetidas. LIKE en SQLite ya no distingue mayusculas para ASCII.
    $sql = @"
SELECT $cols FROM conversacion c
WHERE c.titulo   LIKE '%' || ?1 || '%'
   OR c.proyecto LIKE '%' || ?1 || '%'
   OR c.rama     LIKE '%' || ?1 || '%'
   OR c.cwd      LIKE '%' || ?1 || '%'
   OR c.notas    LIKE '%' || ?1 || '%'
   OR EXISTS (SELECT 1 FROM tag t WHERE t.conversacion_id = c.id AND t.tag LIKE '%' || ?1 || '%')
ORDER BY c.rowid
"@
    $filas = Get-Filas $sql @($Texto)
    foreach ($f in $filas) {
        ConvertTo-Conversacion -Fila $f -Tags (Get-Tag -Id ([string]$f[0]))
    }
}

function Get-Nota {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)
    $f = Get-Filas 'SELECT notas FROM conversacion WHERE id = ?1' @($Id)
    if ($f.Count -eq 0) { return $null }
    [string]$f[0][0]
}

<#
.SYNOPSIS
  Los tags de una conversacion, siempre como coleccion.
.DESCRIPTION
  El ",@(...)" no es adorno: PowerShell DESARMA los arrays de cero o un elemento
  al retornarlos, asi que sin la coma una conversacion sin tags devolvia $null y
  el que llamaba explotaba al hacer .Count.
#>
function Get-Tag {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)
    $f = Get-Filas 'SELECT tag FROM tag WHERE conversacion_id = ?1 ORDER BY tag' @($Id)
    return , @($f | ForEach-Object { [string]$_[0] })
}

# --- escritura ---------------------------------------------------------------

# $null si el string esta vacio. Un campo opcional ausente se guarda como NULL y
# no como cadena vacia: son cosas distintas y mezclarlas ensucia las consultas.
function ConvertTo-NuloSiVacio {
    param([string]$Valor)
    if ([string]::IsNullOrEmpty($Valor)) { $null } else { $Valor }
}

<#
.SYNOPSIS
  Agrega una conversacion. Falla si el id ya existe.
#>
function Add-Conversacion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Titulo,
        [Parameter(Mandatory)][string]$Cwd,
        [Parameter(Mandatory)][string]$Sesion,
        [string]$Proyecto,
        [string]$Rama,
        [string]$Fecha,
        [string]$Notas,
        [string[]]$Tags,
        # Pisa el tamano de ventana detectado. 0 = no lo pises, deducilo.
        [int]$ContextoMax = 0
    )

    if ($Id -notmatch '^[a-z0-9._-]+$') {
        throw "El id '$Id' no sirve: solo a-z 0-9 . _ - (es parte de una URL claudeconv://)"
    }

    $sents = @(
        @{
            Sql = 'INSERT INTO conversacion (id,titulo,proyecto,rama,cwd,sesion,fecha,notas,contextoMax)
                   VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9)'
            Par = @(
                $Id, $Titulo,
                (ConvertTo-NuloSiVacio $Proyecto), (ConvertTo-NuloSiVacio $Rama),
                $Cwd, $Sesion,
                $(if ($Fecha) { $Fecha } else { Get-Date -Format 'yyyy-MM-dd' }),
                (ConvertTo-NuloSiVacio $Notas),
                $(if ($ContextoMax -gt 0) { $ContextoMax } else { $null })
            )
        }
    )
    foreach ($t in @($Tags | Where-Object { $_ })) {
        $sents += @{ Sql = 'INSERT INTO tag (conversacion_id, tag) VALUES (?1,?2)'; Par = @($Id, $t) }
    }

    try { Invoke-Lote $sents | Out-Null }
    catch {
        # La clave primaria ya garantiza que no haya ids repetidos; no hace falta
        # chequear antes (y chequear antes tendria una carrera). Solo se traduce
        # el error a algo legible.
        if ($_.Exception.Message -match 'UNIQUE constraint failed: conversacion.id') {
            throw "Ya existe una conversacion con id '$Id'"
        }
        throw
    }
}

<#
.SYNOPSIS
  Actualiza SOLO los campos que se le pasan.
.DESCRIPTION
  Se usa $PSBoundParameters y no "if ($Titulo)": asi se puede vaciar un campo a
  proposito (-Rama '') sin que se confunda con "no lo mandes".
#>
function Set-Conversacion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$Titulo,
        [string]$Cwd,
        [string]$Sesion,
        [string]$Proyecto,
        [string]$Rama,
        [string]$Fecha,
        [int]$ContextoMax
    )

    # Mapa explicito parametro -> columna, y NO un $k.ToLower(): contextoMax es
    # camelCase y con ToLower() se escribiria en una columna que no existe.
    $mapa = [ordered]@{
        Titulo = 'titulo'; Cwd = 'cwd'; Sesion = 'sesion'; Proyecto = 'proyecto'
        Rama = 'rama'; Fecha = 'fecha'; ContextoMax = 'contextoMax'
    }
    $sets = @()
    $par = @()
    foreach ($k in $mapa.Keys) {
        if (-not $PSBoundParameters.ContainsKey($k)) { continue }
        $par += $PSBoundParameters[$k]
        $sets += "$($mapa[$k]) = ?$($par.Count)"
    }
    if ($sets.Count -eq 0) { return }
    $par += $Id

    $n = Invoke-Lote @(
        @{ Sql = "UPDATE conversacion SET $($sets -join ', ') WHERE id = ?$($par.Count)"; Par = $par }
    )
    # sqlite3_changes cuenta las filas que matcheo el WHERE, asi que 0 significa
    # "ese id no existe" y no "los valores ya eran esos".
    if ($n -eq 0) { throw "No existe una conversacion con id '$Id'" }
}

function Set-Nota {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Texto
    )
    $n = Invoke-Lote @(
        @{ Sql = 'UPDATE conversacion SET notas = ?1 WHERE id = ?2'; Par = @((ConvertTo-NuloSiVacio $Texto), $Id) }
    )
    if ($n -eq 0) { throw "No existe una conversacion con id '$Id'" }
}

function Set-Tag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Tags
    )
    # Existe? El DELETE no lo dice: borrar 0 tags es normal.
    if (-not (Get-Filas 'SELECT 1 FROM conversacion WHERE id = ?1' @($Id)).Count) {
        throw "No existe una conversacion con id '$Id'"
    }
    # Reemplazo completo, y en una sola transaccion: si el DELETE entrara y los
    # INSERT no, la conversacion quedaria sin tags.
    $sents = @(@{ Sql = 'DELETE FROM tag WHERE conversacion_id = ?1'; Par = @($Id) })
    foreach ($t in @($Tags | Where-Object { $_ })) {
        $sents += @{ Sql = 'INSERT INTO tag (conversacion_id, tag) VALUES (?1,?2)'; Par = @($Id, $t) }
    }
    Invoke-Lote $sents | Out-Null
}

<#
.SYNOPSIS
  Saca una conversacion del almacen. NO toca el transcript en disco.
.DESCRIPTION
  Devuelve $true si la saco, $false si no estaba. Borrar el transcript es otra
  cosa y vive en otra capa: aca solo se administra el almacen.
#>
function Remove-Conversacion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)

    $existia = [bool](Get-Filas 'SELECT 1 FROM conversacion WHERE id = ?1' @($Id)).Count
    if (-not $existia) { return $false }

    # Respaldo ANTES de borrar, y va aca adentro y no en quien llama a proposito:
    # borrar es la unica operacion del modulo que no se puede deshacer, y la
    # interfaz le viene prometiendo al usuario que queda red. Una promesa que
    # depende de que tres lugares distintos se acuerden de cumplirla no es una
    # promesa. Un VACUUM INTO sobre una base de este tamano cuesta milisegundos.
    #
    # Se traga la falla: no poder respaldar no es razon para no dejar borrar,
    # pero se deja rastro para que no sea invisible.
    try { Backup-Datos -Destino ((Get-RutaAlmacen) + '.bak') | Out-Null }
    catch { Write-Warning "No pude respaldar antes de borrar: $($_.Exception.Message)" }

    Invoke-Lote @(
        @{ Sql = 'DELETE FROM tag WHERE conversacion_id = ?1'; Par = @($Id) }
        @{ Sql = 'DELETE FROM conversacion WHERE id = ?1'; Par = @($Id) }
    ) | Out-Null
    return $true
}

<#
.SYNOPSIS
  Copia la base a otro archivo.
.DESCRIPTION
  VACUUM INTO y no Copy-Item: da una copia CONSISTENTE aunque el gadget este
  corriendo y escribiendo. Ademas sale compactada.
#>
function Backup-Datos {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Destino)

    # VACUUM INTO falla si el destino ya existe: es a proposito, para no pisar un
    # respaldo por accidente. Se saca antes, que es lo que espera quien llama.
    if (Test-Path -LiteralPath $Destino) { Remove-Item -LiteralPath $Destino -Force }

    $lock = Lock-Almacen
    try {
        $db = [SqliteNativo]::Abrir((Get-RutaAlmacen))
        try { [SqliteNativo]::Ejecutar($db, 'VACUUM INTO ?1', @($Destino)) }
        finally { [SqliteNativo]::Cerrar($db) }
    } finally { Unlock-Almacen $lock }
    $Destino
}

Export-ModuleMember -Function @(
    'Initialize-Datos', 'Backup-Datos',
    'Get-Conversacion', 'Find-Conversacion', 'Get-Nota', 'Get-Tag',
    'Add-Conversacion', 'Set-Conversacion', 'Remove-Conversacion',
    'Set-Nota', 'Set-Tag'
)
