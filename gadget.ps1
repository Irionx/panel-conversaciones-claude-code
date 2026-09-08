# =============================================================================
#  gadget.ps1 - Gadget de escritorio (WPF nativo, sin instalar nada)
#
#  Ventana sin bordes, fondo translucido, arrastrable y ensanchable. Lista las
#  conversaciones de conversaciones.js con su % de contexto y las abre de un
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
#  Cada gadget tiene sus propios timers Y escribe conversaciones.js (el sync de
#  titulos), asi que varios abiertos a la vez se pisan el archivo y multiplican
#  el trabajo. Paso de verdad: llegaron a haber tres corriendo y la herramienta
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

# --- ventana -----------------------------------------------------------------
#  ShowInTaskbar va True FIJO, no en caliente: WPF destruye y recrea el HWND
#  cuando cambia, asi que "boton solo mientras esta minimizada" no vale la pena.
#  De paso, un gadget colgado ya no queda invisible (ver el timer mas abajo).
#  WindowStyle=None no trae boton de minimizar del sistema: lo pone btnMinimizar.
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Conversaciones" Width="348" SizeToContent="Height"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ShowInTaskbar="True" Topmost="True" ResizeMode="NoResize"
        WindowStartupLocation="Manual"
        FontFamily="Segoe UI">
  <Window.Resources>
    <!-- Barra de scroll propia. Dos motivos, y el segundo es el importante:
           (1) la nativa es gris claro de Windows y rompe la estetica;
           (2) va SUPERPUESTA, no en una columna del layout. La nativa ocupa
               ~17px de ancho REAL: cuando aparecia, las tarjetas adelgazaban y
               el texto y las barras se movian de lugar. Y aparecia justo al
               bloquear, porque bloqueado la lista crece 14px (el aire de las
               sombras) y cruzaba el MaxHeight. Superpuesta, el ancho del
               contenido no cambia nunca. -->
    <Style x:Key="ScrollFino" TargetType="ScrollBar">
      <Setter Property="Width" Value="8"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Grid Background="Transparent">
              <Track x:Name="PART_Track" IsDirectionReversed="True">
                <Track.Thumb>
                  <Thumb>
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb">
                        <!-- En reposo casi no se ve (#26 = 15% de blanco): es un
                             indicador, no un elemento de la interfaz. Se
                             enciende cuando el mouse esta encima. -->
                        <Border x:Name="pastilla" Width="4" CornerRadius="2"
                                HorizontalAlignment="Center" Background="#26FFFFFF"/>
                        <ControlTemplate.Triggers>
                          <Trigger Property="IsMouseOver" Value="True">
                            <Setter TargetName="pastilla" Property="Background" Value="#73FFFFFF"/>
                          </Trigger>
                          <Trigger Property="IsDragging" Value="True">
                            <Setter TargetName="pastilla" Property="Background" Value="#CC4ADE80"/>
                          </Trigger>
                        </ControlTemplate.Triggers>
                      </ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
                <!-- Opacity 0 y no Visibility: invisibles pero siguen recibiendo
                     el click, que es lo que da el salto de pagina en la pista. -->
                <Track.DecreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.PageUpCommand" Opacity="0" Focusable="False"/>
                </Track.DecreaseRepeatButton>
                <Track.IncreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.PageDownCommand" Opacity="0" Focusable="False"/>
                </Track.IncreaseRepeatButton>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="ScrollSuperpuesto" TargetType="ScrollViewer">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollViewer">
            <!-- Un solo Grid sin columnas: el contenido y la barra comparten la
                 celda, asi que la barra flota encima en vez de robar ancho.
                 El nombre PART_VerticalScrollBar NO es decorativo: el
                 ScrollViewer lo busca por ese nombre para engancharle el evento
                 Scroll. Sin ese nombre exacto, arrastrar la pastilla no hace
                 nada (se ve bien y no scrollea). -->
            <Grid>
              <ScrollContentPresenter x:Name="PART_ScrollContentPresenter"
                                      CanContentScroll="{TemplateBinding CanContentScroll}"
                                      Content="{TemplateBinding Content}"
                                      ContentTemplate="{TemplateBinding ContentTemplate}"
                                      Margin="{TemplateBinding Padding}"/>
              <ScrollBar x:Name="PART_VerticalScrollBar" Orientation="Vertical"
                         Style="{StaticResource ScrollFino}"
                         HorizontalAlignment="Right" Margin="0,2,4,2"
                         Value="{TemplateBinding VerticalOffset}"
                         Maximum="{TemplateBinding ScrollableHeight}"
                         ViewportSize="{TemplateBinding ViewportHeight}"
                         Visibility="{TemplateBinding ComputedVerticalScrollBarVisibility}"/>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Grid>
    <!-- El margen deja aire para que la sombra del panel se dibuje: sin el,
         queda recortada contra el borde de la ventana, que es un limite duro.
         Regla practica: una DropShadow se extiende BlurRadius/2 + ShadowDepth.
         Con Blur 16 y Prof 3 eso da 11, y el margen tiene que ser >= 11. -->
    <Border x:Name="fondo" CornerRadius="14" Background="#E6161A20" Margin="12"
            BorderBrush="#2EFFFFFF" BorderThickness="1" Padding="14,12,14,12">
      <StackPanel>
        <DockPanel x:Name="cabecera" Margin="0,0,0,10">
          <!-- Bloqueado, los botones quedan flotando sobre el escritorio y no se
               leen. Este Border se convierte en una tarjeta miniatura para
               darles fondo; desbloqueado queda invisible. Lo maneja
               Set-Apariencia. -->
          <!-- VerticalAlignment Top y no el Stretch por defecto: el chip de la
               cuota mide cuatro filas, y sin esto la cajita de los botones se
               estiraba a lo alto y quedaba medio vacia al bloquear. -->
          <Border x:Name="chipBotones" DockPanel.Dock="Right" CornerRadius="9"
                  VerticalAlignment="Top">
            <StackPanel Orientation="Horizontal">
              <Button x:Name="btnCandado" Content="&#128275;" Width="22" Height="22" Margin="2,0,0,0"
                      ToolTip="Bloquear posicion" Cursor="Hand" FontFamily="Segoe UI Emoji"
                      Background="Transparent" BorderThickness="0" Foreground="#8A94A6" FontSize="11"/>
              <Button x:Name="btnArriba" Width="22" Height="22" Margin="2,0,0,0"
                      Cursor="Hand" FontFamily="Segoe MDL2 Assets"
                      Background="Transparent" BorderThickness="0" Foreground="#8A94A6" FontSize="11"/>
              <Button x:Name="btnOpacidad" Content="&#9681;" Width="22" Height="22" Margin="2,0,0,0"
                      ToolTip="Transparencia" Cursor="Hand"
                      Background="Transparent" BorderThickness="0" Foreground="#8A94A6" FontSize="12"/>
              <Button x:Name="btnRefrescar" Content="&#8635;" Width="22" Height="22" Margin="2,0,0,0"
                      ToolTip="Refrescar" Cursor="Hand"
                      Background="Transparent" BorderThickness="0" Foreground="#8A94A6" FontSize="13"/>
              <Button x:Name="btnMinimizar" Content="&#xE921;" Width="22" Height="22" Margin="2,0,0,0"
                      ToolTip="Minimizar a la barra de tareas" Cursor="Hand" FontFamily="Segoe MDL2 Assets"
                      Background="Transparent" BorderThickness="0" Foreground="#8A94A6" FontSize="10"/>
              <Button x:Name="btnCerrar" Content="&#10005;" Width="22" Height="22" Margin="2,0,0,0"
                      ToolTip="Cerrar" Cursor="Hand"
                      Background="Transparent" BorderThickness="0" Foreground="#8A94A6" FontSize="11"/>
            </StackPanel>
          </Border>
          <!-- Contexto sumado de todas las charlas del panel. Reemplaza al
               titulo fijo: "Conversaciones" no informaba nada, y bloqueado ni
               siquiera se veia. Lo llena Set-Resumen en cada refresco. -->
          <!-- Una fila por ventana de cuota: diario (5h) y semanal (7d), cada
               una con su porcentaje, su barra y a que hora resetea. Las dos
               juntas, y no solo la mayor, porque son los dos numeros que
               muestra el statusline y asi no hay forma de que dejen de
               coincidir. La barra va en la columna * : se estira sola cuando se
               ensancha la ventana. -->
          <!-- La barra va en su PROPIA fila, no al lado del texto. Compartiendo
               fila con el nombre y la hora de reset, en una ventana de 348 con
               seis botones al lado, a la barra le quedaban 26px: ilegible. A
               ancho completo se lee, y se estira al ensanchar la ventana. -->
          <Border x:Name="chipResumen" CornerRadius="9" VerticalAlignment="Center">
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
              </Grid.RowDefinitions>

              <TextBlock x:Name="cuotaNom1" Grid.Row="0" Grid.Column="0" FontSize="11.5"
                         FontWeight="SemiBold" Foreground="#F2F5F9"/>
              <TextBlock x:Name="cuotaReset1" Grid.Row="0" Grid.Column="1" FontSize="9.5"
                         Foreground="#6B7484" VerticalAlignment="Center" Margin="10,0,0,0"/>
              <Grid x:Name="cuotaBarra1" Grid.Row="1" Grid.ColumnSpan="2" Height="4" Margin="0,3,0,0">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="0.001*"/>
                  <ColumnDefinition Width="100*"/>
                </Grid.ColumnDefinitions>
                <Border x:Name="cuotaLleno1" Grid.Column="0" CornerRadius="2" Background="#4ADE80"/>
                <Border Grid.Column="1" CornerRadius="2" Background="#22FFFFFF" Margin="1,0,0,0"/>
              </Grid>

              <TextBlock x:Name="cuotaNom2" Grid.Row="2" Grid.Column="0" FontSize="11.5"
                         FontWeight="SemiBold" Foreground="#F2F5F9" Margin="0,6,0,0"/>
              <TextBlock x:Name="cuotaReset2" Grid.Row="2" Grid.Column="1" FontSize="9.5"
                         Foreground="#6B7484" VerticalAlignment="Center" Margin="10,6,0,0"/>
              <Grid x:Name="cuotaBarra2" Grid.Row="3" Grid.ColumnSpan="2" Height="4" Margin="0,3,0,0">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="0.001*"/>
                  <ColumnDefinition Width="100*"/>
                </Grid.ColumnDefinitions>
                <Border x:Name="cuotaLleno2" Grid.Column="0" CornerRadius="2" Background="#4ADE80"/>
                <Border Grid.Column="1" CornerRadius="2" Background="#22FFFFFF" Margin="1,0,0,0"/>
              </Grid>
            </Grid>
          </Border>
        </DockPanel>

        <!-- MaxHeight y no Height: con SizeToContent="Height" la ventana se
             ajusta al contenido, asi que esto es "hasta donde puede crecer".
             Lo mueve el grip de abajo y se guarda en gadget-posicion.json. -->
        <ScrollViewer x:Name="scroller" MaxHeight="520" VerticalScrollBarVisibility="Auto"
                      HorizontalScrollBarVisibility="Disabled"
                      Style="{StaticResource ScrollSuperpuesto}">
          <StackPanel x:Name="lista"/>
        </ScrollViewer>

        <TextBlock x:Name="pie" Foreground="#6B7484" FontSize="10" Margin="2,8,0,0"/>
      </StackPanel>
    </Border>

    <!-- Franjas invisibles sobre los bordes para ensanchar. Van despues del
         Border para quedar por encima, y con Fill transparente (no null) para
         que reciban el mouse. -->
    <Rectangle x:Name="gripIzq" Width="12" HorizontalAlignment="Left" Fill="Transparent" Cursor="SizeWE"/>
    <Rectangle x:Name="gripDer" Width="12" HorizontalAlignment="Right" Fill="Transparent" Cursor="SizeWE"/>
    <!-- El de abajo no cambia el alto de la VENTANA (que lo decide
         SizeToContent) sino el MaxHeight del ScrollViewer, o sea cuanta lista
         se ve antes de scrollear. Margin 12 a los costados para no pelearse
         con los dos grips verticales en las esquinas. -->
    <Rectangle x:Name="gripAbajo" Height="12" VerticalAlignment="Bottom" Margin="12,0,12,0"
               Fill="Transparent" Cursor="SizeNS"/>
  </Grid>
</Window>
'@

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

# --- apariencia segun opacidad y candado -------------------------------------
#  Al bloquear desaparece SOLO el contenedor: las tarjetas mantienen su fondo,
#  porque atenuarlas tambien las volvia ilegibles. Queda la lista flotando
#  sobre el escritorio.
#  El fondo se pone en $null y no en alpha 00 a proposito: un pincel con alpha 0
#  igual recibe clicks (taparia el escritorio), mientras que sin pincel los
#  clicks pasan de largo en las zonas vacias. Los hijos (tarjetas, botones)
#  siguen recibiendo mouse normalmente, asi el candado se puede volver a abrir.
function Get-AlphaFondo {
    return $ALPHAS[$script:idxAlpha % $ALPHAS.Count]
}

# Desbloqueado la tarjeta es apenas un tinte blanco: se lee porque el panel
# oscuro esta detras. Bloqueado ese panel no existe, asi que cada tarjeta tiene
# que llevarse el fondo puesto o queda flotando ilegible sobre el escritorio.
#
# Bloqueado el fondo va OPACO y sin atarse al ciclador de opacidad: la
# transparencia es del contenedor, no de las conversaciones. Un hex de 6 digitos
# es opaco en WPF.
function Get-ColorTarjeta {
    if ($script:bloqueado) { return '#1E222A' }
    return '#14FFFFFF'
}
function Get-ColorHover {
    if ($script:bloqueado) { return '#2B313C' }
    return '#26FFFFFF'
}

function Pincel([string]$Hex) { return [Windows.Media.BrushConverter]::new().ConvertFrom($Hex) }

# --- deja rastro de una falla sin matar el gadget -----------------------------
#  Los timers no pueden dejar escapar una excepcion (ver el comentario del
#  Add_Tick), pero tragarsela en silencio deja el problema invisible.
function Write-Falla {
    param([string]$Donde, $Err)
    try {
        ('{0}  {1}: {2}' -f (Get-Date -Format 's'), $Donde, $Err.Exception.Message) |
            Add-Content -Path (Join-Path $carpeta 'gadget-fallas.log') -Encoding UTF8
    } catch { }
}

function New-Sombra {
    param([double]$Blur = 16, [double]$Prof = 3, [double]$Op = 0.6)
    $s = New-Object Windows.Media.Effects.DropShadowEffect
    $s.BlurRadius = $Blur
    $s.ShadowDepth = $Prof
    $s.Direction = 270
    $s.Color = [Windows.Media.Colors]::Black
    $s.Opacity = $Op
    return $s
}

function Set-Apariencia {
    if ($script:bloqueado) {
        $fondo.Background = $null
        $fondo.BorderBrush = $null
        $fondo.Effect = $null       # la sombra la lleva cada tarjeta
        # Se le devuelve al ScrollViewer el ancho que las tarjetas usan de
        # margen, para que la sombra tenga lugar y la tarjeta mida igual.
        $fondo.Padding = $PAD_BLOQUEADO
        # La cabecera no esta dentro del ScrollViewer, asi que se le pone el
        # mismo aire a mano o el chip queda 12px mas a la derecha que las tarjetas.
        $cabecera.Margin = [Windows.Thickness]::new($AIRE_SOMBRA, 0, $AIRE_SOMBRA, 10)
        # Aire para las sombras de la PRIMERA y la ULTIMA tarjeta, que son las
        # unicas que el ScrollViewer recorta de verdad. Va aca y no en el margen
        # de cada tarjeta, asi el hueco ENTRE tarjetas queda igual que en suelto.
        # Alcance de la sombra (Blur 14 -> 7, Prof 3 hacia abajo): 4 arriba, 10
        # abajo.
        $lista.Margin = [Windows.Thickness]::new(0, 4, 0, 10)

        # Los botones se convierten en una tarjeta miniatura: sin fondo propio
        # son cuatro glifos grises flotando sobre el escritorio.
        $chipBotones.Background = Pincel (Get-ColorTarjeta)
        $chipBotones.BorderBrush = Pincel '#33FFFFFF'
        $chipBotones.BorderThickness = [Windows.Thickness]::new(1)
        $chipBotones.Padding = [Windows.Thickness]::new(5, 3, 5, 3)
        $chipBotones.Effect = New-Sombra -Blur 14 -Prof 3 -Op 0.7
        # Titulo y pie viven sobre el panel: sin panel quedan flotando ilegibles.
        # El resumen SI se queda: bloqueado es cuando mas se mira el panel.
        # Se lleva el mismo chip que los botones para poder leerse sobre el
        # escritorio.
        $chipResumen.Background = Pincel (Get-ColorTarjeta)
        $chipResumen.BorderBrush = Pincel '#33FFFFFF'
        $chipResumen.BorderThickness = [Windows.Thickness]::new(1)
        $chipResumen.Padding = [Windows.Thickness]::new(10, 6, 10, 7)
        $chipResumen.Effect = New-Sombra -Blur 14 -Prof 3 -Op 0.7
        $pie.Visibility = 'Collapsed'
    } else {
        $fondo.Background = Pincel "#$(Get-AlphaFondo)161A20"
        $fondo.BorderBrush = Pincel '#2EFFFFFF'
        # Blur 16 + Prof 3 = 11 de alcance, y el margen del Border es 12: entra
        # entera. Con los 20 de antes se pasaba y la ventana la cortaba.
        $fondo.Effect = New-Sombra -Blur 16 -Prof 3 -Op 0.55
        $fondo.Padding = $PAD_NORMAL
        $cabecera.Margin = [Windows.Thickness]::new(0, 0, 0, 10)
        # Suelto no hay sombra por tarjeta, asi que no hay nada que recortar.
        $lista.Margin = [Windows.Thickness]::new(0)

        # Con el panel detras los botones se leen solos: el chip desaparece.
        $chipBotones.Background = $null
        $chipBotones.BorderBrush = $null
        $chipBotones.BorderThickness = [Windows.Thickness]::new(0)
        $chipBotones.Padding = [Windows.Thickness]::new(0)
        $chipBotones.Effect = $null
        $chipResumen.Background = $null
        $chipResumen.BorderBrush = $null
        $chipResumen.BorderThickness = [Windows.Thickness]::new(0)
        $chipResumen.Padding = [Windows.Thickness]::new(0)
        $chipResumen.Effect = $null
        $pie.Visibility = 'Visible'
    }
    $btnCandado.Content = if ($script:bloqueado) { $LOCK_CERRADO } else { $LOCK_ABIERTO }
    $btnCandado.Foreground = Pincel $(if ($script:bloqueado) { '#E0A45A' } else { '#8A94A6' })
    $btnCandado.ToolTip = if ($script:bloqueado) { 'Desbloquear (posicion fija)' } else { 'Bloquear posicion' }
    # Topmost se aplica aca y no solo en el click: asi el estado guardado tambien
    # se respeta al arrancar, con una sola fuente de verdad.
    $ventana.Topmost = $script:arriba
    $btnArriba.Content = if ($script:arriba) { $PIN_CLAVADO } else { $PIN_SUELTO }
    $btnArriba.Foreground = Pincel $(if ($script:arriba) { '#4ADE80' } else { '#8A94A6' })
    $btnArriba.ToolTip = if ($script:arriba) { 'Siempre arriba: SI (click para soltar)' } else { 'Siempre arriba: NO (click para clavar)' }
    $gripIzq.Cursor = if ($script:bloqueado) { 'Arrow' } else { 'SizeWE' }
    $gripDer.Cursor = $gripIzq.Cursor
    $gripAbajo.Cursor = if ($script:bloqueado) { 'Arrow' } else { 'SizeNS' }
    $cabecera.Cursor = if ($script:bloqueado) { 'Arrow' } else { 'SizeAll' }
}

# --- color segun cuan lleno esta el contexto ---------------------------------
function Get-ColorContexto {
    param([double]$Pct)
    if ($Pct -ge 85) { return '#F87171' }   # rojo
    if ($Pct -ge 60) { return '#FBBF24' }   # ambar
    return '#4ADE80'                         # verde
}

function Escapar { param([string]$T) return [System.Security.SecurityElement]::Escape([string]$T) }

# --- confirmacion propia -----------------------------------------------------
#  MessageBox es el dialogo nativo de Win32: no se puede estilar y rompia la
#  estetica del gadget. Este usa la misma paleta que las tarjetas.
#
#  Devuelve $true solo si se confirmo. El boton de cancelar es el default (Enter)
#  y ademas el de Escape, a proposito: en un dialogo destructivo la tecla facil
#  tiene que ser la que no borra.
function Show-Confirmacion {
    param(
        [Parameter(Mandatory)][string]$Encabezado,
        # No es Mandatory a proposito: un [string] Mandatory con '' hace que
        # PowerShell pida el valor por consola, y un gadget sin consola se cuelga.
        [string]$Nombre = '',
        [array]$Filas = @(),
        [string]$Aviso = '',
        [string]$TextoOk = 'Aceptar',
        # Vacio = se deduce de -Peligro. Los glifos MDL2 estan verificados: si
        # se agrega otro, chequear que exista en la fuente o sale un cuadradito.
        [ValidateSet('', 'cruz', 'tacho', 'engranaje', 'tilde')][string]$Icono = '',
        [switch]$Peligro,
        [switch]$SoloAceptar
    )

    # Un solo ControlTemplate para los dos botones: el look lo define el
    # Background/BorderBrush de cada instancia, via TemplateBinding.
    $x = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        SizeToContent="Height" Width="452" ShowInTaskbar="False" Topmost="True"
        ResizeMode="NoResize" WindowStartupLocation="CenterOwner" FontFamily="Segoe UI">
  <Window.Resources>
    <Style x:Key="Chato" TargetType="Button">
      <Setter Property="Background" Value="#1AFFFFFF"/>
      <Setter Property="BorderBrush" Value="#2EFFFFFF"/>
      <Setter Property="Foreground" Value="#C7CEDA"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Padding" Value="17,7,17,8"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="SnapsToDevicePixels" Value="True"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="marco" CornerRadius="7"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="1"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="marco" Property="Opacity" Value="0.78"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="marco" Property="BorderBrush" Value="#7A8699"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <!-- El margen deja aire para que la sombra se dibuje entera. -->
  <Border x:Name="tarjeta" CornerRadius="14" Background="#F2161A20" Margin="13"
          BorderBrush="#2EFFFFFF" BorderThickness="1" Padding="19,17,19,17">
    <Border.Effect>
      <DropShadowEffect BlurRadius="28" ShadowDepth="0" Opacity="0.6" Color="#000000"/>
    </Border.Effect>
    <StackPanel>
      <StackPanel Orientation="Horizontal" Margin="0,0,0,11">
        <TextBlock x:Name="icono" FontSize="15" VerticalAlignment="Center" Margin="0,0,10,0"/>
        <TextBlock x:Name="encabezado" Foreground="#F2F5F9" FontSize="13.5"
                   FontWeight="SemiBold" VerticalAlignment="Center"/>
      </StackPanel>

      <TextBlock x:Name="nombre" Foreground="#F2F5F9" FontSize="12.5"
                 TextWrapping="Wrap" Margin="0,0,0,15"/>

      <Border x:Name="cajaFilas" CornerRadius="8" Background="#12FFFFFF"
              Padding="13,10,13,10" Margin="0,0,0,14">
        <StackPanel x:Name="filas"/>
      </Border>

      <TextBlock x:Name="aviso" FontSize="11.5" TextWrapping="Wrap" Margin="0,0,0,17"/>

      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="btnNo" Content="Cancelar" Style="{StaticResource Chato}"
                IsDefault="True" IsCancel="True" Margin="0,0,9,0"/>
        <Button x:Name="btnSi" Style="{StaticResource Chato}"/>
      </StackPanel>
    </StackPanel>
  </Border>
</Window>
'@

    $d = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$x)))

    $d.FindName('encabezado').Text = $Encabezado
    $d.FindName('btnSi').Content = $TextoOk

    $nom = $d.FindName('nombre')
    if ($Nombre) { $nom.Text = $Nombre } else { $nom.Visibility = 'Collapsed' }

    # Modo aviso: un solo boton, que pasa a ser tambien el de Escape.
    if ($SoloAceptar) {
        $no = $d.FindName('btnNo')
        $no.Visibility = 'Collapsed'
        $no.IsDefault = $false
        $no.IsCancel = $false
        $si = $d.FindName('btnSi')
        $si.IsDefault = $true
        $si.IsCancel = $true
    }

    # La cruz vive en la fuente normal; el resto en Segoe MDL2 Assets.
    if (-not $Icono) { $Icono = $(if ($Peligro) { 'tacho' } else { 'cruz' }) }
    $glifos = @{
        cruz      = @{ Cod = 0x2715; Mdl2 = $false; Color = '#8A94A6' }
        tacho     = @{ Cod = 0xE74D; Mdl2 = $true; Color = '#F87171' }
        engranaje = @{ Cod = 0xE713; Mdl2 = $true; Color = '#8A94A6' }
        tilde     = @{ Cod = 0xE73E; Mdl2 = $true; Color = '#4ADE80' }
    }
    $g = $glifos[$Icono]

    $ico = $d.FindName('icono')
    $ico.Text = [string][char]$g.Cod
    if ($g.Mdl2) {
        $ico.FontFamily = New-Object Windows.Media.FontFamily -ArgumentList 'Segoe MDL2 Assets'
    }
    $ico.Foreground = Pincel $g.Color

    # Jerarquia: el primario tiene que distinguirse del fantasma, o los dos
    # botones se leen igual y no se sabe cual es la accion.
    $si = $d.FindName('btnSi')
    if ($Peligro) {
        $si.Background = Pincel '#C2352F'
        $si.BorderBrush = Pincel '#E86A62'
        $si.Foreground = Pincel '#FFF2F1'
    } else {
        $si.Background = Pincel '#3C4553'
        $si.BorderBrush = Pincel '#5A6473'
        $si.Foreground = Pincel '#F2F5F9'
    }

    $av = $d.FindName('aviso')
    if ($Aviso) {
        $av.Text = $Aviso
        $av.Foreground = Pincel $(if ($Peligro) { '#EFA9A4' } else { '#8A94A6' })
    } else {
        $av.Visibility = 'Collapsed'
    }

    # Las filas se arman en codigo porque la cantidad es variable. Monoespaciada
    # para que los tamanos queden en columna.
    $cont = $d.FindName('filas')
    if ($Filas.Count -eq 0) {
        $d.FindName('cajaFilas').Visibility = 'Collapsed'
    } else {
        $mono = New-Object Windows.Media.FontFamily -ArgumentList 'Consolas'
        foreach ($f in $Filas) {
            $g = New-Object Windows.Controls.Grid
            $g.Margin = [Windows.Thickness]::new(0, 1.5, 0, 1.5)

            $cA = New-Object Windows.Controls.ColumnDefinition
            $cA.Width = [Windows.GridLength]::new(1, [Windows.GridUnitType]::Star)
            $cB = New-Object Windows.Controls.ColumnDefinition
            $cB.Width = [Windows.GridLength]::Auto
            $g.ColumnDefinitions.Add($cA)
            $g.ColumnDefinitions.Add($cB)

            $tx = New-Object Windows.Controls.TextBlock
            $tx.Text = [string]$f.Texto
            $tx.Foreground = Pincel '#C7CEDA'
            $tx.FontSize = 11
            $tx.FontFamily = $mono
            $tx.TextTrimming = 'CharacterEllipsis'
            [Windows.Controls.Grid]::SetColumn($tx, 0)
            $g.Children.Add($tx) | Out-Null

            if ($f.Dato) {
                $dt = New-Object Windows.Controls.TextBlock
                $dt.Text = [string]$f.Dato
                $dt.Foreground = Pincel '#8A94A6'
                $dt.FontSize = 11
                $dt.FontFamily = $mono
                $dt.Margin = [Windows.Thickness]::new(12, 0, 0, 0)
                [Windows.Controls.Grid]::SetColumn($dt, 1)
                $g.Children.Add($dt) | Out-Null
            }

            $cont.Children.Add($g) | Out-Null
        }
    }

    $d.Owner = $ventana
    $d.FindName('btnSi').Add_Click({ [Windows.Window]::GetWindow($this).DialogResult = $true })
    # Sin barra de titulo hay que mover a mano. Los botones marcan el evento como
    # manejado, asi que esto no interfiere con los clicks.
    $d.FindName('tarjeta').Add_MouseLeftButtonDown({
            try { [Windows.Window]::GetWindow($this).DragMove() } catch { }
        })
    # Foco en el boton que NO destruye (o en el unico, si es un aviso). Se pasa
    # por Tag porque el scriptblock no ve las variables de esta funcion.
    $d.Tag = $(if ($SoloAceptar) { 'btnSi' } else { 'btnNo' })
    $d.Add_Loaded({ $this.FindName($this.Tag).Focus() | Out-Null })

    return ($d.ShowDialog() -eq $true)
}

# --- botones sin chrome ------------------------------------------------------
#  El template por defecto de Button dibuja un recuadro gris/azul al pasar el
#  mouse, y ese fondo no se saca poniendo Background=Transparent: lo pinta el
#  ControlTemplate, no la propiedad. Hay que reemplazar el template entero.
#  Un mismo ControlTemplate se puede compartir entre botones, asi que se arma
#  una sola vez y no una por tarjeta.
$xamlPlano = @'
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
  <Border Background="Transparent">
    <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
  </Border>
</ControlTemplate>
'@
$script:tplPlano = [Windows.Markup.XamlReader]::Load(
    (New-Object System.Xml.XmlNodeReader ([xml]$xamlPlano)))

# --- dibuja una tarjeta ------------------------------------------------------
function New-Tarjeta {
    param($C, $Ctx)

    # El nombre real de la sesion (el de /rename) manda sobre el titulo guardado:
    # asi renombrar en Claude Code se refleja aca sin volver a guardar nada.
    $tituloCard = Get-TituloMostrable -Conversacion $C

    $sub = @($C.proyecto, $C.rama) | Where-Object { $_ } | ForEach-Object { [string]$_ }
    $subtitulo = if ($sub.Count) { $sub -join '  ·  ' } else { [string]$C.cwd }

    if ($Ctx.Hay) {
        $pct = [double]$Ctx.Porcentaje
        $color = Get-ColorContexto $pct
        $dato = '{0}%  ·  {1} de {2}' -f $pct, (Format-Tokens $Ctx.Tokens), (Format-Tokens $Ctx.Limite)
    } else {
        $pct = 0
        $color = '#3A4150'
        $dato = 'sin transcript'
    }

    # La barra se arma con columnas proporcionales (estrellas) en vez de anchos
    # en pixeles: asi se estira sola cuando se ensancha la ventana.
    $lleno = [math]::Max(1.5, [math]::Min($pct, 100))
    $vacio = [math]::Max(0.001, 100 - $lleno)

    $cCard = Get-ColorTarjeta

    # Bloqueada la tarjeta flota sobre cualquier cosa, asi que necesita las dos
    # defensas: la SOMBRA la despega de fondos claros, y el FILO claro la recorta
    # contra fondos oscuros o del mismo color, donde la sombra no se ve.
    if ($script:bloqueado) {
        $bordeCard = 'BorderBrush="#33FFFFFF" BorderThickness="1"'
        $sombraCard = '<Border.Effect><DropShadowEffect BlurRadius="14" ShadowDepth="3" Direction="270" Color="#FF000000" Opacity="0.7"/></Border.Effect>'
        # El margen HORIZONTAL no es estetico: el ScrollViewer recorta a sus
        # limites (tiene que hacerlo, para poder scrollear), asi que sin aire la
        # sombra queda cortada con un filo vertical. Set-Apariencia le resta lo
        # mismo al padding del contenedor, asi la tarjeta no adelgaza.
        #
        # El VERTICAL, en cambio, se iguala al de suelto (0 arriba, 7 abajo): la
        # sombra hacia abajo la tapa sola la tarjeta siguiente, que se dibuja
        # despues y por lo tanto encima. Entre tarjetas no hace falta aire. El
        # unico que se recortaba de verdad era el de los EXTREMOS de la lista, y
        # eso lo resuelve el margen de $lista en Set-Apariencia.
        $margenCard = "$AIRE_SOMBRA,0,$AIRE_SOMBRA,7"
    } else {
        $bordeCard = ''
        $sombraCard = ''
        $margenCard = '0,0,0,7'
    }

    $x = @"
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Background="$cCard" CornerRadius="9" Padding="10,8,10,9" Margin="$margenCard" Cursor="Hand" $bordeCard>
  $sombraCard
  <Grid>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="*"/>
      <ColumnDefinition Width="Auto"/>
    </Grid.ColumnDefinitions>
    <StackPanel Grid.Column="0">
      <TextBlock Text="$(Escapar $tituloCard)" Foreground="#F2F5F9" FontSize="12.5" FontWeight="SemiBold"
                 TextTrimming="CharacterEllipsis"/>
      <TextBlock Text="$(Escapar $subtitulo)" Foreground="#8A94A6" FontSize="10.5" Margin="0,1,0,7"
                 TextTrimming="CharacterEllipsis"/>
      <Grid Height="4">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="$lleno*"/>
          <ColumnDefinition Width="$vacio*"/>
        </Grid.ColumnDefinitions>
        <Border Grid.Column="0" CornerRadius="2" Background="$color"/>
        <Border Grid.Column="1" CornerRadius="2" Background="#22FFFFFF" Margin="1,0,0,0"/>
      </Grid>
      <TextBlock Text="$(Escapar $dato)" Foreground="#6B7484" FontSize="10" Margin="0,5,0,0"/>
    </StackPanel>
  </Grid>
</Border>
"@

    $t = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$x)))
    # El titulo va en el Tag porque el click lo necesita para encontrar la
    # pestana correcta de Windows Terminal, que se llama igual que la sesion.
    $t.Tag = @{ conv = $C; base = $cCard; hover = (Get-ColorHover); titulo = $tituloCard }
    $t.ToolTip = "$($C.cwd)`nclaude --resume $($C.sesion)"

    $t.Add_MouseLeftButtonUp({
            $conv = $this.Tag.conv
            try {
                # Si ya esta abierta, se trae su terminal al frente en vez de
                # abrir una SEGUNDA copia de la misma conversacion. Si por lo
                # que sea no se pudo enfocar, se cae al comportamiento viejo.
                $h = Get-VentanaSesion -Sesion $conv.sesion
                if ($h -ne [IntPtr]::Zero) {
                    # Primero la pestana y despues el foco: al reves se ve un
                    # parpadeo de la pestana equivocada.
                    [void](Select-PestanaSesion -Handle $h -Nombre $this.Tag.titulo)
                    if (Show-VentanaSesion -Handle $h) { return }
                }

                Start-Conversacion -Cwd $conv.cwd -Sesion $conv.sesion | Out-Null
            } catch {
                [Windows.MessageBox]::Show($_.Exception.Message, 'Conversaciones') | Out-Null
            }
        })
    $t.Add_MouseEnter({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFrom($this.Tag.hover) })
    $t.Add_MouseLeave({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFrom($this.Tag.base) })

    # El boton se crea en codigo: FindName no alcanza dentro de un fragmento
    # XAML parseado suelto, que no tiene NameScope propio.

    # Punto de estado del remoto: es semaforo y boton a la vez.
    #   gris  -> cerrada, el click la abre con --remote-control
    #   verde -> hay una terminal viva CON remoto: ya esta en el celular
    #   azul  -> hay una terminal viva SIN remoto
    # El estado sale de $script:estados, que Actualizar calcula UNA sola vez por
    # refresco. Un punto plano y no un glifo MDL2: 0x25CF es Unicode comun, no
    # depende de que la fuente lo tenga.
    $estado = $null
    if ($script:estados) { $estado = $script:estados[([string]$C.sesion).ToLower()] }

    # El glifo distingue REMOTO de simplemente ABIERTA, no solo el color: la
    # señal se lee de un vistazo y el color solo no alcanza cuando el gadget
    # esta en modo fantasma.
    $fuentePunto = $null
    switch ($estado) {
        'remoto' {
            $glifoPunto = [char]0xE701          # señal (WiFi) de Segoe MDL2 Assets
            $fuentePunto = 'Segoe MDL2 Assets'
            $colPunto = '#4ADE80'
            $tipPunto = 'Remoto prendido: esta conversación está disponible en el celular'
        }
        'abierta' {
            $glifoPunto = [char]0x25CF          # punto solido, Unicode comun
            $colPunto = '#60A5FA'
            $tipPunto = 'Abierta en una terminal, pero SIN remoto'
        }
        default {
            $glifoPunto = [char]0x25CF
            $colPunto = '#5A6473'
            $tipPunto = 'Abrir con Remote Control: queda disponible en el celular'
        }
    }

    # Si la organizacion lo bloqueo, el boton no promete nada: se apaga y lo
    # dice. Prometer una accion que siempre falla es peor que no ofrecerla.
    if (-not $script:remotoPermitido -and $estado -ne 'remoto') {
        # 'abierta' CONSERVA su azul: que la conversación esté abierta es
        # información válida aunque el remoto esté bloqueado. Son dos cosas
        # distintas y apagar el azul perdía dato. Lo único que cambia es lo que
        # el botón promete, y eso lo dice el tooltip.
        if ($estado -ne 'abierta') { $colPunto = '#3A4150' }
        $tipPunto = 'Remote Control deshabilitado por la política de tu organización'
    }

    $btnRemoto = New-Object Windows.Controls.Button
    $btnRemoto.Template = $script:tplPlano
    $btnRemoto.Content = $glifoPunto
    if ($fuentePunto) {
        $btnRemoto.FontFamily = New-Object Windows.Media.FontFamily -ArgumentList $fuentePunto
    }
    $btnRemoto.Width = 20; $btnRemoto.Height = 20
    $btnRemoto.FontSize = if ($fuentePunto) { 12 } else { 11 }
    $btnRemoto.Cursor = 'Hand'
    $btnRemoto.VerticalAlignment = 'Top'
    $btnRemoto.BorderThickness = 0
    $btnRemoto.Background = [Windows.Media.Brushes]::Transparent
    $btnRemoto.Foreground = Pincel $colPunto
    # Prendido = a pleno y con un halo verde. El color solo no alcanza para
    # transmitir "esto esta funcionando"; apagado va atenuado y sin halo.
    if ($estado -eq 'remoto') {
        $btnRemoto.Opacity = 1.0
        $halo = New-Object Windows.Media.Effects.DropShadowEffect
        $halo.BlurRadius = 9
        $halo.ShadowDepth = 0
        $halo.Color = [Windows.Media.ColorConverter]::ConvertFromString('#4ADE80')
        $halo.Opacity = 0.85
        $btnRemoto.Effect = $halo
    } else {
        $btnRemoto.Opacity = 0.8
    }
    $btnRemoto.ToolTip = $tipPunto
    $btnRemoto.Tag = @{ conv = $C; titulo = $tituloCard; estado = $estado; opacidad = $btnRemoto.Opacity }
    # El color YA dice el estado, asi que el hover no lo puede pisar: se marca
    # con opacidad, que no compite con el semaforo.
    $btnRemoto.Add_MouseEnter({ $this.Opacity = 1.0 })
    # Vuelve a SU opacidad, no a una fija: el remoto prendido queda a pleno.
    $btnRemoto.Add_MouseLeave({ $this.Opacity = $this.Tag.opacidad })
    $btnRemoto.Add_Click({
            param($s, $e)
            $e.Handled = $true          # que no burbujee y la abra sin remoto
            $conv = $this.Tag.conv

            # Bloqueado por politica: se explica en vez de abrir una terminal que
            # va a morir con "Remote Control is disabled by your organization".
            if (-not $script:remotoPermitido) {
                $pol = @{
                    Encabezado  = 'Remote Control bloqueado'
                    Nombre      = 'Tu organización lo tiene deshabilitado por política.'
                    Filas       = @(@{ Texto = 'allow_remote_control'; Dato = 'false' })
                    Aviso       = 'Sale de ~/.claude/policy-limits.json, que Claude Code reescribe al cambiar de cuenta. Con una cuenta personal vuelve a habilitarse solo.'
                    TextoOk     = 'Entendido'
                    Icono       = 'engranaje'
                    SoloAceptar = $true
                }
                Show-Confirmacion @pol | Out-Null
                return
            }

            # Ya hay terminal viva: abrir otra no prende el remoto. Segun la doc,
            # si la primera ya lo tiene, la segunda arranca con el remoto APAGADO.
            # Se avisa en vez de abrir un duplicado inutil.
            if ($this.Tag.estado) {
                $aviso = if ($this.Tag.estado -eq 'remoto') {
                    'Buscala en claude.ai/code o en la app del celular. Abrir otra terminal no agrega nada.'
                } else {
                    'Está abierta sin remoto. Para prenderlo escribí /remote-control en ESA terminal: abrir otra no lo activa.'
                }
                $p = @{
                    Encabezado  = 'Ya está abierta'
                    Nombre      = $this.Tag.titulo
                    Aviso       = $aviso
                    TextoOk     = 'Entendido'
                    SoloAceptar = $true
                }
                Show-Confirmacion @p | Out-Null
                return
            }

            try { Start-Conversacion -Cwd $conv.cwd -Sesion $conv.sesion -Remoto -Nombre $this.Tag.titulo | Out-Null }
            catch { [Windows.MessageBox]::Show($_.Exception.Message, 'No se pudo abrir en remoto') | Out-Null }
        })

    $btnBorrar = New-Object Windows.Controls.Button
    $btnBorrar.Template = $script:tplPlano     # sin el recuadro del hover
    $btnBorrar.Content = [char]0x2715
    $btnBorrar.Width = 20; $btnBorrar.Height = 20
    $btnBorrar.FontSize = 10
    $btnBorrar.Cursor = 'Hand'
    $btnBorrar.VerticalAlignment = 'Top'
    $btnBorrar.BorderThickness = 0
    $btnBorrar.Background = [Windows.Media.Brushes]::Transparent
    $btnBorrar.Foreground = Pincel '#5A6473'
    $btnBorrar.ToolTip = 'Quitar del panel'
    # Se guarda tambien el titulo que se ve: si la sesion fue renombrada, la
    # confirmacion tiene que nombrar lo mismo que la tarjeta, no el titulo viejo.
    $btnBorrar.Tag = @{ conv = $C; titulo = $tituloCard }
    $btnBorrar.Add_MouseEnter({ $this.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom('#F87171') })
    $btnBorrar.Add_MouseLeave({ $this.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom('#5A6473') })
    $btnBorrar.Add_Click({
            param($s, $e)
            $e.Handled = $true          # que no burbujee y abra la conversacion
            $conv = $this.Tag.conv
            # Splatting: el hashtable va a una variable y se pasa con @p. Escrito
            # como "Show-Confirmacion @{...}" seria un argumento posicional.
            $p = @{
                Encabezado = 'Quitar del panel'
                Nombre     = $this.Tag.titulo
                Aviso      = 'La conversación no se borra: sigue en disco y se puede reabrir con --resume. Del panel queda respaldo en conversaciones.js.bak'
                TextoOk    = 'Quitar'
            }
            if (-not (Show-Confirmacion @p)) { return }
            try {
                Remove-Conversacion -Id $conv.id | Out-Null
                Actualizar
            } catch {
                [Windows.MessageBox]::Show($_.Exception.Message, 'No se pudo borrar') | Out-Null
            }
        })
    # Borrado real, en un boton aparte y NO en el ✕: son dos acciones distintas
    # y esta es irreversible. Meterlas en el mismo click seria un pie de fabrica.
    $btnDestruir = New-Object Windows.Controls.Button
    $btnDestruir.Template = $script:tplPlano     # sin el recuadro del hover
    $btnDestruir.Content = [char]0xE74D          # tacho, de Segoe MDL2 Assets
    $btnDestruir.FontFamily = New-Object Windows.Media.FontFamily -ArgumentList 'Segoe MDL2 Assets'
    $btnDestruir.Width = 20; $btnDestruir.Height = 20
    $btnDestruir.FontSize = 11
    $btnDestruir.Cursor = 'Hand'
    $btnDestruir.VerticalAlignment = 'Top'
    $btnDestruir.BorderThickness = 0
    $btnDestruir.Background = [Windows.Media.Brushes]::Transparent
    $btnDestruir.Foreground = Pincel '#5A6473'
    $btnDestruir.ToolTip = 'Borrar la conversacion de verdad (no se puede deshacer)'
    $btnDestruir.Tag = @{ conv = $C; titulo = $tituloCard }
    $btnDestruir.Add_MouseEnter({ $this.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom('#EF4444') })
    $btnDestruir.Add_MouseLeave({ $this.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom('#5A6473') })
    $btnDestruir.Add_Click({
            param($s, $e)
            $e.Handled = $true          # que no burbujee y abra la conversacion
            $conv = $this.Tag.conv

            # Se listan los rastros ANTES de preguntar: la confirmacion tiene que
            # decir que archivos se van y cuanto pesan, no un "estas seguro?" pelado.
            try {
                $rastros = @(Get-RastrosSesion -Cwd $conv.cwd -Sesion $conv.sesion)
            } catch {
                [Windows.MessageBox]::Show($_.Exception.Message, 'No se pudo borrar') | Out-Null
                return
            }

            $filas = @(@{ Texto = 'la entrada del panel' })
            foreach ($ra in $rastros) {
                $filas += @{ Texto = $ra.Nombre; Dato = (Format-Bytes $ra.Bytes) }
            }
            if ($rastros.Count -eq 0) {
                $filas += @{ Texto = '(el transcript ya no está en disco)' }
            }

            $p = @{
                Encabezado = 'Borrar para siempre'
                Nombre     = $this.Tag.titulo
                Filas      = $filas
                Aviso      = 'No se va a poder reabrir con --resume, y Remove-Item no manda nada a la papelera. Del panel queda respaldo en conversaciones.js.bak; del transcript, nada.'
                TextoOk    = 'Borrar'
                Peligro    = $true
            }
            if (-not (Show-Confirmacion @p)) { return }

            try {
                Remove-ConversacionCompleta -Id $conv.id | Out-Null
                Actualizar
            } catch {
                [Windows.MessageBox]::Show($_.Exception.Message, 'No se pudo borrar') | Out-Null
            }
        })

    # Los tres botones comparten la columna Auto de la derecha.
    $acciones = New-Object Windows.Controls.StackPanel
    $acciones.Orientation = 'Horizontal'
    $acciones.Children.Add($btnRemoto) | Out-Null
    $acciones.Children.Add($btnBorrar) | Out-Null
    $acciones.Children.Add($btnDestruir) | Out-Null

    # Latido: un spinner que gira mientras esa sesion esta pensando.
    #
    # La animacion arranca aca y corre siempre: una animacion sobre un elemento
    # oculto no cuesta nada, y asi el ritmo no se reinicia en cada tick. Lo que
    # se prende y se apaga es la Visibility.
    #
    # HorizontalAlignment Center y no Right: queda centrado bajo los tres
    # botones en vez de pegado al filo derecho de la tarjeta.
    $latido = New-Object Windows.Controls.Grid
    $latido.Width = 16
    $latido.Height = 16
    $latido.HorizontalAlignment = 'Center'
    $latido.Margin = [Windows.Thickness]::new(0, 9, 0, 1)
    $latido.Visibility = 'Collapsed'
    $latido.ToolTip = 'Pensando'

    # La pista: el anillo completo, tenue (#33 = alpha 20%). Sin ella el arco
    # solo se lee como una rayita perdida; con pista se lee como spinner.
    # Margen 1 en un Grid de 16 deja un circulo de 14, y el trazo de 2 se centra
    # en la geometria, asi que sobresale 1 de cada lado y llena los 16 justos.
    $pista = New-Object Windows.Shapes.Ellipse
    $pista.Stroke = Pincel '#334ADE80'
    $pista.StrokeThickness = 2
    $pista.Margin = [Windows.Thickness]::new(1)
    $latido.Children.Add($pista) | Out-Null

    # El arco: un tramo de ese mismo anillo. StrokeDashArray se mide en
    # MULTIPLOS del grosor, y el perimetro de un circulo de 14 es
    # (pi * 14) / 2 = 22 unidades. Con 6 pintado y 16 de hueco queda un arco de
    # ~100 grados, y el ciclo cierra justo en una vuelta.
    $arco = New-Object Windows.Shapes.Ellipse
    $arco.Stroke = Pincel '#4ADE80'
    $arco.StrokeThickness = 2
    $arco.StrokeDashCap = 'Round'
    $arco.Margin = [Windows.Thickness]::new(1)
    $tramo = New-Object Windows.Media.DoubleCollection
    $tramo.Add(6)
    $tramo.Add(16)
    $arco.StrokeDashArray = $tramo

    # Se gira la FIGURA, no el StrokeDashOffset. En un circulo se ve igual, pero
    # girando la figura la velocidad es pareja; moviendo el offset la velocidad
    # depende de como WPF reparte el dash sobre la curva.
    $giroSpin = New-Object Windows.Media.RotateTransform(0)
    $arco.RenderTransformOrigin = New-Object Windows.Point(0.5, 0.5)
    $arco.RenderTransform = $giroSpin
    $latido.Children.Add($arco) | Out-Null

    $spin = New-Object Windows.Media.Animation.DoubleAnimation
    $spin.From = 0
    $spin.To = 360
    $spin.Duration = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(900))
    $spin.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
    $giroSpin.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $spin)

    # Mismo criterio que el halo: el reloj cuelga del RotateTransform, asi que se
    # guarda en el Tag para poder frenarlo al rearmar las tarjetas.
    $latido.Tag = $giroSpin
    $script:latidos[([string]$C.sesion).ToLower()] = $latido

    # --- halo: el borde verde con un brillo dando la vuelta --------------------
    #  Va DENTRO del Grid interno con margen negativo que cancela el Padding del
    #  Border (10,8,10,9), asi el trazo cae justo sobre el filo de la tarjeta.
    #  Envolver el Border en un Grid seria mas prolijo pero rompe $t.Child y los
    #  handlers, que dan por sentado que $t ES el Border.
    #
    #  Son DOS trazos superpuestos, y ahi esta toda la gracia:
    #    base -> verde parejo en TODO el perimetro, fijo. El borde nunca se apaga.
    #    luz  -> un gradiente que va de blanco-verde opaco a transparente; donde
    #            es transparente se ve la base, asi que se lee como un brillo
    #            que viaja SOBRE un borde que sigue verde.
    #  El movimiento sale de rotar el EJE del gradiente, no de mover el trazo.
    #  Como RelativeTransform trabaja en 0..1 sobre el bounding box, no depende
    #  del tamano: no hay que rearmar nada cuando la ventana se ensancha.
    #  Fill nulo y IsHitTestVisible falso para no taparle el click a la tarjeta.
    $capa = New-Object Windows.Controls.Grid
    $capa.IsHitTestVisible = $false
    $capa.Visibility = 'Collapsed'
    $capa.Margin = [Windows.Thickness]::new(-10, -8, -10, -9)
    [Windows.Controls.Grid]::SetColumnSpan($capa, 2)

    $haloBase = New-Object Windows.Shapes.Rectangle
    $haloBase.RadiusX = 9      # igual al CornerRadius del Border, o no calza en las esquinas
    $haloBase.RadiusY = 9
    $haloBase.Stroke = Pincel '#2FA968'
    $haloBase.StrokeThickness = 1.6
    $haloBase.Fill = $null
    $capa.Children.Add($haloBase) | Out-Null

    $luz = New-Object Windows.Media.LinearGradientBrush
    $luz.StartPoint = New-Object Windows.Point(0, 0)
    $luz.EndPoint = New-Object Windows.Point(1, 0)
    # El alpha del hex es el truco: #00 4ADE80 es el MISMO verde pero invisible.
    # Desvanecer contra 'Transparent' pelado ensuciaria el degrade con negro.
    foreach ($p in @(@(0.00, '#FFD9FFE8'), @(0.07, '#FF6EF2A0'),
            @(0.22, '#004ADE80'), @(1.00, '#004ADE80'))) {
        $luz.GradientStops.Add((New-Object Windows.Media.GradientStop(
                    [Windows.Media.ColorConverter]::ConvertFromString($p[1]), $p[0]))) | Out-Null
    }
    $giro = New-Object Windows.Media.RotateTransform(0, 0.5, 0.5)
    $luz.RelativeTransform = $giro

    $haloLuz = New-Object Windows.Shapes.Rectangle
    $haloLuz.RadiusX = 9
    $haloLuz.RadiusY = 9
    $haloLuz.Stroke = $luz
    $haloLuz.StrokeThickness = 1.6
    $haloLuz.Fill = $null
    $capa.Children.Add($haloLuz) | Out-Null

    $vuelta = New-Object Windows.Media.Animation.DoubleAnimation
    $vuelta.From = 0
    $vuelta.To = 360
    $vuelta.Duration = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(2600))
    $vuelta.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
    $giro.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $vuelta)

    # El reloj cuelga del RotateTransform, no del Rectangle. Se guarda en el Tag
    # para poder frenarlo cuando se rearman las tarjetas.
    $capa.Tag = $giro
    $script:halos[([string]$C.sesion).ToLower()] = $capa
    $t.Child.Children.Add($capa) | Out-Null

    $colDer = New-Object Windows.Controls.StackPanel
    $colDer.VerticalAlignment = 'Top'
    $colDer.Children.Add($acciones) | Out-Null
    $colDer.Children.Add($latido) | Out-Null
    [Windows.Controls.Grid]::SetColumn($colDer, 1)
    $t.Child.Children.Add($colDer) | Out-Null

    return $t
}

# --- refresco ----------------------------------------------------------------
# --- semaforo del remoto ------------------------------------------------------
#  Get-EstadosSesion lee ~/.claude/sessions/*.json y tarda ~26 ms, asi que va
#  sincronico y sin vueltas. (Hubo una version con Win32_Process que tardaba
#  ~265 ms y hubo que sacarla del hilo de la UI con un runspace; el registro la
#  dejo obsoleta, y ademas asi el semaforo esta siempre al dia en vez de ir un
#  refresco atrasado.)
$script:estados = @{}
$script:remotoPermitido = $true

# --- cuota real de la cuenta -------------------------------------------------
#  MEDIDO EL 2026-09-08. Aca habia un comentario que decia que la cuota de la
#  cuenta "no existe en ningun archivo local". Era FALSO: el payload que Claude
#  Code le pasa al statusline por stdin trae `rate_limits`, con los porcentajes
#  que calcula el servidor. Nada de estimar.
#
#      "rate_limits": { "five_hour": { "used_percentage": 10, "resets_at": <epoch> },
#                       "seven_day": { "used_percentage": 7,  "resets_at": <epoch> } }
#
#  Lo que NO hay es un archivo que lo guarde: los transcripts no lo traen (se
#  buscó estructuralmente en los 12 mas recientes, cero hits) y el cache del HUD
#  (.usage-cache.json) solo se escribe cuando pega contra la API, que no es el
#  camino que usa aca. Y el statusline es el UNICO consumidor de ese payload.
#
#  Solucion: en settings.json el comando del statusline ahora vuelca su stdin a
#  ~/.claude/statusline-ultimo.json ANTES de pasarselo al HUD (lee todo primero,
#  escribe a un tmp y hace mv, que es atomico). Este archivo es lo que se lee.
#
#  Se guardan las DOS ventanas por separado. El HUD calcula un max(5h, 7d)
#  (render/session-line.js:169) pero en el layout que usa esta maquina dibuja
#  las dos: "Usage" es la de 5h y "Weekly" la de 7 dias (session-line.js:173-189).
#  Mostrar solo el mayor coincidiria HOY y dejaria de coincidir el dia que la
#  semanal pase a la de 5h.
#
#  Pct queda como "la mas urgente de las dos" y se usa para la barra y el color,
#  que es una sola cosa y tiene que reflejar el peor caso.
function Get-CuotaReal {
    $ruta = Join-Path $env:USERPROFILE '.claude\statusline-ultimo.json'
    $nada = [pscustomobject]@{ Hay = $false }
    if (-not (Test-Path -LiteralPath $ruta)) { return $nada }
    try {
        $arch = Get-Item -LiteralPath $ruta
        $rl = (Get-Content -LiteralPath $ruta -Raw -Encoding UTF8 | ConvertFrom-Json).rate_limits
        if (-not $rl) { return $nada }

        # -1 = "esa ventana no vino". Sirve de centinela para el Max de abajo sin
        # tener que andar con $null, que en PS 5.1 se castea a 0 y mentiria.
        [double]$p5 = -1
        [double]$p7 = -1
        if ($rl.five_hour -and $null -ne $rl.five_hour.used_percentage) { $p5 = [double]$rl.five_hour.used_percentage }
        if ($rl.seven_day -and $null -ne $rl.seven_day.used_percentage) { $p7 = [double]$rl.seven_day.used_percentage }
        if ($p5 -lt 0 -and $p7 -lt 0) { return $nada }

        # resets_at viene en SEGUNDOS epoch, no en milisegundos.
        $aFecha = {
            param($ep)
            if (-not $ep) { return $null }
            try { return [DateTimeOffset]::FromUnixTimeSeconds([int64]$ep).ToLocalTime().DateTime } catch { return $null }
        }
        return [pscustomobject]@{
            Hay      = $true
            Pct      = [math]::Round([math]::Max($p5, $p7), 1)
            Pct5h    = $(if ($p5 -ge 0) { [math]::Round($p5, 1) } else { $null })
            Pct7d    = $(if ($p7 -ge 0) { [math]::Round($p7, 1) } else { $null })
            Ventana  = $(if ($p5 -ge $p7) { 'diario' } else { 'semanal' })
            Reset5h  = & $aFecha $rl.five_hour.resets_at
            Reset7d  = & $aFecha $rl.seven_day.resets_at
            Edad     = [int]((Get-Date) - $arch.LastWriteTime).TotalMinutes
        }
    } catch {
        return $nada
    }
}

# --- resumen del panel -------------------------------------------------------
#  Muestra la cuota REAL de la cuenta, una fila por ventana. El contexto sumado
#  de las charlas pasa al tooltip: es otra cosa (cuanta ventana hay en juego) y
#  confundia los dos numeros en el mismo lugar.
function Set-Resumen {
    param([int64]$Tokens, [int64]$Limite)

    $ctxTip = if ($Limite -gt 0) {
        'Contexto en juego: {0} de {1}  ({2}%)' -f (Format-Tokens $Tokens), (Format-Tokens $Limite),
        [math]::Round(100.0 * $Tokens / $Limite, 1)
    } else { 'Contexto en juego: sin datos' }

    # Pinta una fila: nombre, barra proporcional y a que hora resetea. Las
    # columnas van en estrellas y no en pixeles, asi la barra se estira sola
    # cuando se ensancha la ventana.
    function Pintar-Fila($fila, [string]$nombre, $pct, $reset, [string]$formatoReset) {
        if ($null -eq $pct) {
            $fila.Nom.Text = ''
            $fila.Reset.Text = ''
            $fila.Barra.Visibility = 'Collapsed'
            return
        }
        $fila.Barra.Visibility = 'Visible'
        $fila.Nom.Text = '{0} {1}%' -f $nombre, $pct
        $fila.Reset.Text = if ($reset) { '↻ ' + ([string]::Format($formatoReset, $reset)) } else { '' }
        $lleno = [math]::Max(0.001, [math]::Min([double]$pct, 100))
        $fila.Barra.ColumnDefinitions[0].Width = New-Object Windows.GridLength ($lleno, ([Windows.GridUnitType]::Star))
        $fila.Barra.ColumnDefinitions[1].Width = New-Object Windows.GridLength ((100 - $lleno), ([Windows.GridUnitType]::Star))
        # Cada barra con el color de SU propio porcentaje: si la semanal esta en
        # rojo y la diaria en verde, hay que verlo de un vistazo.
        $fila.Lleno.Background = Pincel (Get-ColorContexto $lleno)
    }

    $q = Get-CuotaReal
    if (-not $q.Hay) {
        $filasCuota[0].Nom.Text = 'sin datos de cuota'
        $filasCuota[0].Reset.Text = ''
        $filasCuota[0].Barra.Visibility = 'Collapsed'
        $filasCuota[1].Nom.Text = ''
        $filasCuota[1].Reset.Text = ''
        $filasCuota[1].Barra.Visibility = 'Collapsed'
        $chipResumen.ToolTip = "No hay cuota todavia.`nLa escribe el statusline de Claude Code en`n~\.claude\statusline-ultimo.json cada vez que dibuja.`nAbri una sesion y aparece.`n`n$ctxTip"
        return
    }

    # La diaria resetea dentro del dia: alcanza la hora. La semanal cae otro
    # dia, asi que ahi la hora sola no dice nada y va la fecha.
    Pintar-Fila $filasCuota[0] 'diario'  $q.Pct5h $q.Reset5h '{0:HH:mm}'
    Pintar-Fila $filasCuota[1] 'semanal' $q.Pct7d $q.Reset7d '{0:dd/MM}'

    $tip = @('Cuota de la cuenta, los mismos numeros que el statusline:')
    if ($null -ne $q.Pct5h) { $tip += '   diario  (5h) = "Usage"  : {0}%' -f $q.Pct5h }
    if ($null -ne $q.Pct7d) { $tip += '   semanal (7d) = "Weekly" : {0}%' -f $q.Pct7d }
    if ($q.Reset5h) { $tip += 'La diaria resetea {0:HH:mm} del {0:dd/MM}' -f $q.Reset5h }
    if ($q.Reset7d) { $tip += 'La semanal resetea {0:HH:mm} del {0:dd/MM}' -f $q.Reset7d }
    # Si nadie dibujo statusline en un rato el dato quedo viejo: se dice, en vez
    # de mostrar un numero de hace horas como si fuera de ahora.
    $tip += if ($q.Edad -ge 10) { 'OJO: dato de hace {0} min (no hay sesion dibujando statusline)' -f $q.Edad }
    else { 'Dato de hace {0} min' -f $q.Edad }
    $tip += ''
    $tip += $ctxTip
    $chipResumen.ToolTip = $tip -join "`n"
}

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
        # es la unica forma de que el index.html se entere de un renombrado.
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
        Nombre     = 'Hasta que estén las cuatro piezas, el panel anda a medias.'
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
