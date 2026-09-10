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

    # --- 1. version ----------------------------------------------------------
    if (-not $Version) {
        # --dirty avisa si hay cambios sin commitear: el paquete queda marcado
        # como "no reproducible" en vez de mentir que es el tag limpio.
        $Version = (& git describe --tags --always --dirty 2>$null)
        if ($LASTEXITCODE -ne 0 -or -not $Version) { $Version = 'sin-version' }
        $Version = ([string]$Version).Trim().TrimStart('v')
    }
    Escribir ('  Version: {0}' -f $Version)

    # El .exe se compila SOLO desde una version limpia. Un "1.1.0-4-gab12-dirty"
    # queda escrito como AppVersion en Programas y caracteristicas, y despues no
    # hay forma de saber que arbol era. El zip si la acepta: para eso existe la
    # marca --dirty.
    if ($Exe -and $Version -notmatch '^\d+\.\d+\.\d+$') {
        Escribir
        Escribir ('  Para el .exe hace falta una version limpia (x.y.z), y esta es "{0}".' -f $Version) 'Red'
        Escribir '  Commitea y tagea, o pasala a mano:  .\dev\build.ps1 -Exe -Version 1.2.0' 'Yellow'
        Escribir
        exit 1
    }

    # --- 2. juntar -----------------------------------------------------------
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

    # --- 3. el papelito de instalacion y la version --------------------------
    #  Va en .txt en la raiz del zip: es lo primero que ve alguien que abre esto
    #  y no sabe nada. El .exe lo muestra en el wizard, asi que tiene que servir
    #  a los dos lectores: el que descomprimio y el que ya instalo.
    $instalar = @"
PANEL DE CONVERSACIONES DE CLAUDE CODE   -   version $Version
=============================================================

SI ESTAS INSTALANDO CON EL .EXE
-------------------------------
No tenes que hacer nada de lo de abajo: el instalador lo hace todo. Cuando
termine, abrilo desde el menu inicio y segui en COMO SE USA.

SI BAJASTE EL ZIP
-----------------
1. Descomprimi esta carpeta donde la quieras tener. Se puede mover despues: el
   instalador se re-apunta solo.

2. Abri PowerShell EN esta carpeta y corre:

       .\setup.ps1 -Instalar

   Escribe solo en tu usuario (HKCU y el PATH de usuario). NO pide admin.

3. Abri "Gadget de conversaciones.lnk" y listo.

COMO SE USA
-----------
En Claude Code, escribi  /save  en la conversacion que quieras guardar: queda
en el panel con un resumen de dos o tres lineas. Si le pusiste nombre con
/rename, el panel muestra ese nombre. Y  ! guardar  la guarda al instante, sin
pasar por la IA.

Un click en la tarjeta reabre la conversacion donde la dejaste. El boton (i)
del panel explica todo el resto: cada icono, cada boton y como se archiva.

Los comandos de terminal necesitan una terminal NUEVA, porque las que ya
estaban abiertas (Claude Code incluido) siguen con el PATH viejo:

       guardar "Titulo de la charla"
       borrar-conversacion -Listar
       cerrar-gadget

QUE INSTALA
-----------
Siete piezas, todas reversibles y todas en tu usuario. Para ver el estado en
cualquier momento:  .\setup.ps1

Dos de las siete pueden quedar como "aviso", y eso NO es una falla:

  - el plugin claude-hud de Claude Code, que no es parte de esto. Sin el, la
    barra de % de contexto es una estimacion y puede errar bastante.
  - el volcado de la cuota, que necesita que Claude Code ya tenga su
    settings.json. Sin el, el chip de arriba dice "sin datos de cuota".

Los dos se pueden completar despues: corres  .\setup.ps1 -Instalar  de nuevo y
listo.

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

    # La version, adentro de lo que se instala. Sin esto, cuando alguien escribe
    # "no me anda" no hay manera de saber que version tiene: el zip la lleva en
    # el nombre y el .exe en el registro, pero la carpeta instalada no la sabia.
    # La lee la ventana de ayuda del panel.
    [System.IO.File]::WriteAllText((Join-Path $stage 'VERSION'), ($Version + "`r`n"),
        [System.Text.UTF8Encoding]::new($false))

    # --- 4. verificar EL PAQUETE ---------------------------------------------
    #  Los tests corren ADENTRO del staging, y no es un detalle de estilo: el
    #  paquete lleva solo lo que git tiene versionado, asi que un archivo sin
    #  trackear esta en el arbol de trabajo (todo verde) y NO en el zip. Paso de
    #  verdad: cuatro piezas nuevas del gadget sin commitear, 63 tests en verde,
    #  y el paquete moria al arrancar porque gadget.ps1 dot-sourcea las piezas.
    #  Si fallan, el staging NO se borra: es el unico lugar donde se reproduce.
    #  Y se corren sobre una COPIA, no sobre el staging: arrancar la app deja
    #  archivos generados. La primera version de esto testeaba el staging mismo,
    #  la suite le creaba adentro un datos\conversaciones.db vacio y ese archivo
    #  entraba al zip; lo agarro el chequeo de datos personales de mas abajo.
    #  Regla: no ejecutar NADA adentro de lo que se va a empaquetar.
    if (-not $SinTests) {
        Escribir
        Escribir '  Verificando el paquete armado...' 'Cyan'
        $prueba = $stage + '-prueba'
        if (Test-Path -LiteralPath $prueba) { Remove-Item -LiteralPath $prueba -Recurse -Force }
        Copy-Item -LiteralPath $stage -Destination $prueba -Recurse -Force
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $prueba 'probar.ps1') | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Escribir '  Los tests FALLARON DENTRO DEL PAQUETE. No se empaqueta nada.' 'Red'
            Escribir ('  La copia queda para investigar:  {0}' -f $prueba) 'Yellow'
            Escribir
            exit 1
        }
        Remove-Item -LiteralPath $prueba -Recurse -Force
        Escribir '  Tests en verde sobre el paquete.' 'Green'
    }

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
