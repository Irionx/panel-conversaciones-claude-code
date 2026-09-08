# =============================================================================
#  Tests de la capa de Datos
# -----------------------------------------------------------------------------
#  Se corre a mano:  powershell -NoProfile -File lib\Datos\Datos.Tests.ps1
#  Sale 0 si todo pasa, 1 si algo falla.
#
#  Nada toca el conversaciones.js de verdad: se trabaja sobre una copia en el
#  temp. Un test que puede comerse tus datos no es un test, es una ruleta.
# =============================================================================
$ErrorActionPreference = 'Stop'

$raiz = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:fallas = 0
$script:pasados = 0

function Probar([string]$Que, [scriptblock]$Bloque) {
    try {
        & $Bloque
        Write-Host ("  OK    {0}" -f $Que)
        $script:pasados++
    } catch {
        Write-Host ("  FALLA {0}" -f $Que) -ForegroundColor Red
        Write-Host ("        {0}" -f $_.Exception.Message) -ForegroundColor Red
        $script:fallas++
    }
}
function Afirmar([bool]$Cond, [string]$Mensaje) {
    if (-not $Cond) { throw $Mensaje }
}

# --- banco de pruebas --------------------------------------------------------
$tmp = Join-Path $env:TEMP ("datos-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$archivo = Join-Path $tmp 'conversaciones.js'

# Un almacen minimo, con la misma forma que el de verdad.
@'
/* almacen de prueba */
window.CONVERSACIONES = [
    {
        "id":  "uno",
        "titulo":  "Primera",
        "proyecto":  "alfa",
        "cwd":  "C:\\local repos gh\\alfa",
        "sesion":  "AAAAAAAA-1111-2222-3333-444444444444",
        "fecha":  "2026-09-01",
        "tags":  [ "rojo", "azul" ],
        "notas":  "nota de la primera"
    },
    {
        "id":  "dos",
        "titulo":  "Segunda",
        "proyecto":  "beta",
        "cwd":  "C:\\local repos gh\\beta",
        "sesion":  "BBBBBBBB-1111-2222-3333-444444444444",
        "fecha":  "2026-09-02"
    }
];
'@ | Set-Content -LiteralPath $archivo -Encoding UTF8

Import-Module (Join-Path $PSScriptRoot 'Datos.psd1') -Force
Initialize-Datos -Ruta $archivo

Write-Host ''
Write-Host '=== la frontera del modulo ==='

Probar 'las internas NO se pueden llamar desde afuera' {
    foreach ($f in 'Read-Almacen', 'Write-Almacen', 'Invoke-ConBloqueo', 'Get-RutaAlmacen') {
        if (Get-Command $f -ErrorAction SilentlyContinue) {
            throw "$f quedo exportada; la UI podria depender de ella y el paso 2 la rompe"
        }
    }
}
Probar 'las 11 publicas SI estan' {
    $esperadas = 'Initialize-Datos', 'Backup-Datos', 'Get-Conversacion', 'Find-Conversacion',
    'Get-Nota', 'Get-Tag', 'Add-Conversacion', 'Set-Conversacion',
    'Remove-Conversacion', 'Set-Nota', 'Set-Tag'
    foreach ($f in $esperadas) {
        if (-not (Get-Command $f -Module Datos -ErrorAction SilentlyContinue)) { throw "falta $f" }
    }
}

Write-Host ''
Write-Host '=== lectura ==='

Probar 'Get-Conversacion devuelve todas' {
    $t = @(Get-Conversacion)
    Afirmar ($t.Count -eq 2) "esperaba 2, hay $($t.Count)"
}
Probar 'Get-Conversacion -Id' {
    $c = Get-Conversacion -Id 'uno'
    Afirmar ($c.titulo -eq 'Primera') "titulo inesperado: $($c.titulo)"
}
Probar 'Get-Conversacion -Sesion no distingue mayusculas' {
    $c = Get-Conversacion -Sesion 'aaaaaaaa-1111-2222-3333-444444444444'
    Afirmar ($null -ne $c -and $c.id -eq 'uno') 'no encontro la sesion en minuscula'
}
Probar 'los backslashes del path salen intactos' {
    $c = Get-Conversacion -Id 'uno'
    Afirmar ($c.cwd -ceq 'C:\local repos gh\alfa') "cwd roto: $($c.cwd)"
}
Probar 'Get-Tag devuelve coleccion vacia y no null cuando no hay tags' {
    $t = Get-Tag -Id 'dos'
    Afirmar ($null -ne $t) 'devolvio null: el que llama no puede hacer .Count'
    Afirmar ($t.Count -eq 0) "esperaba 0, hay $($t.Count)"
}
Probar 'Find-Conversacion busca en notas' {
    $r = @(Find-Conversacion -Texto 'nota de la primera')
    Afirmar ($r.Count -eq 1 -and $r[0].id -eq 'uno') "esperaba 1 (uno), dio $($r.Count)"
}
Probar 'Find-Conversacion busca en tags' {
    $r = @(Find-Conversacion -Texto 'azul')
    Afirmar ($r.Count -eq 1 -and $r[0].id -eq 'uno') "esperaba 1 (uno), dio $($r.Count)"
}

Write-Host ''
Write-Host '=== escritura ==='

# Texto con todo lo que hoy hay que escapar a mano
$notaFea = "Diagnostico: probe el token 'interno' y dio 404.`nLinea dos con `"comillas`" y C:\ruta\con\barras"

Probar 'Add-Conversacion + round-trip exacto del texto feo' {
    Add-Conversacion -Id 'tres' -Titulo 'Tercera' -Cwd 'C:\tmp\gama' `
        -Sesion 'CCCCCCCC-1111-2222-3333-444444444444' -Proyecto 'gama' `
        -Rama 'feat/algo' -Notas $notaFea -Tags 'verde'
    $c = Get-Conversacion -Id 'tres'
    Afirmar ($null -ne $c) 'no se agrego'
    Afirmar ($c.notas -ceq $notaFea) 'la nota no volvio identica'
    Afirmar ($c.cwd -ceq 'C:\tmp\gama') "cwd roto: $($c.cwd)"
    Afirmar ((@(Get-Conversacion)).Count -eq 3) 'no quedaron 3'
}
Probar 'Add-Conversacion rechaza un id invalido' {
    try {
        Add-Conversacion -Id 'MAL id!' -Titulo 'x' -Cwd 'c:\x' -Sesion 'x'
        throw 'lo acepto, y ese id romperia la URL claudeconv://'
    } catch { if ($_.Exception.Message -notmatch 'no sirve') { throw } }
}
Probar 'Add-Conversacion rechaza un id repetido' {
    try {
        Add-Conversacion -Id 'uno' -Titulo 'x' -Cwd 'c:\x' -Sesion 'x'
        throw 'permitio duplicar la id'
    } catch { if ($_.Exception.Message -notmatch 'Ya existe') { throw } }
}
Probar 'Set-Conversacion toca SOLO lo que se le pasa' {
    Set-Conversacion -Id 'uno' -Titulo 'Primera renombrada'
    $c = Get-Conversacion -Id 'uno'
    Afirmar ($c.titulo -eq 'Primera renombrada') 'no cambio el titulo'
    Afirmar ($c.proyecto -eq 'alfa') 'se llevo puesto el proyecto'
    Afirmar ($c.notas -eq 'nota de la primera') 'se llevo puestas las notas'
}
Probar 'Set-Conversacion puede vaciar un campo a proposito' {
    Set-Conversacion -Id 'tres' -Rama ''
    Afirmar ((Get-Conversacion -Id 'tres').rama -eq '') 'no se pudo vaciar la rama'
}
Probar 'Set-Conversacion agrega un campo que no existia' {
    Set-Conversacion -Id 'dos' -Rama 'main'
    Afirmar ((Get-Conversacion -Id 'dos').rama -eq 'main') 'no agrego rama a una entrada sin rama'
}
Probar 'Set-Nota y Set-Tag' {
    Set-Nota -Id 'dos' -Texto 'nota nueva'
    Set-Tag -Id 'dos' -Tags @('x', 'y', 'z')
    Afirmar ((Get-Nota -Id 'dos') -eq 'nota nueva') 'no guardo la nota'
    Afirmar ((Get-Tag -Id 'dos').Count -eq 3) 'no guardo los 3 tags'
}
Probar 'Set-* sobre un id que no existe avisa en vez de callarse' {
    try { Set-Nota -Id 'nada' -Texto 'x'; throw 'no aviso' }
    catch { if ($_.Exception.Message -notmatch 'No existe') { throw } }
}
Probar 'Remove-Conversacion devuelve true y saca la entrada' {
    Afirmar ((Remove-Conversacion -Id 'tres') -eq $true) 'no devolvio true'
    Afirmar ($null -eq (Get-Conversacion -Id 'tres')) 'sigue ahi'
}
Probar 'Remove-Conversacion devuelve false si no estaba' {
    Afirmar ((Remove-Conversacion -Id 'nunca-existio') -eq $false) 'no devolvio false'
}

Write-Host ''
Write-Host '=== escritura atomica ==='

Probar 'no queda ningun .tmp tirado' {
    $sobras = @(Get-ChildItem -LiteralPath $tmp -Filter '*.tmp' -ErrorAction SilentlyContinue)
    Afirmar ($sobras.Count -eq 0) ("quedaron: " + ($sobras.Name -join ', '))
}
Probar 'File.Replace dejo el anterior en .bak' {
    Afirmar (Test-Path -LiteralPath "$archivo.bak") 'no hay .bak'
}
Probar 'el almacen sigue siendo JS valido y parseable' {
    $t = @(Get-Conversacion)
    Afirmar ($t.Count -eq 2) "quedaron $($t.Count) en vez de 2"
}
# REGRESION: ConvertFrom-Json en PS 5.1 emite el array como UN objeto. Si la
# lectura no emite elemento por elemento, la escritura mete el array adentro de
# si mismo y el almacen queda anidado. Paso de verdad.
Probar 'el array NO quedo anidado adentro de si mismo' {
    $raw = Get-Content -LiteralPath $archivo -Raw
    $cuerpo = $raw.Substring($raw.IndexOf('['))
    Afirmar ($cuerpo -notmatch '^\[\s*\[') 'el array quedo metido adentro de si mismo'
    foreach ($c in Get-Conversacion) {
        Afirmar ($null -ne $c.id -and '' -ne [string]$c.id) 'hay una entrada sin id: senal de anidado'
    }
}
Probar 'no se escriben campos opcionales vacios' {
    $raw = Get-Content -LiteralPath $archivo -Raw
    Afirmar ($raw -notmatch '"proyecto":\s*""') 'quedo un "proyecto": "" de relleno'
}

Probar 'Backup-Datos deja una copia usable' {
    $dest = Join-Path $tmp 'copia.js'
    Backup-Datos -Destino $dest | Out-Null
    Afirmar (Test-Path -LiteralPath $dest) 'no creo la copia'
    Afirmar ((Get-Item $dest).Length -eq (Get-Item $archivo).Length) 'la copia no mide igual'
}

Write-Host ''
Write-Host '=== el mutex: dos procesos no se pisan ==='

Probar 'una escritura ESPERA a que el otro proceso suelte el candado' {
    # El hijo va a un .ps1 y se lanza con -File, NO con -Command por
    # -ArgumentList: pasar un comando con $ y comillas por la linea de comandos
    # se mangla y el hijo arranca roto. Pasaba: el test decia "no espero" cuando
    # en realidad el hijo nunca habia llegado a tomar el candado.
    $listo = Join-Path $tmp 'tomado.txt'
    $hijoPs1 = Join-Path $tmp 'hijo.ps1'
    @"
`$m = New-Object System.Threading.Mutex(`$false, 'Local\GiaConversacionesDatos')
[void]`$m.WaitOne(5000)
Set-Content -LiteralPath '$listo' -Value 'ok'
Start-Sleep -Milliseconds 2000
`$m.ReleaseMutex()
"@ | Set-Content -LiteralPath $hijoPs1 -Encoding ASCII

    $hijo = Start-Process powershell -PassThru -WindowStyle Hidden `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $hijoPs1)

    # Se ESPERA la senal en vez de dormir un rato y cruzar los dedos: si el hijo
    # no arranca, el test tiene que decir eso y no "el candado no sirve".
    $limite = [Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path -LiteralPath $listo) -and $limite.ElapsedMilliseconds -lt 8000) {
        Start-Sleep -Milliseconds 50
    }
    Afirmar (Test-Path -LiteralPath $listo) 'el proceso hijo nunca tomo el candado (problema del test, no del modulo)'

    $reloj = [Diagnostics.Stopwatch]::StartNew()
    Set-Nota -Id 'uno' -Texto 'escrita despues de esperar'
    $reloj.Stop()
    $hijo.WaitForExit(8000) | Out-Null

    Afirmar ($reloj.ElapsedMilliseconds -gt 800) `
    ("escribio en {0} ms: NO espero, o sea que el candado no sirve" -f $reloj.ElapsedMilliseconds)
    Afirmar ((Get-Nota -Id 'uno') -eq 'escrita despues de esperar') 'no escribio despues de esperar'
    Write-Host ("        (espero {0} ms al otro proceso)" -f $reloj.ElapsedMilliseconds)
}

Write-Host ''
Write-Host '=== el almacen vacio ==='
#  Va ULTIMO a proposito: vacia el almacen, asi que cualquier test que corra
#  despues se queda sin datos con los que trabajar.

Probar 'se puede vaciar del todo y volver a llenar' {
    foreach ($c in @(Get-Conversacion)) { Remove-Conversacion -Id $c.id | Out-Null }
    $t = @(Get-Conversacion)
    Afirmar ($t.Count -eq 0) "esperaba 0, hay $($t.Count) (el @(`$null) miente el conteo)"
    Add-Conversacion -Id 'renacido' -Titulo 'Uno solo' -Cwd 'C:\x' -Sesion 'S9'
    $t = @(Get-Conversacion)
    Afirmar ($t.Count -eq 1) "esperaba 1, hay $($t.Count)"
    Afirmar ($t[0].id -eq 'renacido') 'no es el que agregue'
}

# --- limpieza ----------------------------------------------------------------
Remove-Module Datos -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host ("{0} pasados, {1} fallas" -f $script:pasados, $script:fallas)
exit ([int]($script:fallas -gt 0))
