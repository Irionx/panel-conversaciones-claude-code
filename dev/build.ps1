# =============================================================================
#  build.ps1 - arma el paquete distribuible
# -----------------------------------------------------------------------------
#    .\dev\build.ps1                 usa la version del ultimo tag
#    .\dev\build.ps1 -Version 1.1.0  la fija a mano
#    .\dev\build.ps1 -SinTests       saltea la verificacion (para probar el build)
#
#  Deja  dev\dist\conversaciones-<version>.zip  listo para mandar.
#
#  QUE ARCHIVOS ENTRAN: los que git tiene versionados, y nada mas. No hay una
#  lista a mano en este script, a proposito. Una lista a mano se desactualiza el
#  dia que alguien agrega un archivo y se olvida de venir aca; el indice de git
#  ya sabe exactamente que es codigo y que son datos, porque eso es justo lo que
#  encodea el .gitignore. Sale gratis y no puede quedar viejo.
#
#  Consecuencia buena: datos\conversaciones.db, conversaciones.js y el .lnk
#  quedan afuera SOLOS, porque estan ignorados. Nunca se va a filtrar tu base ni
#  tus notas dentro de un paquete que le mandas a otra persona.
# =============================================================================
[CmdletBinding()]
param(
    [string]$Version,
    [switch]$SinTests,
    # Ademas del zip, compila el instalador .exe con Inno Setup. Necesita Inno
    # instalado en ESTA maquina (solo para buildear; el .exe que sale no lo pide).
    [switch]$Exe
)
$ErrorActionPreference = 'Stop'

$raiz = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Push-Location $raiz
try {
    function Escribir([string]$T = '', [string]$C = 'Gray') { Write-Host $T -ForegroundColor $C }

    # --- 1. verificar --------------------------------------------------------
    #  Primero los tests. Un paquete que no paso los tests no es un paquete, es
    #  un problema con moño.
    if (-not $SinTests) {
        Escribir
        Escribir '  Verificando antes de empaquetar...' 'Cyan'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $raiz 'probar.ps1') | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Escribir '  Los tests FALLARON. No se empaqueta nada.' 'Red'
            Escribir '  Corre .\probar.ps1 para ver que se rompio.' 'Red'
            Escribir
            exit 1
        }
        Escribir '  Tests en verde.' 'Green'
    }

    # --- 2. version ----------------------------------------------------------
    if (-not $Version) {
        # --dirty avisa si hay cambios sin commitear: el paquete queda marcado
        # como "no reproducible" en vez de mentir que es el tag limpio.
        $Version = (& git describe --tags --always --dirty 2>$null)
        if ($LASTEXITCODE -ne 0 -or -not $Version) { $Version = 'sin-version' }
        $Version = ([string]$Version).Trim().TrimStart('v')
    }
    Escribir ('  Version: {0}' -f $Version)

    # --- 3. juntar -----------------------------------------------------------
    $archivos = @(& git ls-files)
    if (-not $archivos.Count) { throw 'git ls-files no devolvio nada: estas en un repo?' }

    $dist = Join-Path $raiz 'dev\dist'
    $stage = Join-Path $dist ('conversaciones-' + $Version)
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    New-Item -ItemType Directory -Path $stage -Force | Out-Null

    foreach ($a in $archivos) {
        $destino = Join-Path $stage $a
        $dirDestino = Split-Path -Parent $destino
        if (-not (Test-Path -LiteralPath $dirDestino)) {
            New-Item -ItemType Directory -Path $dirDestino -Force | Out-Null
        }
        Copy-Item -LiteralPath (Join-Path $raiz $a) -Destination $destino -Force
    }
    Escribir ('  {0} archivos copiados' -f $archivos.Count)

    # --- 4. el papelito de instalacion ---------------------------------------
    #  Va en .txt en la raiz del zip: es lo primero que ve alguien que abre esto
    #  y no sabe nada.
    $instalar = @"
PANEL DE CONVERSACIONES DE CLAUDE CODE   -   version $Version
=============================================================

COMO INSTALARLO
---------------
1. Descomprimi esta carpeta donde la quieras tener. Se puede mover despues: el
   instalador se re-apunta solo.

2. Abri PowerShell EN esta carpeta y corre:

       .\setup.ps1 -Instalar

   Escribe solo en tu usuario (HKCU y el PATH de usuario). NO pide admin.

3. Abri una terminal NUEVA (el PATH viejo se queda en las que ya estaban
   abiertas, Claude Code incluido) y ya tenes los comandos:

       guardar "Titulo de la charla"
       borrar-conversacion -Listar
       cerrar-gadget

4. Abri "Gadget de conversaciones.lnk" y listo.

QUE INSTALA
-----------
Seis piezas, todas reversibles y todas en tu usuario. Para ver el estado en
cualquier momento:  .\setup.ps1

Una de las piezas te va a avisar si NO tenes el plugin claude-hud de Claude
Code. No es obligatorio, pero sin el la barra de % de contexto es una
estimacion y puede errar bastante.

COMPROBAR QUE ANDA
------------------
       .\probar.ps1        corre todos los tests, no toca tus datos
       .\datos.ps1         muestra lo que hay guardado

TUS DATOS
---------
Se guardan en datos\conversaciones.db (una base SQLite que se crea sola). El
backup es copiar ese archivo. Este paquete viene SIN datos: arrancas de cero.

MAS
---
LEEME.md          como se usa, en detalle
ARQUITECTURA.md   por que esta armado asi, y que se descarto
Cada carpeta tiene su LEEME.txt.
"@
    [System.IO.File]::WriteAllText((Join-Path $stage 'INSTALAR.txt'),
        ($instalar -replace "`r`n", "`n" -replace "`n", "`r`n"),
        [System.Text.UTF8Encoding]::new($true))

    # --- 5. zip --------------------------------------------------------------
    $zip = Join-Path $dist ('conversaciones-' + $Version + '.zip')
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    # Entrada por entrada y NO con ZipFile::CreateFromDirectory. En .NET
    # Framework ese metodo escribe los separadores como "\", y el estandar ZIP
    # exige "/". Windows lo tolera, pero un descompresor que respeta el formato
    # avisa ("appears to use backslashes as path separators") y puede terminar
    # creando archivos con el backslash en el NOMBRE en vez de carpetas. El
    # paquete se manda a otras maquinas: tiene que estar bien formado.
    $carpetaRaizZip = 'conversaciones-' + $Version
    $fs = [System.IO.File]::Open($zip, [System.IO.FileMode]::CreateNew)
    try {
        $za = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($f in (Get-ChildItem -LiteralPath $stage -Recurse -File)) {
                $rel = $f.FullName.Substring($stage.Length).TrimStart('\')
                $nombre = $carpetaRaizZip + '/' + ($rel -replace '\\', '/')
                $e = $za.CreateEntry($nombre, [System.IO.Compression.CompressionLevel]::Optimal)
                $salida = $e.Open()
                try {
                    # El stream de ENTRADA tambien se cierra. Sin este Dispose
                    # los archivos del staging quedan tomados y el Remove-Item
                    # de abajo falla con "esta siendo utilizado en otro proceso".
                    $entrada = [System.IO.File]::OpenRead($f.FullName)
                    try { $entrada.CopyTo($salida) } finally { $entrada.Dispose() }
                } finally { $salida.Dispose() }
            }
        } finally { $za.Dispose() }
    } finally { $fs.Dispose() }

    $kb = [math]::Round((Get-Item -LiteralPath $zip).Length / 1KB)
    Escribir
    Escribir ('  Listo: dev\dist\{0}  ({1} KB)' -f (Split-Path -Leaf $zip), $kb) 'Green'
    Escribir

    # Red de seguridad: si alguna vez un cambio en el .gitignore deja entrar la
    # base o las notas, esto lo grita ANTES de que el paquete salga de la maquina.
    $adentro = [System.IO.Compression.ZipFile]::OpenRead($zip)
    try {
        $peligro = @($adentro.Entries | Where-Object {
                $_.FullName -match 'conversaciones\.db$|conversaciones\.js$|\.log$'
            })
    } finally { $adentro.Dispose() }
    if ($peligro.Count) {
        Escribir '  PARA: el paquete tiene datos personales adentro!' 'Red'
        $peligro | ForEach-Object { Escribir ('    ' + $_.FullName) 'Red' }
        Escribir '  Revisa el .gitignore antes de mandarlo.' 'Red'
        Escribir
        exit 1
    }
    Escribir '  Verificado: no lleva datos personales adentro.' 'DarkGray'

    # --- 7. el instalador .exe (opcional) -----------------------------------
    if ($Exe) {
        # Tres lugares posibles, y el PRIMERO es el mas probable: un
        # "winget install" sin admin lo pone por usuario en
        # %LOCALAPPDATA%\Programs, no en Program Files. El instalador clasico de
        # Inno, en cambio, va al (x86) incluso en una maquina de 64.
        $iscc = @(
            (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
            (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
        ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1

        if (-not $iscc) {
            Escribir
            Escribir '  Para el .exe falta Inno Setup 6 en ESTA maquina.' 'Yellow'
            Escribir '  (solo para compilar: el .exe que sale no lo necesita)' 'DarkGray'
            Escribir '      winget install JRSoftware.InnoSetup' 'Cyan'
            Escribir '  El zip ya esta hecho: podes mandar ese mientras.' 'DarkGray'
            Escribir
        } else {
            Escribir
            Escribir '  Compilando el instalador .exe...' 'Cyan'
            $iss = Join-Path $raiz 'dev\instalador.iss'
            # /Q para que no escupa una linea por archivo. El OutputDir del .iss
            # es relativo al .iss, o sea dev\dist.
            & $iscc "/Q" "/DMiVersion=$Version" "/DMiOrigen=$stage" $iss
            if ($LASTEXITCODE -ne 0) {
                Escribir '  Inno Setup fallo. El zip igual quedo hecho.' 'Red'
            } else {
                # $rutaExe y NO $exe: los nombres de variable en PowerShell son
                # case-insensitive, asi que $exe ES el parametro $Exe, que esta
                # declarado [switch]. Asignarle un string tira
                # "no se puede convertir System.String al tipo SwitchParameter"
                # y aborta el script DESPUES de haber compilado el .exe, dejando
                # el staging tirado. Paso.
                $rutaExe = Join-Path $dist ('instalar-conversaciones-' + $Version + '.exe')
                if (Test-Path -LiteralPath $rutaExe) {
                    $kbExe = [math]::Round((Get-Item -LiteralPath $rutaExe).Length / 1KB)
                    Escribir ('  Listo: dev\dist\{0}  ({1} KB)' -f (Split-Path -Leaf $rutaExe), $kbExe) 'Green'
                } else {
                    Escribir '  Inno dijo que salio bien pero no encuentro el .exe.' 'Yellow'
                }
            }
            Escribir
        }
    }

    # El staging se borra al final, no antes: el .iss lo necesita como origen.
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    Escribir
} finally { Pop-Location }
