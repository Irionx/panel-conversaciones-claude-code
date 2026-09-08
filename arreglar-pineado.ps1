# =============================================================================
#  arreglar-pineado.ps1 - repara el acceso directo que Windows fabrica al pinear
# -----------------------------------------------------------------------------
#  Al pinear un gadget que corre bajo powershell.exe, Windows NO pinea tu
#  ventana: crea un .lnk propio apuntando al ejecutable, sin argumentos y con el
#  icono de PowerShell. Ese boton no abre el gadget y muestra el logo equivocado.
#
#  Hay que tocar TRES cosas, y la tercera es la que casi nadie sabe:
#    1. Args + WorkingDirectory -> que abra el gadget de verdad
#    2. IconLocation            -> el globo
#    3. System.AppUserModel.ID  -> para que la VENTANA en ejecucion se funda con
#       el boton pineado en vez de abrir un segundo boton al lado. Tiene que
#       coincidir con el que el proceso se pone con
#       SetCurrentProcessExplicitAppUserModelID.
#
#  El AppUserModelID de un .lnk no se toca con WScript.Shell: vive en su
#  property store y hay que ir por COM (IPropertyStore).
#
#  Uso:  .\arreglar-pineado.ps1            -> solo informa
#        .\arreglar-pineado.ps1 -Aplicar   -> repara
# =============================================================================
param([switch]$Aplicar)
$ErrorActionPreference = 'Stop'

$APPID = 'GIA.Conversaciones.Gadget'
$carpeta = Split-Path -Parent $MyInvocation.MyCommand.Path
$icono = Join-Path $carpeta 'gadget.ico'
$script = Join-Path $carpeta 'gadget.ps1'
$dirPin = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'

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

    // OJO: en x64 un PROPVARIANT mide 24 bytes (vt + 3 ushort reservados + una
    // union de 16). Declararlo de 16 le pasa a COM un buffer corto: SetValue
    // igual anda (solo lee los primeros 16) pero GetValue escribe de mas y
    // devuelve basura. Sintoma: escribis bien y al leer parece vacio.
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

    // Nada de InitPropVariantFromString: no esta exportada en la propsys.dll de
    // este Windows. El PROPVARIANT de string se arma a mano, que son dos campos:
    // vt = VT_LPWSTR (31) y un puntero a memoria COM. PropVariantClear despues
    // libera ese puntero, asi que no hay fuga.
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
        string s = (v.vt == 31) ? Marshal.PtrToStringUni(v.p) : null;
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

$sh = New-Object -ComObject WScript.Shell

# --- 0. el acceso directo ORIGEN ---------------------------------------------
#  MEDIDO EL 2026-09-08: editar el .lnk que Windows fabrica al pinear NO SIRVE.
#  Al reiniciar el Explorador lo REGENERA desde su propio modelo (que, si
#  pineaste la ventana corriendo, dice "powershell.exe sin argumentos") y se
#  lleva puestos Args e IconLocation. Solo sobrevive el property store: el
#  AppUserModelID quedo, todo lo demas volvio a cero.
#
#  Entonces el pin tiene que NACER de un acceso directo bueno. Se prepara aca el
#  origen; despues se pinea ESE, no la ventana.
$origen = Join-Path $carpeta 'Gadget de conversaciones.lnk'
if (Test-Path -LiteralPath $origen) {
    $o = $sh.CreateShortcut($origen)
    $o.TargetPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $o.Arguments = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $script)
    $o.WorkingDirectory = $carpeta
    $o.IconLocation = ('{0},0' -f $icono)
    $o.Description = 'Panel de conversaciones de Claude Code'
    $o.Save()
    [LnkAppId]::Escribir($origen, $APPID)
    Write-Host '=== acceso directo ORIGEN (el que hay que pinear) ==='
    $v = $sh.CreateShortcut($origen)
    Write-Host ('  archivo : {0}' -f (Split-Path -Leaf $origen))
    Write-Host ('  Args    : {0}' -f $v.Arguments)
    Write-Host ('  Icono   : {0}' -f $v.IconLocation)
    Write-Host ('  AppId   : {0}' -f [LnkAppId]::Leer($origen))
    Write-Host ''
}

# --- que .lnk pineados apuntan a powershell.exe? -----------------------------
$candidatos = Get-ChildItem -LiteralPath $dirPin -Filter '*.lnk' | ForEach-Object {
    $l = $sh.CreateShortcut($_.FullName)
    [pscustomobject]@{
        Archivo = $_.Name
        Ruta    = $_.FullName
        Target  = $l.TargetPath
        Args    = $l.Arguments
        Icono   = $l.IconLocation
        AppId   = $(try { [LnkAppId]::Leer($_.FullName) } catch { '<error>' })
    }
} | Where-Object { $_.Target -like '*powershell.exe' }

Write-Host '=== accesos directos pineados que apuntan a powershell.exe ==='
foreach ($c in $candidatos) {
    Write-Host ''
    Write-Host ('  {0}' -f $c.Archivo)
    Write-Host ('     Args  : {0}' -f $(if ($c.Args) { $c.Args } else { '<VACIO>' }))
    Write-Host ('     Icono : {0}' -f $(if ($c.Icono -and $c.Icono -ne ',0') { $c.Icono } else { '<el del exe>' }))
    Write-Host ('     AppId : {0}' -f $(if ($c.AppId) { $c.AppId } else { '<ninguno>' }))
}

# PELIGRO: "sin Args y sin AppId" NO alcanza para identificarlo. El PowerShell
# pineado de verdad tambien cumple eso, y elegir por orden alfabetico seria
# jugarse el acceso directo bueno a una casualidad.
# El que fabrica Windows al pinear es el unico que ademas queda con el
# IconLocation VACIO (',0'): hereda el icono del exe sin escribir ruta.
# Dos formas de estar roto, y la segunda importa para poder correr esto dos
# veces: (a) recien fabricado por Windows, o (b) ya apunta al gadget pero le
# falta el AppId (una corrida anterior que quedo por la mitad).
$roto = @($candidatos | Where-Object {
        $nuevo = (-not $_.Args) -and ($_.Icono -eq ',0' -or -not $_.Icono)
        $aMedias = ($_.Args -like '*gadget.ps1*')
        (-not $_.AppId) -and ($nuevo -or $aMedias)
    })
if ($roto.Count -eq 0) {
    Write-Host ''
    Write-Host 'No hay ningun pineado roto para reparar.'
    return
}
if ($roto.Count -gt 1) {
    Write-Host ''
    Write-Host 'AMBIGUO: hay mas de un candidato. No toco nada.'
    $roto | ForEach-Object { Write-Host ('   - ' + $_.Archivo) }
    return
}
$roto = $roto[0]

Write-Host ''
Write-Host ('--> a reparar: {0}' -f $roto.Archivo)
if (-not $Aplicar) {
    Write-Host '    (corre con -Aplicar para repararlo)'
    return
}

Copy-Item -LiteralPath $roto.Ruta -Destination ($roto.Ruta + '.bak') -Force
$l = $sh.CreateShortcut($roto.Ruta)
$l.Arguments = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $script)
$l.WorkingDirectory = $carpeta
$l.IconLocation = ('{0},0' -f $icono)
$l.Description = 'Panel de conversaciones de Claude Code'
$l.Save()
# El AppUserModelID va DESPUES: el Save de WScript.Shell reescribe el .lnk y se
# llevaria puesto el property store.
[LnkAppId]::Escribir($roto.Ruta, $APPID)

$v = $sh.CreateShortcut($roto.Ruta)
Write-Host ''
Write-Host 'reparado:'
Write-Host ('   Args  : {0}' -f $v.Arguments)
Write-Host ('   Icono : {0}' -f $v.IconLocation)
Write-Host ('   AppId : {0}' -f [LnkAppId]::Leer($roto.Ruta))
Write-Host ''
Write-Host 'Hace falta reiniciar el Explorador para que la barra lo relea.'
