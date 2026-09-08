# =============================================================================
#  gadget.ps1 - Gadget de escritorio (WPF nativo, sin instalar nada)
#
#  Ventana sin bordes, fondo translucido, arrastrable y ensanchable. Lista las
#  conversaciones guardadas con su % de contexto y las abre de un
#  click. El candado fija la posicion y vuelve el panel mas discreto.
#
#  Se lanza con "Gadget de conversaciones.lnk". Para depurar, correr este .ps1.
# =============================================================================

param([switch]$Debug)

$ErrorActionPreference = 'Stop'
$carpeta = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $carpeta 'lib-conversaciones.ps1')
. (Join-Path $carpeta 'lib-setup.ps1')

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# --- las piezas del gadget ---------------------------------------------------
#  Se dot-sourcean y no van como modulo a proposito: comparten el estado de la
#  ventana ($ventana, $lista, $script:bloqueado...) y el scope aislado de un
#  modulo lo cortaria. La capa de Datos SI es un modulo porque no comparte nada.
#
#  El orden importa una sola vez: Xaml.ps1 define $xaml y tiene que estar antes
#  de que se instancie la ventana, mas abajo.
foreach ($pieza in 'Xaml', 'Apariencia', 'Confirmacion', 'Tarjeta', 'Cuota') {
    . (Join-Path $carpeta "gadget\$pieza.ps1")
}

# --- identidad propia ante la barra de tareas --------------------------------
#  Sin esto el gadget NO tiene identidad: Windows lo resuelve contra el acceso
#  directo desde el que se lanzo, y le pone SU nombre ("Gadget de
#  conversaciones") y SU icono. Da igual lo que tenga la ventana: la barra ni lo
#  mira. Medido: el boton mostraba el monitorcito de shell32.dll,13 mientras
#  WM_GETICON sobre la ventana ya devolvia el globo verde.
#
#  Con AppUserModelID propio la barra usa el titulo y el icono de la VENTANA.
#  Va antes de crear cualquier ventana, o no tiene efecto.
try {
    if (-not ('AppId' -as [type])) {
        Add-Type -Namespace '' -Name AppId -MemberDefinition @'
[DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
public static extern void SetCurrentProcessExplicitAppUserModelID(string id);
'@
    }
    [AppId]::SetCurrentProcessExplicitAppUserModelID('GIA.Conversaciones.Gadget')
} catch { }

# --- una sola instancia -------------------------------------------------------
#  Cada gadget tiene sus propios timers Y escribe en la base (el sync de
#  titulos), asi que varios abiertos a la vez multiplican el trabajo al pedo.
#  (Pisarse el archivo ya no puede pasar: la capa de Datos serializa con un
#  candado entre procesos. El motivo de una sola instancia ahora es el ruido.) Paso de verdad: llegaron a haber tres corriendo y la herramienta
#  se trababa.
#
#  El mutex va en Local\ (por sesion de Windows), que es lo que corresponde para
#  una app de escritorio de un solo usuario.
$script:mutex = New-Object System.Threading.Mutex($false, 'Local\GiaConversacionesGadget')
try {
    $tomado = $script:mutex.WaitOne(0)
} catch [System.Threading.AbandonedMutexException] {
    # Lo dejo un gadget que murio mal: se puede tomar igual.
    $tomado = $true
}
if (-not $tomado) {
    [Windows.MessageBox]::Show(
        "El gadget ya esta abierto.`n`nSi no lo ves, puede haber quedado uno colgado: cerralo desde el Administrador de tareas (powershell.exe) y volve a abrir.",
        'Conversaciones') | Out-Null
    exit
}

$archivoPos = Join-Path $carpeta 'gadget-posicion.json'
$ALPHAS = @('E6', 'B3', '73')   # opaco / medio / fantasma
$ANCHO_MIN = 278
$ANCHO_MAX = 740
# Alto de la LISTA (el MaxHeight del ScrollViewer), no de la ventana: la ventana
# se ajusta sola al contenido. 120 deja ver una tarjeta y algo; el maximo se
# recorta despues contra el alto real del escritorio.
$ALTO_MIN = 120
$ALTO_MAX = 1400
# Aire que necesita la sombra de cada tarjeta DENTRO del ScrollViewer, que
# recorta a sus limites. Ver el comentario en New-Tarjeta.
$AIRE_SOMBRA = 12
$PAD_NORMAL = [Windows.Thickness]::new(14, 12, 14, 12)
$PAD_BLOQUEADO = [Windows.Thickness]::new(14 - $AIRE_SOMBRA, 12, 14 - $AIRE_SOMBRA, 12)
$LOCK_CERRADO = [char]::ConvertFromUtf32(0x1F512)
$LOCK_ABIERTO = [char]::ConvertFromUtf32(0x1F513)
# Chinche de Segoe MDL2: rellena (0xE842) = clavado arriba, acostada (0xE718) =
# suelto. Relleno vs contorno se lee de un vistazo a 11px; un tachado no.
$PIN_CLAVADO = [char]0xE842
$PIN_SUELTO = [char]0xE718


$ventana = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$xaml)))

# Sin esto la barra de tareas muestra el icono del PROCESO, o sea el de
# powershell.exe: parece una consola perdida. El .ico lo genera hacer-icono.ps1
# y trae 8 tamanos.
#
# El marco de 32 se elige A MANO y no es un capricho: un BitmapImage sobre un
# .ico multi-tamano se queda con el marco MAS CHICO (16), y la barra de tareas
# -que a 100% pide 24- tendria que AGRANDARLO. Medido, no supuesto. Dandole el
# de 32, WPF baja a 24 para la barra y a 16 (2:1 exacto) para el titulo.
# try/catch porque un icono roto o ausente jamas puede impedir que arranque.
$rutaIcono = Join-Path $carpeta 'gadget.ico'
if (Test-Path -LiteralPath $rutaIcono) {
    try {
        $marcos = (New-Object Windows.Media.Imaging.IconBitmapDecoder(
                [uri]$rutaIcono,
                [Windows.Media.Imaging.BitmapCreateOptions]::None,
                [Windows.Media.Imaging.BitmapCacheOption]::OnLoad)).Frames
        $ico = $marcos | Where-Object { $_.PixelWidth -eq 32 } | Select-Object -First 1
        if (-not $ico) { $ico = $marcos | Sort-Object PixelWidth -Descending | Select-Object -First 1 }
        $ventana.Icon = $ico
    } catch { }
}

$fondo = $ventana.FindName('fondo')
$lista = $ventana.FindName('lista')
$pie = $ventana.FindName('pie')
$cabecera = $ventana.FindName('cabecera')
$gripIzq = $ventana.FindName('gripIzq')
$gripDer = $ventana.FindName('gripDer')
$gripAbajo = $ventana.FindName('gripAbajo')
$scroller = $ventana.FindName('scroller')
$btnCandado = $ventana.FindName('btnCandado')
$btnArriba = $ventana.FindName('btnArriba')
$chipBotones = $ventana.FindName('chipBotones')
$chipResumen = $ventana.FindName('chipResumen')
# Las dos filas de la cuota. Se guardan en pares para que Set-Resumen las
# recorra con un solo bloque en vez de duplicar el codigo.
$filasCuota = @(
    @{ Nom = $ventana.FindName('cuotaNom1'); Barra = $ventana.FindName('cuotaBarra1')
        Lleno = $ventana.FindName('cuotaLleno1'); Reset = $ventana.FindName('cuotaReset1')
    },
    @{ Nom = $ventana.FindName('cuotaNom2'); Barra = $ventana.FindName('cuotaBarra2')
        Lleno = $ventana.FindName('cuotaLleno2'); Reset = $ventana.FindName('cuotaReset2')
    }
)

# --- estado recordado --------------------------------------------------------
$area = [Windows.SystemParameters]::WorkArea
$script:idxAlpha = 0
$script:bloqueado = $false
$script:arriba = $true          # Topmost: arranca como estaba, es un gadget
$script:posOk = $false
# sesion -> el StackPanel de puntitos de esa tarjeta. Se rearma en cada refresco.
$script:latidos = @{}
# sesion -> la capa (Grid) del halo del borde. Mismo ciclo de vida.
$script:halos = @{}

if (Test-Path $archivoPos) {
    try {
        $p = Get-Content $archivoPos -Raw | ConvertFrom-Json
        $l = [double]$p.left
        $t = [double]$p.top
        if (-not [double]::IsNaN($l) -and $l -ge -50 -and $l -lt $area.Right -and $t -ge -50 -and $t -lt $area.Bottom) {
            $ventana.Left = $l
            $ventana.Top = $t
            $script:posOk = $true
        }
        if ($null -ne $p.alpha) { $script:idxAlpha = [int]$p.alpha }
        if ($null -ne $p.bloqueado) { $script:bloqueado = [bool]$p.bloqueado }
        if ($null -ne $p.arriba) { $script:arriba = [bool]$p.arriba }
        if ($p.ancho -and [double]$p.ancho -ge $ANCHO_MIN -and [double]$p.ancho -le $ANCHO_MAX) {
            $ventana.Width = [double]$p.ancho
        }
        if ($p.alto -and [double]$p.alto -ge $ALTO_MIN -and [double]$p.alto -le $ALTO_MAX) {
            $scroller.MaxHeight = [double]$p.alto
        }
    } catch { }
}

# El posicionamiento final va en Loaded: recien ahi se conoce ActualWidth/Height.
# Antes de eso mezclar WorkArea (DIP) con el tamano de la ventana da resultados
# raros en pantallas escaladas (aca, 1920x1200 fisicos = 1536x912 DIP a 125%).
$ventana.Add_Loaded({
        $wa = [Windows.SystemParameters]::WorkArea
        if (-not $script:posOk) {
            $ventana.Left = $wa.Right - $ventana.ActualWidth - 20
            $ventana.Top = $wa.Top + 20
        }
        $ventana.Left = [math]::Max($wa.Left, [math]::Min($ventana.Left, $wa.Right - $ventana.ActualWidth))
        $ventana.Top = [math]::Max($wa.Top, [math]::Min($ventana.Top, $wa.Bottom - $ventana.ActualHeight))

        # Escala DIP<->fisico, para traducir el movimiento del mouse al redimensionar.
        $src = [Windows.PresentationSource]::FromVisual($ventana)
        $script:escala = if ($src) { $src.CompositionTarget.TransformToDevice.M11 } else { 1.0 }
        if ($script:escala -le 0) { $script:escala = 1.0 }
    })




# --- refresco ----------------------------------------------------------------
# --- semaforo del remoto ------------------------------------------------------
#  Get-EstadosSesion lee ~/.claude/sessions/*.json y tarda ~26 ms, asi que va
#  sincronico y sin vueltas. (Hubo una version con Win32_Process que tardaba
#  ~265 ms y hubo que sacarla del hilo de la UI con un runspace; el registro la
#  dejo obsoleta, y ademas asi el semaforo esta siempre al dia en vez de ir un
#  refresco atrasado.)
$script:estados = @{}
$script:remotoPermitido = $true


function Actualizar {
    $lista.Children.Clear()
    # Las tarjetas se rearman de cero, asi que los latidos viejos apuntan a
    # elementos que ya no estan en el arbol.
    #
    # CRITICO: una animacion con RepeatBehavior.Forever NO se detiene sola
    # cuando el elemento sale del arbol; el reloj queda vivo en el sistema de
    # timing de WPF. Sin este BeginAnimation(..., $null) cada refresco sumaba
    # relojes por tarjeta y el gadget se iba trabando de a poco.
    foreach ($ind in @($script:latidos.Values)) {
        $ind.Tag.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $null)
    }
    $script:latidos = @{}
    # El halo corre la misma suerte: la vuelta del gradiente tambien es Forever
    # y su reloj vive en el RotateTransform que quedo guardado en el Tag.
    foreach ($h in @($script:halos.Values)) {
        $h.Tag.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $null)
    }
    $script:halos = @{}
    try {
        # El @() es obligatorio: con una sola conversacion la funcion devuelve
        # un escalar y $convs.Count quedaria vacio.
        #
        # Sync- en vez de Get-: de paso baja a disco el nombre de /rename, que
        # es lo que despues muestran los comandos de linea (borrar -Listar y
        # compania), que leen el titulo guardado y no lo resuelven en vivo.
        $convs = @(Sync-TitulosGuardados)
    } catch {
        $err = New-Object Windows.Controls.TextBlock
        $err.Text = $_.Exception.Message
        $err.Foreground = Pincel '#F87171'
        $err.TextWrapping = 'Wrap'
        $err.FontSize = 11
        $lista.Children.Add($err) | Out-Null
        return
    }

    # Una sola lectura para TODAS las tarjetas: New-Tarjeta la saca de
    # $script:estados. Si falla devuelve vacio y los puntos quedan grises.
    $script:estados = Get-EstadosSesion
    # Se relee en cada refresco a proposito: Claude Code reescribe la politica
    # al cambiar de cuenta, y el gadget no tiene por que reiniciarse por eso.
    $script:remotoPermitido = Test-RemotoPermitido

    $sumTok = [int64]0
    $sumLim = [int64]0
    foreach ($c in $convs) {
        $ctx = Get-ContextoSesion -Cwd $c.cwd -Sesion $c.sesion -Limite ([int]$c.contextoMax)
        # Solo suman las que tienen dato: una sin transcript no aporta ventana.
        if ($ctx.Hay) {
            $sumTok += [int64]$ctx.Tokens
            $sumLim += [int64]$ctx.Limite
        }
        $lista.Children.Add((New-Tarjeta -C $c -Ctx $ctx)) | Out-Null
    }
    Set-Resumen -Tokens $sumTok -Limite $sumLim
    $palabra = if ($convs.Count -eq 1) { 'conversación' } else { 'conversaciones' }
    $candado = if ($script:bloqueado) { '  ·  bloqueado' } else { '' }
    $pie.Text = '{0} {1}  ·  {2}{3}' -f $convs.Count, $palabra, (Get-Date -Format 'HH:mm'), $candado

    # Las tarjetas nacen con el latido apagado: se resuelve ya mismo en vez de
    # esperar hasta 2 segundos al primer tick del timer.
    Actualizar-Actividad
}

# --- mover -------------------------------------------------------------------
$cabecera.Add_MouseLeftButtonDown({
        if ($script:bloqueado) { return }
        $ventana.DragMove()
    })

# --- ensanchar ---------------------------------------------------------------
#  Se trabaja con la posicion absoluta del cursor (pixeles fisicos) y se divide
#  por la escala DPI. Usar coordenadas relativas a la ventana no sirve para el
#  grip izquierdo: al mover la ventana se mueve tambien el marco de referencia
#  y el delta se anula solo.
$script:redim = $null

function Iniciar-Redim {
    param($Grip, [string]$Lado)
    if ($script:bloqueado) { return }
    $script:redim = @{
        lado = $Lado
        x0   = [System.Windows.Forms.Cursor]::Position.X
        y0   = [System.Windows.Forms.Cursor]::Position.Y
        w0   = $ventana.ActualWidth
        l0   = $ventana.Left
        h0   = $scroller.MaxHeight
    }
    $Grip.CaptureMouse() | Out-Null
}

function Mover-Redim {
    if (-not $script:redim) { return }
    $r = $script:redim

    # El grip de abajo trabaja sobre el MaxHeight de la LISTA, no sobre el alto
    # de la ventana: con SizeToContent="Height" el alto de la ventana lo decide
    # el contenido, asi que asignarle Height no haria nada. Lo que se agranda es
    # cuanta lista se ve antes de tener que scrollear.
    if ($r.lado -eq 'abajo') {
        $delta = ([System.Windows.Forms.Cursor]::Position.Y - $r.y0) / $script:escala
        # Tope real: lo que queda de pantalla desde donde arranca la ventana,
        # menos el alto de cabecera + pie + margenes. Sin esto se puede estirar
        # la lista mas alto que el escritorio y el pie queda fuera de vista.
        $techo = [math]::Min($ALTO_MAX,
            [Windows.SystemParameters]::WorkArea.Height - $ventana.Top - 90)
        $scroller.MaxHeight = [math]::Max($ALTO_MIN, [math]::Min($techo, $r.h0 + $delta))
        return
    }

    $delta = ([System.Windows.Forms.Cursor]::Position.X - $r.x0) / $script:escala
    if ($r.lado -eq 'der') {
        $ancho = $r.w0 + $delta
    } else {
        $ancho = $r.w0 - $delta
    }
    $ancho = [math]::Max($ANCHO_MIN, [math]::Min($ANCHO_MAX, $ancho))

    $ventana.Width = $ancho
    # Al agarrar del borde izquierdo el lado derecho tiene que quedarse quieto.
    if ($r.lado -eq 'izq') { $ventana.Left = $r.l0 + ($r.w0 - $ancho) }
}

function Terminar-Redim {
    param($Grip)
    if (-not $script:redim) { return }
    $script:redim = $null
    $Grip.ReleaseMouseCapture()
}

$gripIzq.Add_MouseLeftButtonDown({ Iniciar-Redim -Grip $this -Lado 'izq' })
$gripDer.Add_MouseLeftButtonDown({ Iniciar-Redim -Grip $this -Lado 'der' })
$gripAbajo.Add_MouseLeftButtonDown({ Iniciar-Redim -Grip $this -Lado 'abajo' })
$gripIzq.Add_MouseMove({ Mover-Redim })
$gripDer.Add_MouseMove({ Mover-Redim })
$gripAbajo.Add_MouseMove({ Mover-Redim })
$gripIzq.Add_MouseLeftButtonUp({ Terminar-Redim -Grip $this })
$gripDer.Add_MouseLeftButtonUp({ Terminar-Redim -Grip $this })
$gripAbajo.Add_MouseLeftButtonUp({ Terminar-Redim -Grip $this })

# --- botones -----------------------------------------------------------------
$ventana.FindName('btnCerrar').Add_Click({ $ventana.Close() })
$ventana.FindName('btnMinimizar').Add_Click({ $ventana.WindowState = 'Minimized' })
$ventana.FindName('btnRefrescar').Add_Click({ Actualizar })
$ventana.FindName('btnOpacidad').Add_Click({
        $script:idxAlpha = ($script:idxAlpha + 1) % $ALPHAS.Count
        Set-Apariencia
        # No hace falta redibujar: la opacidad es del contenedor y las tarjetas
        # no dependen de ella. Bloqueado el ciclador no se nota hasta destrabar.
    })
$btnCandado.Add_Click({
        $script:bloqueado = -not $script:bloqueado
        Set-Apariencia
        Actualizar      # las tarjetas se redibujan con la transparencia nueva
    })
# Soltar el Topmost manda la ventana atras de la que tenga el foco. No hace falta
# Actualizar: no cambia ni un pixel de las tarjetas, solo el orden Z.
$btnArriba.Add_Click({
        $script:arriba = -not $script:arriba
        Set-Apariencia
    })

$ventana.Add_Closing({
        try {
            # Minimizada, Left/Top valen -32000 (donde Windows estaciona las
            # ventanas minimizadas) y ActualWidth 0: guardar eso deja el gadget
            # fuera de pantalla en el proximo arranque. RestoreBounds tiene el
            # rectangulo de cuando estaba desplegada, que es el que interesa.
            $r = if ($ventana.WindowState -eq 'Normal') {
                [pscustomobject]@{ Left = $ventana.Left; Top = $ventana.Top; Width = $ventana.ActualWidth }
            } else {
                $ventana.RestoreBounds
            }
            @{
                left      = $r.Left
                top       = $r.Top
                ancho     = $r.Width
                # El alto es del ScrollViewer, no de la ventana: no lo afecta
                # que este minimizada, asi que va directo.
                alto      = $scroller.MaxHeight
                alpha     = $script:idxAlpha
                bloqueado = $script:bloqueado
                arriba    = $script:arriba
            } | ConvertTo-Json | Set-Content -Path $archivoPos -Encoding UTF8
        } catch { }
    })

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(30)
# Un tick que tira deja el dispatcher en un estado raro y la ventana deja de
# responder: ahi no se puede ni cerrar y queda un huerfano. Se traga el error y
# se sigue vivo; el detalle queda en gadget-fallas.log. Al menos ahora el
# huerfano se VE en la barra de tareas (ShowInTaskbar=True) y se puede matar.
$timer.Add_Tick({ try { Actualizar } catch { Write-Falla 'refresco' $_ } })
$timer.Start()

# --- latido: prender y apagar los puntitos -----------------------------------
#  Va en un timer propio y mucho mas rapido que el refresco general. Rebuildear
#  las tarjetas cada 2 segundos seria caro, cortaria el hover y haria parpadear
#  todo; aca solo se toca la Visibility de un StackPanel que ya existe.
# --- llego dato nuevo de alguna pestana? -------------------------------------
#  claude-hud reescribe su context-cache cada vez que CUALQUIER pestaña
#  renderiza su statusline. Mirar ese directorio es enterarse en el momento, en
#  vez de esperar hasta 30 s al proximo tick del refresco general.
#
#  Va por sondeo dentro del timer que YA corre cada 2 s, y no con un
#  FileSystemWatcher: los eventos del watcher llegan en un hilo del pool y en
#  PowerShell hay que marshalarlos al dispatcher a mano. Mas riesgo que
#  beneficio para un stat cada dos segundos.
$script:dirCacheHud = Join-Path $env:USERPROFILE '.claude\plugins\claude-hud\context-cache'
$script:selloCache = [datetime]::MinValue
$script:ultimoRefresco = [datetime]::MinValue

function Test-DatoNuevo {
    if (-not (Test-Path -LiteralPath $script:dirCacheHud)) { return $false }

    try {
        $ultimo = Get-ChildItem -LiteralPath $script:dirCacheHud -Filter '*.json' -ErrorAction Stop |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
    } catch { return $false }
    if (-not $ultimo) { return $false }

    if ($ultimo.LastWriteTime -le $script:selloCache) { return $false }
    $script:selloCache = $ultimo.LastWriteTime

    # Techo de frecuencia: con varias pestañas trabajando esto se escribe a cada
    # turno, y rebuildear la lista tan seguido corta el hover y hace parpadear.
    if (((Get-Date) - $script:ultimoRefresco).TotalSeconds -lt 12) { return $false }
    $script:ultimoRefresco = Get-Date
    return $true
}

function Actualizar-Actividad {
    # Si alguna pestaña publico numeros nuevos, se redibuja entero (que ya
    # incluye el latido) y no hace falta seguir.
    if (Test-DatoNuevo) {
        Actualizar
        return
    }

    try { $pensando = Get-ActividadSesiones } catch { return }

    # Se saca una copia de las claves: el refresco grande puede reemplazar el
    # hashtable entero mientras esto corre.
    foreach ($sesion in @($script:latidos.Keys)) {
        $ind = $script:latidos[$sesion]
        if (-not $ind) { continue }
        $vis = if ($pensando.ContainsKey($sesion)) { 'Visible' } else { 'Collapsed' }
        if ($ind.Visibility -ne $vis) { $ind.Visibility = $vis }
        # El halo del borde se prende y se apaga con los mismos puntitos.
        $halo = $script:halos[$sesion]
        if ($halo -and $halo.Visibility -ne $vis) { $halo.Visibility = $vis }
    }
}

$timerLatido = New-Object Windows.Threading.DispatcherTimer
$timerLatido.Interval = [TimeSpan]::FromSeconds(2)
$timerLatido.Add_Tick({ try { Actualizar-Actividad } catch { Write-Falla 'latido' $_ } })
$timerLatido.Start()

# --- chequeo de instalacion --------------------------------------------------
#  Se mide el estado real en cada arranque, sin marcador de "ya instalado": asi,
#  si moves la carpeta, la proxima vez se re-apunta solo.
function Invoke-ChequeoSetup {
    $piezas = @(Get-EstadoInstalacion -Carpeta $carpeta)
    if (@($piezas | Where-Object { -not $_.Ok }).Count -eq 0) { return }

    # Si ya dijo que no a exactamente esto, no se vuelve a preguntar. Si aparece
    # algo NUEVO roto la huella cambia, y se ofrece de nuevo.
    $huella = Get-HuellaFaltantes -Piezas $piezas
    $marca = Join-Path $carpeta 'setup-omitido.json'
    if (Test-Path $marca) {
        try {
            if ((Get-Content $marca -Raw | ConvertFrom-Json).huella -eq $huella) { return }
        } catch { }
    }

    $filas = foreach ($p in $piezas) {
        @{ Texto = $p.Nombre; Dato = $(if ($p.Ok) { 'ok' } else { 'falta' }) }
    }

    $pedir = @{
        Encabezado = 'Falta completar la instalación'
        Nombre     = 'Hasta que esté completa, el panel anda a medias.'
        Filas      = @($filas)
        Aviso      = 'Se escribe sólo en tu usuario (HKCU y PATH de usuario): no hace falta admin.'
        TextoOk    = 'Instalar'
        Icono      = 'engranaje'
    }
    if (-not (Show-Confirmacion @pedir)) {
        try {
            @{ huella = $huella; cuando = (Get-Date -Format 'o') } |
                ConvertTo-Json | Set-Content -Path $marca -Encoding UTF8
        } catch { }
        return
    }

    $tocoPath = @($piezas | Where-Object { -not $_.Ok -and $_.Clave -eq 'path' }).Count -gt 0
    $r = Repair-Instalacion -Piezas $piezas
    Remove-Item -LiteralPath $marca -Force -ErrorAction SilentlyContinue

    $hechas = @()
    foreach ($h in $r.Hechas) { $hechas += @{ Texto = $h; Dato = 'instalado' } }
    foreach ($e in $r.Errores) { $hechas += @{ Texto = $e; Dato = 'error' } }

    $avisoFinal = if ($r.Errores.Count -gt 0) {
        'Quedó algo sin instalar. Corré .\setup.ps1 en una terminal para ver el detalle.'
    } elseif ($tocoPath) {
        'El PATH cambió: los comandos aparecen en las terminales que abras de ahora en más. Las ya abiertas, Claude Code incluido, siguen con el PATH viejo.'
    } else { '' }

    $avisar = @{
        Encabezado  = $(if ($r.Errores.Count -gt 0) { 'Instalación incompleta' } else { 'Instalación lista' })
        Filas       = @($hechas)
        Aviso       = $avisoFinal
        TextoOk     = 'Listo'
        Icono       = $(if ($r.Errores.Count -gt 0) { 'engranaje' } else { 'tilde' })
        SoloAceptar = $true
    }
    Show-Confirmacion @avisar | Out-Null
    Actualizar
}

# Va en ContentRendered y no en Loaded: un dialogo modal necesita que la ventana
# dueña ya este mostrada, o el Owner tira excepcion.
$script:setupChequeado = $false
$ventana.Add_ContentRendered({
        if ($script:setupChequeado) { return }
        $script:setupChequeado = $true
        try {
            Invoke-ChequeoSetup
        } catch {
            # Si falla el chequeo, el gadget tiene que seguir vivo igual. Se usa
            # MessageBox y no el dialogo propio porque justamente puede ser el
            # que esta roto.
            [Windows.MessageBox]::Show($_.Exception.Message, 'Chequeo de instalacion') | Out-Null
        }
    })

Set-Apariencia
Actualizar
$ventana.ShowDialog() | Out-Null
