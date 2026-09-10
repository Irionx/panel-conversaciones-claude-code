# =============================================================================
#  Tests de la pieza 5 del instalador: el volcado de la cuota
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
Write-Host '=== las siete piezas siguen ahi ==='

Probar 'Get-EstadoInstalacion devuelve las 7 claves' {
    # La raiz del proyecto, no app\: lib-setup.ps1 mide cosas que cuelgan de la
    # raiz (bin\, skill\, el acceso directo).
    $raizProy = Split-Path -Parent $PSScriptRoot
    $claves = @(Get-EstadoInstalacion -Carpeta $raizProy -Ajustes (Join-Path $tmp 'no-existe.json') |
        ForEach-Object { $_.Clave })
    foreach ($k in 'protocolo', 'path', 'skill', 'shims', 'cuota', 'acceso', 'hud') {
        Afirmar ($claves -contains $k) "falta la pieza '$k'. Hay: $($claves -join ', ')"
    }
    Afirmar ($claves.Count -eq 7) "hay $($claves.Count) piezas, esperaba 7: $($claves -join ', ')"
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
    $esperado = 'protocolo', 'path', 'skill', 'shims', 'cuota', 'acceso', 'hud'
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

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host ("{0} pasados, {1} fallas" -f $script:pasados, $script:fallas)
exit ([int]($script:fallas -gt 0))
