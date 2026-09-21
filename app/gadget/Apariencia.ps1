# =============================================================================
#  Apariencia.ps1 - colores, pinceles, sombras y el modo bloqueado
# -----------------------------------------------------------------------------
#  Todo lo que decide COMO se ve el panel, sin saber que hay adentro. Set-Apariencia
#  es la unica fuente de verdad del estado bloqueado/suelto: se llama al arrancar
#  y en cada toggle, asi el estado guardado y el de la sesion no se separan.
# =============================================================================

# --- apariencia segun el candado ---------------------------------------------
#  Al bloquear desaparece SOLO el contenedor: las tarjetas mantienen su fondo,
#  porque atenuarlas tambien las volvia ilegibles. Queda la lista flotando
#  sobre el escritorio.
#  El fondo se pone en $null y no en alpha 00 a proposito: un pincel con alpha 0
#  igual recibe clicks (taparia el escritorio), mientras que sin pincel los
#  clicks pasan de largo en las zonas vacias. Los hijos (tarjetas, botones)
#  siguen recibiendo mouse normalmente, asi el candado se puede volver a abrir.
# Desbloqueado la tarjeta es apenas un tinte blanco: se lee porque el panel
# oscuro esta detras. Bloqueado ese panel no existe, asi que cada tarjeta tiene
# que llevarse el fondo puesto o queda flotando ilegible sobre el escritorio.
#
# Bloqueado el fondo va OPACO: un hex de 6 digitos no lleva alpha en WPF.
function Get-ColorTarjeta {
    if ($script:bloqueado) { return '#1E222A' }
    return '#14FFFFFF'
}
function Get-ColorHover {
    if ($script:bloqueado) { return '#2B313C' }
    return '#26FFFFFF'
}

# --- el icono de la ventana y el logo de la barra de titulo -------------------
#  Sin esto la barra de tareas muestra el icono del PROCESO, o sea el de
#  powershell.exe: parece una consola perdida. El .ico lo genera hacer-icono.ps1
#  y trae 8 tamanos.
#
#  El marco de 32 se elige A MANO y no es un capricho: un BitmapImage sobre un
#  .ico multi-tamano se queda con el marco MAS CHICO (16), y la barra de tareas
#  -que a 100% pide 24- tendria que AGRANDARLO. Medido, no supuesto. Dandole el
#  de 32, WPF baja a 24 para la barra y a 16 (2:1 exacto) para el titulo.
#
#  El mismo bitmap alimenta el logo de la barra de titulo: decodificar el .ico
#  dos veces para mostrar la misma imagen no tiene sentido.
#
#  try/catch porque un icono roto o ausente jamas puede impedir que arranque.
function Set-IconoVentana {
    param([Parameter(Mandatory)][string]$Ruta)

    if (-not (Test-Path -LiteralPath $Ruta)) { return }
    try {
        $marcos = (New-Object Windows.Media.Imaging.IconBitmapDecoder(
                [uri]$Ruta,
                [Windows.Media.Imaging.BitmapCreateOptions]::None,
                [Windows.Media.Imaging.BitmapCacheOption]::OnLoad)).Frames
        $ico = $marcos | Where-Object { $_.PixelWidth -eq 32 } | Select-Object -First 1
        if (-not $ico) { $ico = $marcos | Sort-Object PixelWidth -Descending | Select-Object -First 1 }
        $ventana.Icon = $ico
        if ($logo) { $logo.Source = $ico }
    } catch { }
}

function Pincel([string]$Hex) { return [Windows.Media.BrushConverter]::new().ConvertFrom($Hex) }

# --- deja rastro de una falla sin matar el gadget -----------------------------
#  Los timers no pueden dejar escapar una excepcion (ver el comentario del
#  Add_Tick), pero tragarsela en silencio deja el problema invisible.
function Write-Falla {
    param([string]$Donde, $Err)
    try {
        ('{0}  {1}: {2}' -f (Get-Date -Format 's'), $Donde, $Err.Exception.Message) |
            Add-Content -Path (Join-Path (Split-Path -Parent $carpeta) 'datos\gadget-fallas.log') -Encoding UTF8
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

# --- anima el alto de un elemento --------------------------------------------
#  FillBehavior Stop mas el valor fijado a mano: si la animacion queda puesta,
#  el Height del elemento queda congelado y no lo mueve nadie mas. Al terminar,
#  'ocultar' lo saca del layout y 'auto' le devuelve el alto al contenido.
#  El handler de Completed lo invoca el dispatcher, asi que las variables de
#  aca no estarian en su pila: va con GetNewClosure.
function Animar-Alto {
    param(
        [Parameter(Mandatory)]$Elemento,
        [double]$Desde, [double]$Hasta, [int]$Ms,
        [ValidateSet('nada', 'ocultar', 'auto')][string]$Al = 'nada'
    )

    $propAlto = [Windows.FrameworkElement]::HeightProperty
    $fin = switch ($Al) {
        'ocultar' { { $Elemento.Visibility = 'Collapsed' }.GetNewClosure() }
        'auto' { { $Elemento.ClearValue($propAlto) }.GetNewClosure() }
        default { $null }
    }

    if ($Ms -le 0) {
        $Elemento.BeginAnimation($propAlto, $null)
        $Elemento.Height = $Hasta
        if ($fin) { & $fin }
        return
    }

    $suave = New-Object Windows.Media.Animation.CubicEase
    $suave.EasingMode = 'EaseInOut'
    $a = New-Object Windows.Media.Animation.DoubleAnimation
    $a.From = $Desde
    $a.To = $Hasta
    $a.Duration = [Windows.Duration]::new([TimeSpan]::FromMilliseconds($Ms))
    $a.EasingFunction = $suave
    $a.FillBehavior = 'Stop'
    if ($fin) { $a.Add_Completed($fin) }
    $Elemento.Height = $Hasta
    $Elemento.BeginAnimation($propAlto, $a)
}

# Cuanto mide la lista desplegada. El valor anotado al colapsar es el bueno;
# arrancando ya colapsado no hay ninguno y se mide contra el ancho de la
# cabecera, que es el mismo que el del ScrollViewer.
function Get-AltoLista {
    if ($script:altoLista -gt 0) { return $script:altoLista }
    $scroller.Measure([Windows.Size]::new($cabecera.ActualWidth, [double]::PositiveInfinity))
    if ($scroller.DesiredSize.Height -le 0) { return $scroller.MaxHeight }
    return [Math]::Min($scroller.DesiredSize.Height, $scroller.MaxHeight)
}

# --- colapsar el panel a su cabecera -----------------------------------------
#  Se anima el alto del ScrollViewer y del pie, NO el de la ventana: con
#  SizeToContent="Height" la ventana sigue sola al contenido. Animar el alto de
#  la ventana obligaria a apagar SizeToContent y a devolverselo despues, y a
#  pelearse con el grip de abajo, que mueve el MaxHeight de la lista.
function Set-Colapsado {
    param([switch]$SinAnimar)

    $ms = if ($SinAnimar) { 0 } else { 190 }
    if ($script:colapsado) {
        # Se anota cuanto median para volver exactamente a lo mismo.
        if ($scroller.ActualHeight -gt 0) { $script:altoLista = $scroller.ActualHeight }
        if ($pie.Visibility -eq 'Visible' -and $pie.ActualHeight -gt 0) { $script:altoPie = $pie.ActualHeight }
        if ($pie.Visibility -eq 'Visible') {
            Animar-Alto -Elemento $pie -Desde $pie.ActualHeight -Hasta 0 -Ms $ms -Al 'ocultar'
        }
        Animar-Alto -Elemento $scroller -Desde $scroller.ActualHeight -Hasta 0 -Ms $ms -Al 'ocultar'
    } else {
        $scroller.Visibility = 'Visible'
        Animar-Alto -Elemento $scroller -Desde 0 -Hasta (Get-AltoLista) -Ms $ms -Al 'auto'
        # Bloqueado el pie no vuelve: ahi lo esconde Set-Apariencia a proposito.
        if (-not $script:bloqueado) {
            $pie.Visibility = 'Visible'
            Animar-Alto -Elemento $pie -Desde 0 -Hasta $script:altoPie -Ms $ms -Al 'auto'
        }
    }
    Set-Apariencia
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
        # El logo y el nombre se van con el pie: son decoracion, y sin panel
        # detras quedarian flotando ilegibles sobre el escritorio. Los botones
        # SI se quedan, porque son la unica forma de volver a destrabar.
        $chipTitulo.Visibility = 'Collapsed'
        $pie.Visibility = 'Collapsed'
    } else {
        # Opaco, y el MISMO valor que declara el XAML: asi la ventana no pega un
        # salto de color en el primer Set-Apariencia.
        $fondo.Background = Pincel '#161A20'
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
        $chipTitulo.Visibility = 'Visible'
        $pie.Visibility = if ($script:colapsado) { 'Collapsed' } else { 'Visible' }
    }
    # La barra de scroll va superpuesta sobre el padding derecho del PANEL, no
    # sobre las tarjetas: el margen negativo estira el ScrollViewer hasta el
    # borde y el Padding le devuelve el lugar al contenido. Sale del padding que
    # acaba de quedar, que no es el mismo suelto que bloqueado.
    $canal = $fondo.Padding.Right
    $scroller.Margin = [Windows.Thickness]::new(0, 0, -$canal, 0)
    $scroller.Padding = [Windows.Thickness]::new(0, 0, $canal, 0)
    # Colapsado el chevron apunta para abajo: senala lo que va a pasar, no el
    # estado. Es el mismo criterio que el candado y el pin.
    $btnColapsar.Content = if ($script:colapsado) { $CHEVRON_ABAJO } else { $CHEVRON_ARRIBA }
    $btnColapsar.ToolTip = if ($script:colapsado) { 'Desplegar el panel' } else { 'Colapsar a la cabecera' }
    $btnCandado.Content = if ($script:bloqueado) { $LOCK_CERRADO } else { $LOCK_ABIERTO }
    $btnCandado.Foreground = Pincel $(if ($script:bloqueado) { '#E0A45A' } else { '#8A94A6' })
    $btnCandado.ToolTip = if ($script:bloqueado) { 'Desbloquear (posicion fija)' } else { 'Bloquear posicion' }
    # Topmost se aplica aca y no solo en el click: asi el estado guardado tambien
    # se respeta al arrancar, con una sola fuente de verdad.
    $ventana.Topmost = $script:arriba
    $btnArriba.Content = if ($script:arriba) { $PIN_CLAVADO } else { $PIN_SUELTO }
    $btnArriba.Foreground = Pincel $(if ($script:arriba) { '#4ADE80' } else { '#8A94A6' })
    $btnArriba.ToolTip = if ($script:arriba) { 'Siempre arriba: SI (click para soltar)' } else { 'Siempre arriba: NO (click para clavar)' }
    # El boton del archivo se enciende en ambar cuando estas ADENTRO del
    # archivo: es la unica pista de por que la lista cambio de contenido.
    $btnArchivadas.Foreground = Pincel $(if ($script:verArchivadas) { '#E0A45A' } else { '#8A94A6' })
    $btnArchivadas.ToolTip = if ($script:verArchivadas) {
        'Estas viendo el archivo (click para volver al panel)'
    } else { 'Ver las conversaciones archivadas' }
    $gripIzq.Cursor = if ($script:bloqueado) { 'Arrow' } else { 'SizeWE' }
    $gripDer.Cursor = $gripIzq.Cursor
    $gripAbajo.Cursor = if ($script:bloqueado -or $script:colapsado) { 'Arrow' } else { 'SizeNS' }
    $barraTitulo.Cursor = if ($script:bloqueado) { 'Arrow' } else { 'SizeAll' }
}

# --- color segun cuan lleno esta el contexto ---------------------------------
function Get-ColorContexto {
    param([double]$Pct)
    if ($Pct -ge 85) { return '#F87171' }   # rojo
    if ($Pct -ge 60) { return '#FBBF24' }   # ambar
    return '#4ADE80'                         # verde
}

function Escapar { param([string]$T) return [System.Security.SecurityElement]::Escape([string]$T) }
