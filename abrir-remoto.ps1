# =============================================================================
#  abrir-remoto.ps1
#  Abre una conversacion del panel con Remote Control prendido, para poder
#  seguirla desde el celular.
#
#  Pensado para que lo invoque la sesion "recepcion" cuando se lo piden DESDE el
#  telefono. La salida es corta y sin adornos a proposito: se lee en una
#  pantalla chica y la tiene que poder repetir un modelo sin interpretarla.
#
#  SEGURIDAD: no recibe rutas ni comandos, solo un texto de busqueda que se usa
#  para filtrar. La carpeta y el UUID salen de conversaciones.js, que es un
#  archivo local de confianza, igual que en abrir-conversacion.ps1.
#
#    .\abrir-remoto.ps1                      lista todo con su estado
#    .\abrir-remoto.ps1 despacho             busca y abre si hay UNA sola
#    .\abrir-remoto.ps1 -Id el-slug-exacto   abre esa, sin buscar
#    .\abrir-remoto.ps1 despacho -DryRun     muestra que haria, no abre
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Buscar,
    [string]$Id,
    [switch]$Listar,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$carpeta = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $carpeta 'lib-conversaciones.ps1')

# Sync- y no Get-: de paso baja el nombre de /rename, que es el que el usuario
# va a tipear desde el celular.
$convs = @(Sync-TitulosGuardados -Carpeta $carpeta)
if ($convs.Count -eq 0) {
    'El panel esta vacio: no hay ninguna conversacion guardada.'
    return
}

$estados = Get-EstadosSesion

function Mostrar {
    param($Lista)
    foreach ($c in $Lista) {
        $e = $estados[([string]$c.sesion).ToLower()]
        $marca = switch ($e) {
            'remoto'  { '[REMOTO ]' }
            'abierta' { '[abierta]' }
            default   { '[cerrada]' }
        }
        '  {0} {1}   ({2})' -f $marca, (Get-TituloMostrable -Conversacion $c), $c.id
    }
}

# --- listar -------------------------------------------------------------------
if ($Listar -or (-not $Buscar -and -not $Id)) {
    "Conversaciones en el panel ($($convs.Count)):"
    Mostrar $convs
    ''
    'Para abrir una en remoto:  abrir-remoto.ps1 <parte del titulo>'
    return
}

# --- elegir cual --------------------------------------------------------------
if ($Id) {
    $elegidas = @($convs | Where-Object { $_.id -eq $Id })
    if ($elegidas.Count -eq 0) {
        "No hay ninguna conversacion con id '$Id'. Las que hay:"
        Mostrar $convs
        return
    }
} else {
    $t = $Buscar.Trim()
    $elegidas = @($convs | Where-Object {
            (Get-TituloMostrable -Conversacion $_) -like "*$t*" -or
            $_.id -like "*$t*" -or
            ([string]$_.proyecto) -like "*$t*"
        })

    if ($elegidas.Count -eq 0) {
        "No encontre ninguna que coincida con '$t'. Las que hay:"
        Mostrar $convs
        return
    }
    # Ambiguo NO se resuelve solo: abrir la que no era obliga a ir hasta la PC
    # a cerrarla, que es justo lo que este script existe para evitar.
    if ($elegidas.Count -gt 1) {
        "Hay $($elegidas.Count) que coinciden con '$t'. Cual de estas:"
        Mostrar $elegidas
        return
    }
}

$c = $elegidas[0]
$titulo = Get-TituloMostrable -Conversacion $c
$estado = $estados[([string]$c.sesion).ToLower()]

# --- ya hay una terminal viva? ------------------------------------------------
# Abrir una segunda no prende el remoto: segun la doc de Remote Control, si la
# primera ya lo tiene, la segunda arranca con el remoto APAGADO.
if ($estado -eq 'remoto') {
    "Ya esta en remoto: '$titulo'."
    'Buscala en claude.ai/code o en la app del celular; deberia estar ahi con ese nombre.'
    return
}
if ($estado -eq 'abierta') {
    "'$titulo' ya esta abierta en una terminal de la PC, pero SIN remoto."
    'Abrir otra no lo prende: hay que escribir /remote-control en ESA terminal.'
    return
}

# --- abrir --------------------------------------------------------------------
$r = Start-Conversacion -Cwd $c.cwd -Sesion $c.sesion -Remoto -Nombre $titulo -DryRun:$DryRun

if ($DryRun) {
    'DRY RUN: no se abrio nada.'
    "  titulo : $titulo"
    "  cwd    : $($r.Cwd)"
    "  args   : $($r.Args)"
    return
}

"Listo, abriendo '$titulo' con Remote Control."
'En unos segundos aparece con ese nombre en la lista de claude.ai/code y de la app.'
