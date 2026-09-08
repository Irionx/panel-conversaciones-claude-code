# =============================================================================
#  borrar.ps1 - Borra una conversacion del panel Y del disco.
#
#  OJO: no es lo mismo que "Quitar". Quitar solo saca la entrada del panel y
#  deja la charla intacta. Esto borra el transcript .jsonl y la carpeta del
#  uuid: la conversacion deja de existir y no se reabre con --resume.
#
#  USO
#    .\borrar.ps1 test                 # muestra que se va y pide confirmacion
#    .\borrar.ps1 test -DryRun         # solo muestra, no toca nada
#    .\borrar.ps1 test -y              # sin preguntar
#    .\borrar.ps1 -Listar              # ids disponibles en el panel
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Id,
    [switch]$Listar,
    [switch]$DryRun,
    [switch]$y
)

$ErrorActionPreference = 'Stop'
$carpeta = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $carpeta 'lib-conversaciones.ps1')

function Escribir { param([string]$T = '', [string]$C = 'Gray') Write-Host $T -ForegroundColor $C }

# --- modo listar --------------------------------------------------------------
#  Tambien es lo que se ve si no pasas id: mejor mostrar las opciones que tirar
#  un error de uso.
if ($Listar -or -not $Id) {
    $convs = @(Get-Conversaciones -Carpeta $carpeta)
    Escribir
    if ($convs.Count -eq 0) {
        Escribir '  El panel esta vacio.' 'DarkGray'
        Escribir
        return
    }
    Escribir '  Conversaciones en el panel' 'White'
    Escribir
    foreach ($c in $convs) {
        Escribir ('    {0,-46} {1}' -f $c.id, $c.titulo)
    }
    Escribir
    Escribir '  Para borrar una:  borrar-conversacion <id>' 'DarkGray'
    Escribir
    return
}

# --- que se va a borrar -------------------------------------------------------
$conv = @(Get-Conversaciones -Carpeta $carpeta | Where-Object { $_.id -eq $Id })[0]
if (-not $conv) {
    throw "No hay ninguna conversacion con id '$Id'. Corre 'borrar-conversacion -Listar' para ver los ids."
}

$rastros = @(Get-RastrosSesion -Cwd $conv.cwd -Sesion $conv.sesion)

Escribir
Escribir ('  Borrar "{0}"' -f ($conv.titulo | ForEach-Object { if ($_) { $_ } else { $conv.id } })) 'White'
Escribir ('    id       : ' + $conv.id)
Escribir ('    sesion   : ' + $conv.sesion)
Escribir ('    carpeta  : ' + $conv.cwd)
Escribir
Escribir '    Se borra para siempre:' 'Yellow'
Escribir '      - la entrada del panel'
foreach ($r in $rastros) {
    Escribir ('      - {0}  ({1})' -f $r.Nombre, (Format-Bytes $r.Bytes))
}
if ($rastros.Count -eq 0) {
    Escribir '      - (el transcript ya no esta en disco)' 'DarkGray'
}
Escribir

if ($DryRun) {
    Escribir '  -DryRun: no se toco nada.' 'Cyan'
    Escribir
    return
}

# --- confirmacion -------------------------------------------------------------
#  Read-Host necesita una terminal interactiva. Desde el prompt "!" de Claude
#  Code no siempre la hay, asi que en vez de colgarse se pide volver con -y.
if (-not $y) {
    Escribir '  No se va a poder reabrir con --resume.' 'Yellow'
    try {
        $tecleado = Read-Host '  Escribi BORRAR para confirmar'
    } catch {
        Escribir
        Escribir '  Esta terminal no permite confirmar de forma interactiva.' 'Red'
        Escribir ('  Si estas seguro, volve a correr:  borrar-conversacion {0} -y' -f $Id) 'Yellow'
        Escribir
        return
    }
    if ($tecleado -ne 'BORRAR') {
        Escribir '  Cancelado, no se toco nada.' 'DarkGray'
        Escribir
        return
    }
}

# --- borrar -------------------------------------------------------------------
$res = Remove-ConversacionCompleta -Carpeta $carpeta -Id $Id
$quedan = @(Get-Conversaciones -Carpeta $carpeta).Count

Escribir
Escribir '  Conversacion borrada' 'Green'
Escribir ('    id       : ' + $res.Id)
Escribir ('    sesion   : ' + $res.Sesion)
foreach ($b in $res.Borrados) {
    Escribir ('    borrado  : {0}  ({1})' -f $b.Nombre, (Format-Bytes $b.Bytes))
}
Escribir ('    total    : {0} en el panel' -f $quedan)
Escribir
