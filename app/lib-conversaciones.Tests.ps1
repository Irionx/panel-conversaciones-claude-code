# =============================================================================
#  Tests de lib-conversaciones.ps1
# -----------------------------------------------------------------------------
#  Se corre a mano:  powershell -NoProfile -File lib-conversaciones.Tests.ps1
#  Sale 0 si todo pasa, 1 si algo falla.
#
#  OJO: dot-sourcear la libreria engancha la base REAL (el Initialize-Datos esta
#  al nivel superior del archivo). Por eso todo lo que se prueba aca recibe los
#  datos por parametro y NUNCA lee ni escribe la base de la persona.
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

. (Join-Path $PSScriptRoot 'lib-conversaciones.ps1')

Write-Host ''
Write-Host '=== el id de una conversacion: slug + sufijo si choca ==='

# Estos casos SON el contrato que guardar.ps1 tenia escrito adentro. El id es la
# clave primaria de la tarjeta, asi que si el algoritmo cambia, el panel y /save
# dejan de generar el mismo y la misma conversacion entra dos veces.
Probar 'el titulo se vuelve slug: minuscula, sin acentos y con guiones' {
    $casos = @{
        'Nivelar dev con test' = 'nivelar-dev-con-test'
        'Nivelación del ñandú' = 'nivelacion-del-nandu'
        'ABC 123!!!'           = 'abc-123'
        'Dos   espacios'       = 'dos-espacios'
    }
    foreach ($t in $casos.Keys) {
        $dio = New-IdConversacion -Titulo $t -Existentes @()
        Afirmar ($dio -eq $casos[$t]) "'$t' dio '$dio' y esperaba '$($casos[$t])'"
    }
}

Probar 'un titulo que no deja ninguna letra cae a "conversacion"' {
    foreach ($t in '   ', '---', '!!!', '') {
        $dio = New-IdConversacion -Titulo $t -Existentes @()
        Afirmar ($dio -eq 'conversacion') "'$t' dio '$dio'"
    }
}

Probar 'se corta en 48 y no deja un guion colgando al final' {
    # El corte cae justo sobre un guion: sin el Trim quedaria "...cuarenta-".
    $dio = New-IdConversacion -Existentes @() `
        -Titulo 'Un titulo muy largo que se pasa de los cuarenta y ocho caracteres'
    Afirmar ($dio -eq 'un-titulo-muy-largo-que-se-pasa-de-los-cuarenta') "dio '$dio'"
    Afirmar ($dio.Length -le 48) "mide $($dio.Length)"
}

Probar 'si el id ya existe le pone sufijo, y sigue contando' {
    $dio = New-IdConversacion -Titulo 'Nivelar dev' -Existentes @('nivelar-dev')
    Afirmar ($dio -eq 'nivelar-dev-2') "dio '$dio'"

    $dio = New-IdConversacion -Titulo 'Nivelar dev' -Existentes @('nivelar-dev', 'nivelar-dev-2')
    Afirmar ($dio -eq 'nivelar-dev-3') "dio '$dio'"

    # Con un solo existente: en PS 5.1 un array de un elemento se desarma al
    # volver de una funcion, asi que este caso NO es redundante.
    $dio = New-IdConversacion -Titulo 'Sola' -Existentes @('sola')
    Afirmar ($dio -eq 'sola-2') "dio '$dio'"
}

Probar 'los ids ajenos no estorban' {
    $dio = New-IdConversacion -Titulo 'Nivelar dev' -Existentes @('otra-cosa', 'y-otra')
    Afirmar ($dio -eq 'nivelar-dev') "dio '$dio'"
}

Write-Host ''
Write-Host '=== lanzar una conversacion: la de siempre y la nueva ==='

# La carpeta tiene que existir de verdad: las dos funciones la validan.
$script:tmp = Join-Path $env:TEMP ("conv-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $script:tmp -Force | Out-Null
$script:uuid = '11111111-2222-3333-4444-555555555555'

Probar 'la linea de --resume no cambio: misma forma que antes del refactor' {
    # Esto es el guardarrail del refactor. Los cuatro llamadores que ya existen
    # (abrir-conversacion, abrir-remoto y las dos de Tarjeta.ps1) dependen de
    # esta linea exacta.
    $r = Start-Conversacion -Cwd $script:tmp -Sesion $script:uuid -DryRun
    Afirmar ($r.Cwd -eq $script:tmp) "el cwd volvio como '$($r.Cwd)'"
    Afirmar (-not $r.Remoto) 'dijo remoto sin pedirselo'
    if ($r.Exe -match 'wt\.exe$') {
        Afirmar ($r.Args -eq ('-w 0 new-tab -d "{0}" cmd /k claude --resume {1}' -f $script:tmp, $script:uuid)) `
            "la linea de wt es '$($r.Args)'"
    } else {
        Afirmar ($r.Args -eq ('/k cd /d "{0}" && claude --resume {1}' -f $script:tmp, $script:uuid)) `
            "la linea de cmd es '$($r.Args)'"
    }
}

Probar 'el remoto sigue saneando el nombre y no pierde los acentos' {
    $r = Start-Conversacion -Cwd $script:tmp -Sesion $script:uuid -Remoto `
        -Nombre 'Diálogo & "raro" | peligroso' -DryRun
    Afirmar ($r.Remoto) 'no quedo marcado como remoto'
    Afirmar ($r.Args -match '--remote-control "Diálogo raro peligroso"') "la linea es '$($r.Args)'"
}

Probar 'una conversacion NUEVA no lleva --resume ni pide uuid' {
    $r = Start-ConversacionNueva -Cwd $script:tmp -DryRun
    Afirmar ($r.Args -notmatch '--resume') "la linea trae --resume: '$($r.Args)'"
    Afirmar ($r.Args -match 'claude\s*$') "no termina en claude pelado: '$($r.Args)'"
    Afirmar ($r.Cwd -eq $script:tmp) "el cwd volvio como '$($r.Cwd)'"
}

Probar 'las dos lanzan en la MISMA terminal: una sola verdad para la linea' {
    # Si alguien vuelve a escribir el armado de la linea aparte, esto se cae.
    $vieja = Start-Conversacion -Cwd $script:tmp -Sesion $script:uuid -DryRun
    $nueva = Start-ConversacionNueva -Cwd $script:tmp -DryRun
    Afirmar ($vieja.Exe -eq $nueva.Exe) "una abre con $($vieja.Exe) y la otra con $($nueva.Exe)"
    # Lo de adelante del comando (ventana, pestaña y carpeta) tiene que ser igual.
    $hasta = $vieja.Args.IndexOf('claude')
    Afirmar ($hasta -gt 0) "no encontre 'claude' en '$($vieja.Args)'"
    Afirmar ($vieja.Args.Substring(0, $hasta) -eq $nueva.Args.Substring(0, $hasta)) `
        "difieren antes del comando:`n        $($vieja.Args)`n        $($nueva.Args)"
}

Probar 'una carpeta que no existe no lanza nada' {
    $falsa = Join-Path $script:tmp 'no-existe-ni-va-a-existir'
    $tiro = $false
    try { Start-ConversacionNueva -Cwd $falsa -DryRun } catch { $tiro = $true }
    Afirmar $tiro 'acepto una carpeta inexistente'

    $tiro = $false
    try { Start-Conversacion -Cwd $falsa -Sesion $script:uuid -DryRun } catch { $tiro = $true }
    Afirmar $tiro 'la de --resume tambien acepto una carpeta inexistente'
}

Probar 'un uuid con mala forma sigue sin pasar' {
    $tiro = $false
    try { Start-Conversacion -Cwd $script:tmp -Sesion 'no-soy-un-uuid' -DryRun } catch { $tiro = $true }
    Afirmar $tiro 'acepto un uuid con mala forma'
}

Write-Host ''
Write-Host '=== el alta desde el historial, escribiendo de verdad ==='

# De ACA EN ADELANTE la base apunta a una temporal. Va al final del archivo a
# proposito: redirigirla a mitad de camino dejaria a los tests de abajo mirando
# una base que no es la que creen.
# Hace falta escribir de verdad: los tests del gadget prueban el CALCULO de los
# campos, pero nunca que Add-Conversacion los acepte. El id, por ejemplo, tiene
# que pasar un ^[a-z0-9._-]+$ que se valida recien ahi adentro.
. (Join-Path $PSScriptRoot 'gadget\Cajon.ps1')
$script:tmpBase = Join-Path $env:TEMP ("alta-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $script:tmpBase -Force | Out-Null
Initialize-Datos -Ruta (Join-Path $script:tmpBase 'prueba.db')

function Fila-Historial([string]$Titulo, [string]$Sesion) {
    [pscustomobject]@{
        Sesion = $Sesion; Dir = 'C:\no\existe'; Carpeta = 'C--x'
        # Una carpeta que existe: Get-RamaDe le hace Push-Location.
        Cwd = $env:TEMP; Titulo = $Titulo; Bytes = 10; Fecha = (Get-Date)
        Guardada = $false; Conv = $null
    }
}

Probar 'la base de prueba arranca vacia (si no, el resto no prueba nada)' {
    Afirmar (@(Get-Conversacion).Count -eq 0) 'la temporal vino con datos'
}

Probar 'una fila del historial entra al panel y se puede releer entera' {
    $f = Fila-Historial 'Nivelación del ñandú' '11111111-2222-3333-4444-555555555555'
    $alta = Get-AltaDesdeHistorial -S $f
    Add-Conversacion -Id $alta.Id -Titulo $alta.Titulo -Cwd $alta.Cwd -Sesion $alta.Sesion `
        -Proyecto $alta.Proyecto -Rama (Get-RamaDe -Cwd $alta.Cwd) | Out-Null

    $leida = Get-Conversacion -Id $alta.Id
    Afirmar ($null -ne $leida) "no se pudo releer '$($alta.Id)'"
    Afirmar ($leida.titulo -eq 'Nivelación del ñandú') "el titulo quedo '$($leida.titulo)'"
    Afirmar ($leida.sesion -eq $f.Sesion) 'el uuid no quedo bien'
    Afirmar ($leida.cwd -eq (ConvertTo-RutaWindows $env:TEMP)) "el cwd quedo '$($leida.cwd)'"
    Afirmar ($leida.proyecto -eq (Split-Path -Leaf $env:TEMP)) "el proyecto quedo '$($leida.proyecto)'"
}

Probar 'dos conversaciones con el mismo nombre no se pisan' {
    $f = Fila-Historial 'Nivelación del ñandú' '99999999-8888-7777-6666-555555555555'
    $alta = Get-AltaDesdeHistorial -S $f
    Afirmar ($alta.Id -eq 'nivelacion-del-nandu-2') "el segundo id quedo '$($alta.Id)'"
    Add-Conversacion -Id $alta.Id -Titulo $alta.Titulo -Cwd $alta.Cwd -Sesion $alta.Sesion `
        -Proyecto $alta.Proyecto | Out-Null
    Afirmar (@(Get-Conversacion).Count -eq 2) "quedaron $(@(Get-Conversacion).Count) y esperaba 2"
}

Probar 'una sesion sin nombre entra igual, con un id que la base acepta' {
    # Un titulo vacio daria un id vacio, y Add-Conversacion lo rechaza porque el
    # id es parte de una URL claudeconv://.
    $f = Fila-Historial '' 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
    $alta = Get-AltaDesdeHistorial -S $f
    Add-Conversacion -Id $alta.Id -Titulo $alta.Titulo -Cwd $alta.Cwd -Sesion $alta.Sesion | Out-Null
    Afirmar ($null -ne (Get-Conversacion -Id $alta.Id)) "no entro: '$($alta.Id)'"
}

Remove-Item -LiteralPath $script:tmpBase -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $script:tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host ("{0} pasados, {1} fallas" -f $script:pasados, $script:fallas)
exit ([int]($script:fallas -gt 0))
