# =============================================================================
#  Datos - la unica capa que sabe donde y como se guardan las conversaciones
# -----------------------------------------------------------------------------
#  Nadie fuera de este modulo ve un path de archivo, un ConvertFrom-Json ni
#  (cuando llegue el paso 2) una sentencia SQL. Esa es toda la razon de que este
#  modulo exista: cambiar de motor tiene que tocar UN archivo, no ocho.
#
#  Hoy atras hay un .js. Manana un SQLite. Las funciones exportadas no cambian.
#  Ver ARQUITECTURA.md secciones 3, 4 y 5.
#
#  DOS COSAS QUE ARREGLA respecto de lo que habia en lib-conversaciones.ps1:
#
#  1. ESCRITURA ATOMICA. Antes se hacia WriteAllText directo sobre el archivo
#     bueno: si el proceso moria a mitad de camino, quedaba un .js cortado. Ahora
#     se escribe a un temporal y se reemplaza de un golpe con File.Replace, que
#     ademas rota el .bak en la misma operacion.
#
#  2. UN CANDADO ENTRE PROCESOS. El gadget llama a Sync-TitulosGuardados en cada
#     refresco y reescribe el archivo entero cuando detecta un /rename. Si
#     `guardar` corria desde una terminal en ese mismo momento, uno de los dos se
#     perdia... y el `catch {}` del gadget se tragaba la falla en silencio.
# =============================================================================

$script:Ruta = $null
$script:NOMBRE_MUTEX = 'Local\GiaConversacionesDatos'
$script:ESPERA_MUTEX_MS = 5000

# --- infraestructura ---------------------------------------------------------

<#
.SYNOPSIS
  Fija donde vive el almacen y lo prepara si hace falta.
.DESCRIPTION
  Se llama una vez al arrancar. Sin esto el resto de las funciones no sabe con
  que archivo trabajar y falla con un mensaje claro en vez de adivinar.
#>
function Initialize-Datos {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Ruta)

    if (-not (Test-Path -LiteralPath $Ruta)) {
        throw "No encuentro el almacen de datos en: $Ruta"
    }
    $script:Ruta = (Resolve-Path -LiteralPath $Ruta).Path
}

function Get-RutaAlmacen {
    if (-not $script:Ruta) {
        throw 'La capa de datos no esta inicializada. Llama a Initialize-Datos primero.'
    }
    $script:Ruta
}

# --- el candado --------------------------------------------------------------
#  POR QUE ESTO NO ES UN Invoke-ConBloqueo { ... } QUE ENVUELVE UN SCRIPTBLOCK:
#
#  Se intento y no funciona. En PowerShell los scriptblocks NO son closures: al
#  invocarlo con `& $bloque`, el bloque corre en un scope hijo del scope de la
#  funcion que hace el `&` -- no del scope donde se ESCRIBIO. O sea que un
#  bloque escrito dentro de Add-Conversacion no ve $Id, y la funcion falla con
#  "No existe una conversacion con id ''". Se arregla con .GetNewClosure(), pero
#  es un footgun que hay que acordarse en cada uno de los 7 lugares.
#
#  Esta capa es el cimiento de todo: mejor explicito y aburrido que ingenioso.
#  El par Lock/Unlock siempre va con try/finally.

function Lock-Almacen {
    # El mutex es del sistema (prefijo Local\), asi que sincroniza entre
    # PROCESOS: el gadget, `guardar` desde una terminal y `borrar` desde otra.
    # Un lock dentro del proceso no serviria de nada.
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
        # Se tira excepcion en vez de escribir igual: perder el cambio de otro
        # en silencio es exactamente el bug que esto viene a matar.
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

# --- el motor: hoy un .js ----------------------------------------------------
#  TODO lo especifico del formato vive de aca hasta el proximo separador. Es lo
#  que se reemplaza entero en el paso 2 (feat/sqlite).

function Read-Almacen {
    $archivo = Get-RutaAlmacen
    $texto = Get-Content -LiteralPath $archivo -Raw -Encoding UTF8

    $marca = $texto.IndexOf('window.CONVERSACIONES')
    if ($marca -lt 0) { throw 'El almacen no define window.CONVERSACIONES' }
    $ini = $texto.IndexOf('[', $marca)
    $fin = $texto.LastIndexOf(']')
    if ($ini -lt 0 -or $fin -le $ini) { throw 'No pude leer el array del almacen' }

    $json = $texto.Substring($ini, $fin - $ini + 1)

    # Red de seguridad para archivos editados a mano: si alguien pego un path de
    # Windows con barra simple ("C:\local repos") el JSON seria invalido. Se
    # duplica todo backslash que no forme parte de un escape valido. La
    # alternancia consume primero los escapes correctos, asi un "\\" ya bien
    # escrito no se toca.
    $json = [regex]::Replace($json, '\\(["\\/bfnrtu])|\\', {
            param($m)
            if ($m.Groups[1].Success) { $m.Value } else { '\\' }
        })

    # OJO, ACA HAY UNA TRAMPA QUE YA COSTO UNA VEZ:
    # ConvertFrom-Json en PS 5.1 emite el array entero como UN SOLO objeto (un
    # Object[]), no como N objetos. Devolver "@($json | ConvertFrom-Json)" da un
    # array de UN elemento que ES el array, y entonces un "$todas + $nueva" del
    # lado de la escritura mete el array adentro de si mismo y el almacen queda
    # anidado. Hay un test que verifica justamente eso.
    # Por eso se emiten los elementos de a uno: asi el pipeline se comporta
    # normal y "@(Read-Almacen)" da la cantidad de verdad.
    $arr = $json | ConvertFrom-Json
    foreach ($item in @($arr)) {
        # Un almacen vacio ("[]") devuelve $null, y @($null) es un array con un
        # elemento nulo. Se filtra o el conteo miente.
        if ($null -ne $item) { $item }
    }
}

function Write-Almacen {
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$Conversaciones)

    $archivo = Get-RutaAlmacen
    $texto = Get-Content -LiteralPath $archivo -Raw -Encoding UTF8

    $marca = $texto.IndexOf('window.CONVERSACIONES')
    $ini = $texto.IndexOf('[', $marca)
    $fin = $texto.LastIndexOf(']')
    if ($marca -lt 0 -or $ini -lt 0 -or $fin -le $ini) { throw 'No pude ubicar el array en el almacen' }

    if ($Conversaciones.Count -eq 0) {
        $cuerpo = '[]'
    } else {
        # Objeto por objeto: ConvertTo-Json en PS 5.1 desarma un array de un solo
        # elemento y nos comeria los corchetes.
        $piezas = foreach ($c in $Conversaciones) {
            $j = $c | ConvertTo-Json -Depth 6
            '    ' + ($j -replace "`r`n", "`n").Replace("`n", "`n    ")
        }
        $cuerpo = "[`n" + ($piezas -join ",`n") + "`n]"
    }
    $nuevo = $texto.Substring(0, $ini) + $cuerpo + $texto.Substring($fin + 1)

    # Temporal + File.Replace en vez de WriteAllText sobre el archivo bueno. Si
    # el proceso muere durante el WriteAllText queda un .js cortado a la mitad;
    # con Replace, o esta el viejo entero o el nuevo entero. Y de paso Replace
    # deja el anterior en .bak en la misma operacion atomica.
    $tmp = "$archivo.tmp"
    $bak = "$archivo.bak"
    [System.IO.File]::WriteAllText($tmp, $nuevo, [System.Text.UTF8Encoding]::new($false))
    try {
        [System.IO.File]::Replace($tmp, $archivo, $bak)
    } catch {
        # Replace exige que el destino exista y que ambos esten en el mismo
        # volumen. Si algo de eso no se cumple, Move -Force sigue siendo atomico
        # dentro del volumen, solo que sin rotar el .bak.
        Move-Item -LiteralPath $tmp -Destination $archivo -Force
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
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

    $lock = Lock-Almacen
    try { $todas = Read-Almacen } finally { Unlock-Almacen $lock }

    switch ($PSCmdlet.ParameterSetName) {
        'PorId' { $todas | Where-Object { [string]$_.id -eq $Id } }
        # El UUID se compara en minuscula: Claude Code lo escribe en minuscula
        # pero a mano se pega de cualquier forma.
        'PorSesion' { $todas | Where-Object { ([string]$_.sesion).ToLower() -eq $Sesion.ToLower() } }
        default { $todas }
    }
}

<#
.SYNOPSIS
  Busca texto libre en titulo, proyecto, rama, cwd, notas y tags.
#>
function Find-Conversacion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Texto)

    $t = $Texto.ToLower()
    Get-Conversacion | Where-Object {
        $heno = @(
            [string]$_.titulo, [string]$_.proyecto, [string]$_.rama,
            [string]$_.cwd, [string]$_.notas
        ) + @($_.tags)
        ($heno -join ' ').ToLower().Contains($t)
    }
}

function Get-Nota {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)
    $c = Get-Conversacion -Id $Id
    if ($c) { [string]$c.notas } else { $null }
}

<#
.SYNOPSIS
  Los tags de una conversacion, siempre como coleccion.
.DESCRIPTION
  El ",@(...)" del return no es adorno: PowerShell DESARMA los arrays de cero o
  un elemento al retornarlos, asi que sin la coma una conversacion sin tags
  devolvia $null y el que llamaba explotaba al hacer .Count. La coma envuelve el
  array para que salga entero.
#>
function Get-Tag {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)
    $c = Get-Conversacion -Id $Id
    if (-not $c) { return , @() }
    return , @($c.tags | Where-Object { $null -ne $_ })
}

# --- escritura ---------------------------------------------------------------
#  Todas leen y escriben DENTRO del mismo candado. Si se hiciera
#  Get-Conversacion + Write-Almacen por separado, entre las dos otro proceso
#  podria tocar el mismo archivo y uno de los dos cambios se perderia.

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
        [string[]]$Tags
    )

    if ($Id -notmatch '^[a-z0-9._-]+$') {
        throw "El id '$Id' no sirve: solo a-z 0-9 . _ - (es parte de una URL claudeconv://)"
    }

    $lock = Lock-Almacen
    try {
        $todas = @(Read-Almacen)
        if ($todas | Where-Object { [string]$_.id -eq $Id }) {
            throw "Ya existe una conversacion con id '$Id'"
        }
        # Los opcionales solo se escriben si tienen algo: un "proyecto": "" en el
        # almacen es ruido que despues hay que filtrar en todos los que leen.
        # El orden de las claves es el que se ve en el archivo, de ahi [ordered].
        $nueva = [ordered]@{ id = $Id; titulo = $Titulo }
        if ($Proyecto) { $nueva.proyecto = $Proyecto }
        $nueva.cwd = $Cwd
        $nueva.sesion = $Sesion
        $nueva.fecha = if ($Fecha) { $Fecha } else { Get-Date -Format 'yyyy-MM-dd' }
        if ($Rama) { $nueva.rama = $Rama }
        if ($Tags) { $nueva.tags = @($Tags) }
        if ($Notas) { $nueva.notas = $Notas }
        Write-Almacen -Conversaciones ($todas + [pscustomobject]$nueva)
    } finally { Unlock-Almacen $lock }
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
        [string]$Fecha
    )

    $campos = @{}
    foreach ($k in 'Titulo', 'Cwd', 'Sesion', 'Proyecto', 'Rama', 'Fecha') {
        if ($PSBoundParameters.ContainsKey($k)) { $campos[$k.ToLower()] = $PSBoundParameters[$k] }
    }
    if ($campos.Count -eq 0) { return }

    Set-CampoInterno -Id $Id -Campos $campos
}

function Set-Nota {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Texto
    )
    Set-CampoInterno -Id $Id -Campos @{ notas = $Texto }
}

function Set-Tag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Tags
    )
    Set-CampoInterno -Id $Id -Campos @{ tags = @($Tags) }
}

# Privada: el read-modify-write que comparten Set-Conversacion, Set-Nota y
# Set-Tag. Se pasa un hashtable y no un scriptblock justamente por el problema
# de scoping que se explica arriba.
function Set-CampoInterno {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][hashtable]$Campos
    )
    $lock = Lock-Almacen
    try {
        $todas = @(Read-Almacen)
        $c = $todas | Where-Object { [string]$_.id -eq $Id }
        if (-not $c) { throw "No existe una conversacion con id '$Id'" }
        foreach ($k in $Campos.Keys) {
            # Add-Member -Force: el campo puede no existir todavia (rama, notas y
            # tags son opcionales y no estan en todas las entradas).
            $c | Add-Member -NotePropertyName $k -NotePropertyValue $Campos[$k] -Force
        }
        Write-Almacen -Conversaciones $todas
    } finally { Unlock-Almacen $lock }
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

    $lock = Lock-Almacen
    try {
        $todas = @(Read-Almacen)
        $quedan = @($todas | Where-Object { [string]$_.id -ne $Id })
        if ($quedan.Count -eq $todas.Count) { return $false }
        Write-Almacen -Conversaciones $quedan
        return $true
    } finally { Unlock-Almacen $lock }
}

<#
.SYNOPSIS
  Copia el almacen a otro archivo.
.DESCRIPTION
  Toma el candado antes de copiar: sin eso se podria copiar justo en el medio de
  una escritura y quedarse con un respaldo invalido, que es peor que no tenerlo.
#>
function Backup-Datos {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Destino)

    $origen = Get-RutaAlmacen
    $lock = Lock-Almacen
    try { Copy-Item -LiteralPath $origen -Destination $Destino -Force }
    finally { Unlock-Almacen $lock }
    $Destino
}

Export-ModuleMember -Function @(
    'Initialize-Datos', 'Backup-Datos',
    'Get-Conversacion', 'Find-Conversacion', 'Get-Nota', 'Get-Tag',
    'Add-Conversacion', 'Set-Conversacion', 'Remove-Conversacion',
    'Set-Nota', 'Set-Tag'
)
