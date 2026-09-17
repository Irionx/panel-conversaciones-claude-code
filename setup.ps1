# =============================================================================
#  setup.ps1 - Verifica (y si se lo pedis, repara) la instalacion del panel.
#
#  USO
#    .\setup.ps1                    muestra el estado de las ocho piezas
#    .\setup.ps1 -Instalar          repara lo que falte (pide confirmacion)
#    .\setup.ps1 -Instalar -y       sin preguntar
#    .\setup.ps1 -Desinstalar -y    deshace lo que toco (NO toca datos\)
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
    [switch]$Desinstalar,
    [switch]$y
)

$ErrorActionPreference = 'Stop'
$carpeta = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $carpeta 'app\lib-setup.ps1')

function Escribir { param([string]$T = '', [string]$C = 'Gray') Write-Host $T -ForegroundColor $C }

# --- desinstalar --------------------------------------------------------------
#  Va ANTES de medir el estado: desinstalar no necesita saber que falta, y
#  ademas es lo que llama el desinstalador del .exe, que corre sin terminal.
if ($Desinstalar) {
    Escribir
    Escribir '  Desinstalando el panel de conversaciones' 'White'
    Escribir ('  ' + $carpeta) 'DarkGray'
    Escribir
    if (-not $y) {
        Escribir '  Se van a deshacer: el protocolo, bin\ del PATH, la junction del' 'Gray'
        Escribir '  skill, el acceso directo y el volcado de la cuota en tu statusline' 'Gray'
        Escribir '  (ese ultimo solo si lo escribio este instalador y nadie lo edito).' 'Gray'
        Escribir '  Si el panel esta abierto, se cierra. TUS DATOS NO SE TOCAN (datos\).' 'Gray'
        Escribir
        try { $tecleado = Read-Host '  Escribi SI para desinstalar' } catch {
            Escribir '  Esta terminal no permite confirmar. Usa -Desinstalar -y' 'Red'
            Escribir
            exit 1
        }
        if ($tecleado -ne 'SI') { Escribir '  Cancelado.' 'DarkGray'; Escribir; exit 0 }
    }
    # El panel abierto se cierra ANTES: si no, queda flotando en pantalla despues
    # de desinstalar, y encima tiene la carpeta tomada para el desinstalador del
    # .exe, que borra archivos justo despues de llamar aca.
    try { & (Join-Path $carpeta 'app\cerrar-gadget.ps1') | Out-Null } catch { }

    $u = Uninstall-Instalacion -Carpeta $carpeta
    Escribir
    foreach ($h in $u.Hechas) { Escribir ('  deshecho : ' + $h) 'Green' }
    foreach ($a in $u.Avisos) { Escribir ('  aviso    : ' + $a) 'Yellow' }
    foreach ($e in $u.Errores) { Escribir ('  ERROR    : ' + $e) 'Red' }
    if (-not $u.Hechas.Count) { Escribir '  No habia nada instalado apuntando aca.' 'DarkGray' }
    Escribir
    Escribir '  Tus conversaciones siguen en datos\conversaciones.db.' 'Cyan'
    Escribir '  Si tambien las queres borrar, borra esa carpeta a mano: no la toca nadie.' 'DarkGray'
    Escribir '  Y si bajaste el zip, lo que queda es borrar esta carpeta.' 'DarkGray'
    Escribir
    exit ([int]($u.Errores.Count -gt 0))
}

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

# --- el COMO de lo que no se puede arreglar desde aca -------------------------
#  Decir "falta el plugin claude-hud" y no decir como se instala es dejar a la
#  persona en la mitad. Los comandos se MUESTRAN, no se corren: es un plugin de
#  otra persona y Claude Code pide su propia confirmacion.
foreach ($p in @($piezas | Where-Object { -not $_.Ok -and $_.Como })) {
    Escribir ('  Para ' + $p.Nombre + ', en una terminal:') 'Cyan'
    foreach ($c in $p.Como) { Escribir ('      ' + $c) 'White' }
    Escribir '  (despues reinicia Claude Code para que el plugin cargue)' 'DarkGray'
    Escribir
}

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

# --- otra instalacion tiene piezas nuestras? --------------------------------
#  El protocolo, la junction del skill y bin\ en el PATH son de SLOT UNICO en el
#  sistema: no hay forma de que dos copias los tengan a la vez. No se bloquea la
#  instalacion, pero se dice de quien son antes de que la persona escriba SI.
$ajenas = @($faltan | Where-Object { $_.Detalle -match 'lo tiene otra carpeta|la junction la tiene otra' })
if ($ajenas.Count -gt 0) {
    Escribir '  OJO: otra instalacion del panel tiene estas piezas:' 'Yellow'
    foreach ($a in $ajenas) { Escribir ('    ' + $a.Detalle) 'DarkGray' }
    Escribir '  Son de slot unico. Si sigo, pasan a apuntar aca y esa otra copia queda' 'Yellow'
    Escribir '  sin /save y sin claudeconv:// hasta que corras SU setup.ps1.' 'Yellow'
    Escribir
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
# Aviso y no ERROR: son piezas que no se pueden arreglar desde aca. Pintarlas de
# rojo hacia que una instalacion perfecta pareciera fallada.
foreach ($a in $r.Avisos) { Escribir ('  aviso     : ' + $a) 'Yellow' }
foreach ($e in $r.Errores) { Escribir ('  ERROR     : ' + $e) 'Red' }
Escribir

if ($tocoPath -and $r.Hechas.Count -gt 0) {
    Escribir '  El PATH cambio: abri una terminal nueva para que aparezcan los comandos.' 'Cyan'
    Escribir '  (los procesos ya abiertos, Claude Code incluido, siguen con el PATH viejo)' 'DarkGray'
    Escribir
}

if ($r.Errores.Count -gt 0) { exit 1 }
