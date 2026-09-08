# =============================================================================
#  Tarjeta.ps1 - una tarjeta del panel
# -----------------------------------------------------------------------------
#  New-Tarjeta arma una conversacion entera: titulo, subtitulo, barra de
#  contexto, los tres botones, el spinner de "pensando" y el halo del borde.
#  Es la pieza mas grande del gadget y la que mas se toca.
#
#  Tambien vive aca el ControlTemplate sin chrome de los botones, porque es lo
#  unico que lo usa.
# =============================================================================

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
