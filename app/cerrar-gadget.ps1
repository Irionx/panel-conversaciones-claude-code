# =============================================================================
#  cerrar-gadget.ps1 - Cierra el gadget, incluso si esta trabado.
#
#  Existe porque el gadget NO sale en la barra de tareas ni en Alt+Tab
#  (ShowInTaskbar="False"), y en el Administrador de tareas figura como un
#  "Windows PowerShell" mas, sin nada que lo distinga: su MainWindowTitle esta
#  vacio porque la consola va oculta y la ventana WPF no cuenta como principal.
#
#  USO
#    cerrar-gadget            cierra el que este corriendo
#    cerrar-gadget -Listar    solo muestra, no cierra
#
#  OJO: es un cierre forzado, asi que se saltea el guardado de la posicion y
#  el tamano. Si el gadget responde, es mejor cerrarlo con su boton X.
# =============================================================================

[CmdletBinding()]
param([switch]$Listar)

$ErrorActionPreference = 'Stop'

function Escribir { param([string]$T = '', [string]$C = 'Gray') Write-Host $T -ForegroundColor $C }

# El filtro tiene que ser PRECISO. Con '*gadget.ps1*' pasaban dos cosas feas:
#   1. matcheaba 'cerrar-gadget.ps1', o sea ESTE script se contaba y se mataba;
#   2. matcheaba cualquier powershell que MENCIONE gadget.ps1, como un comando
#      de diagnostico que tenga ese texto en su propia linea de comandos.
# Pidiendo la barra invertida antes ('\gadget.ps1') se descarta 'cerrar-gadget'
# y ademas se excluye el proceso actual por PID.
$procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match '\\gadget\.ps1' })

Escribir
if ($procs.Count -eq 0) {
    Escribir '  No hay ningun gadget corriendo.' 'DarkGray'
    Escribir
    return
}

$palabra = if ($procs.Count -eq 1) { 'instancia' } else { 'instancias' }
Escribir ('  {0} {1} del gadget:' -f $procs.Count, $palabra) 'White'
foreach ($p in $procs) { Escribir ('    pid {0}' -f $p.ProcessId) }
Escribir

if ($Listar) {
    Escribir '  -Listar: no se cerro nada.' 'Cyan'
    Escribir
    return
}

$cerrados = 0
foreach ($p in $procs) {
    try {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
        $cerrados++
    } catch {
        Escribir ('  no pude cerrar el pid {0}: {1}' -f $p.ProcessId, $_.Exception.Message) 'Red'
    }
}

Escribir ('  Cerrado: {0} de {1}' -f $cerrados, $procs.Count) 'Green'
Escribir '  (la posicion y el tamano no se guardaron: fue cierre forzado)' 'DarkGray'
Escribir
