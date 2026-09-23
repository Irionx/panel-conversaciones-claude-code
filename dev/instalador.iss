; =============================================================================
;  instalador.iss - receta del instalador .exe (Inno Setup 6)
; -----------------------------------------------------------------------------
;  No se compila a mano: lo llama  .\dev\build.ps1 -Exe , que le pasa la version
;  y la carpeta ya armada. Compilarlo suelto no tiene sentido porque necesita
;  ese staging.
;
;  QUE HACE Y QUE NO:
;    - Copia los archivos e invoca  setup.ps1 -Instalar -y , que es el MISMO
;      instalador de siempre. Toda la logica vive ahi, no aca: si algun dia se
;      cambia el .exe por otra cosa, no se reescribe nada.
;    - Al desinstalar invoca  setup.ps1 -Desinstalar -y  ANTES de borrar los
;      archivos, porque ese script vive adentro de la carpeta que se va a borrar.
;    - NO toca datos\. Inno solo borra lo que instalo, y la base se crea en
;      tiempo de ejecucion, asi que desinstalar no se lleva las conversaciones.
;
;  PrivilegesRequired=lowest: se instala en el usuario, sin UAC. Es coherente
;  con el resto del proyecto, que nunca pidio admin para nada.
; =============================================================================

#ifndef MiVersion
  #define MiVersion "0.0.0"
#endif
#ifndef MiOrigen
  #error Falta /DMiOrigen=<carpeta con los archivos ya armados>
#endif

#define MiNombre "Hilos de Claudio"
#define MiIdCorto "Conversaciones"
; TIENE que ser el mismo que se pone el proceso con
; SetCurrentProcessExplicitAppUserModelID en gadget.ps1, y el mismo que
; lib-setup.ps1 le escribe al .lnk. Si un acceso directo no lo lleva, al
; pinearlo Windows abre un SEGUNDO boton en la barra de tareas al lado del
; pineado, porque no puede juntar la ventana con su acceso.
#define MiAppUserModelId "GIA.Conversaciones.Gadget"

[Setup]
AppId={{8E3A1C74-5B2D-4F6E-9A11-C0D7E2B4F8A3}
AppName={#MiNombre}
AppVersion={#MiVersion}
AppVerName={#MiNombre} {#MiVersion}
; Version en los metadatos del propio setup.exe: es lo que se ve en las
; propiedades del archivo. build.ps1 se niega a compilar el .exe si la version
; no es x.y.z limpia, asi que aca siempre entra un numero valido.
VersionInfoVersion={#MiVersion}
AppPublisher=GIA
DefaultDirName={localappdata}\Programs\{#MiIdCorto}
DefaultGroupName={#MiNombre}
DisableProgramGroupPage=yes
; Que se vea a donde va a quedar: la carpeta importa, porque los datos viven ahi.
DisableDirPage=no
PrivilegesRequired=lowest
OutputDir=dist
OutputBaseFilename=instalar-conversaciones-{#MiVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
SetupIconFile={#MiOrigen}\app\gadget.ico
UninstallDisplayIcon={app}\app\gadget.ico
UninstallDisplayName={#MiNombre}
LicenseFile=
InfoBeforeFile={#MiOrigen}\INSTALAR.txt

[Languages]
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"

[Files]
Source: "{#MiOrigen}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Por el lanzador y NO por powershell.exe: powershell es de consola, y en
; Windows 11 abre una ventana de Windows Terminal al lado del panel. build.ps1
; lo compila y lo mete en el paquete, asi que cuando se crean estos ya existe.
Name: "{group}\{#MiNombre}"; Filename: "{app}\app\Conversaciones.exe"; \
    WorkingDir: "{app}"; IconFilename: "{app}\app\gadget.ico"; \
    AppUserModelID: "{#MiAppUserModelId}"
Name: "{autodesktop}\{#MiNombre}"; Filename: "{app}\app\Conversaciones.exe"; \
    WorkingDir: "{app}"; IconFilename: "{app}\app\gadget.ico"; \
    AppUserModelID: "{#MiAppUserModelId}"; Tasks: escritorio

[Tasks]
Name: "escritorio"; Description: "Crear un acceso directo en el Escritorio"; GroupDescription: "Accesos:"

[Run]
; El instalador de verdad es setup.ps1. Aca solo se lo invoca.
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\setup.ps1"" -Instalar -y"; \
    WorkingDir: "{app}"; StatusMsg: "Registrando el protocolo, el PATH y el skill /save..."; \
    Flags: runhidden
Filename: "{app}\app\Conversaciones.exe"; \
    WorkingDir: "{app}"; Description: "Abrir el gadget ahora"; Flags: postinstall nowait skipifsilent

[UninstallRun]
; ANTES de borrar los archivos: setup.ps1 vive adentro de la carpeta que se va.
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\setup.ps1"" -Desinstalar -y"; \
    WorkingDir: "{app}"; RunOnceId: "DeshacerInstalacion"; Flags: runhidden
; Y el gadget cerrado, o los archivos quedan tomados.
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\app\cerrar-gadget.ps1"""; \
    WorkingDir: "{app}"; RunOnceId: "CerrarGadget"; Flags: runhidden

[Messages]
es.FinishedLabel=La instalacion termino.%n%nTus conversaciones se guardan en datos\conversaciones.db, dentro de la carpeta de instalacion. El backup es copiar ese archivo.%n%nOJO: los comandos (guardar, borrar-conversacion) necesitan una terminal NUEVA, porque las que ya estaban abiertas siguen con el PATH viejo.
