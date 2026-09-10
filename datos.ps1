# =============================================================================
#  datos.ps1 - mirar lo que hay guardado
# -----------------------------------------------------------------------------
#    .\datos.ps1                      la lista completa
#    .\datos.ps1 chat-plus-2          una conversacion entera, con sus notas
#    .\datos.ps1 -Buscar keycloak     busca en titulo, proyecto, rama, notas y tags
#    .\datos.ps1 -Respaldar           copia la base con la fecha en el nombre
#
#  Existe por dos razones. Una: el gadget muestra las tarjetas pero NO las notas,
#  y eran lo unico que se veia en el panel del navegador que se retiro. Dos: la
#  base es SQLite y "abrirla para mirar" no es abrir un archivo de texto.
#
#  Si queres hurgar la base a mano (tablas, SQL suelto), el que sirve es
#  DB Browser for SQLite: https://sqlitebrowser.org -- abri datos\conversaciones.db
#  y listo. Este script no expone SQL a proposito: la regla del proyecto es que
#  solo la capa de Datos sepa como se guarda. Ver ARQUITECTURA.md seccion 3.
# =============================================================================
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Id,
    [string]$Buscar,
    [switch]$Respaldar
)
$ErrorActionPreference = 'Stop'

$carpeta = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $carpeta 'app\lib\Datos\Datos.psd1') -Force
Initialize-Datos -Ruta (Join-Path $carpeta 'datos\conversaciones.db')

function Escribir([string]$T = '', [string]$C = 'Gray') { Write-Host $T -ForegroundColor $C }

# --- respaldar ---------------------------------------------------------------
if ($Respaldar) {
    $dest = Join-Path $carpeta ('datos\conversaciones-{0}.db' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Backup-Datos -Destino $dest | Out-Null
    $kb = [math]::Round((Get-Item -LiteralPath $dest).Length / 1KB)
    Escribir
    Escribir ('  Respaldo hecho: {0}  ({1} KB)' -f (Split-Path -Leaf $dest), $kb) 'Green'
    Escribir '  Es una copia consistente aunque el gadget este abierto.'
    Escribir
    return
}

# --- una sola, con todo ------------------------------------------------------
if ($Id) {
    $c = Get-Conversacion -Id $Id
    if (-not $c) {
        # Ayuda en vez de un error seco: casi siempre es un id a medias.
        $parecidos = @(Get-Conversacion | Where-Object { $_.id -like "*$Id*" })
        Escribir
        Escribir "  No hay ninguna con id '$Id'." 'Yellow'
        if ($parecidos.Count) {
            Escribir '  Quisiste decir:'
            $parecidos | ForEach-Object { Escribir ('    ' + $_.id) 'Cyan' }
        } else {
            Escribir '  Corre .\datos.ps1 sin argumentos para ver los ids.'
        }
        Escribir
        return
    }
    $tags = Get-Tag -Id $c.id
    Escribir
    Escribir ('  ' + $c.titulo) 'White'
    Escribir ('  ' + ('-' * [Math]::Min(70, $c.titulo.Length)))
    foreach ($p in @(@('id', $c.id), @('proyecto', $c.proyecto), @('rama', $c.rama),
            @('carpeta', $c.cwd), @('sesion', $c.sesion), @('fecha', $c.fecha),
            @('tags', ($tags -join ', ')), @('contextoMax', $c.contextoMax))) {
        if ($p[1]) { Escribir ('    {0,-12} {1}' -f $p[0], $p[1]) }
    }
    if ($c.notas) {
        Escribir
        Escribir '    notas' 'White'
        # Se recorta a 78 respetando palabras: las notas llegan a 1800 letras y
        # sin cortar quedan ilegibles en una consola.
        $linea = ''
        foreach ($palabra in ([string]$c.notas -replace "`r", '') -split '\s+') {
            if (($linea.Length + $palabra.Length + 1) -gt 78) { Escribir ('    ' + $linea) 'DarkGray'; $linea = '' }
            $linea = if ($linea) { "$linea $palabra" } else { $palabra }
        }
        if ($linea) { Escribir ('    ' + $linea) 'DarkGray' }
    }
    Escribir
    return
}

# --- la lista ----------------------------------------------------------------
# El @() envuelve al IF ENTERO, no a cada rama. Poniendolo adentro, el array de
# un solo elemento se desarma al salir del if y $convs.Count queda vacio: con una
# sola coincidencia el pie decia "  conversaciones" sin el numero.
$convs = @(if ($Buscar) { Find-Conversacion -Texto $Buscar } else { Get-Conversacion })

Escribir
if ($Buscar) { Escribir ("  Buscando '$Buscar'") 'White' } else { Escribir '  Conversaciones guardadas' 'White' }
Escribir

if ($convs.Count -eq 0) {
    Escribir $(if ($Buscar) { '    Nada.' } else { '    La base esta vacia.' }) 'DarkGray'
    Escribir
    return
}

foreach ($c in $convs) {
    $sub = @($c.proyecto, $c.rama) | Where-Object { $_ }
    Escribir ('    {0,-48} {1}' -f $c.id, $c.titulo) 'Cyan'
    if ($sub) { Escribir ('    {0,-48} {1}' -f '', ($sub -join '  -  ')) 'DarkGray' }
    $t = Get-Tag -Id $c.id
    $marca = @()
    # Va PRIMERO: si la buscas porque no aparece en el panel, esto es la
    # respuesta y no tiene que estar escondida al final de la linea.
    if ($c.archivada) { $marca += 'ARCHIVADA (escondida del panel)' }
    if ($c.notas) { $marca += ('{0} letras de notas' -f ([string]$c.notas).Length) }
    if ($t.Count) { $marca += ($t -join ', ') }
    if ($marca) { Escribir ('    {0,-48} {1}' -f '', ($marca -join '   |   ')) 'DarkGray' }
}

$bd = Join-Path $carpeta 'datos\conversaciones.db'
Escribir
$palabra = if ($convs.Count -eq 1) { 'conversacion' } else { 'conversaciones' }
Escribir ('    {0} {1}   |   la base pesa {2} KB' -f $convs.Count, $palabra, [math]::Round((Get-Item $bd).Length / 1KB)) 'DarkGray'
Escribir '    .\datos.ps1 <id> para ver una entera con sus notas' 'DarkGray'
Escribir
