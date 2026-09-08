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
Write-Host '=== las cinco piezas siguen ahi ==='

Probar 'Get-EstadoInstalacion devuelve las 5 claves' {
    $claves = @(Get-EstadoInstalacion -Carpeta $PSScriptRoot -Ajustes (Join-Path $tmp 'no-existe.json') |
        ForEach-Object { $_.Clave })
    foreach ($k in 'protocolo', 'path', 'skill', 'shims', 'cuota') {
        Afirmar ($claves -contains $k) "falta la pieza '$k'. Hay: $($claves -join ', ')"
    }
}

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host ("{0} pasados, {1} fallas" -f $script:pasados, $script:fallas)
exit ([int]($script:fallas -gt 0))
