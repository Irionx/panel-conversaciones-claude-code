# =============================================================================
#  Tests del cambio de cuenta de Claude Code
# -----------------------------------------------------------------------------
#  Se corre a mano:  powershell -NoProfile -File lib-cuentas.Tests.ps1
#  Sale 0 si todo pasa, 1 si algo falla.
#
#  Todo contra carpetas de MENTIRA en el temp. La config real de Claude Code no
#  se toca: esto reescribe la credencial de la persona, y probarlo contra el
#  archivo de verdad seria dejarla afuera de su propia sesion.
#
#  El test que importa es el viaje redondo: ir a otra cuenta y volver tiene que
#  dejar la credencial byte a byte como estaba, y el resto de .claude.json --que
#  tiene el estado de todos los proyectos-- sin una coma de diferencia.
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

. (Join-Path $PSScriptRoot 'lib-cuentas.ps1')

$tmp = Join-Path $env:TEMP ("cuentas-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

$script:dentroDe30Dias = [DateTimeOffset]::UtcNow.AddDays(30).ToUnixTimeMilliseconds()
$script:ayer = [DateTimeOffset]::UtcNow.AddDays(-1).ToUnixTimeMilliseconds()

function Texto-Credencial([string]$Token, [int64]$Vence) {
    '{"claudeAiOauth":{"accessToken":"' + $Token + '","refreshToken":"r-' + $Token +
    '","expiresAt":' + $Vence + ',"refreshTokenExpiresAt":' + $Vence +
    ',"scopes":["user:inference","user:profile"],"subscriptionType":"max"}}'
}

# Con ruido adelante y atras a proposito: .claude.json de verdad trae el estado
# de todos los proyectos, y hay que probar que sobrevive intacto.
function Texto-Ajustes([string]$Mail, [string]$Uid, [string]$Ruido = 'inicial') {
    '{"numStartups":42,"proyectoRuido":"' + $Ruido +
    '","projects":{"C:\\repo":{"history":["una","otra"],"allowedTools":[]}},' +
    '"userID":"' + $Uid + '","oauthAccount":{"accountUuid":"u-' + $Uid +
    '","emailAddress":"' + $Mail + '","organizationName":"Org de ' + $Mail +
    '","billingType":"max","displayName":"Nombre ' + $Mail + '"},"tipsHistory":{"x":1}}'
}

function Nuevo-Claude {
    $dir = Join-Path $tmp ([guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}
function Poner-Sesion([string]$Dir, [string]$Mail, [string]$Token, [int64]$Vence, [string]$Ruido = 'inicial') {
    [IO.File]::WriteAllText((Join-Path $Dir '.credentials.json'), (Texto-Credencial $Token $Vence), $utf8)
    [IO.File]::WriteAllText((Join-Path $Dir '.claude.json'), (Texto-Ajustes $Mail $Token $Ruido), $utf8)
}
function Leer([string]$Ruta) { [IO.File]::ReadAllText($Ruta) }

Write-Host ''
Write-Host '=== cirugia sobre el JSON ==='

Probar 'ubica el tramo exacto de un objeto anidado' {
    $t = '{"a":1,"oauthAccount":{"x":{"y":2},"z":3},"b":4}'
    $r = Get-TramoJson -Texto $t -Clave 'oauthAccount'
    Afirmar ($null -ne $r) 'no lo encontro'
    Afirmar ($r.Json -ceq '{"x":{"y":2},"z":3}') "corto mal: $($r.Json)"
}
Probar 'ubica el tramo de un string' {
    $r = Get-TramoJson -Texto '{"userID":"abc-123","otra":1}' -Clave 'userID'
    Afirmar ($r.Json -ceq '"abc-123"') "corto mal: $($r.Json)"
}
Probar 'las llaves adentro de un string no desarman el conteo' {
    $t = '{"oauthAccount":{"nombre":"llave } falsa","n":1},"fin":2}'
    $r = Get-TramoJson -Texto $t -Clave 'oauthAccount'
    Afirmar ($r.Json -ceq '{"nombre":"llave } falsa","n":1}') "corto mal: $($r.Json)"
}
Probar 'una comilla escapada tampoco' {
    $t = '{"oauthAccount":{"nombre":"dice \" y sigue }","n":1},"fin":2}'
    $r = Get-TramoJson -Texto $t -Clave 'oauthAccount'
    Afirmar ($r.Json -ceq '{"nombre":"dice \" y sigue }","n":1}') "corto mal: $($r.Json)"
}
Probar 'si la clave aparece dos veces NO se toca nada' {
    $t = '{"userID":"a","hijo":{"userID":"b"}}'
    Afirmar ($null -eq (Get-TramoJson -Texto $t -Clave 'userID')) 'eligio una de las dos'
    Afirmar ($null -eq (Set-TramoJson -Texto $t -Clave 'userID' -Json '"z"')) 'empalmo igual'
}
Probar 'si la clave no esta, tampoco' {
    Afirmar ($null -eq (Get-TramoJson -Texto '{"a":1}' -Clave 'userID')) 'invento un tramo'
}
Probar 'el empalme deja el resto del texto byte a byte' {
    $t = '{"antes":"no me toques","oauthAccount":{"v":1},"despues":"a mi tampoco"}'
    $n = Set-TramoJson -Texto $t -Clave 'oauthAccount' -Json '{"v":2,"mas":true}'
    Afirmar ($n -ceq '{"antes":"no me toques","oauthAccount":{"v":2,"mas":true},"despues":"a mi tampoco"}') "quedo: $n"
}

Write-Host ''
Write-Host '=== vencimientos ==='

Probar 'manda el refresh token, no el access' {
    # El access vencio hace rato y el refresh sigue vivo: la cuenta sirve, porque
    # Claude renueva el access solo mientras el refresh este bueno.
    $c = '{"claudeAiOauth":{"expiresAt":' + $script:ayer + ',"refreshTokenExpiresAt":' + $script:dentroDe30Dias + '}}'
    $v = Get-VencimientoCredencial $c
    Afirmar (-not $v.Vencida) 'la dio por vencida mirando el access'
    Afirmar ($v.Dias -ge 28) "calculo mal los dias: $($v.Dias)"
}
Probar 'sin credencial se considera vencida' {
    Afirmar ((Get-VencimientoCredencial $null).Vencida) 'dijo que una credencial que no existe sirve'
    Afirmar ((Get-VencimientoCredencial 'esto no es json').Vencida) 'se trago un archivo roto'
}

Write-Host ''
Write-Host '=== archivar la cuenta viva ==='

Probar 'archiva bajo el slug del mail' {
    $d = Nuevo-Claude
    Poner-Sesion $d 'ana@empresa.com' 'tok-ana' $script:dentroDe30Dias
    $r = Save-CuentaViva -Claude $d
    Afirmar ($null -ne $r) 'no archivo nada'
    Afirmar (Test-Path (Join-Path $d 'cuentas\ana-empresa-com.json')) "no esta el archivo: $r"
}
Probar 'no reescribe si no cambio nada' {
    $d = Nuevo-Claude
    Poner-Sesion $d 'ana@empresa.com' 'tok-ana' $script:dentroDe30Dias
    $f = Save-CuentaViva -Claude $d
    $antes = (Get-Item $f).LastWriteTimeUtc.Ticks
    Start-Sleep -Milliseconds 30
    Save-CuentaViva -Claude $d | Out-Null
    Afirmar ((Get-Item $f).LastWriteTimeUtc.Ticks -eq $antes) 'reescribio el archivo sin motivo'
}
Probar 'si el token se renovo, vuelve a archivarlo' {
    $d = Nuevo-Claude
    Poner-Sesion $d 'ana@empresa.com' 'tok-viejo' $script:dentroDe30Dias
    $f = Save-CuentaViva -Claude $d
    Poner-Sesion $d 'ana@empresa.com' 'tok-nuevo' $script:dentroDe30Dias
    Save-CuentaViva -Claude $d | Out-Null
    $o = Leer $f | ConvertFrom-Json
    Afirmar ($o.credencialTexto -match 'tok-nuevo') 'se quedo con la foto vieja del token'
}
Probar 'sin sesion iniciada no archiva ni explota' {
    $d = Nuevo-Claude
    Afirmar ($null -eq (Save-CuentaViva -Claude $d)) 'archivo algo que no existe'
    Afirmar ((@(Get-Cuentas -Claude $d)).Count -eq 0) 'listo cuentas de la nada'
}

Write-Host ''
Write-Host '=== la lista ==='

Probar 'con UNA sola cuenta sigue devolviendo un array' {
    # Se llama con @() igual que la UI. Sin el, un array de un elemento se
    # desarma al retornarlo y el dialogo termina iterando las letras del mail.
    $d = Nuevo-Claude
    Poner-Sesion $d 'ana@empresa.com' 'tok-ana' $script:dentroDe30Dias
    $l = @(Get-Cuentas -Claude $d)
    Afirmar ($l -is [array]) 'no devolvio un array'
    Afirmar ($l.Count -eq 1) "conto $($l.Count)"
    Afirmar ($l[0].Mail -is [string]) 'el mail no quedo como texto'
}
Probar 'el @() de quien llama NO anida la lista' {
    # El bug que se vio en pantalla: con `return , @(...)` adentro de la funcion
    # Y un @() afuera, las dos protecciones se cancelan y queda UN elemento que
    # ES la lista entera. La fila salia con los dos mails pegados y
    # "System.Object[]" donde va la organizacion.
    $d = Nuevo-Claude
    Poner-Sesion $d 'zoe@empresa.com' 'tok-zoe' $script:dentroDe30Dias
    Get-Cuentas -Claude $d | Out-Null
    Poner-Sesion $d 'ana@empresa.com' 'tok-ana' $script:dentroDe30Dias
    $l = @(Get-Cuentas -Claude $d)
    Afirmar ($l.Count -eq 2) "con @() conto $($l.Count) en vez de 2"
    foreach ($c in $l) {
        Afirmar ($c -is [hashtable]) "un elemento vino como $($c.GetType().Name)"
        Afirmar ($c.Mail -is [string]) "el mail vino como $($c.Mail.GetType().Name)"
    }
}
Probar 'marca cual es la activa y la pone primera' {
    $d = Nuevo-Claude
    Poner-Sesion $d 'zoe@empresa.com' 'tok-zoe' $script:dentroDe30Dias
    Get-Cuentas -Claude $d | Out-Null
    Poner-Sesion $d 'ana@empresa.com' 'tok-ana' $script:dentroDe30Dias
    $l = @(Get-Cuentas -Claude $d)
    Afirmar ($l.Count -eq 2) "conto $($l.Count)"
    Afirmar ($l[0].Mail -ceq 'ana@empresa.com') "la primera fue $($l[0].Mail)"
    Afirmar ($l[0].Activa) 'no marco la activa'
    Afirmar (-not $l[1].Activa) 'marco activa a la que no lo es'
}
Probar 'trae el nombre, la org y el vencimiento de cada una' {
    $d = Nuevo-Claude
    Poner-Sesion $d 'ana@empresa.com' 'tok-ana' $script:dentroDe30Dias
    $c = (@(Get-Cuentas -Claude $d))[0]
    Afirmar ($c.Org -ceq 'Org de ana@empresa.com') "org: $($c.Org)"
    Afirmar (-not $c.Vencida) 'la dio por vencida'
    Afirmar ($c.Dias -ge 28) "dias: $($c.Dias)"
}

Write-Host ''
Write-Host '=== el cambio ==='

Probar 'cambiar deja la credencial de la otra cuenta, byte a byte' {
    $d = Nuevo-Claude
    Poner-Sesion $d 'ana@empresa.com' 'tok-ana' $script:dentroDe30Dias
    $credAna = Leer (Join-Path $d '.credentials.json')
    Get-Cuentas -Claude $d | Out-Null

    Poner-Sesion $d 'zoe@empresa.com' 'tok-zoe' $script:dentroDe30Dias
    Get-Cuentas -Claude $d | Out-Null

    $r = Switch-Cuenta -Mail 'ana@empresa.com' -Claude $d
    Afirmar ($r.Ok) "no cambio: $($r.Avisos -join '; ')"
    Afirmar ((Leer (Join-Path $d '.credentials.json')) -ceq $credAna) 'la credencial no quedo identica'
}
Probar 'y deja la identidad de esa cuenta en .claude.json' {
    $d = Nuevo-Claude
    Poner-Sesion $d 'ana@empresa.com' 'tok-ana' $script:dentroDe30Dias
    Get-Cuentas -Claude $d | Out-Null
    Poner-Sesion $d 'zoe@empresa.com' 'tok-zoe' $script:dentroDe30Dias
    Get-Cuentas -Claude $d | Out-Null

    Switch-Cuenta -Mail 'ana@empresa.com' -Claude $d | Out-Null
    $viva = Get-CuentaViva -Claude $d
    Afirmar ($viva.Mail -ceq 'ana@empresa.com') "el panel seguiria mostrando $($viva.Mail)"
    Afirmar ((Leer (Join-Path $d '.claude.json')) -match '"userID":"tok-ana"') 'no cambio el userID'
}
Probar 'el resto de .claude.json sobrevive sin una coma de diferencia' {
    $d = Nuevo-Claude
    Poner-Sesion $d 'ana@empresa.com' 'tok-ana' $script:dentroDe30Dias
    Get-Cuentas -Claude $d | Out-Null
    # Estando en zoe se "trabaja": cambia el estado de los proyectos.
    Poner-Sesion $d 'zoe@empresa.com' 'tok-zoe' $script:dentroDe30Dias 'trabaje-un-rato'
    Get-Cuentas -Claude $d | Out-Null

    Switch-Cuenta -Mail 'ana@empresa.com' -Claude $d | Out-Null
    $final = Leer (Join-Path $d '.claude.json')
    $esperado = Texto-Ajustes 'ana@empresa.com' 'tok-ana' 'trabaje-un-rato'
    Afirmar ($final -ceq $esperado) "quedo distinto:`n$final`n---`n$esperado"
}
Probar 'el viaje redondo: ir y volver deja las dos credenciales intactas' {
    $d = Nuevo-Claude
    Poner-Sesion $d 'ana@empresa.com' 'tok-ana' $script:dentroDe30Dias
    $credAna = Leer (Join-Path $d '.credentials.json')
    Get-Cuentas -Claude $d | Out-Null
    Poner-Sesion $d 'zoe@empresa.com' 'tok-zoe' $script:dentroDe30Dias
    $credZoe = Leer (Join-Path $d '.credentials.json')
    Get-Cuentas -Claude $d | Out-Null

    Switch-Cuenta -Mail 'ana@empresa.com' -Claude $d | Out-Null
    Afirmar ((Leer (Join-Path $d '.credentials.json')) -ceq $credAna) 'la ida rompio la credencial'
    Switch-Cuenta -Mail 'zoe@empresa.com' -Claude $d | Out-Null
    Afirmar ((Leer (Join-Path $d '.credentials.json')) -ceq $credZoe) 'la vuelta rompio la credencial'
}
Probar 'antes de pisar la credencial viva, la re-archiva' {
    # Si zoe renovo su token despues del ultimo archivado y no lo guardamos,
    # al volver a zoe la copia esta rotada y hay que loguearse igual.
    $d = Nuevo-Claude
    Poner-Sesion $d 'ana@empresa.com' 'tok-ana' $script:dentroDe30Dias
    Get-Cuentas -Claude $d | Out-Null
    Poner-Sesion $d 'zoe@empresa.com' 'tok-zoe' $script:dentroDe30Dias
    Get-Cuentas -Claude $d | Out-Null
    Poner-Sesion $d 'zoe@empresa.com' 'tok-zoe-renovado' $script:dentroDe30Dias

    Switch-Cuenta -Mail 'ana@empresa.com' -Claude $d | Out-Null
    $g = Leer (Join-Path $d 'cuentas\zoe-empresa-com.json') | ConvertFrom-Json
    Afirmar ($g.credencialTexto -match 'tok-zoe-renovado') 'se perdio el token renovado'
}
Probar 'una cuenta que no tenemos guardada no toca nada' {
    $d = Nuevo-Claude
    Poner-Sesion $d 'ana@empresa.com' 'tok-ana' $script:dentroDe30Dias
    $antes = Leer (Join-Path $d '.credentials.json')
    $r = Switch-Cuenta -Mail 'nadie@empresa.com' -Claude $d
    Afirmar (-not $r.Ok) 'dijo que cambio'
    Afirmar ($r.Avisos.Count -eq 1) 'no explico por que no pudo'
    Afirmar ((Leer (Join-Path $d '.credentials.json')) -ceq $antes) 'toco la credencial igual'
}
Probar 'si el token guardado esta vencido, cambia igual pero avisa' {
    $d = Nuevo-Claude
    Poner-Sesion $d 'vieja@empresa.com' 'tok-vieja' $script:ayer
    Get-Cuentas -Claude $d | Out-Null
    Poner-Sesion $d 'ana@empresa.com' 'tok-ana' $script:dentroDe30Dias
    Get-Cuentas -Claude $d | Out-Null

    $r = Switch-Cuenta -Mail 'vieja@empresa.com' -Claude $d
    Afirmar ($r.Ok) 'no la puso'
    Afirmar ($r.Vencida) 'no detecto que estaba vencida'
    Afirmar (($r.Avisos -join ' ') -match 'loguearse') "no avisa que hay que loguearse: $($r.Avisos -join '; ')"
}
Probar 'sacar una cuenta guardada' {
    $d = Nuevo-Claude
    Poner-Sesion $d 'ana@empresa.com' 'tok-ana' $script:dentroDe30Dias
    Get-Cuentas -Claude $d | Out-Null
    Afirmar (Remove-CuentaGuardada -Mail 'ana@empresa.com' -Claude $d) 'dijo que no la borro'
    Afirmar (-not (Remove-CuentaGuardada -Mail 'ana@empresa.com' -Claude $d)) 'borro dos veces la misma'
}

Write-Host ''
Write-Host '=== la config real no se toca ==='

Probar 'pasando una carpeta, el .claude.json real queda afuera' {
    # Sin esto, un llamado con -Claude y sin -Ajustes iria a leer y ESCRIBIR la
    # configuracion de verdad del usuario. Es el error que borra una sesion.
    $d = Nuevo-Claude
    Poner-Sesion $d 'ana@empresa.com' 'tok-ana' $script:dentroDe30Dias
    Afirmar ((Resolve-RutaAjustes $d $null) -ceq (Join-Path $d '.claude.json')) 'no resolvio a la carpeta que le pasaron'
}

Probar 'no ensucia la consola cuando los archivos todavia no existen' {
    # El gadget corre con ErrorActionPreference = Continue. Ahi ConvertFrom-Json
    # con entrada nula escupe su error POR AFUERA del try, y se vio de verdad en
    # el primer archivado y al pedir una cuenta que no esta guardada.
    $previo = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $Error.Clear()
        $d = Nuevo-Claude
        Poner-Sesion $d 'ana@empresa.com' 'tok-ana' $script:dentroDe30Dias
        Save-CuentaViva -Claude $d | Out-Null
        Switch-Cuenta -Mail 'nadie@empresa.com' -Claude $d | Out-Null
        Get-Cuentas -Claude $d | Out-Null
        Afirmar ($Error.Count -eq 0) ("dejo " + $Error.Count + " errores: " + ($Error[0]))
    } finally { $ErrorActionPreference = $previo }
}

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host ("{0} pasados, {1} fallas" -f $script:pasados, $script:fallas)
exit ([int]($script:fallas -gt 0))
