# =============================================================================
#  Tests de la capa de Datos
# -----------------------------------------------------------------------------
#  Se corre a mano:  powershell -NoProfile -File lib\Datos\Datos.Tests.ps1
#  Sale 0 si todo pasa, 1 si algo falla.
#
#  Nada toca la base de verdad: se trabaja sobre uNa base nueva en el temp. Un
#  test que puede comerse tus datos no es un test, es una ruleta.
#
#  Los datos de prueba se cargan con la propia API y no escribiendo un archivo a
#  mano: asi los tests no saben nada del motor. Es lo que permitio cambiar de
#  .js a SQLite sin reescribirlos.
# =============================================================================
$ErrorActionPreference = 'Stop'

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
$archivo = Join-Path $tmp 'conversaciones.db'

Import-Module (Join-Path $PSScriptRoot 'Datos.psd1') -Force
Initialize-Datos -Ruta $archivo

Add-Conversacion -Id 'uno' -Titulo 'Primera' -Proyecto 'alfa' `
    -Cwd 'C:\local repos gh\alfa' -Sesion 'AAAAAAAA-1111-2222-3333-444444444444' `
    -Fecha '2026-09-01' -Tags 'rojo', 'azul' -Notas 'nota de la primera'
Add-Conversacion -Id 'dos' -Titulo 'Segunda' -Proyecto 'beta' `
    -Cwd 'C:\local repos gh\beta' -Sesion 'BBBBBBBB-1111-2222-3333-444444444444' `
    -Fecha '2026-09-02'

Write-Host ''
Write-Host '=== la frontera del modulo ==='

Probar 'las internas NO se pueden llamar desde afuera' {
    foreach ($f in 'Get-Filas', 'Invoke-Lote', 'Lock-Almacen', 'Unlock-Almacen',
        'Get-RutaAlmacen', 'ConvertTo-Conversacion', 'ConvertTo-NuloSiVacio') {
        if (Get-Command $f -ErrorAction SilentlyContinue) {
            throw "$f quedo exportada; la UI podria depender de ella y un cambio de motor la rompe"
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
Probar 'los tags vienen en el objeto de la conversacion' {
    $c = Get-Conversacion -Id 'uno'
    Afirmar ((@($c.tags)).Count -eq 2) "esperaba 2 tags, hay $((@($c.tags)).Count)"
}
Probar 'Find-Conversacion busca en notas' {
    $r = @(Find-Conversacion -Texto 'nota de la primera')
    Afirmar ($r.Count -eq 1 -and $r[0].id -eq 'uno') "esperaba 1 (uno), dio $($r.Count)"
}
Probar 'Find-Conversacion busca en tags' {
    $r = @(Find-Conversacion -Texto 'azul')
    Afirmar ($r.Count -eq 1 -and $r[0].id -eq 'uno') "esperaba 1 (uno), dio $($r.Count)"
}
Probar 'Find-Conversacion no repite filas cuando matchean varios tags' {
    Set-Tag -Id 'uno' -Tags @('verde', 'verdoso', 'verdisimo')
    $r = @(Find-Conversacion -Texto 'verd')
    Afirmar ($r.Count -eq 1) "el join duplico la fila: dio $($r.Count)"
    Set-Tag -Id 'uno' -Tags @('rojo', 'azul')
}

Write-Host ''
Write-Host '=== escritura ==='

# Texto con todo lo que antes habia que escapar a mano
$notaFea = "Diagnostico: probe el token 'interno' y dio 404.`nLinea dos con `"comillas`" y C:\ruta\con\barras"

Probar 'Add-Conversacion + round-trip exacto del texto feo' {
    Add-Conversacion -Id 'tres' -Titulo 'Tercera' -Cwd 'C:\tmp\gama' `
        -Sesion 'CCCCCCCC-1111-2222-3333-444444444444' -Proyecto 'gama' `
        -Rama 'feat/algo' -Notas $notaFea -Tags 'verde' -ContextoMax 1000000
    $c = Get-Conversacion -Id 'tres'
    Afirmar ($null -ne $c) 'no se agrego'
    Afirmar ($c.notas -ceq $notaFea) 'la nota no volvio identica'
    Afirmar ($c.cwd -ceq 'C:\tmp\gama') "cwd roto: $($c.cwd)"
    Afirmar ([int]$c.contextoMax -eq 1000000) "contextoMax roto: $($c.contextoMax)"
    Afirmar ((@(Get-Conversacion)).Count -eq 3) 'no quedaron 3'
}
Probar 'los opcionales que no se pasan quedan en NULL, no en cadena vacia' {
    $c = Get-Conversacion -Id 'dos'
    Afirmar ($null -eq $c.rama) 'rama quedo en cadena vacia en vez de NULL'
    Afirmar ($null -eq $c.notas) 'notas quedo en cadena vacia en vez de NULL'
    Afirmar ($null -eq $c.contextoMax) 'contextoMax quedo en 0 en vez de NULL'
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
Probar 'un alta fallida no deja tags huerfanos' {
    try { Add-Conversacion -Id 'uno' -Titulo 'x' -Cwd 'c:\x' -Sesion 'x' -Tags 'basura' } catch { }
    $r = @(Find-Conversacion -Texto 'basura')
    Afirmar ($r.Count -eq 0) 'quedaron tags de un alta que fallo: la transaccion no revirtio'
}
Probar 'Set-Conversacion toca SOLO lo que se le pasa' {
    Set-Conversacion -Id 'uno' -Titulo 'Primera renombrada'
    $c = Get-Conversacion -Id 'uno'
    Afirmar ($c.titulo -eq 'Primera renombrada') 'no cambio el titulo'
    Afirmar ($c.proyecto -eq 'alfa') 'se llevo puesto el proyecto'
    Afirmar ($c.notas -eq 'nota de la primera') 'se llevo puestas las notas'
    Afirmar ((@($c.tags)).Count -eq 2) 'se llevo puestos los tags'
}
Probar 'Set-Conversacion puede vaciar un campo a proposito' {
    Set-Conversacion -Id 'tres' -Rama ''
    Afirmar (-not (Get-Conversacion -Id 'tres').rama) 'no se pudo vaciar la rama'
}
Probar 'Set-Conversacion escribe contextoMax en SU columna (no contextomax)' {
    Set-Conversacion -Id 'dos' -ContextoMax 200000
    Afirmar ([int](Get-Conversacion -Id 'dos').contextoMax -eq 200000) 'no lo guardo donde el gadget lo busca'
}
Probar 'Set-Nota y Set-Tag' {
    Set-Nota -Id 'dos' -Texto 'nota nueva'
    Set-Tag -Id 'dos' -Tags @('x', 'y', 'z')
    Afirmar ((Get-Nota -Id 'dos') -eq 'nota nueva') 'no guardo la nota'
    Afirmar ((Get-Tag -Id 'dos').Count -eq 3) 'no guardo los 3 tags'
}
Probar 'Set-Tag reemplaza, no acumula' {
    Set-Tag -Id 'dos' -Tags @('unico')
    $t = Get-Tag -Id 'dos'
    Afirmar ($t.Count -eq 1 -and $t[0] -eq 'unico') "quedaron $($t.Count): $($t -join ',')"
}
Probar 'Set-* sobre un id que no existe avisa en vez de callarse' {
    foreach ($sb in @({ Set-Nota -Id 'nada' -Texto 'x' },
            { Set-Tag -Id 'nada' -Tags @('x') },
            { Set-Conversacion -Id 'nada' -Titulo 'x' })) {
        try { & $sb; throw 'no aviso' }
        catch { if ($_.Exception.Message -notmatch 'No existe') { throw } }
    }
}
Probar 'Remove-Conversacion devuelve true, saca la entrada y sus tags' {
    Afirmar ((Remove-Conversacion -Id 'tres') -eq $true) 'no devolvio true'
    Afirmar ($null -eq (Get-Conversacion -Id 'tres')) 'sigue ahi'
    Afirmar ((Get-Tag -Id 'tres').Count -eq 0) 'quedaron tags huerfanos'
}
Probar 'Remove-Conversacion devuelve false si no estaba' {
    Afirmar ((Remove-Conversacion -Id 'nunca-existio') -eq $false) 'no devolvio false'
}
# La interfaz le promete al usuario que al borrar queda red ("Del panel queda
# respaldo en datos\conversaciones.db.bak"). Si el respaldo no se hace, la app
# esta mintiendo justo en la operacion que no se puede deshacer.
Probar 'borrar deja el respaldo que la interfaz promete' {
    $bak = "$archivo.bak"
    Remove-Item -LiteralPath $bak -Force -ErrorAction SilentlyContinue
    Add-Conversacion -Id 'sacrificio' -Titulo 'Para borrar' -Cwd 'C:\x' -Sesion 'S8'
    Remove-Conversacion -Id 'sacrificio' | Out-Null

    Afirmar (Test-Path -LiteralPath $bak) 'no dejo respaldo antes de borrar'
    # Y que el respaldo sea de ANTES: tiene que tener la conversacion borrada.
    Initialize-Datos -Ruta $bak
    $tenia = [bool](Get-Conversacion -Id 'sacrificio')
    Initialize-Datos -Ruta $archivo
    Afirmar $tenia 'el respaldo se hizo DESPUES de borrar: no sirve de nada'
    Afirmar ($null -eq (Get-Conversacion -Id 'sacrificio')) 'no borro de la base buena'
}
Probar 'un borrado que no encuentra nada no pisa el respaldo bueno' {
    $bak = "$archivo.bak"
    $antes = (Get-Item -LiteralPath $bak).LastWriteTime
    Start-Sleep -Milliseconds 20
    Remove-Conversacion -Id 'no-existe-nada' | Out-Null
    Afirmar ((Get-Item -LiteralPath $bak).LastWriteTime -eq $antes) `
        'un id inexistente rehizo el respaldo y te comio la red anterior'
}
Probar 'el orden de la lista es el de alta, y un update no lo cambia' {
    $antes = @(Get-Conversacion) | ForEach-Object { $_.id }
    Set-Conversacion -Id 'uno' -Titulo 'Primera otra vez'
    $despues = @(Get-Conversacion) | ForEach-Object { $_.id }
    Afirmar (($antes -join ',') -eq ($despues -join ',')) `
        "editar reordeno la lista: $($antes -join ',') -> $($despues -join ',')"
}

Write-Host ''
Write-Host '=== el archivo ==='

Probar 'en reposo es UN SOLO archivo (nada de -wal ni -shm)' {
    $sobras = @(Get-ChildItem -LiteralPath $tmp -Filter 'conversaciones.db-*' -ErrorAction SilentlyContinue)
    Afirmar ($sobras.Count -eq 0) ("aparecieron: " + ($sobras.Name -join ', ') + " -- se activo WAL?")
}
Probar 'las migraciones no se re-aplican al reabrir' {
    # Si se re-aplicaran, el CREATE TABLE explotaria por tabla duplicada.
    Initialize-Datos -Ruta $archivo
    Afirmar ((@(Get-Conversacion)).Count -eq 2) 'reabrir la base perdio datos'
}
Probar 'Backup-Datos deja una copia consistente y usable' {
    $dest = Join-Path $tmp 'copia.db'
    Backup-Datos -Destino $dest | Out-Null
    Afirmar (Test-Path -LiteralPath $dest) 'no creo la copia'
    $cabecera = [System.Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($dest)[0..14])
    Afirmar ($cabecera -eq 'SQLite format 3') "la copia no es una base SQLite: '$cabecera'"

    # Y que se pueda LEER de verdad, no solo que exista
    Initialize-Datos -Ruta $dest
    $n = (@(Get-Conversacion)).Count
    Initialize-Datos -Ruta $archivo
    Afirmar ($n -eq 2) "la copia tiene $n conversaciones en vez de 2"
}
Probar 'Backup-Datos pisa un respaldo anterior sin quejarse' {
    $dest = Join-Path $tmp 'copia.db'
    Backup-Datos -Destino $dest | Out-Null
    Afirmar (Test-Path -LiteralPath $dest) 'se perdio la copia al rehacerla'
}

Write-Host ''
Write-Host '=== el candado: dos procesos no se pisan ==='

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
    Afirmar ($t.Count -eq 0) "esperaba 0, hay $($t.Count)"
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
