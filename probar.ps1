# =============================================================================
#  probar.ps1 - corre todo lo que se puede verificar sin abrir la ventana
# -----------------------------------------------------------------------------
#  Uso:  .\probar.ps1
#
#  Sale 0 si esta todo bien. Es lo primero que hay que correr despues de tocar
#  algo, y lo primero que tiene que correr alguien que acaba de instalar esto en
#  su maquina.
#
#  NO toca tus datos: cada suite trabaja sobre copias en el temp.
#  Lo unico que NO cubre es que la ventana se dibuje bien; para eso hay que
#  abrir el gadget y mirarlo.
# =============================================================================
$ErrorActionPreference = 'Continue'
$carpeta = Split-Path -Parent $MyInvocation.MyCommand.Path

$suites = @(
    @{ Nombre = 'capa de datos'; Ruta = 'app\lib\Datos\Datos.Tests.ps1' }
    @{ Nombre = 'carga del gadget'; Ruta = 'app\gadget\Gadget.Tests.ps1' }
    @{ Nombre = 'instalador'; Ruta = 'app\lib-setup.Tests.ps1' }
)

$fallaron = @()
foreach ($s in $suites) {
    Write-Host ''
    Write-Host ('=== {0} ' -f $s.Nombre).PadRight(70, '=') -ForegroundColor Cyan
    $ruta = Join-Path $carpeta $s.Ruta
    # En un proceso aparte: cada suite dot-sourcea librerias y define funciones
    # con los mismos nombres. Corriendolas juntas se pisarian entre ellas y el
    # resultado no querria decir nada.
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ruta
    if ($LASTEXITCODE -ne 0) { $fallaron += $s.Nombre }
}

Write-Host ''
Write-Host ''.PadRight(70, '=')
if ($fallaron.Count) {
    Write-Host ('  FALLARON: ' + ($fallaron -join ', ')) -ForegroundColor Red
    Write-Host ''
    exit 1
}
Write-Host '  Todo en verde.' -ForegroundColor Green
Write-Host ''
Write-Host '  Falta lo que no se puede automatizar: abri el gadget y fijate que'
Write-Host '  se vean las conversaciones con sus barras. Si algo anda mal, corre'
Write-Host '  .\setup.ps1 para ver el estado de la instalacion.'
Write-Host ''
