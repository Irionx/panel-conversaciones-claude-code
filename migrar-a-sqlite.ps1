# =============================================================================
#  migrar-a-sqlite.ps1 - pasa conversaciones.js a datos\conversaciones.db
# -----------------------------------------------------------------------------
#  ES DE UN SOLO USO. Se corre una vez, se verifica, y despues se borra del
#  proyecto: una instalacion nueva arranca con la base vacia y no necesita
#  migrar nada. Queda en el historial de git por si alguna vez hace falta.
#
#  No toca conversaciones.js: lo lee y nada mas. Si algo sale mal, el archivo
#  viejo sigue ahi tal cual.
#
#  Uso:  .\migrar-a-sqlite.ps1            -> muestra que haria
#        .\migrar-a-sqlite.ps1 -Aplicar   -> migra
# =============================================================================
param([switch]$Aplicar)
$ErrorActionPreference = 'Stop'

$carpeta = Split-Path -Parent $MyInvocation.MyCommand.Path
$origen = Join-Path $carpeta 'conversaciones.js'
$destino = Join-Path $carpeta 'datos\conversaciones.db'

if (-not (Test-Path -LiteralPath $origen)) { throw "No encuentro $origen" }

# --- leer el .js viejo -------------------------------------------------------
#  Esta logica ya no vive en la lib (se fue con el cambio de motor). Se copia
#  aca porque este script es lo ultimo que necesita entender el formato viejo.
$texto = Get-Content -LiteralPath $origen -Raw -Encoding UTF8
$marca = $texto.IndexOf('window.CONVERSACIONES')
if ($marca -lt 0) { throw 'conversaciones.js no define window.CONVERSACIONES' }
$ini = $texto.IndexOf('[', $marca)
$fin = $texto.LastIndexOf(']')
$json = $texto.Substring($ini, $fin - $ini + 1)

# Red de seguridad del formato viejo: un path pegado a mano con barra simple
# ("C:\local repos") hacia invalido el JSON.
$json = [regex]::Replace($json, '\\(["\\/bfnrtu])|\\', {
        param($m)
        if ($m.Groups[1].Success) { $m.Value } else { '\\' }
    })

# ConvertFrom-Json en PS 5.1 emite el array entero como UN objeto: hay que
# desarmarlo o queda una sola "conversacion" que es la lista completa.
$viejas = @(@($json | ConvertFrom-Json) | ForEach-Object { $_ })

Write-Host ''
Write-Host ('  origen  : {0}  ({1} conversaciones)' -f (Split-Path -Leaf $origen), $viejas.Count)
Write-Host ('  destino : datos\conversaciones.db')
Write-Host ''
foreach ($v in $viejas) {
    $n = if ($v.notas) { ([string]$v.notas).Length } else { 0 }
    $t = if ($v.tags) { (@($v.tags)).Count } else { 0 }
    Write-Host ('    {0,-50} {1,5} letras de notas, {2} tags' -f $v.id, $n, $t)
}
Write-Host ''

if (-not $Aplicar) {
    Write-Host '  (corre con -Aplicar para migrar)' -ForegroundColor Cyan
    Write-Host ''
    return
}

# --- migrar ------------------------------------------------------------------
Import-Module (Join-Path $carpeta 'lib\Datos\Datos.psd1') -Force
Initialize-Datos -Ruta $destino

$yaHay = @(Get-Conversacion).Count
if ($yaHay -gt 0) {
    throw "La base ya tiene $yaHay conversaciones. Migrar encima duplicaria todo. Si querias rehacerla, borra $destino primero."
}

foreach ($v in $viejas) {
    $p = @{
        Id     = [string]$v.id
        Titulo = [string]$v.titulo
        Cwd    = [string]$v.cwd
        Sesion = [string]$v.sesion
    }
    foreach ($par in @(@('proyecto', 'Proyecto'), @('rama', 'Rama'), @('fecha', 'Fecha'), @('notas', 'Notas'))) {
        if ($v.PSObject.Properties[$par[0]] -and $v.($par[0])) { $p[$par[1]] = [string]$v.($par[0]) }
    }
    if ($v.PSObject.Properties['tags'] -and $v.tags) { $p.Tags = @($v.tags) }
    if ($v.PSObject.Properties['contextoMax'] -and $v.contextoMax) { $p.ContextoMax = [int]$v.contextoMax }
    Add-Conversacion @p
}

# --- verificar: campo por campo, no "parece que anduvo" ----------------------
$nuevas = @(Get-Conversacion)
$problemas = @()
if ($nuevas.Count -ne $viejas.Count) {
    $problemas += "cantidad: {0} vieja(s) vs {1} nueva(s)" -f $viejas.Count, $nuevas.Count
}
foreach ($v in $viejas) {
    $n = Get-Conversacion -Id ([string]$v.id)
    if (-not $n) { $problemas += "falta '$($v.id)'"; continue }
    foreach ($campo in 'titulo', 'cwd', 'sesion', 'proyecto', 'rama', 'fecha', 'notas') {
        $a = [string]$v.$campo
        $b = [string]$n.$campo
        if ($a -cne $b) { $problemas += "$($v.id).$campo difiere" }
    }
    $ta = @($v.tags) | Where-Object { $_ } | Sort-Object
    $tb = @($n.tags) | Sort-Object
    if (($ta -join '|') -cne ($tb -join '|')) { $problemas += "$($v.id).tags difiere" }
    if ([int]$v.contextoMax -ne [int]$n.contextoMax) { $problemas += "$($v.id).contextoMax difiere" }
}

Write-Host ''
if ($problemas.Count) {
    Write-Host '  MIGRACION CON PROBLEMAS:' -ForegroundColor Red
    $problemas | ForEach-Object { Write-Host ('    - ' + $_) -ForegroundColor Red }
    Write-Host ''
    Write-Host '  conversaciones.js NO se toco. Revisa antes de seguir.' -ForegroundColor Red
    exit 1
}

$tam = (Get-Item -LiteralPath $destino).Length
Write-Host ('  Migradas {0}/{0}, campo por campo, sin diferencias.' -f $nuevas.Count) -ForegroundColor Green
Write-Host ('  La base pesa {0:N0} bytes.' -f $tam)
Write-Host ''
Write-Host '  conversaciones.js quedo intacto. Borralo cuando estes tranquilo.'
Write-Host ''
