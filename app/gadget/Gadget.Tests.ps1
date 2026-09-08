# =============================================================================
#  Test de carga del gadget
# -----------------------------------------------------------------------------
#  Se corre a mano:  powershell -NoProfile -File gadget\Gadget.Tests.ps1
#  Sale 0 si todo pasa, 1 si algo falla.
#
#  NO abre la ventana. Hace lo mismo que gadget.ps1 al arrancar -- cargar las
#  librerias, las piezas y el XAML -- y verifica que quede todo en pie. Eso
#  alcanza para agarrar la clase de bug que aparece al partir un archivo grande:
#  una pieza que se carga antes de la dependencia que necesita, un x:Name que se
#  quedo sin su FindName, una funcion que se perdio en el corte.
#
#  Ya atajo uno de verdad: Tarjeta.ps1 arma el ControlTemplate de los botones a
#  nivel superior, asi que necesita el Add-Type de WPF ANTES. Con el dot-source
#  puesto antes, el gadget no abria.
# =============================================================================
$ErrorActionPreference = 'Stop'

$script:fallas = 0
$script:pasados = 0
function Probar([string]$Que, [scriptblock]$Bloque) {
    try { & $Bloque; Write-Host ("  OK    {0}" -f $Que); $script:pasados++ }
    catch {
        Write-Host ("  FALLA {0}" -f $Que) -ForegroundColor Red
        Write-Host ("        {0}" -f $_.Exception.Message) -ForegroundColor Red
        $script:fallas++
    }
}
function Afirmar([bool]$Cond, [string]$Mensaje) { if (-not $Cond) { throw $Mensaje } }

$carpeta = Split-Path -Parent $PSScriptRoot

Write-Host ''
Write-Host '=== carga, en el mismo orden que gadget.ps1 ==='

# OJO: la carga va al NIVEL SUPERIOR del test y no adentro de un Probar { }.
# Un scriptblock invocado con & abre un scope nuevo, asi que dot-sourcear ahi
# adentro deja las funciones y $xaml encerradas y despues "no existe nada".
# Es la misma trampa de scoping que hay documentada en Datos.psm1.
. (Join-Path $carpeta 'lib-conversaciones.ps1')
. (Join-Path $carpeta 'lib-setup.ps1')
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms
foreach ($pieza in 'Xaml', 'Apariencia', 'Confirmacion', 'Tarjeta', 'Cuota') {
    . (Join-Path $carpeta "gadget\$pieza.ps1")
}
Write-Host '  OK    librerias, WPF y las 5 piezas cargaron sin explotar'
$script:pasados++
Probar 'el ControlTemplate de los botones quedo armado' {
    # Es codigo de nivel superior en Tarjeta.ps1 y necesita WPF ya cargado: si
    # el dot-source se adelanta al Add-Type, esto queda en $null.
    Afirmar ($null -ne $script:tplPlano) 'tplPlano quedo nulo: se cargo Tarjeta.ps1 antes del Add-Type?'
}

Write-Host ''
Write-Host '=== lo que cada pieza tiene que dejar ==='

Probar 'Xaml.ps1 define $xaml y es XAML valido' {
    Afirmar ($null -ne $xaml -and $xaml.Length -gt 100) 'no quedo definido $xaml'
    $v = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$xaml)))
    Afirmar ($null -ne $v) 'el XAML no cargo'
    $script:ventanaPrueba = $v
}
Probar 'todos los x:Name que busca gadget.ps1 existen en el XAML' {
    # Se sacan del propio gadget.ps1 en vez de listarlos a mano: si manana
    # alguien agrega un FindName y se olvida del XAML, este test lo agarra.
    $txt = Get-Content -LiteralPath (Join-Path $carpeta 'gadget.ps1') -Raw
    $nombres = [regex]::Matches($txt, "FindName\('([^']+)'\)") |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    Afirmar ($nombres.Count -gt 5) "esperaba varios FindName, encontre $($nombres.Count)"
    $faltan = @($nombres | Where-Object { -not $script:ventanaPrueba.FindName($_) })
    Afirmar ($faltan.Count -eq 0) ("el XAML no tiene: " + ($faltan -join ', '))
    Write-Host ("        ({0} x:Name verificados)" -f $nombres.Count)
}
Probar 'las funciones de cada pieza estan definidas' {
    $esperadas = @{
        'Apariencia.ps1'   = 'Get-AlphaFondo', 'Get-ColorTarjeta', 'Get-ColorHover', 'Pincel',
        'Write-Falla', 'New-Sombra', 'Set-Apariencia', 'Get-ColorContexto', 'Escapar'
        'Confirmacion.ps1' = , 'Show-Confirmacion'
        'Tarjeta.ps1'      = , 'New-Tarjeta'
        'Cuota.ps1'        = 'Get-CuotaReal', 'Set-Resumen'
    }
    foreach ($pieza in $esperadas.Keys) {
        foreach ($f in $esperadas[$pieza]) {
            Afirmar ([bool](Get-Command $f -ErrorAction SilentlyContinue)) "falta $f (de $pieza)"
        }
    }
}
Probar 'la capa de Datos llego a traves de la libreria' {
    foreach ($f in 'Get-Conversacion', 'Set-Conversacion', 'Remove-Conversacion') {
        Afirmar ([bool](Get-Command $f -ErrorAction SilentlyContinue)) "falta $f"
    }
}

Write-Host ''
Write-Host '=== que ninguna pieza se quedo con codigo que no le toca ==='

Probar 'ninguna pieza abre la ventana principal ni crea timers' {
    # Se buscan cosas PRECISAS y sobre codigo, no sobre comentarios. La primera
    # version buscaba 'ShowDialog()' y 'Add_Tick' sueltos: marcaba el ShowDialog
    # del dialogo de confirmacion (que obviamente tiene que mostrarse) y la
    # palabra Add_Tick escrita adentro de un comentario. Un test que grita por
    # cosas que estan bien se termina ignorando, que es peor que no tenerlo.
    $prohibidos = @{
        '\$ventana\.ShowDialog' = 'abre la ventana principal'
        'DispatcherTimer'       = 'crea un timer'
        'Add-Type -AssemblyName' = 'carga assemblies'
    }
    foreach ($p in Get-ChildItem -LiteralPath (Join-Path $carpeta 'gadget') -Filter '*.ps1') {
        if ($p.Name -like '*.Tests.ps1') { continue }
        $codigo = (Get-Content -LiteralPath $p.FullName |
            ForEach-Object { ($_ -replace '#.*$', '') }) -join "`n"
        foreach ($pat in $prohibidos.Keys) {
            if ($codigo -match $pat) {
                throw "$($p.Name) $($prohibidos[$pat]): eso va en gadget.ps1, no en las piezas"
            }
        }
    }
}
Probar 'gadget.ps1 quedo bajo 600 lineas' {
    $n = (Get-Content -LiteralPath (Join-Path $carpeta 'gadget.ps1')).Count
    Afirmar ($n -lt 600) "gadget.ps1 tiene $n lineas: volvio a crecer, hay que partirlo otra vez"
    Write-Host ("        ({0} lineas)" -f $n)
}

Write-Host ''
Write-Host ("{0} pasados, {1} fallas" -f $script:pasados, $script:fallas)
exit ([int]($script:fallas -gt 0))
