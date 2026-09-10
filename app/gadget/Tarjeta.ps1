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

    # El recap que escribio /save manda: va con etiqueta y hasta 3 lineas. Si
    # todavia no hay, el ultimo pedido del transcript, en una sola linea.
    $etiquetaRecap = ''
    $altoRecap = 13
    $recap = [string]$C.recap
    if ($recap) { $etiquetaRecap = 'recap: '; $altoRecap = 39 }
    else { $recap = [string]$Ctx.Recap }
    $visRecap = if ($recap) { 'Visible' } else { 'Collapsed' }

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
      <ColumnDefinition Width="Auto"/>
      <ColumnDefinition Width="*"/>
      <ColumnDefinition Width="Auto"/>
    </Grid.ColumnDefinitions>
    <!-- Dos filas: el titulo comparte renglon con los botones y todo lo demas
         usa el ancho completo, tambien el que queda debajo de los botones. -->
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock Grid.Row="0" Grid.Column="1" Text="$(Escapar $tituloCard)" Foreground="#F2F5F9"
               FontSize="12.5" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"
               VerticalAlignment="Center" Margin="0,0,6,0"/>
    <StackPanel Grid.Row="1" Grid.Column="1" Grid.ColumnSpan="2">
      <TextBlock Text="$(Escapar $subtitulo)" Foreground="#8A94A6" FontSize="10.5" Margin="0,1,0,0"
                 TextTrimming="CharacterEllipsis"/>
      <!-- MaxHeight en multiplos de LineHeight: 13 = una linea, 39 = tres. Con
           Wrap + TextTrimming, la ultima linea que entra termina en ellipsis. -->
      <TextBlock Foreground="#78828F" FontSize="10" Margin="0,3,0,0" TextWrapping="Wrap"
                 TextTrimming="CharacterEllipsis" LineHeight="13" LineStackingStrategy="BlockLineHeight"
                 MaxHeight="$altoRecap" Visibility="$visRecap"><Run Text="$(Escapar $etiquetaRecap)"
                 FontWeight="SemiBold" Foreground="#9AA4B5"/><Run Text="$(Escapar $recap)" FontStyle="Italic"/></TextBlock>
      <Grid Height="4" Margin="0,7,0,0">
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

    # Sin guarda de arrastre aca a proposito: el asa captura el mouse, asi que
    # durante un arrastre el Up NO llega a la tarjeta. Este handler volvio a ser
    # lo que era, un click que abre la conversacion.
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

    # El PUNTO dice si la conversacion esta abierta y no se clickea; la ANTENA
    # es el boton del remoto, siempre con el mismo icono. Antes eran un solo
    # boton que alternaba entre los dos glifos.
    $abierta = $estado -in 'remoto', 'abierta'
    $colPunto = if ($abierta) { '#60A5FA' } else { '#39404D' }
    $tipPunto = switch ($estado) {
        'remoto' { 'Abierta en una terminal, con Remote Control' }
        'abierta' { 'Abierta en una terminal' }
        default { 'No está abierta en ninguna terminal' }
    }
    $colRemoto = if ($estado -eq 'remoto') { '#4ADE80' } else { '#5A6473' }
    $tipRemoto = switch ($estado) {
        'remoto' { 'Remoto prendido: esta conversación está disponible en el celular' }
        'abierta' { 'Abierta sin remoto: escribí /remote-control en ESA terminal para prenderlo' }
        default { 'Abrir con Remote Control: queda disponible en el celular' }
    }
    # Bloqueado por la organizacion: la antena se apaga y lo dice. El punto no
    # cambia, porque que este abierta sigue siendo cierto.
    if (-not $script:remotoPermitido -and $estado -ne 'remoto') {
        $colRemoto = '#3A4150'
        $tipRemoto = 'Remote Control deshabilitado por la política de tu organización'
    }

    $punto = New-Object Windows.Shapes.Ellipse
    $punto.Width = 7; $punto.Height = 7
    $punto.VerticalAlignment = 'Top'
    $punto.Margin = [Windows.Thickness]::new(0, 7, 4, 0)     # centrado con los botones de 20
    $punto.Fill = Pincel $colPunto
    $punto.ToolTip = $tipPunto

    $btnRemoto = New-Object Windows.Controls.Button
    $btnRemoto.Template = $script:tplPlano
    $btnRemoto.Content = [char]0xE701          # antena, de Segoe MDL2 Assets
    $btnRemoto.FontFamily = New-Object Windows.Media.FontFamily -ArgumentList 'Segoe MDL2 Assets'
    $btnRemoto.Width = 20; $btnRemoto.Height = 20
    $btnRemoto.FontSize = 12
    $btnRemoto.Cursor = 'Hand'
    $btnRemoto.VerticalAlignment = 'Top'
    $btnRemoto.BorderThickness = 0
    $btnRemoto.Background = [Windows.Media.Brushes]::Transparent
    $btnRemoto.Foreground = Pincel $colRemoto
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
    $btnRemoto.ToolTip = $tipRemoto
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
                Aviso      = 'La conversación no se borra: sigue en disco y se puede reabrir con --resume. Del panel queda respaldo en datos\conversaciones.db.bak'
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
                Aviso      = 'No se va a poder reabrir con --resume, y Remove-Item no manda nada a la papelera. Del panel queda respaldo en datos\conversaciones.db.bak; del transcript, nada.'
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

    # --- archivar / desarchivar ---------------------------------------------
    #  Archivar ESCONDE del panel: la fila queda entera (notas, tags, orden) y
    #  vuelve con el mismo boton desde la vista del archivo. Por eso no pide
    #  confirmacion, a diferencia del ✕ y del tacho: no hay nada que perder.
    $btnArchivar = New-Object Windows.Controls.Button
    $btnArchivar.Template = $script:tplPlano
    $btnArchivar.Content = $(if ($script:verArchivadas) { [char]0xE8B5 } else { [char]0xE7B8 })
    $btnArchivar.FontFamily = New-Object Windows.Media.FontFamily -ArgumentList 'Segoe MDL2 Assets'
    $btnArchivar.Width = 20; $btnArchivar.Height = 20
    $btnArchivar.FontSize = 11
    $btnArchivar.Cursor = 'Hand'
    $btnArchivar.VerticalAlignment = 'Top'
    $btnArchivar.BorderThickness = 0
    $btnArchivar.Foreground = Pincel '#5A6473'
    $btnArchivar.ToolTip = $(if ($script:verArchivadas) {
            'Desarchivar: vuelve al panel'
        } else { 'Archivar: la esconde del panel, sin borrar nada' })
    $btnArchivar.Tag = @{ conv = $C }
    $btnArchivar.Add_MouseEnter({ $this.Foreground = Pincel '#4ADE80' })
    $btnArchivar.Add_MouseLeave({ $this.Foreground = Pincel '#5A6473' })
    $btnArchivar.Add_Click({
            try {
                # -Archivada es lo CONTRARIO de la vista: en el panel se archiva,
                # y adentro del archivo se desarchiva.
                Set-ArchivadoConversacion -Id $this.Tag.conv.id `
                    -Archivada (-not $script:verArchivadas) | Out-Null
                Actualizar
            } catch {
                [Windows.MessageBox]::Show($_.Exception.Message, 'No se pudo archivar') | Out-Null
            }
        })

    # Los botones comparten la columna Auto de la derecha. El orden va de menos
    # a mas grave: abrir en remoto, archivar, quitar del panel, borrar el
    # transcript.
    $acciones = New-Object Windows.Controls.StackPanel
    $acciones.Orientation = 'Horizontal'
    $acciones.Children.Add($punto) | Out-Null
    $acciones.Children.Add($btnRemoto) | Out-Null
    $acciones.Children.Add($btnArchivar) | Out-Null
    $acciones.Children.Add($btnBorrar) | Out-Null
    $acciones.Children.Add($btnDestruir) | Out-Null


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
    [Windows.Controls.Grid]::SetColumnSpan($capa, 3)
    [Windows.Controls.Grid]::SetRowSpan($capa, 2)

    $haloBase = New-Object Windows.Shapes.Rectangle
    $haloBase.RadiusX = 9      # igual al CornerRadius del Border, o no calza en las esquinas
    $haloBase.RadiusY = 9
    $haloBase.Stroke = Pincel '#2FA968'
    $haloBase.StrokeThickness = 1.6
    $haloBase.Fill = $null
    $capa.Children.Add($haloBase) | Out-Null

    # Reflejo de vidrio: una franja clara en diagonal que cruza la tarjeta de
    # izquierda a derecha en 0.7 s y espera; el ciclo dura 4 s. En
    # RelativeTransform, como el halo: no depende del tamano de la tarjeta.
    $reflejo = New-Object Windows.Media.LinearGradientBrush
    $reflejo.StartPoint = New-Object Windows.Point(0, 0)
    $reflejo.EndPoint = New-Object Windows.Point(1, 1)
    foreach ($p in @(@(0.36, '#00FFFFFF'), @(0.46, '#10FFFFFF'), @(0.50, '#2AFFFFFF'),
            @(0.54, '#10FFFFFF'), @(0.64, '#00FFFFFF'))) {
        $reflejo.GradientStops.Add((New-Object Windows.Media.GradientStop(
                    [Windows.Media.ColorConverter]::ConvertFromString($p[1]), $p[0]))) | Out-Null
    }
    # De -1.4 a +1.4 anchos: a +-1 la franja diagonal todavia asoma en una esquina.
    $corrida = New-Object Windows.Media.TranslateTransform(-1.4, 0)
    $reflejo.RelativeTransform = $corrida

    $vidrio = New-Object Windows.Shapes.Rectangle
    $vidrio.RadiusX = 9
    $vidrio.RadiusY = 9
    $vidrio.Fill = $reflejo
    $capa.Children.Add($vidrio) | Out-Null

    $barrido = New-Object Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $barrido.Duration = New-Object Windows.Duration ([TimeSpan]::FromSeconds(4))
    $barrido.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
    $k0 = New-Object Windows.Media.Animation.DiscreteDoubleKeyFrame(-1.4,
        [Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::Zero))
    $k1 = New-Object Windows.Media.Animation.EasingDoubleKeyFrame(1.4,
        [Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds(700)))
    $k1.EasingFunction = New-Object Windows.Media.Animation.SineEase
    [void]$barrido.KeyFrames.Add($k0)
    [void]$barrido.KeyFrames.Add($k1)
    $corrida.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, $barrido)

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

    # Los relojes cuelgan de los transforms, no de los Rectangle. Van en el Tag
    # para poder frenarlos cuando se rearman las tarjetas (ver Actualizar).
    $capa.Tag = @{ Giro = $giro; Corrida = $corrida }
    $script:halos[([string]$C.sesion).ToLower()] = $capa
    $t.Child.Children.Add($capa) | Out-Null

    # --- el asa para reordenar ----------------------------------------------
    #  Seis puntos, el grip de siempre, dibujados con Ellipse y no con un glifo
    #  de fuente: Segoe MDL2 no trae un grip vertical decente, y un cuadradito
    #  de glifo faltante seria peor que no poner nada.
    #
    #  Solo en la vista normal. En el archivo no se reordena (ver
    #  Start-Arrastre): renumerar las archivadas pisaria los numeros de las
    #  activas, y mostrar el asa seria prometer algo que no va a pasar.
    if (-not $script:verArchivadas) {
        $asa = New-Object Windows.Controls.Grid
        $asa.Width = 10
        $asa.Height = 15
        $asa.VerticalAlignment = 'Center'
        $asa.Margin = [Windows.Thickness]::new(0, 0, 8, 0)
        $asa.Cursor = 'SizeNS'
        # Transparente pero NO $null: un pincel transparente igual recibe el
        # mouse. Sin pincel, el asa solo responderia encima de los puntos.
        $asa.Background = [Windows.Media.Brushes]::Transparent
        $asa.Opacity = 0.45
        $asa.ToolTip = 'Arrastrar para cambiar el orden'
        foreach ($fila in 0..2) {
            foreach ($col in 0..1) {
                $punto = New-Object Windows.Shapes.Ellipse
                $punto.Width = 3; $punto.Height = 3
                $punto.Fill = Pincel '#8A94A6'
                $punto.HorizontalAlignment = 'Left'
                $punto.VerticalAlignment = 'Top'
                $punto.Margin = [Windows.Thickness]::new(1 + $col * 5, 1 + $fila * 5, 0, 0)
                $asa.Children.Add($punto) | Out-Null
            }
        }
        $asa.Tag = $t
        $asa.Add_MouseEnter({ $this.Opacity = 1.0 })
        $asa.Add_MouseLeave({ if (-not $script:arrastre) { $this.Opacity = 0.45 } })
        # Handled = $true CORTA el burbujeo hacia la tarjeta. Sin eso el
        # MouseLeftButtonUp del asa sigue subiendo, la tarjeta lo toma como un
        # click y ABRE la conversacion justo al terminar de arrastrarla.
        # El try/catch NO es decorativo: una excepcion que escapa de un handler
        # de mouse la levanta el dispatcher de WPF y MATA el proceso. Paso de
        # verdad: al soltar la tarjeta se cerraba el gadget entero, porque este
        # archivo llamaba a una funcion que ya no existia. Los timers ya tenian
        # esta red (ver su Add_Tick); los handlers de mouse la necesitan igual.
        $asa.Add_MouseLeftButtonDown({
                $args[1].Handled = $true
                try { Start-Arrastre -Tarjeta $this.Tag -Asa $this }
                catch { Write-Falla 'arrastre/inicio' $_ }
            })
        $asa.Add_MouseMove({
                try { Move-Arrastre } catch { Write-Falla 'arrastre/mover' $_ }
            })
        $asa.Add_MouseLeftButtonUp({
                $args[1].Handled = $true
                try { Stop-Arrastre } catch { Write-Falla 'arrastre/soltar' $_ }
            })
        # Si se pierde la captura (Alt-Tab, otra ventana roba el foco) hay que
        # cerrar el arrastre igual: si quedara abierto, Actualizar se saltea
        # para siempre y el panel se congela sin ninguna senal.
        $asa.Add_LostMouseCapture({
                try { Stop-Arrastre } catch { Write-Falla 'arrastre/captura' $_ }
            })
        [Windows.Controls.Grid]::SetColumn($asa, 0)
        [Windows.Controls.Grid]::SetRowSpan($asa, 2)
        $t.Child.Children.Add($asa) | Out-Null
    }

    $acciones.VerticalAlignment = 'Center'
    [Windows.Controls.Grid]::SetColumn($acciones, 2)
    $t.Child.Children.Add($acciones) | Out-Null

    return $t
}
