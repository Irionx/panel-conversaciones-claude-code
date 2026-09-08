# =============================================================================
#  setup.ps1 - Verifica (y si se lo pedis, repara) la instalacion del panel.
#
#  USO
#    .\setup.ps1                 muestra el estado de las cuatro piezas
#    .\setup.ps1 -Instalar       repara lo que falte (pide confirmacion)
#    .\setup.ps1 -Instalar -y    sin preguntar
#
#  El gadget hace este mismo chequeo cada vez que arranca, asi que normalmente
#  no hace falta correr esto a mano. Sirve para ver que pasa y para instalar sin
#  abrir el gadget.
#
#  A proposito NO tiene un wrapper .cmd: "setup" es un nombre demasiado generico
#  para dejarlo suelto en el PATH.
# =============================================================================

[CmdletBinding()]
param(
    [switch]$Instalar,
    [switch]$y
)

$ErrorActionPreference = 'Stop'
$carpeta = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $carpeta 'lib-setup.ps1')

function Escribir { param([string]$T = '', [string]$C = 'Gray') Write-Host $T -ForegroundColor $C }

$piezas = @(Get-EstadoInstalacion -Carpeta $carpeta)
$faltan = @($piezas | Where-Object { -not $_.Ok })

Escribir
Escribir '  Instalacion del panel de conversaciones' 'White'
Escribir ('  ' + $carpeta) 'DarkGray'
Escribir

foreach ($p in $piezas) {
    $marca = if ($p.Ok) { ' ok   ' } else { ' falta' }
    $color = if ($p.Ok) { 'Green' } else { 'Yellow' }
    Write-Host ('  ' + $marca) -ForegroundColor $color -NoNewline
    Write-Host ('  {0,-24} {1}' -f $p.Nombre, $p.Detalle) -ForegroundColor 'Gray'
}
Escribir

if ($faltan.Count -eq 0) {
    Escribir '  Todo en orden, no hay nada que hacer.' 'Green'
    Escribir
    return
}

if (-not $Instalar) {
    $palabra = if ($faltan.Count -eq 1) { 'pieza' } else { 'piezas' }
    Escribir ('  Falta {0} {1}. Para instalar:  .\setup.ps1 -Instalar' -f $faltan.Count, $palabra) 'Yellow'
    Escribir
    return
}

# --- confirmacion -------------------------------------------------------------
#  Read-Host necesita terminal interactiva; desde el prompt "!" de Claude Code
#  no siempre la hay, asi que en vez de colgarse pide volver con -y.
if (-not $y) {
    Escribir '  Se escribe en HKCU y en el PATH de usuario. No hace falta admin.' 'Yellow'
    try {
        $tecleado = Read-Host '  Escribi SI para instalar'
    } catch {
        Escribir
        Escribir '  Esta terminal no permite confirmar de forma interactiva.' 'Red'
        Escribir '  Volve a correr:  .\setup.ps1 -Instalar -y' 'Yellow'
        Escribir
        return
    }
    if ($tecleado -ne 'SI') {
        Escribir '  Cancelado, no se toco nada.' 'DarkGray'
        Escribir
        return
    }
}

# --- instalar -----------------------------------------------------------------
$tocoPath = @($faltan | Where-Object { $_.Clave -eq 'path' }).Count -gt 0
$r = Repair-Instalacion -Piezas $piezas

Escribir
foreach ($h in $r.Hechas) { Escribir ('  instalado : ' + $h) 'Green' }
foreach ($e in $r.Errores) { Escribir ('  ERROR     : ' + $e) 'Red' }
Escribir

if ($tocoPath -and $r.Hechas.Count -gt 0) {
    Escribir '  El PATH cambio: abri una terminal nueva para que aparezcan los comandos.' 'Cyan'
    Escribir '  (los procesos ya abiertos, Claude Code incluido, siguen con el PATH viejo)' 'DarkGray'
    Escribir
}

if ($r.Errores.Count -gt 0) { exit 1 }
