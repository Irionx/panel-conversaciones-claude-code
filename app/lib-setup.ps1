# =============================================================================
#  lib-setup.ps1 - Verifica y repara la instalacion del panel.
#
#  Ocho piezas, y se devuelven EN ESTE ORDEN:
#    1. el protocolo claudeconv://        (para los enlaces claudeconv://)
#    2. la carpeta en el PATH de usuario  (para que exista el comando guardar)
#    3. la junction del skill /save       (para que exista /save en Claude Code)
#    4. los shims para bash               (para que ande desde el prompt "!")
#    5. el volcado de la cuota            (para el chip de cuota de la cabecera)
#    6. el lanzador Conversaciones.exe    (abre el gadget sin consola a la vista)
#    7. el acceso directo                 (el .lnk que abre el gadget)
#    8. el plugin claude-hud              (no es nuestro: solo se avisa)
#
#  El lanzador va antes que el acceso directo porque el .lnk apunta a el.
#  Las piezas 5 y 8 pueden no tener arreglo posible: no hay settings.json que
#  envolver, o el plugin no esta. Eso es un AVISO y NO un error; si se cuentan
#  como error, una instalacion perfecta termina en rojo y con exit 1 en toda
#  maquina que no tenga el plugin. Ver Repair-Instalacion.
#
#  La base de datos no es una pieza: la crea sola la capa de Datos la primera
#  vez que arranca cualquier cosa. Ver ARQUITECTURA.md.
#
#  Todo en scope de USUARIO (HKCU y PATH User): nunca hace falta admin.
#
#  No se guarda ningun "ya instalado": se mide el estado real en cada corrida.
#  Asi, si moves la carpeta, la proxima vez se re-apunta solo.
#
#  Lo usan setup.ps1 (CLI) y gadget.ps1 (al arrancar).
# =============================================================================

$script:ClaveProto = 'HKCU:\Software\Classes\claudeconv'
$script:VersionShims = 3
$script:NombreAcceso = 'Gadget de conversaciones.lnk'
# Tiene que ser EL MISMO que el proceso se pone con
# SetCurrentProcessExplicitAppUserModelID en gadget.ps1. Si no coinciden, la
# ventana en ejecucion abre un segundo boton en la barra al lado del pineado.
$script:AppUserModelId = 'GIA.Conversaciones.Gadget'

# --- el AppUserModelID de un .lnk no se toca con WScript.Shell ---------------
#  Vive en el property store del acceso directo, asi que hay que ir por COM:
#  IShellLink -> IPersistFile::Load -> IPropertyStore -> SetValue -> Commit.
#
#  DOS COSAS QUE COSTARON UN RATO:
#   - PROPVARIANT mide 24 bytes en x64, no 16 (vt + 3 ushort reservados + una
#     union de 16). Declarado de 16, SetValue igual anda porque lee solo los
#     primeros 16, pero GetValue escribe de mas y devuelve basura SIN error:
#     escribis bien y al leer parece vacio.
#   - InitPropVariantFromString NO esta exportada en la propsys.dll de este
#     Windows. El PROPVARIANT de string se arma a mano: vt = VT_LPWSTR (31) y un
#     puntero a memoria COM, que PropVariantClear libera despues.
if (-not ('LnkAppId' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class LnkAppId {
    [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
    private class ShellLink { }

    [ComImport, Guid("0000010b-0000-0000-C000-000000000046"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IPersistFile {
        void GetClassID(out Guid pClassID);
        [PreserveSig] int IsDirty();
        void Load([MarshalAs(UnmanagedType.LPWStr)] string f, int mode);
        void Save([MarshalAs(UnmanagedType.LPWStr)] string f, [MarshalAs(UnmanagedType.Bool)] bool remember);
        void SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string f);
        void GetCurFile([MarshalAs(UnmanagedType.LPWStr)] out string f);
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROPERTYKEY { public Guid fmtid; public uint pid; }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROPVARIANT { public ushort vt; public ushort r1, r2, r3; public IntPtr p; public IntPtr p2; }

    [ComImport, Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IPropertyStore {
        void GetCount(out uint c);
        void GetAt(uint i, out PROPERTYKEY k);
        void GetValue(ref PROPERTYKEY k, out PROPVARIANT v);
        void SetValue(ref PROPERTYKEY k, ref PROPVARIANT v);
        void Commit();
    }

    private const ushort VT_LPWSTR = 31;

    [DllImport("ole32.dll", PreserveSig = false)]
    private static extern void PropVariantClear(ref PROPVARIANT pv);

    // PKEY_AppUserModel_ID
    private static PROPERTYKEY Key() {
        PROPERTYKEY k = new PROPERTYKEY();
        k.fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");
        k.pid = 5;
        return k;
    }

    public static string Leer(string lnk) {
        object o = new ShellLink();
        ((IPersistFile)o).Load(lnk, 0);
        PROPERTYKEY k = Key();
        PROPVARIANT v;
        ((IPropertyStore)o).GetValue(ref k, out v);
        string s = (v.vt == VT_LPWSTR) ? Marshal.PtrToStringUni(v.p) : null;
        PropVariantClear(ref v);
        Marshal.ReleaseComObject(o);
        return s;
    }

    public static void Escribir(string lnk, string appId) {
        object o = new ShellLink();
        IPersistFile pf = (IPersistFile)o;
        pf.Load(lnk, 2); // STGM_READWRITE
        PROPERTYKEY k = Key();
        PROPVARIANT v = new PROPVARIANT();
        v.vt = VT_LPWSTR;
        v.p = Marshal.StringToCoTaskMemUni(appId);
        IPropertyStore ps = (IPropertyStore)o;
        ps.SetValue(ref k, ref v);
        ps.Commit();
        PropVariantClear(ref v);
        pf.Save(lnk, true);
        Marshal.ReleaseComObject(o);
    }
}
'@
}

# --- shims para bash ---------------------------------------------------------
#  Se generan desde aca y no se editan a mano, asi el setup los puede reparar.
#  La carpeta sale de BASH_SOURCE: sin rutas hardcodeadas, el shim viaja con la
#  carpeta y sigue funcionando si la moves.
function Get-TextoShim {
    param([Parameter(Mandatory)][string]$Cmd)

    return @"
#!/usr/bin/env bash
# shim v$script:VersionShims - lo genera lib-setup.ps1, no editar a mano.
#
# Existe porque Git Bash NO resuelve .cmd desde el PATH (solo el nombre exacto
# y .exe), asi que hace falta un archivo sin extension con este nombre.
aqui="`$(cd "`$(dirname "`${BASH_SOURCE[0]}")" && pwd)"
exec "`$aqui/$Cmd" "`$@"
"@
}

# --- escribe un shim con las reglas que lo hacen funcionar --------------------
#  LF obligatorio: con CRLF el shebang queda "/usr/bin/env bash\r" y no arranca.
#  Sin BOM: bash no lo entiende en la primera linea.
function Write-Shim {
    param(
        [Parameter(Mandatory)][string]$Ruta,
        [Parameter(Mandatory)][string]$Contenido
    )
    $lf = $Contenido -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($Ruta, $lf, [System.Text.UTF8Encoding]::new($false))
}

# --- los .cmd son wrappers minimos para cmd.exe y PowerShell -----------------
function Get-TextoCmd {
    param([Parameter(Mandatory)][string]$Ps1)

    return @"
@echo off
REM Wrapper generado por lib-setup.ps1 si faltaba.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\app\$Ps1" %*
"@
}

# --- el volcado de la cuota, como texto ---------------------------------------
#  Vive en una funcion y no suelto adentro del arreglo porque lo necesitan los
#  DOS lados: instalar (para envolver el statusline) y desinstalar (para
#  reconocer si el que hay es exactamente el nuestro). Dos copias del mismo
#  literal se desincronizan, y el dia que eso pasa el desinstalador deja de
#  reconocer lo que instalo y no deshace nada.
function Get-TextoVolcado {
    return 'cc_cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; cc_pl=$(cat); ' +
    'cc_t="$cc_cfg/.statusline.$$.tmp"; printf ''%s'' "$cc_pl" > "$cc_t" && ' +
    'mv -f "$cc_t" "$cc_cfg/statusline-ultimo.json" 2>/dev/null'
}

# --- deshacer el volcado, SOLO si es exactamente el nuestro -------------------
#  Devuelve { Texto; Como }: Texto es el settings.json ya sin el volcado, o
#  $null si no se puede tocar con seguridad, y Como dice que hacer a mano.
#
#  Por que tanto cuidado: el comando del statusline es de la persona, no
#  nuestro, y en la practica aparece EDITADO A MANO. Medido en la maquina de
#  desarrollo: un statusline que entreteje el volcado con el comando de
#  claude-hud en vez de envolverlo. Desarmar eso a ciegas le rompe el HUD. Asi
#  que se deshace unicamente lo que coincide byte a byte con lo que escribe
#  este instalador; cualquier otra cosa se deja intacta y se explica.
function Get-AjustesSinVolcado {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Texto,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Comando
    )

    $vol = Get-TextoVolcado
    $abre = '; printf ''%s'' "$cc_pl" | { '
    $cierra = ' ; }'

    # Caso 1: no habia statusline y lo agregamos entero. Se saca el bloque.
    # -ceq y no -eq: en PowerShell -eq entre strings NO distingue mayusculas, y
    # aca la comparacion tiene que ser exacta.
    if ($Comando -ceq $vol) {
        $bloque = '  "statusLine": { "type": "command", "command": ' + ($vol | ConvertTo-Json) + ' },'
        foreach ($cand in @(($bloque + "`r`n"), ($bloque + "`n"), $bloque)) {
            if ($Texto.Contains($cand)) {
                return [pscustomobject]@{ Texto = $Texto.Replace($cand, ''); Como = @() }
            }
        }
        return [pscustomobject]@{ Texto = $null; Como = @(
                'el statusline es solo el volcado, pero no ubico su bloque en el archivo:',
                'saca la clave "statusLine" de ~\.claude\settings.json a mano') }
    }

    # Caso 2: envolvimos un statusline que ya estaba. Se restaura el de adentro.
    if ($Comando.StartsWith($vol + $abre) -and $Comando.EndsWith($cierra)) {
        $desde = ($vol + $abre).Length
        $original = $Comando.Substring($desde, $Comando.Length - $desde - $cierra.Length)
        $de = $Comando | ConvertTo-Json
        if (-not $Texto.Contains($de)) {
            return [pscustomobject]@{ Texto = $null; Como = @(
                    'no ubico el comando del statusline en el archivo; sacalo a mano') }
        }
        return [pscustomobject]@{ Texto = $Texto.Replace($de, ($original | ConvertTo-Json)); Como = @() }
    }

    # Cualquier otra cosa: no lo escribimos nosotros, o lo editaron. No se toca.
    return [pscustomobject]@{ Texto = $null; Como = @(
            'tu statusline no es el que escribio este instalador (esta editado a mano),',
            'asi que no lo toco: desarmarlo a ciegas puede romperte el HUD. Para sacarlo,',
            'borra de su comando la parte que escribe statusline-ultimo.json y deja el resto.') }
}

# --- el lanzador: donde queda y como se sabe si esta al dia -------------------
#  Un compilado nunca sale igual dos veces, asi que no se compara el .exe: se le
#  graba adentro (en Comments, sus propiedades de archivo) el hash de lanzador.cs.
#  Si el codigo cambia, la marca deja de coincidir y la pieza 6 lo recompila.
function Get-RutaLanzador {
    param([Parameter(Mandatory)][string]$Carpeta)
    return (Join-Path $Carpeta 'app\Conversaciones.exe')
}
function Get-MarcaLanzador {
    param([Parameter(Mandatory)][string]$Fuente)
    return ('fuente sha256 ' + (Get-FileHash -LiteralPath $Fuente -Algorithm SHA256).Hash.ToLowerInvariant())
}

# --- compila el lanzador ------------------------------------------------------
#  Con el C# que trae .NET Framework, o sea Windows: sin SDK. Por CodeDom y no
#  llamando a csc.exe a mano: es lo mismo que usa Add-Type, que el gadget ya
#  corre despues de soltar su consola sin que asome ninguna ventana.
function Build-Lanzador {
    param([Parameter(Mandatory)][string]$Carpeta)

    # CodeDom es de .NET Framework: en PowerShell 7 el tipo ni siquiera existe.
    # Sin este aviso el error habla de un tipo que no se encuentra y nadie ata
    # eso con "abrilo con powershell.exe".
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        throw 'el lanzador se compila con Windows PowerShell 5.1 (powershell.exe), no con PowerShell 7'
    }

    $fuente = Join-Path $Carpeta 'app\lanzador.cs'
    $info = @(
        '[assembly: System.Reflection.AssemblyTitle("Panel de conversaciones de Claude Code")]',
        '[assembly: System.Reflection.AssemblyProduct("Conversaciones")]',
        ('[assembly: System.Reflection.AssemblyDescription("{0}")]' -f (Get-MarcaLanzador -Fuente $fuente))
    ) -join "`r`n"

    $cp = New-Object System.CodeDom.Compiler.CompilerParameters
    $cp.GenerateExecutable = $true
    $cp.GenerateInMemory = $false
    $cp.OutputAssembly = Get-RutaLanzador -Carpeta $Carpeta
    # winexe = subsistema de ventanas: al abrirlo, Windows no le crea consola.
    $cp.CompilerOptions = ('/target:winexe /platform:anycpu /optimize+ "/win32icon:{0}"' -f (Join-Path $Carpeta 'app\gadget.ico'))
    [void]$cp.ReferencedAssemblies.Add('System.dll')
    [void]$cp.ReferencedAssemblies.Add('System.Windows.Forms.dll')

    $prov = New-Object Microsoft.CSharp.CSharpCodeProvider
    try {
        $r = $prov.CompileAssemblyFromSource($cp, [string[]]@([System.IO.File]::ReadAllText($fuente), $info))
    } finally { $prov.Dispose() }
    $errs = @($r.Errors | Where-Object { -not $_.IsWarning } | ForEach-Object { $_.ErrorText })
    if ($errs.Count) { throw ('no compilo lanzador.cs: ' + ($errs -join '; ')) }
}

# --- estado de las ocho piezas ------------------------------------------------
#  Devuelve un objeto por pieza: Clave, Nombre, Ok, Detalle y un scriptblock
#  Arreglar (o $null si no se puede arreglar solo).
#
#  Los scriptblocks usan .GetNewClosure() a proposito: sin eso, al invocarlos
#  desde otro scope las variables de esta funcion no resuelven.
function Get-EstadoInstalacion {
    param(
        # La RAIZ del proyecto, no app\: lib-setup.ps1 vive en app\ pero mide
        # cosas que cuelgan de la raiz (bin\, skill\, el protocolo).
        [string]$Carpeta = (Split-Path -Parent $PSScriptRoot),
        # Sale por parametro para poder probar la pieza 5 contra un settings.json
        # de mentira. Un arreglo que solo se puede probar contra el archivo de
        # verdad no se prueba nunca.
        [string]$Ajustes = (Join-Path $env:USERPROFILE '.claude\settings.json'),
        # Igual que $Ajustes, y por el mismo motivo: en la maquina del que
        # desarrolla el plugin SIEMPRE esta instalado, asi que el caso "falta"
        # no se podria probar nunca contra la ruta real.
        [string]$CacheHud = (Join-Path $env:USERPROFILE '.claude\plugins\claude-hud\context-cache')
    )

    $Carpeta = (Resolve-Path -LiteralPath $Carpeta).Path.TrimEnd('\')
    # El protocolo y el acceso directo abren los dos por el lanzador (pieza 6).
    $lanzador = Get-RutaLanzador -Carpeta $Carpeta

    # Las FUNCIONES tampoco viajan en un .GetNewClosure(): el scriptblock queda
    # atado a un modulo nuevo, que solo ve el scope global, y lib-setup.ps1 esta
    # dot-sourceado en el scope de quien lo llamo. Invocado como ".\setup.ps1"
    # eso rompia shims, cuota y lanzador con "el termino X no se reconoce".
    $fnTextoShim = ${function:Get-TextoShim}
    $fnTextoCmd = ${function:Get-TextoCmd}
    $fnEscribirShim = ${function:Write-Shim}
    $fnTextoVolcado = ${function:Get-TextoVolcado}
    $fnBuildLanzador = ${function:Build-Lanzador}

    # --- 1. protocolo claudeconv:// ------------------------------------------
    #  Se copia a una local a proposito: dentro de un .GetNewClosure() un
    #  $script:algo se resuelve contra el scope NUEVO del closure, donde no
    #  existe, y llega como $null. Las locales si se capturan.
    $claveProto = $script:ClaveProto
    $claveCmd = Join-Path $claveProto 'shell\open\command'
    $esperado = ('"{0}" --abrir "%1"' -f $lanzador)
    $actual = $null
    if (Test-Path $claveCmd) { $actual = [string](Get-Item $claveCmd).GetValue('') }

    $detalleProto = if (-not $actual) { 'sin registrar' }
    elseif ($actual -ne $esperado) {
        # Dos formas: la de ahora y la vieja, que abria powershell.exe directo.
        # La vieja de ESTA carpeta no es "otra carpeta": setup.ps1 avisaria que
        # le esta sacando el protocolo a otra instalacion, y es esta misma.
        $otra = '?'; $vieja = $false
        if ($actual -match '"(.+)\\app\\Conversaciones\.exe"') { $otra = $Matches[1] }
        elseif ($actual -match '-File "(.+)\\app\\abrir-conversacion\.ps1"') { $otra = $Matches[1]; $vieja = $true }
        if ($otra -ine $Carpeta) { 'lo tiene otra carpeta: ' + $otra }
        elseif ($vieja) { 'apunta aca, pero abre PowerShell directo (deja una consola)' }
        else { 'apunta aca, pero con otro comando' }
    }
    else { 'registrado y apuntando aca' }

    [pscustomobject]@{
        Clave    = 'protocolo'
        Nombre   = 'protocolo claudeconv://'
        Ok       = ($actual -eq $esperado)
        Detalle  = $detalleProto
        Arreglar = {
            New-Item -Path $claveProto -Force | Out-Null
            Set-ItemProperty -Path $claveProto -Name '(default)' -Value 'URL:Claude Code Conversacion'
            Set-ItemProperty -Path $claveProto -Name 'URL Protocol' -Value ''
            New-Item -Path (Join-Path $claveProto 'DefaultIcon') -Force | Out-Null
            Set-ItemProperty -Path (Join-Path $claveProto 'DefaultIcon') -Name '(default)' -Value ('{0},0' -f $lanzador)
            New-Item -Path $claveCmd -Force | Out-Null
            Set-ItemProperty -Path $claveCmd -Name '(default)' -Value $esperado
        }.GetNewClosure()
    }

    # --- 2. bin\ en el PATH de usuario ---------------------------------------
    #  Va bin\ y no la raiz: en el PATH solo tienen que estar los comandos, no
    #  todo el proyecto. Antes la raiz entera estaba en el PATH y eso exponia
    #  cualquier .ps1 o .cmd que apareciera al lado.
    #
    #  Si quedo la RAIZ del layout viejo en el PATH, se saca: dejarla no rompe
    #  nada pero ensucia, y peor, `guardar` seguiria resolviendo al archivo
    #  viejo si alguien no borro el anterior.
    $dirBin = Join-Path $Carpeta 'bin'
    $pathUser = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $entradas = @($pathUser -split ';' | Where-Object { $_ } | ForEach-Object { $_.Trim().TrimEnd('\') })
    $enPath = $entradas -icontains $dirBin
    $sobraRaiz = $entradas -icontains $Carpeta

    $detallePath = if ($enPath -and -not $sobraRaiz) { 'bin\ ya esta en el PATH de usuario' }
    elseif ($enPath) { 'bin\ esta, pero quedo tambien la raiz del layout viejo' }
    else { 'falta bin\ en el PATH de usuario' }

    [pscustomobject]@{
        Clave    = 'path'
        Nombre   = 'bin\ en el PATH'
        Ok       = ($enPath -and -not $sobraRaiz)
        Detalle  = $detallePath
        Arreglar = {
            # NUNCA 'setx PATH "%PATH%;..."': %PATH% trae tambien el PATH de
            # maquina (lo copiaria dentro del de usuario) y setx trunca a 1024
            # caracteres. La API de .NET con scope User no tiene ninguno de los
            # dos problemas.
            $viejo = [Environment]::GetEnvironmentVariable('PATH', 'User')
            # Se recalcula aca dentro y no se confia en el chequeo de afuera:
            # asi llamarlo dos veces no deja la carpeta duplicada.
            $partes = @($viejo -split ';' | Where-Object { $_ } |
                Where-Object { $_.Trim().TrimEnd('\') -ine $Carpeta } |
                Where-Object { $_.Trim().TrimEnd('\') -ine $dirBin })
            $partes += $dirBin
            [Environment]::SetEnvironmentVariable('PATH', ($partes -join ';'), 'User')
        }.GetNewClosure()
    }

    # --- 3. junction del skill /save -----------------------------------------
    $origenSkill = Join-Path $Carpeta 'skill'
    $destinoSkill = Join-Path $env:USERPROFILE '.claude\skills\save'

    $okSkill = $false
    $detalleSkill = 'sin crear'
    $puedeSkill = $true

    if (-not (Test-Path -LiteralPath $origenSkill)) {
        $detalleSkill = 'falta la carpeta skill\ en el panel'
        $puedeSkill = $false
    } elseif (Test-Path -LiteralPath $destinoSkill) {
        $item = Get-Item -LiteralPath $destinoSkill -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            $blanco = ([string[]]$item.Target)[0]
            if ($blanco -and $blanco.TrimEnd('\') -ieq $origenSkill.TrimEnd('\')) {
                $okSkill = $true
                $detalleSkill = 'junction apuntando aca'
            } else {
                $detalleSkill = 'la junction la tiene otra carpeta: ' + $blanco
            }
        } else {
            # Hay un skill de verdad ahi: no se pisa nada sin avisar.
            $detalleSkill = 'ya hay una carpeta real ahi, no la piso'
            $puedeSkill = $false
        }
    }

    [pscustomobject]@{
        Clave    = 'skill'
        Nombre   = 'skill /save'
        Ok       = $okSkill
        Detalle  = $detalleSkill
        Arreglar = if ($puedeSkill) {
            {
                $padre = Split-Path -Parent $destinoSkill
                if (-not (Test-Path -LiteralPath $padre)) {
                    New-Item -ItemType Directory -Force -Path $padre | Out-Null
                }
                # Si habia una junction vieja apuntando mal, se saca primero.
                #
                # OJO: NO usar Remove-Item -Recurse aca. En PowerShell 5.1 puede
                # seguir la junction y borrar el CONTENIDO del destino, o sea el
                # skill\SKILL.md original de esta carpeta. Directory::Delete borra
                # solo el punto de reparse y nunca lo atraviesa.
                if (Test-Path -LiteralPath $destinoSkill) {
                    [System.IO.Directory]::Delete($destinoSkill, $false)
                }
                # Junction y no symlink: no pide admin ni modo desarrollador.
                New-Item -ItemType Junction -Path $destinoSkill -Target $origenSkill | Out-Null
            }.GetNewClosure()
        } else { $null }
    }

    # --- 4. shims y wrappers --------------------------------------------------
    $arch = @(
        @{ Shim = 'guardar'; Cmd = 'guardar.cmd'; Ps1 = 'guardar.ps1' },
        @{ Shim = 'borrar-conversacion'; Cmd = 'borrar-conversacion.cmd'; Ps1 = 'borrar.ps1' },
        @{ Shim = 'cerrar-gadget'; Cmd = 'cerrar-gadget.cmd'; Ps1 = 'cerrar-gadget.ps1' }
    )

    $faltantes = @()
    foreach ($a in $arch) {
        # Los comandos viven en bin\, que es lo unico que va al PATH.
        $rutaShim = Join-Path $dirBin $a.Shim
        $rutaCmd = Join-Path $dirBin $a.Cmd

        if (-not (Test-Path -LiteralPath $rutaCmd)) { $faltantes += $a.Cmd }

        if (-not (Test-Path -LiteralPath $rutaShim)) {
            $faltantes += $a.Shim
        } else {
            $txt = [System.IO.File]::ReadAllText($rutaShim)
            if ($txt -notmatch ('shim v{0}\b' -f $script:VersionShims)) {
                $faltantes += ('{0} (desactualizado)' -f $a.Shim)
            } elseif ($txt.Contains("`r")) {
                $faltantes += ('{0} (CRLF)' -f $a.Shim)
            }
        }
    }

    [pscustomobject]@{
        Clave    = 'shims'
        Nombre   = 'comandos para bash'
        Ok       = ($faltantes.Count -eq 0)
        Detalle  = if ($faltantes.Count -eq 0) { 'los 6 archivos de bin\ al dia' } else { 'faltan o estan viejos: ' + ($faltantes -join ', ') }
        Arreglar = {
            foreach ($a in $arch) {
                if (-not (Test-Path -LiteralPath $dirBin)) {
                    New-Item -ItemType Directory -Path $dirBin -Force | Out-Null
                }
                & $fnEscribirShim -Ruta (Join-Path $dirBin $a.Shim) -Contenido (& $fnTextoShim -Cmd $a.Cmd)
                $rutaCmd = Join-Path $dirBin $a.Cmd
                # El .cmd solo se crea si falta: los que vienen con la carpeta
                # tienen documentacion propia y no hay por que pisarla.
                if (-not (Test-Path -LiteralPath $rutaCmd)) {
                    [System.IO.File]::WriteAllText($rutaCmd, ((& $fnTextoCmd -Ps1 $a.Ps1) -replace "`n", "`r`n"), [System.Text.UTF8Encoding]::new($false))
                }
            }
        }.GetNewClosure()
    }

    # --- 5. el volcado de la cuota -------------------------------------------
    #  La cuota real de la cuenta (rate_limits) NO existe en ningun archivo:
    #  Claude Code se la pasa por stdin al comando del statusline, y el
    #  statusline es su unico consumidor. Sin este volcado, el chip de la
    #  cabecera dice "sin datos de cuota". Ver ARQUITECTURA.md seccion 7.
    #
    #  Se ENVUELVE el comando que haya, no se reemplaza: cada uno tiene el
    #  statusline que quiere y pisarselo seria una falta de respeto (y ademas
    #  romperia su HUD). Se lee todo el stdin primero (cc_pl=$(cat)) para que el
    #  consumidor no pueda matar la escritura con un SIGPIPE y dejar el archivo
    #  cortado, se escribe a un temporal y se hace mv, que es atomico.
    # Copia local: dentro de un .GetNewClosure() un parametro se captura, pero
    # conviene el nombre corto para que el codigo de abajo se lea igual.
    $ajustes = $Ajustes
    $cmdActual = $null
    $hayAjustes = Test-Path -LiteralPath $ajustes
    if ($hayAjustes) {
        try { $cmdActual = [string](Get-Content -LiteralPath $ajustes -Raw | ConvertFrom-Json).statusLine.command } catch { }
    }
    # El marcador es la propia ruta del volcado: sirva la forma que sirva, si ya
    # esta ahi es que alguien ya lo instalo. Asi es idempotente.
    $cuotaOk = $cmdActual -and $cmdActual.Contains('statusline-ultimo.json')

    $detalleCuota = if (-not $hayAjustes) { 'no encuentro settings.json de Claude Code' }
    elseif ($cuotaOk) { 'el statusline vuelca la cuota' }
    elseif ($cmdActual) { 'hay un statusline, pero no vuelca la cuota' }
    else { 'no hay statusline configurado' }

    [pscustomobject]@{
        Clave    = 'cuota'
        Nombre   = 'volcado de la cuota'
        Ok       = [bool]$cuotaOk
        Detalle  = $detalleCuota
        # Sin settings.json no hay nada que arreglar desde aca.
        Arreglar = if (-not $hayAjustes) { $null } else {
            {
                # El literal vive en Get-TextoVolcado: lo comparte con el
                # desinstalador, que necesita reconocer exactamente esto.
                $volcado = & $fnTextoVolcado

                $txt = Get-Content -LiteralPath $ajustes -Raw
                Copy-Item -LiteralPath $ajustes -Destination ($ajustes + '.bak') -Force

                if ($cmdActual) {
                    # Envolver: el comando original entra en un grupo y se le
                    # alimenta el stdin que ya se leyo.
                    $nuevo = $volcado + '; printf ''%s'' "$cc_pl" | { ' + $cmdActual + ' ; }'
                    # Reemplazo del literal JSON exacto: mucho mas seguro que
                    # reserializar todo el settings.json del usuario.
                    $de = $cmdActual | ConvertTo-Json
                    $a = $nuevo | ConvertTo-Json
                    if (-not $txt.Contains($de)) {
                        throw 'no pude ubicar el comando del statusline en settings.json; toca a mano'
                    }
                    $txt = $txt.Replace($de, $a)
                } else {
                    # No habia statusline: se agrega uno que solo vuelca y no
                    # imprime nada, asi no aparece una linea vacia.
                    $bloque = '  "statusLine": { "type": "command", "command": ' + ($volcado | ConvertTo-Json) + ' },'
                    $i = $txt.IndexOf('{')
                    if ($i -lt 0) { throw 'settings.json no parece un objeto JSON' }
                    $txt = $txt.Substring(0, $i + 1) + "`n" + $bloque + $txt.Substring($i + 1)
                }
                # Si quedo JSON invalido, no se escribe: mejor sin cuota que con
                # el settings.json roto.
                $null = $txt | ConvertFrom-Json
                [System.IO.File]::WriteAllText($ajustes, $txt, [System.Text.UTF8Encoding]::new($false))
            }.GetNewClosure()
        }
    }

    # --- 6. el lanzador ------------------------------------------------------
    #  powershell.exe es de consola: abierto desde un acceso o un enlace, Windows
    #  le crea una, y en Windows 11 es una ventana de Windows Terminal que
    #  -WindowStyle Hidden no esconde. Conversaciones.exe no la crea: lanzador.cs.
    $fuenteLanz = Join-Path $Carpeta 'app\lanzador.cs'
    $okLanz = $false
    if (-not (Test-Path -LiteralPath $fuenteLanz)) { $detalleLanz = 'falta app\lanzador.cs' }
    elseif (-not (Test-Path -LiteralPath $lanzador)) { $detalleLanz = 'sin compilar' }
    elseif ((Get-Item -LiteralPath $lanzador).VersionInfo.Comments -cne (Get-MarcaLanzador -Fuente $fuenteLanz)) {
        $detalleLanz = 'desactualizado: cambio lanzador.cs'
    } else {
        $okLanz = $true
        $detalleLanz = 'compilado y al dia'
    }

    [pscustomobject]@{
        Clave    = 'lanzador'
        Nombre   = 'lanzador sin consola'
        Ok       = $okLanz
        Detalle  = $detalleLanz
        # Sin el codigo no hay nada que compilar.
        Arreglar = if (Test-Path -LiteralPath $fuenteLanz) {
            { & $fnBuildLanzador -Carpeta $Carpeta }.GetNewClosure()
        } else { $null }
    }

    # --- 7. el acceso directo -------------------------------------------------
    #  Antes esto vivia en un arreglar-pineado.ps1 suelto que habia que acordarse
    #  de correr. Mover la carpeta app\ dejo el acceso directo apuntando a un
    #  .ps1 que ya no existia y NADIE aviso: el gadget simplemente no abria. Una
    #  pieza del instalador se mide sola en cada arranque, un script suelto no.
    #
    #  De paso, ahora el .lnk se puede fabricar de cero, asi que no hace falta
    #  versionar un binario con rutas absolutas adentro.
    $rutaLnk = Join-Path $Carpeta $script:NombreAcceso
    $icoLnk = ('{0}\app\gadget.ico,0' -f $Carpeta)
    $appId = $script:AppUserModelId

    $okLnk = $false
    $detalleLnk = 'no existe'
    if (Test-Path -LiteralPath $rutaLnk) {
        try {
            $sh = New-Object -ComObject WScript.Shell
            $l = $sh.CreateShortcut($rutaLnk)
            $mal = @()
            # Uno viejo abre powershell.exe directo: anda, pero deja una consola.
            if ($l.TargetPath -like '*\powershell.exe') { $mal += 'abre PowerShell directo (deja una consola)' }
            elseif ($l.TargetPath -ine $lanzador -or $l.Arguments) { $mal += 'apunta a otra carpeta' }
            if ($l.IconLocation -ne $icoLnk) { $mal += 'sin el icono' }
            # El AppUserModelID es el que funde la ventana con el boton pineado.
            # El $( ) NO es de adorno: en PS 5.1 un try/catch entre parentesis
            # comunes no es una expresion y tira "el termino 'try' no se
            # reconoce". Hace falta la subexpresion.
            $idActual = $(try { [LnkAppId]::Leer($rutaLnk) } catch { $null })
            if ($idActual -ne $appId) { $mal += 'sin AppUserModelID' }
            $okLnk = ($mal.Count -eq 0)
            $detalleLnk = if ($okLnk) { 'listo y apuntando aca' } else { ($mal -join ', ') }
        } catch {
            $detalleLnk = 'no lo pude leer: ' + $_.Exception.Message
        }
    }


    [pscustomobject]@{
        Clave    = 'acceso'
        Nombre   = 'acceso directo'
        Ok       = $okLnk
        Detalle  = $detalleLnk
        Arreglar = {
            $sh = New-Object -ComObject WScript.Shell
            $l = $sh.CreateShortcut($rutaLnk)
            $l.TargetPath = $lanzador
            $l.Arguments = ''
            $l.WorkingDirectory = $Carpeta
            $l.IconLocation = $icoLnk
            $l.Description = 'Panel de conversaciones de Claude Code'
            $l.Save()
            # El AppUserModelID va DESPUES del Save: el Save de WScript.Shell
            # reescribe el .lnk entero y se llevaria puesto el property store.
            [LnkAppId]::Escribir($rutaLnk, $appId)
        }.GetNewClosure()
    }

    # --- 8. el plugin claude-hud ----------------------------------------------
    #  NO es parte de esta instalacion y no se puede arreglar desde aca, pero si
    #  falta hay que DECIRLO: lib-conversaciones.ps1 saca de su cache el tamano
    #  real de la ventana de contexto. Sin eso cae a adivinar (200k o 1M segun
    #  cuantos tokens haya) y la barra puede errar por 68 puntos: una sesion de
    #  171k en un modelo de 1M se muestra al 85% en rojo cuando va por el 17%.
    #
    #  Se declara como pieza justamente para que no sea una dependencia oculta:
    #  el que instala esto en otra maquina se tiene que enterar.
    $hayHud = Test-Path -LiteralPath $CacheHud

    # Los dos comandos que lo instalan. El marketplace va PRIMERO: el plugin no
    # esta en el oficial, asi que sin agregarlo el install no lo encuentra.
    #
    # Se MUESTRAN y no se corren, y esto es a proposito:
    #   - es codigo de otra persona (jarrodwatts/claude-hud). Claude Code pide
    #     confirmacion antes de instalar un plugin, y este setup corre en
    #     silencio desde el .exe: saltearle esa confirmacion a alguien para
    #     bajarle un repo ajeno no es nuestro lugar.
    #   - no serviria igual: el plugin necesita que Claude Code se reinicie para
    #     cargarse, y despues correr una vez para escribir su cache.
    #   - y "claude" puede no estar en el PATH, asi que se chequea antes de
    #     recomendar un comando que no va a andar.
    $hayClaude = [bool](Get-Command claude -ErrorAction SilentlyContinue)

    [pscustomobject]@{
        Clave    = 'hud'
        Nombre   = 'plugin claude-hud'
        Ok       = $hayHud
        Detalle  = if ($hayHud) { 'instalado: el % de contexto es exacto' }
        else { 'no esta: el % de contexto va a ser una estimacion (puede errar mucho)' }
        # Instalarlo es cosa de Claude Code, no de este panel: ver arriba.
        Arreglar = $null
        # El COMO, para las piezas que no se pueden arreglar desde aca. Lo
        # muestran setup.ps1 y el dialogo del gadget.
        Como     = if ($hayHud) { @() }
        elseif ($hayClaude) {
            @('claude plugin marketplace add jarrodwatts/claude-hud',
                'claude plugin install claude-hud@claude-hud')
        } else {
            @('no encuentro el comando "claude" en el PATH:',
                'abri Claude Code y escribi  /plugin  para instalar claude-hud')
        }
    }

}

# --- repara las piezas que esten mal -----------------------------------------
function Repair-Instalacion {
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$Piezas)

    $hechas = @()
    $errores = @()
    $avisos = @()

    foreach ($p in $Piezas) {
        if ($p.Ok) { continue }
        # Sin arreglo posible NO es un error: es algo que no esta en nuestras
        # manos (el plugin claude-hud) o que todavia no se puede (no hay
        # settings.json). Error es lo que intentamos arreglar y fallo; si no se
        # separan, exit 1 deja de querer decir nada.
        if (-not $p.Arreglar) {
            $avisos += ('{0}: {1}' -f $p.Nombre, $p.Detalle)
            continue
        }
        try {
            & $p.Arreglar
            $hechas += $p.Nombre
        } catch {
            $errores += ('{0}: {1}' -f $p.Nombre, $_.Exception.Message)
        }
    }

    return [pscustomobject]@{ Hechas = $hechas; Errores = $errores; Avisos = $avisos }
}

# --- deshace lo que toco la instalacion --------------------------------------
#  NUNCA toca datos\. Desinstalar la app no es tirar las conversaciones del
#  usuario: si quiere borrarlas, las borra el. Y si reinstala, se las encuentra.
#
#  Tampoco borra la carpeta del proyecto: de eso se encarga quien la puso ahi
#  (el instalador .exe, o el usuario que descomprimio el zip).
function Uninstall-Instalacion {
    [CmdletBinding()]
    param(
        [string]$Carpeta = (Split-Path -Parent $PSScriptRoot),
        # Por parametro por el mismo motivo que en Get-EstadoInstalacion: probar
        # esto contra el settings.json de verdad seria jugar a la ruleta con la
        # terminal de la persona.
        [string]$Ajustes = (Join-Path $env:USERPROFILE '.claude\settings.json')
    )

    $Carpeta = (Resolve-Path -LiteralPath $Carpeta).Path.TrimEnd('\')
    $hechas = @()
    $errores = @()
    $avisos = @()

    # 1. el protocolo, solo si sigue apuntando ACA. Si otro panel lo reclamo, se
    #    lo deja: no es nuestro para borrar.
    try {
        $claveCmd = Join-Path $script:ClaveProto 'shell\open\command'
        if (Test-Path $claveCmd) {
            $actual = [string](Get-Item $claveCmd).GetValue('')
            if ($actual -like ('*' + $Carpeta + '*')) {
                Remove-Item -Path $script:ClaveProto -Recurse -Force
                $hechas += 'protocolo claudeconv://'
            }
        }
    } catch { $errores += 'protocolo: ' + $_.Exception.Message }

    # 2. bin\ del PATH de usuario (y la raiz, si quedo del layout viejo)
    try {
        $dirBin = Join-Path $Carpeta 'bin'
        $viejo = [Environment]::GetEnvironmentVariable('PATH', 'User')
        $partes = @($viejo -split ';' | Where-Object { $_ } |
            Where-Object { $_.Trim().TrimEnd('\') -ine $dirBin } |
            Where-Object { $_.Trim().TrimEnd('\') -ine $Carpeta })
        if ($partes.Count -ne @($viejo -split ';' | Where-Object { $_ }).Count) {
            [Environment]::SetEnvironmentVariable('PATH', ($partes -join ';'), 'User')
            $hechas += 'bin\ del PATH'
        }
    } catch { $errores += 'PATH: ' + $_.Exception.Message }

    # 3. la junction del skill, solo si apunta aca. Si es una carpeta REAL, no
    #    se toca: seria borrarle un skill propio al usuario.
    try {
        $destinoSkill = Join-Path $env:USERPROFILE '.claude\skills\save'
        if (Test-Path -LiteralPath $destinoSkill) {
            $item = Get-Item -LiteralPath $destinoSkill -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                $blanco = ([string[]]$item.Target)[0]
                if ($blanco -and $blanco.TrimEnd('\') -ieq (Join-Path $Carpeta 'skill').TrimEnd('\')) {
                    # Remove-Item sobre una junction borra el VINCULO, no el
                    # destino, siempre que no se le pase -Recurse.
                    [IO.Directory]::Delete($destinoSkill)
                    $hechas += 'junction del skill /save'
                }
            }
        }
    } catch { $errores += 'skill: ' + $_.Exception.Message }

    # 4. el acceso directo
    try {
        $rutaLnk = Join-Path $Carpeta $script:NombreAcceso
        if (Test-Path -LiteralPath $rutaLnk) {
            Remove-Item -LiteralPath $rutaLnk -Force
            $hechas += 'acceso directo'
        }
    } catch { $errores += 'acceso directo: ' + $_.Exception.Message }

    # 5. el volcado del statusline, y SOLO si es byte a byte el que escribimos
    #    nosotros. Ver Get-AjustesSinVolcado: si esta editado a mano no se toca
    #    y se explica como sacarlo. Antes no se deshacia nunca, asi que
    #    desinstalar dejaba siempre ese resto adentro de la config ajena.
    try {
        if (Test-Path -LiteralPath $Ajustes) {
            $txt = [System.IO.File]::ReadAllText($Ajustes)
            $cmd = ''
            try { $cmd = [string]($txt | ConvertFrom-Json).statusLine.command } catch { }
            if ($cmd -and $cmd.Contains('statusline-ultimo.json')) {
                $r = Get-AjustesSinVolcado -Texto $txt -Comando $cmd
                if ($r.Texto) {
                    # Nunca se escribe JSON invalido, y el respaldo va aparte del
                    # .bak que dejo la instalacion para no pisar el original.
                    $null = $r.Texto | ConvertFrom-Json
                    Copy-Item -LiteralPath $Ajustes -Destination ($Ajustes + '.desinstalar.bak') -Force
                    [System.IO.File]::WriteAllText($Ajustes, $r.Texto, [System.Text.UTF8Encoding]::new($false))
                    $hechas += 'volcado de la cuota en el statusline'
                } else {
                    $avisos += $r.Como
                }
            }
        }
    } catch { $errores += 'statusline: ' + $_.Exception.Message }

    return [pscustomobject]@{ Hechas = $hechas; Errores = $errores; Avisos = $avisos }
}

# --- huella de lo que falta --------------------------------------------------
#  Sirve para no volver a preguntar por exactamente lo mismo que ya se rechazo.
#  Si aparece algo NUEVO roto, la huella cambia y se vuelve a ofrecer.
function Get-HuellaFaltantes {
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$Piezas)
    return (($Piezas | Where-Object { -not $_.Ok } | ForEach-Object { $_.Clave } | Sort-Object) -join '|')
}
