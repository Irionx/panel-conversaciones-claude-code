# =============================================================================
#  Tests del instalador: el volcado de la cuota (pieza 5) y el lanzador (pieza 6)
# -----------------------------------------------------------------------------
#  Se corre a mano:  powershell -NoProfile -File lib-setup.Tests.ps1
#  Sale 0 si todo pasa, 1 si algo falla.
#
#  Todo contra settings.json de MENTIRA en el temp. El de verdad no se toca:
#  este arreglo le mete mano a la configuracion de Claude Code del usuario, y
#  probarlo contra el archivo real seria jugar a la ruleta con su terminal.
#
#  Tres casos, y el del medio es el que importa: si alguien ya tiene su
#  statusline, hay que ENVOLVERLO, no pisarlo.
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

. (Join-Path $PSScriptRoot 'lib-setup.ps1')

$tmp = Join-Path $env:TEMP ("setup-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

function Nuevo-Ajustes([string]$Contenido) {
    $f = Join-Path $tmp ("s" + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.json')
    [System.IO.File]::WriteAllText($f, $Contenido, [System.Text.UTF8Encoding]::new($false))
    $f
}
function Pieza-Cuota([string]$Ajustes) {
    Get-EstadoInstalacion -Carpeta $PSScriptRoot -Ajustes $Ajustes |
    Where-Object { $_.Clave -eq 'cuota' }
}

Write-Host ''
Write-Host '=== deteccion ==='

Probar 'sin settings.json: avisa y no ofrece arreglo' {
    $p = Pieza-Cuota (Join-Path $tmp 'no-existe.json')
    Afirmar (-not $p.Ok) 'dijo que estaba ok'
    Afirmar ($null -eq $p.Arreglar) 'ofrecio arreglar algo que no existe'
}
Probar 'con statusline ajeno: detecta que falta el volcado' {
    $f = Nuevo-Ajustes '{ "statusLine": { "type": "command", "command": "mi-hud --lindo" } }'
    $p = Pieza-Cuota $f
    Afirmar (-not $p.Ok) 'dijo que estaba ok'
    Afirmar ($null -ne $p.Arreglar) 'no ofrecio arreglarlo'
}
Probar 'ya instalado: no lo vuelve a tocar' {
    $f = Nuevo-Ajustes '{ "statusLine": { "type": "command", "command": "cosas > $cc_cfg/statusline-ultimo.json" } }'
    Afirmar (Pieza-Cuota $f).Ok 'no reconocio que ya estaba'
}

Write-Host ''
Write-Host '=== el arreglo ==='

Probar 'ENVUELVE el statusline ajeno en vez de pisarlo' {
    $f = Nuevo-Ajustes @'
{
  "algoMio": 123,
  "statusLine": { "type": "command", "command": "mi-hud --lindo \"con comillas\"" },
  "otraCosa": { "anidado": true }
}
'@
    & (Pieza-Cuota $f).Arreglar
    $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
    $cmd = [string]$j.statusLine.command

    Afirmar ($cmd.Contains('mi-hud --lindo "con comillas"')) `
        "se llevo puesto el statusline del usuario: $cmd"
    Afirmar ($cmd.Contains('statusline-ultimo.json')) 'no agrego el volcado'
    # El volcado tiene que ir ANTES: si va despues, ya se consumio el stdin.
    Afirmar ($cmd.IndexOf('statusline-ultimo.json') -lt $cmd.IndexOf('mi-hud')) `
        'puso el volcado DESPUES del comando: el stdin ya estaria consumido'
    # Y el resto del archivo intacto
    Afirmar ($j.algoMio -eq 123 -and $j.otraCosa.anidado -eq $true) 'toco otras claves del settings'
}
Probar 'deja un .bak antes de tocar nada' {
    $f = Nuevo-Ajustes '{ "statusLine": { "type": "command", "command": "algo" } }'
    & (Pieza-Cuota $f).Arreglar
    Afirmar (Test-Path -LiteralPath ($f + '.bak')) 'no dejo respaldo'
}
Probar 'sin statusline: agrega uno que solo vuelca' {
    $f = Nuevo-Ajustes "{`n  `"algoMio`": 1`n}"
    & (Pieza-Cuota $f).Arreglar
    $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
    Afirmar ($null -ne $j.statusLine) 'no agrego statusLine'
    Afirmar ([string]$j.statusLine.command).Contains('statusline-ultimo.json') 'no vuelca'
    Afirmar ($j.algoMio -eq 1) 'se llevo puesta la otra clave'
}
Probar 'despues de arreglar, la deteccion dice que ya esta (idempotente)' {
    $f = Nuevo-Ajustes '{ "statusLine": { "type": "command", "command": "mi-hud" } }'
    & (Pieza-Cuota $f).Arreglar
    Afirmar (Pieza-Cuota $f).Ok 'no se reconoce a si mismo: correrlo dos veces envolveria dos veces'
    $antes = Get-Content -LiteralPath $f -Raw
    $p = Pieza-Cuota $f
    if (-not $p.Ok -and $p.Arreglar) { & $p.Arreglar }
    Afirmar ((Get-Content -LiteralPath $f -Raw) -ceq $antes) 'la segunda pasada modifico el archivo'
}
Probar 'nunca deja un settings.json invalido' {
    $f = Nuevo-Ajustes '{ "statusLine": { "type": "command", "command": "mi-hud" } }'
    & (Pieza-Cuota $f).Arreglar
    $null = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json   # tira si es invalido
}

Write-Host ''
Write-Host '=== deshacer el volcado, al desinstalar ==='

Probar 'deshace el envoltorio y devuelve el statusline original' {
    $f = Nuevo-Ajustes '{ "statusLine": { "type": "command", "command": "mi-hud --lindo \"con comillas\"" }, "otra": 1 }'
    & (Pieza-Cuota $f).Arreglar
    $txt = [System.IO.File]::ReadAllText($f)
    $cmd = [string]($txt | ConvertFrom-Json).statusLine.command
    $r = Get-AjustesSinVolcado -Texto $txt -Comando $cmd
    Afirmar ($null -ne $r.Texto) ('no lo deshizo: ' + ($r.Como -join ' '))
    $j = $r.Texto | ConvertFrom-Json
    Afirmar ($j.statusLine.command -ceq 'mi-hud --lindo "con comillas"') ('quedo: ' + $j.statusLine.command)
    Afirmar ($j.otra -eq 1) 'se llevo otra clave del archivo'
}
Probar 'si el volcado lo agregamos nosotros, saca el bloque entero' {
    $f = Nuevo-Ajustes '{ "algoMio": 123 }'
    & (Pieza-Cuota $f).Arreglar
    $txt = [System.IO.File]::ReadAllText($f)
    $cmd = [string]($txt | ConvertFrom-Json).statusLine.command
    $r = Get-AjustesSinVolcado -Texto $txt -Comando $cmd
    Afirmar ($null -ne $r.Texto) ('no lo deshizo: ' + ($r.Como -join ' '))
    $j = $r.Texto | ConvertFrom-Json
    Afirmar ($null -eq $j.statusLine) 'dejo la clave statusLine que agrego el instalador'
    Afirmar ($j.algoMio -eq 123) 'se llevo lo que ya estaba en el archivo'
}
Probar 'un statusline editado a mano NO se toca' {
    # Medido en la maquina de desarrollo: un statusline que ENTRETEJE el volcado
    # con el comando del HUD en vez de dejarlo envuelto. Desarmar eso a ciegas
    # le rompe el statusline a la persona, asi que no se toca y se explica.
    $mano = 'cfg="$HOME/.claude"; pl=$(cat); printf ''%s'' "$pl" > "$cfg/statusline-ultimo.json"; printf ''%s'' "$pl" | node hud.js'
    $r = Get-AjustesSinVolcado -Texto '{ "statusLine": { "command": "x" } }' -Comando $mano
    Afirmar ($null -eq $r.Texto) 'toco un statusline que no escribio el instalador'
    Afirmar ($r.Como.Count -ge 1) 'no explico como sacarlo a mano'
}
Probar 'ida y vuelta: instalar y desinstalar deja el archivo igual que antes' {
    $antes = '{ "statusLine": { "type": "command", "command": "mi-hud" }, "z": true }'
    $f = Nuevo-Ajustes $antes
    & (Pieza-Cuota $f).Arreglar
    $txt = [System.IO.File]::ReadAllText($f)
    $r = Get-AjustesSinVolcado -Texto $txt -Comando ([string]($txt | ConvertFrom-Json).statusLine.command)
    Afirmar ($r.Texto -ceq $antes) ("no volvio al original.`n        antes: $antes`n        ahora: $($r.Texto)")
}

Write-Host ''
Write-Host '=== las ocho piezas siguen ahi ==='

Probar 'Get-EstadoInstalacion devuelve las 8 claves' {
    # La raiz del proyecto, no app\: lib-setup.ps1 mide cosas que cuelgan de la
    # raiz (bin\, skill\, el acceso directo).
    $raizProy = Split-Path -Parent $PSScriptRoot
    $claves = @(Get-EstadoInstalacion -Carpeta $raizProy -Ajustes (Join-Path $tmp 'no-existe.json') |
        ForEach-Object { $_.Clave })
    foreach ($k in 'protocolo', 'path', 'skill', 'shims', 'cuota', 'lanzador', 'acceso', 'hud') {
        Afirmar ($claves -contains $k) "falta la pieza '$k'. Hay: $($claves -join ', ')"
    }
    Afirmar ($claves.Count -eq 8) "hay $($claves.Count) piezas, esperaba 8: $($claves -join ', ')"
}
Probar 'las piezas que no se pueden arreglar solas lo declaran' {
    $raizProy = Split-Path -Parent $PSScriptRoot
    $p = @(Get-EstadoInstalacion -Carpeta $raizProy -Ajustes (Join-Path $tmp 'no-existe.json'))
    # claude-hud es un plugin de Claude Code: no es nuestro para instalar. Tiene
    # que venir con Arreglar = $null para que Repair-Instalacion no lo intente y
    # reporte un error falso.
    $hud = $p | Where-Object { $_.Clave -eq 'hud' }
    Afirmar ($null -eq $hud.Arreglar) 'la pieza hud dice que se puede arreglar sola, y no'
}
Probar 'si falta claude-hud, dice COMO instalarlo' {
    # Con -CacheHud a una ruta que no existe: en la maquina del que desarrolla
    # esto el plugin esta siempre instalado, asi que sin el parametro el caso
    # "falta" no se podria probar nunca. Misma idea que -Ajustes.
    $raizProy = Split-Path -Parent $PSScriptRoot
    $hud = @(Get-EstadoInstalacion -Carpeta $raizProy -Ajustes (Join-Path $tmp 'no-existe.json') `
            -CacheHud (Join-Path $tmp 'no-hay-hud')) | Where-Object { $_.Clave -eq 'hud' }
    Afirmar (-not $hud.Ok) 'dijo que el plugin estaba'
    Afirmar ($null -eq $hud.Arreglar) 'ofrecio instalarlo solo, y no es nuestro para instalar'
    Afirmar ($hud.Como.Count -ge 1) 'avisa que falta pero no dice como resolverlo'
    Afirmar ((($hud.Como) -join ' ') -match 'claude-hud') 'el como no menciona el plugin'
}
Probar 'si claude-hud esta, no molesta con el como' {
    $raizProy = Split-Path -Parent $PSScriptRoot
    $falso = Join-Path $tmp 'hud-falso'
    New-Item -ItemType Directory -Path $falso -Force | Out-Null
    $hud = @(Get-EstadoInstalacion -Carpeta $raizProy -Ajustes (Join-Path $tmp 'no-existe.json') `
            -CacheHud $falso) | Where-Object { $_.Clave -eq 'hud' }
    Afirmar ($hud.Ok) 'no reconocio el cache del plugin'
    Afirmar ($hud.Como.Count -eq 0) 'sigue explicando como instalar algo que ya esta'
}

Probar 'las devuelve en el orden que documenta la cabecera' {
    # El orden es lo que ve la persona en setup.ps1. El hud va ULTIMO: es el
    # unico que no se puede arreglar desde aca, y en el medio de la lista
    # parecia un paso mas de la instalacion.
    $raizProy = Split-Path -Parent $PSScriptRoot
    $claves = @(Get-EstadoInstalacion -Carpeta $raizProy -Ajustes (Join-Path $tmp 'no-existe.json') |
        ForEach-Object { $_.Clave })
    $esperado = 'protocolo', 'path', 'skill', 'shims', 'cuota', 'lanzador', 'acceso', 'hud'
    Afirmar (($claves -join ',') -eq ($esperado -join ',')) "salieron en este orden: $($claves -join ', ')"
}

Write-Host ''
Write-Host '=== un aviso no es un error ==='

Probar 'una pieza sin arreglo posible va a Avisos y NO a Errores' {
    # Es LA razon de que exista Avisos: sin esto, cualquier maquina sin el
    # plugin claude-hud terminaba una instalacion perfecta en rojo y con exit 1,
    # y el .exe corre justamente setup.ps1 -Instalar -y.
    $r = Repair-Instalacion -Piezas @(
        [pscustomobject]@{ Clave = 'hud'; Nombre = 'plugin claude-hud'; Ok = $false
            Detalle = 'no esta'; Arreglar = $null })
    Afirmar ($r.Errores.Count -eq 0) "lo conto como error: $($r.Errores -join '; ')"
    Afirmar ($r.Avisos.Count -eq 1) 'no quedo el aviso'
    Afirmar ($r.Hechas.Count -eq 0) 'dijo que instalo algo'
}
Probar 'un arreglo que explota SI es un error' {
    $r = Repair-Instalacion -Piezas @(
        [pscustomobject]@{ Clave = 'x'; Nombre = 'pieza de prueba'; Ok = $false
            Detalle = 'falta'; Arreglar = { throw 'no pude' } })
    Afirmar ($r.Errores.Count -eq 1) 'se comio el error'
    Afirmar ($r.Avisos.Count -eq 0) 'un fallo real quedo como aviso'
}
Probar 'una pieza que ya estaba ok no se toca' {
    $r = Repair-Instalacion -Piezas @(
        [pscustomobject]@{ Clave = 'x'; Nombre = 'ya estaba'; Ok = $true
            Detalle = 'ok'; Arreglar = { throw 'esto no tendria que correr' } })
    Afirmar (($r.Hechas.Count + $r.Errores.Count + $r.Avisos.Count) -eq 0) 'toco una pieza que estaba ok'
}

Write-Host ''
Write-Host '=== el lanzador (pieza 6) ==='

# Una raiz de mentira con el lanzador de verdad y dos ESPIAS en lugar de
# gadget.ps1 y abrir-conversacion.ps1: anotan si tienen ventana de consola y que
# les llego. El gadget real no se abre nunca.
$raizL = Join-Path $tmp 'raiz-lanzador'
$appL = Join-Path $raizL 'app'
New-Item -ItemType Directory -Path $appL -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'lanzador.cs'), (Join-Path $PSScriptRoot 'gadget.ico') -Destination $appL
$espia = @'
Add-Type -Namespace '' -Name Espia -MemberDefinition '[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();'
$destino = Join-Path (Split-Path -Parent $PSScriptRoot) ('espia-' + [IO.Path]::GetFileNameWithoutExtension($PSCommandPath) + '.json')
@{ consola = [int64][Espia]::GetConsoleWindow(); url = $Url
    linea = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID").CommandLine } |
    ConvertTo-Json | Set-Content -LiteralPath ($destino + '.tmp')
Move-Item -LiteralPath ($destino + '.tmp') -Destination $destino
'@
Set-Content -LiteralPath (Join-Path $appL 'gadget.ps1') -Value $espia -Encoding UTF8
Set-Content -LiteralPath (Join-Path $appL 'abrir-conversacion.ps1') -Value ("param([string]`$Url)`r`n" + $espia) -Encoding UTF8

function Esperar-Espia([string]$Nombre) {
    $f = Join-Path $raizL ('espia-' + $Nombre + '.json')
    $limite = (Get-Date).AddSeconds(45)
    while (-not (Test-Path -LiteralPath $f) -and (Get-Date) -lt $limite) { Start-Sleep -Milliseconds 200 }
    if (-not (Test-Path -LiteralPath $f)) { throw "el script no arranco en 45s ($Nombre)" }
    return (Get-Content -LiteralPath $f -Raw | ConvertFrom-Json)
}
function Pieza-De([string]$Clave) {
    @(Get-EstadoInstalacion -Carpeta $raizL -Ajustes (Join-Path $tmp 'no-existe.json')) |
    Where-Object { $_.Clave -eq $Clave }
}

Probar 'compila, y sale como app de VENTANAS, no de consola' {
    Build-Lanzador -Carpeta $raizL
    $exe = Get-RutaLanzador -Carpeta $raizL
    Afirmar (Test-Path -LiteralPath $exe) 'no dejo Conversaciones.exe'
    # Subsistema del PE: 2 = ventanas, 3 = consola. Es TODO el punto: uno de
    # consola haria aparecer la misma ventana que se quiere sacar.
    $b = [System.IO.File]::ReadAllBytes($exe)
    $sub = [BitConverter]::ToUInt16($b, [BitConverter]::ToInt32($b, 0x3C) + 92)
    Afirmar ($sub -eq 2) "subsistema $sub, esperaba 2 (ventanas)"
}
Probar 'la pieza lo ve al dia, y desactualizado si cambia lanzador.cs' {
    $p = Pieza-De 'lanzador'
    Afirmar $p.Ok ('recien compilado y dice: ' + $p.Detalle)
    $cs = Join-Path $appL 'lanzador.cs'
    [System.IO.File]::AppendAllText($cs, "`r`n// cambio")
    try {
        $p = Pieza-De 'lanzador'
        Afirmar (-not $p.Ok) 'cambio el codigo y no lo noto: quedaria andando el lanzador viejo'
        Afirmar ($null -ne $p.Arreglar) 'no ofrece recompilarlo'
    } finally {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'lanzador.cs') -Destination $cs -Force
    }
}
Probar 'arranca el gadget SIN ventana de consola' {
    [void][System.Diagnostics.Process]::Start((Get-RutaLanzador -Carpeta $raizL))
    $e = Esperar-Espia 'gadget'
    # 0 = no hay ventana de consola, ni propia ni prestada a Windows Terminal.
    Afirmar ($e.consola -eq 0) "el script tiene ventana de consola (hwnd $($e.consola))"
    # gadget.ps1 y cerrar-gadget.ps1 reconocen al gadget vivo por esta linea.
    Afirmar ($e.linea -match '-File "(.+)\\app\\gadget\.ps1"') "cambio la linea de comando: $($e.linea)"
}
Probar '--abrir le pasa la URL intacta, con espacios y &' {
    $url = 'claudeconv://abrir?id=prueba-1&remoto=1&x=a%20b c'
    [void][System.Diagnostics.Process]::Start((Get-RutaLanzador -Carpeta $raizL), ('--abrir "{0}"' -f $url))
    $e = Esperar-Espia 'abrir-conversacion'
    Afirmar ($e.consola -eq 0) "el handler del protocolo tiene ventana de consola (hwnd $($e.consola))"
    Afirmar ($e.url -ceq $url) "llego [$($e.url)], esperaba [$url]"
}
Probar 'un acceso directo viejo (powershell.exe directo) se detecta y se migra' {
    # Es el caso de TODAS las instalaciones anteriores a esta pieza.
    $lnk = Join-Path $raizL 'Gadget de conversaciones.lnk'
    $sh = New-Object -ComObject WScript.Shell
    $l = $sh.CreateShortcut($lnk)
    $l.TargetPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $l.Arguments = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}\app\gadget.ps1"' -f $raizL)
    $l.Save()
    $p = Pieza-De 'acceso'
    Afirmar (-not $p.Ok) 'dio por bueno un acceso que abre powershell.exe directo'
    Afirmar ($p.Detalle -match 'PowerShell directo') "no dice por que esta mal: $($p.Detalle)"
    & $p.Arreglar
    $l = $sh.CreateShortcut($lnk)
    Afirmar ($l.TargetPath -ieq (Get-RutaLanzador -Carpeta $raizL)) "quedo apuntando a $($l.TargetPath)"
    Afirmar (-not $l.Arguments) "le quedaron argumentos: $($l.Arguments)"
    $p = Pieza-De 'acceso'
    Afirmar $p.Ok ('migrado y sigue mal: ' + $p.Detalle)
}


Write-Host ''
Write-Host '=== los arreglos, invocados como los invoca una persona ==='

Probar 'shims, cuota y lanzador se arreglan al correr ".\setup.ps1"' {
    # Bug que rompia la instalacion de cualquiera: .GetNewClosure() ata el
    # scriptblock a un modulo nuevo, que solo ve el scope global. Si lib-setup
    # se dot-sourcea en un scope HIJO -- lo que pasa al tipear ".\setup.ps1" --
    # sus funciones no llegan y el arreglo muere con "el termino X no se
    # reconoce". Se escapo porque los otros tests llaman a Build-Lanzador
    # directo, y porque con "powershell -File" el bug NO aparece.
    $raizC = Join-Path $tmp 'raiz-closure'
    New-Item -ItemType Directory -Path (Join-Path $raizC 'app') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'lanzador.cs') -Destination (Join-Path $raizC 'app\lanzador.cs')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'gadget.ico') -Destination (Join-Path $raizC 'app\gadget.ico')
    $ajustesC = Join-Path $raizC 'settings.json'
    Set-Content -LiteralPath $ajustesC -Encoding UTF8 `
        -Value '{ "statusLine": { "type": "command", "command": "algun-hud" } }'

    $drv = Join-Path $raizC 'correr.ps1'
    Set-Content -LiteralPath $drv -Encoding UTF8 -Value @"
`$ErrorActionPreference = 'Stop'
. '$(Join-Path $PSScriptRoot 'lib-setup.ps1')'
`$p = @(Get-EstadoInstalacion -Carpeta '$raizC' -Ajustes '$ajustesC' -CacheHud '$(Join-Path $raizC 'sin-hud')') |
    Where-Object { `$_.Clave -in @('shims', 'cuota', 'lanzador') }
(Repair-Instalacion -Piezas `$p).Errores -join ' | '
"@

    # -Command y NO -File: con -File el dot-source cae en el scope de nivel
    # superior, las funciones se ven y el bug no aparece. Este es el camino que
    # usa la gente, y el unico que lo destapa.
    $salida = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '$drv'" 2>&1) -join ' '
    Afirmar ($salida -notmatch 'no se reconoce') ("el arreglo no vio sus funciones: " + $salida)
    Afirmar (Test-Path -LiteralPath (Join-Path $raizC 'app\Conversaciones.exe')) 'no compilo el lanzador'
    Afirmar (Test-Path -LiteralPath (Join-Path $raizC 'bin\guardar')) 'no escribio los shims'
    Afirmar ((Get-Content -LiteralPath $ajustesC -Raw) -match 'statusline-ultimo') 'no envolvio el statusline'
}
Probar 'ningun Arreglar llama a una funcion de lib-setup.ps1 por nombre' {
    # El test de arriba prueba las tres piezas que se rompieron; este cubre la
    # pieza que alguien agregue manana. Adentro de un .GetNewClosure() el nombre
    # no resuelve: la funcion tiene que viajar capturada en una variable.
    $f = Join-Path $PSScriptRoot 'lib-setup.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$null)
    $mias = @{}
    foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        $mias[$fn.Name] = $true
    }
    $closures = $ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
            $args[0].Member.Value -eq 'GetNewClosure' }, $true)
    Afirmar ($closures.Count -ge 5) "esperaba varios closures, encontre $($closures.Count)"
    foreach ($c in $closures) {
        foreach ($cmd in $c.Expression.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)) {
            $n = $cmd.GetCommandName()
            if ($n -and $mias.ContainsKey($n)) {
                throw "linea $($cmd.Extent.StartLineNumber): el closure llama a $n por nombre; capturala con `${function:$n}"
            }
        }
    }
}
Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host ("{0} pasados, {1} fallas" -f $script:pasados, $script:fallas)
exit ([int]($script:fallas -gt 0))
