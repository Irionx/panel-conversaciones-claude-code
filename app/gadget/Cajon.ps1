# =============================================================================
#  Cajon.ps1 - la segunda columna: el archivo y el historial de Claude
# =============================================================================
#  POR QUE UN CAJON Y NO OTRA PANTALLA: el archivo REEMPLAZABA la lista, asi que
#  para comparar lo guardado contra lo archivado habia que ir y volver de
#  memoria. Abriendo a la derecha se ven las dos a la vez, y una conversacion
#  que cruza de lado se VE cruzar.
#
#  EL ANCHO DE LA VENTANA NO SE ANIMA, a proposito. Se anima el del cajon y la
#  ventana se cuelga de su SizeChanged sumando el delta. Animar Window.Width
#  dejaria esa propiedad tomada por el reloj de la animacion y los grips de los
#  costados (Posicion.ps1) no podrian volver a escribirla: el panel quedaria sin
#  poder ensancharse a mano, y el sintoma aparece recien al intentarlo.
#
#  LAS TRES COSAS QUE LO HACEN IR FLUIDO, todas medidas:
#    1. NO se rearma en cada refresco. Actualizar corre cada 2 s; rearmar las
#       103 tarjetas del historial cuesta 609 ms y las 8 del archivo 350 ms.
#       Se compara una FIRMA barata (la base sola son 14,7 ms) y solo se rearma
#       si cambio algo de verdad.
#    2. La lista es un ListBox, no un StackPanel adentro de un ScrollViewer. El
#       StackPanel no virtualiza: media y dibujaba las 103 tarjetas para mostrar
#       8, y un relayout costaba 68 ms (15 fps de techo mientras el cajon abre).
#    3. Filtrar y ordenar NO rearman nada: las tarjetas se construyen una vez y
#       despues solo se le cambia el ItemsSource al ListBox.
# =============================================================================

# 314 = 300 de lista + los 14 del canal, que van ADENTRO del ancho animado
# (ver el comentario del cajon en Xaml.ps1).
$script:ANCHO_CAJON = 314
$script:MS_CAJON = 260
$script:MS_VUELO = 190
# Lo que le comen al alto los renglones de arriba del cajon, para que las dos
# columnas terminen parejas y la ventana no crezca al abrirlo.
$script:ALTO_TITULO_CAJON = 27
$script:ALTO_BARRA_CAJON = 32
$script:vistaCajon = ''

# El historial recorre ~/.claude/projects entero: 1,4 s medidos sobre 119
# sesiones y 679 MB. NO puede entrar en Actualizar. Se cachea.
$script:discoCache = $null
$script:discoCacheHora = [datetime]::MinValue
$script:TTL_DISCO = 30

# Lo que esta DIBUJADO ahora mismo, para no rearmarlo al pedo.
$script:selloCajon = ''
$script:histVistas = @()        # @{ Ses = <sesion>; Caja = <Border> } ya armadas
$script:histFiltro = ''
$script:histOrden = 'fecha'     # 'fecha' | 'peso'
$script:histSel = @{}           # sesion (minuscula) -> $true

function Get-SesionesCacheadas {
    param([switch]$Forzar)
    if ($Forzar -or $null -eq $script:discoCache -or
        ((Get-Date) - $script:discoCacheHora).TotalSeconds -gt $script:TTL_DISCO) {
        $script:discoCache = @(Get-SesionesEnDisco)
        $script:discoCacheHora = Get-Date
    }
    return $script:discoCache
}

# --- cableado -----------------------------------------------------------------
#  Vive aca y no en gadget.ps1 porque el cableado del cajon es del cajon (y
#  porque hay un test que no deja a gadget.ps1 pasar las 600 lineas). gadget.ps1
#  lo llama con una linea sola.
#  Todo va a $script:: estos handlers se disparan desde el reloj de una
#  animacion y desde el pump de un dialogo modal, y ahi PowerShell resuelve por
#  la PILA DE LLAMADAS, no por donde esta escrito el codigo.
function Connect-Cajon {
    foreach ($n in 'cajon', 'cajonTitulo', 'listaCajon', 'cajonBarra', 'cajonBuscar',
        'cajonBuscarGuia', 'cajonSeleccion', 'cajonSelTexto', 'btnOrdenFecha',
        'btnOrdenPeso', 'btnHistorial', 'btnArchivadas', 'btnCajonCerrar',
        'btnSelNada', 'btnSelBorrar') {
        Set-Variable -Name $n -Scope Script -Value ($script:ventana.FindName($n))
    }
    # Los botones de adentro del cajon llevan el mismo template plano que los de
    # las tarjetas; los de la cabecera ya los hizo gadget.ps1.
    foreach ($b in $script:btnCajonCerrar, $script:btnSelNada, $script:btnSelBorrar,
        $script:btnOrdenFecha, $script:btnOrdenPeso) {
        $b.Template = $script:tplPlano
    }

    $script:btnArchivadas.Add_Click({ Set-Cajon -Vista 'archivadas' })
    $script:btnHistorial.Add_Click({ Set-Cajon -Vista 'historial' })
    $script:btnCajonCerrar.Add_Click({ Set-Cajon })
    $script:btnSelNada.Add_Click({ Clear-SeleccionHistorial })
    $script:btnSelBorrar.Add_Click({ Invoke-BorrarSeleccionadas })
    $script:btnOrdenFecha.Add_Click({
            $script:histOrden = 'fecha'; Set-AparienciaCajon; Aplicar-FiltroHistorial
        })
    $script:btnOrdenPeso.Add_Click({
            $script:histOrden = 'peso'; Set-AparienciaCajon; Aplicar-FiltroHistorial
        })

    # El buscador filtra SIN rearmar las tarjetas: solo le cambia el ItemsSource
    # al ListBox. Rearmarlas costaria 609 ms por cada tecla.
    $script:cajonBuscar.Add_TextChanged({
            $script:histFiltro = $script:cajonBuscar.Text
            # El texto guia es un TextBlock atras del TextBox: WPF no trae
            # placeholder, y un trigger sobre Text no existe.
            $script:cajonBuscarGuia.Visibility =
            if ($script:cajonBuscar.Text) { 'Collapsed' } else { 'Visible' }
            Aplicar-FiltroHistorial
        })

    # El ancho de la VENTANA sigue al del cajon, delta a delta.
    $script:cajon.Add_SizeChanged({
            param($remitente, $ev)
            Sync-AnchoVentana -Delta ($ev.NewSize.Width - $ev.PreviousSize.Width)
        })
}

# --- abrir y cerrar -----------------------------------------------------------
function Set-Cajon {
    param([string]$Vista = '')

    if ($Vista -and $Vista -eq $script:vistaCajon) { $Vista = '' }
    $estaba = [bool]$script:vistaCajon
    $script:vistaCajon = $Vista
    $script:selloCajon = ''          # cambiar de vista siempre rearma

    if ($Vista) {
        $script:cajon.Visibility = 'Visible'
        # El disco se relee ACA, al abrir, y nunca desde el timer: Actualizar
        # corre cada 2 s y una relectura cuesta 1,4 s. Asi la espera es cuando
        # vos la pediste, y no un tiron cada medio minuto sin motivo visible.
        if ($Vista -eq 'historial') { Get-SesionesCacheadas | Out-Null }
        Actualizar-Cajon
        if (-not $estaba) { Start-AnchoCajon -Hasta $script:ANCHO_CAJON }
    } else {
        Start-AnchoCajon -Hasta 0
    }
    Set-AparienciaCajon
}

function Start-AnchoCajon {
    param([double]$Hasta)
    $a = New-Object Windows.Media.Animation.DoubleAnimation
    $a.From = $script:cajon.ActualWidth
    $a.To = $Hasta
    $a.Duration = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds($script:MS_CAJON))
    $e = New-Object Windows.Media.Animation.CubicEase
    $e.EasingMode = 'EaseInOut'
    $a.EasingFunction = $e
    $a.Add_Completed({ Stop-AnchoCajon })
    $script:cajon.BeginAnimation([Windows.FrameworkElement]::WidthProperty, $a)
}

function Stop-AnchoCajon {
    # Colapsar recien al final: con Width 0 y Visible la columna sigue viva y el
    # ClipToBounds no evita que su contenido reciba el mouse.
    if (-not $script:vistaCajon) {
        $script:cajon.Visibility = 'Collapsed'
        $script:listaCajon.ItemsSource = $null
        $script:histVistas = @()
        $script:histSel = @{}
        $script:selloCajon = ''
    }
}

# El ancho de la ventana sigue al del cajon, delta a delta. Lo engancha
# gadget.ps1 al SizeChanged del cajon.
function Sync-AnchoVentana {
    param([double]$Delta)
    if ([math]::Abs($Delta) -lt 0.01) { return }
    $nuevo = $script:ventana.Width + $Delta
    if ([double]::IsNaN($nuevo) -or $nuevo -lt 200) { return }
    $script:ventana.Width = $nuevo
    # Creciendo hacia la derecha el que se tiene que correr es el borde
    # IZQUIERDO: el panel vive pegado al borde derecho de la pantalla.
    $wa = [Windows.SystemParameters]::WorkArea
    if ($script:ventana.Left + $nuevo -gt $wa.Right) {
        $script:ventana.Left = [math]::Max($wa.Left, $wa.Right - $nuevo)
    }
}

function Set-AparienciaCajon {
    $script:btnArchivadas.Foreground = Pincel $(
        if ($script:vistaCajon -eq 'archivadas') { '#E0A45A' } else { '#8A94A6' })
    $script:btnArchivadas.ToolTip = if ($script:vistaCajon -eq 'archivadas') {
        'Cerrar el archivo'
    } else { 'Ver las conversaciones archivadas, al lado' }
    $script:btnHistorial.Foreground = Pincel $(
        if ($script:vistaCajon -eq 'historial') { '#7DD3FC' } else { '#8A94A6' })
    $script:btnHistorial.ToolTip = if ($script:vistaCajon -eq 'historial') {
        'Cerrar el historial'
    } else { 'Todas las conversaciones de Claude que hay en disco' }
    $script:btnOrdenFecha.Foreground = Pincel $(
        if ($script:histOrden -eq 'fecha') { '#7DD3FC' } else { '#5A6473' })
    $script:btnOrdenPeso.Foreground = Pincel $(
        if ($script:histOrden -eq 'peso') { '#7DD3FC' } else { '#5A6473' })
}

# --- el contenido -------------------------------------------------------------
#  Barato cuando no cambio nada: calcula una firma y se va.
function Actualizar-Cajon {
    if (-not $script:vistaCajon) { return }

    $hayBarra = ($script:vistaCajon -eq 'historial')
    $script:cajonBarra.Visibility = if ($hayBarra) { 'Visible' } else { 'Collapsed' }

    # Que las dos columnas terminen parejas: al cajon le comen alto sus renglones.
    $cromo = $script:ALTO_TITULO_CAJON
    if ($hayBarra) { $cromo += $script:ALTO_BARRA_CAJON }
    if ($script:cajonSeleccion.Visibility -eq 'Visible') { $cromo += $script:ALTO_BARRA_CAJON }
    $script:listaCajon.MaxHeight = [math]::Max(60, $script:scroller.MaxHeight - $cromo)

    if ($script:vistaCajon -eq 'archivadas') { Actualizar-Archivo } else { Actualizar-Historial }
}

function Actualizar-Archivo {
    # FIRMA BARATA: la base sola son 14,7 ms. Lo caro es Sync-TitulosGuardados
    # (104 ms) y resolver cada titulo (7,7 ms), y eso solo se paga si cambio
    # algo. El TTL ademas hace que un /rename aparezca sin tocar nada.
    $crudas = @(Get-Conversacion -Estado 'archivadas')
    $sello = 'arch|' + (($crudas | ForEach-Object { '{0}:{1}' -f $_.id, $_.titulo }) -join '|')
    if ($sello -eq $script:selloCajon) { return }
    $script:selloCajon = $sello

    # Sync- y no Get-: de paso baja a disco el nombre de /rename, igual que hace
    # Actualizar con las activas.
    $convs = @(Sync-TitulosGuardados -Estado 'archivadas')
    $script:cajonTitulo.Text = if ($convs.Count -eq 1) { '1 archivada' } else { "$($convs.Count) archivadas" }

    $items = [System.Collections.ArrayList]::new()
    foreach ($c in $convs) { [void]$items.Add((New-TarjetaArchivada -C $c)) }
    if ($convs.Count -eq 0) {
        [void]$items.Add((New-AvisoCajon 'Nada archivado todavía. La bandeja de cada tarjeta las manda acá.'))
    }
    $script:listaCajon.ItemsSource = $items
}

function Actualizar-Historial {
    # Se usa lo que YA esta cacheado. Quien decide releer el disco es Set-Cajon
    # al abrir, o un borrado: desde aca nunca, que esto corre cada 2 segundos.
    if ($null -eq $script:discoCache) { return }
    $ses = @($script:discoCache)
    # La firma es la hora de la cache: si no se releyo, no hay nada nuevo.
    $sello = 'hist|' + $script:discoCacheHora.Ticks
    if ($sello -eq $script:selloCajon) { return }
    $script:selloCajon = $sello

    # Las tarjetas se arman UNA vez. Filtrar y ordenar despues solo reordenan
    # esta lista: rearmarlas costaria 609 ms por cada tecla del buscador.
    $script:histVistas = @()
    foreach ($s in $ses) {
        $caja = New-TarjetaHistorial -S $s
        # El tilde se guarda al armar: destildar "todas" tiene que poder apagarlos
        # sin volver a buscarlos por el arbol.
        $script:histVistas += @{
            Ses  = $s
            Caja = $caja
            Chk  = [Windows.LogicalTreeHelper]::FindLogicalNode($caja, 'chk')
        }
    }
    Aplicar-FiltroHistorial
}

#  Filtra y ordena SIN rearmar: solo cambia el ItemsSource del ListBox.
function Aplicar-FiltroHistorial {
    if ($script:vistaCajon -ne 'historial') { return }

    $texto = ([string]$script:histFiltro).Trim()
    $vistas = $script:histVistas
    if ($texto) {
        $vistas = @($vistas | Where-Object {
                ([string]$_.Ses.Titulo) -like "*$texto*" -or ([string]$_.Ses.Cwd) -like "*$texto*"
            })
    }
    $vistas = @(if ($script:histOrden -eq 'peso') {
            $vistas | Sort-Object { [int64]$_.Ses.Bytes } -Descending
        } else {
            $vistas | Sort-Object { $_.Ses.Fecha } -Descending
        })

    $items = [System.Collections.ArrayList]::new()
    foreach ($v in $vistas) { [void]$items.Add($v.Caja) }
    if ($vistas.Count -eq 0) {
        [void]$items.Add((New-AvisoCajon $(
                    if ($texto) { "Nada que coincida con `"$texto`"." }
                    else { 'No encontré transcripts en ~/.claude/projects.' })))
    }
    $script:listaCajon.ItemsSource = $items

    $total = $script:histVistas.Count
    $sueltas = @($script:histVistas | Where-Object { -not $_.Ses.Guardada }).Count
    $script:cajonTitulo.Text = if ($texto -and $vistas.Count -ne $total) {
        '{0} de {1}  ·  {2} sin guardar' -f $vistas.Count, $total, $sueltas
    } else {
        '{0} en disco  ·  {1} sin guardar' -f $total, $sueltas
    }
    Set-BarraSeleccion
}

function New-AvisoCajon {
    param([Parameter(Mandatory)][string]$Texto)
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = $Texto
    $t.Foreground = Pincel '#6B7484'
    $t.FontSize = 11
    $t.TextWrapping = 'Wrap'
    $t.Margin = [Windows.Thickness]::new(2, 6, 2, 8)
    return $t
}

# --- la seleccion multiple ----------------------------------------------------
function Set-SeleccionHistorial {
    param([Parameter(Mandatory)][string]$Sesion, [Parameter(Mandatory)][bool]$Tildada)
    $k = $Sesion.ToLower()
    if ($Tildada) { $script:histSel[$k] = $true } else { [void]$script:histSel.Remove($k) }
    Set-BarraSeleccion
}

function Set-BarraSeleccion {
    # Solo cuentan las que se ven: filtrar y despues borrar "todas" no puede
    # llevarse algo que el filtro estaba escondiendo.
    $sel = @(Get-SeleccionadasVisibles)
    if ($sel.Count -eq 0) {
        $script:cajonSeleccion.Visibility = 'Collapsed'
        return
    }
    # A mano y no con Measure-Object -Property { ... }: en PowerShell 5.1 ese
    # parametro toma el NOMBRE de una propiedad, un scriptblock no lo evalua y
    # la suma da 0 sin decir nada.
    $bytes = [int64]0
    foreach ($s in $sel) { $bytes += [int64]$s.Bytes }
    $script:cajonSelTexto.Text = '{0} tildada{1}  ·  {2}' -f `
        $sel.Count, $(if ($sel.Count -eq 1) { '' } else { 's' }), (Format-Bytes $bytes)
    $script:cajonSeleccion.Visibility = 'Visible'
}

function Get-SeleccionadasVisibles {
    $cajas = @($script:listaCajon.ItemsSource)
    foreach ($v in $script:histVistas) {
        if (-not $script:histSel[([string]$v.Ses.Sesion).ToLower()]) { continue }
        if ($cajas -notcontains $v.Caja) { continue }
        $v.Ses
    }
}

function Clear-SeleccionHistorial {
    $script:histSel = @{}
    foreach ($v in $script:histVistas) { if ($v.Chk) { $v.Chk.IsChecked = $false } }
    Set-BarraSeleccion
}

function Invoke-BorrarSeleccionadas {
    $sel = @(Get-SeleccionadasVisibles)
    if ($sel.Count -eq 0) { return }

    # Una confirmacion para todas, no N seguidas. Se listan las primeras y se
    # dice cuantas quedan: una lista de 60 filas no la lee nadie.
    $filas = @()
    foreach ($s in ($sel | Select-Object -First 8)) {
        $filas += @{ Texto = $(if ($s.Titulo) { [string]$s.Titulo } else { [string]$s.Sesion })
            Dato            = (Format-Bytes ([int64]$s.Bytes))
        }
    }
    if ($sel.Count -gt 8) { $filas += @{ Texto = "… y $($sel.Count - 8) más" } }
    $enPanel = @($sel | Where-Object { $_.Guardada }).Count
    $aviso = 'No se van a poder reabrir con --resume, y Remove-Item no manda nada a la papelera.'
    if ($enPanel -gt 0) {
        $aviso += " $enPanel de estas están en el panel: también se van sus tarjetas."
    }

    $bytes = [int64]0
    foreach ($s in $sel) { $bytes += [int64]$s.Bytes }
    $opciones = @{
        Encabezado = 'Borrar para siempre'
        Nombre     = '{0} conversaciones  ·  {1}' -f $sel.Count, (Format-Bytes $bytes)
        Filas      = $filas
        Aviso      = $aviso
        TextoOk    = "Borrar las $($sel.Count)"
        Peligro    = $true
    }
    if (-not (Show-Confirmacion @opciones)) { return }

    $fallaron = @()
    foreach ($s in $sel) {
        try {
            Remove-SesionEnDisco -Dir $s.Dir -Sesion $s.Sesion | Out-Null
            if ($s.Guardada -and $s.Conv) { Remove-Conversacion -Id $s.Conv.id | Out-Null }
        } catch {
            # Se sigue con las demas: que una este abierta en Claude Code no
            # tiene por que frenar el resto.
            $fallaron += '{0}: {1}' -f $s.Sesion.Substring(0, 8), $_.Exception.Message
        }
    }
    $script:histSel = @{}
    Get-SesionesCacheadas -Forzar | Out-Null
    $script:selloCajon = ''
    Actualizar-Cajon
    Actualizar
    if ($fallaron.Count) {
        [Windows.MessageBox]::Show(($fallaron -join "`n`n"),
            "No pude borrar $($fallaron.Count) de $($sel.Count)") | Out-Null
    }
}

# --- la tarjeta del historial -------------------------------------------------
#  Una fila por transcript en disco. Lo que importa de un vistazo es si esta
#  GUARDADA o no: lo que no lo esta es lo que se puede limpiar sin perder nada
#  del panel. Por eso el punto de color va adelante y no al final.
function New-TarjetaHistorial {
    param([Parameter(Mandatory)]$S)

    $titulo = if ($S.Titulo) { [string]$S.Titulo } else { '(sin nombre)  ' + $S.Sesion.Substring(0, 8) }
    $donde = if ($S.Cwd) { [string]$S.Cwd } else { [string]$S.Carpeta }
    $dato = '{0:dd/MM/yy}  ·  {1}' -f $S.Fecha, (Format-Bytes $S.Bytes)
    $color = if ($S.Guardada) { '#4ADE80' } else { '#5A6473' }

    $x = @"
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Background="$(Get-ColorTarjeta)" CornerRadius="9" Padding="8,6,7,7" Margin="0,0,0,6">
  <Grid>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="Auto"/>
      <ColumnDefinition Width="Auto"/>
      <ColumnDefinition Width="*"/>
      <ColumnDefinition Width="Auto"/>
    </Grid.ColumnDefinitions>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <CheckBox x:Name="chk" Grid.Row="0" Grid.Column="0" VerticalAlignment="Center" Margin="0,0,7,0"/>
    <Border Grid.Row="0" Grid.Column="1" Width="6" Height="6" CornerRadius="3" Background="$color"
            VerticalAlignment="Center" Margin="0,0,6,0"/>
    <TextBlock Grid.Row="0" Grid.Column="2" Text="$(Escapar $titulo)" Foreground="#C7CEDA" FontSize="12"
               FontWeight="SemiBold" TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/>
    <TextBlock Grid.Row="1" Grid.Column="2" Grid.ColumnSpan="2" Text="$(Escapar $donde)" Foreground="#6B7484"
               FontSize="10" Margin="0,1,0,0" TextTrimming="CharacterEllipsis"/>
    <TextBlock Grid.Row="2" Grid.Column="2" Grid.ColumnSpan="2" Text="$(Escapar $dato)" Foreground="#5A6473"
               FontSize="10" Margin="0,2,0,0"/>
  </Grid>
</Border>
"@
    $t = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$x)))

    # El estilo del tilde vive en Window.Resources y no en este XAML suelto: un
    # fragmento aparte no ve los recursos de la ventana, y parsearlo 103 veces
    # costaria mas que la tarjeta entera.
    $chk = [Windows.LogicalTreeHelper]::FindLogicalNode($t, 'chk')
    $chk.Style = $script:ventana.FindResource('ChkFino')
    $chk.Tag = @{ ses = $S }
    $chk.Add_Click({ Set-SeleccionHistorial -Sesion $this.Tag.ses.Sesion -Tildada ([bool]$this.IsChecked) })

    $tip = if ($S.Guardada) {
        'Está en el panel. Borrar se lleva el transcript Y la tarjeta'
    } else {
        'No está en el panel. Borra el transcript de disco'
    }
    $btn = New-BotonTarjeta -Glifo 0xE74D -Mdl2 -Vertical 'Top' -Tip $tip -Hover '#EF4444' `
        -Tag @{ ses = $S }
    $btn.Add_Click({ Invoke-BorrarDelHistorial -S $this.Tag.ses })
    [Windows.Controls.Grid]::SetColumn($btn, 3)
    [void]$t.Child.Children.Add($btn)
    return $t
}

function Invoke-BorrarDelHistorial {
    param([Parameter(Mandatory)]$S)

    # Si esta en el panel es exactamente el mismo borrado que desde una tarjeta:
    # un solo camino, una sola confirmacion.
    if ($S.Guardada -and $S.Conv) {
        Invoke-BorrarTarjeta -Conv $S.Conv -Titulo ([string]$S.Titulo)
    } else {
        try {
            $rastros = @(Get-RastrosEn -Dir $S.Dir -Sesion $S.Sesion)
        } catch {
            [Windows.MessageBox]::Show($_.Exception.Message, 'No se pudo borrar') | Out-Null
            return
        }
        $filas = @()
        foreach ($ra in $rastros) { $filas += @{ Texto = $ra.Nombre; Dato = (Format-Bytes $ra.Bytes) } }
        if ($rastros.Count -eq 0) { $filas += @{ Texto = '(ya no queda nada en disco)' } }

        $opciones = @{
            Encabezado = 'Borrar para siempre'
            Nombre     = $(if ($S.Titulo) { [string]$S.Titulo } else { [string]$S.Sesion })
            Filas      = $filas
            Aviso      = 'Esta conversación NO está en el panel, así que no hay nada que quitar de ahí. No se va a poder reabrir con --resume, y Remove-Item no manda nada a la papelera.'
            TextoOk    = 'Borrar'
            Peligro    = $true
        }
        if (-not (Show-Confirmacion @opciones)) { return }
        try {
            Remove-SesionEnDisco -Dir $S.Dir -Sesion $S.Sesion | Out-Null
        } catch {
            [Windows.MessageBox]::Show($_.Exception.Message, 'No se pudo borrar') | Out-Null
            return
        }
    }
    [void]$script:histSel.Remove(([string]$S.Sesion).ToLower())
    Get-SesionesCacheadas -Forzar | Out-Null
    $script:selloCajon = ''
    Actualizar-Cajon
}

# --- el vuelo de una tarjeta de una columna a la otra -------------------------
#  Archivar y desarchivar mueven una conversacion de lado. Con el cajon abierto
#  las dos listas estan a la vista, asi que el salto se nota: la tarjeta sale
#  volando hacia el lado al que va y recien ahi se escribe en la base.
#
#  Sin el cajon abierto no hay a donde volar y se hace derecho: animar algo que
#  nadie va a ver solo agrega 190 ms de espera.
$script:vueloId = ''
$script:vueloArchivar = $false

function Start-VueloTarjeta {
    param(
        [Parameter(Mandatory)]$Conv,
        [Parameter(Mandatory)][bool]$Archivar,
        $Desde
    )

    if ($script:vistaCajon -ne 'archivadas' -or -not $Desde -or $script:vueloId) {
        Set-ArchivadoConversacion -Id $Conv.id -Archivada $Archivar | Out-Null
        $script:selloCajon = ''
        Actualizar
        return
    }

    $script:vueloId = [string]$Conv.id
    $script:vueloArchivar = $Archivar

    $tt = New-Object Windows.Media.TranslateTransform
    $Desde.RenderTransform = $tt
    $dx = if ($Archivar) { 120 } else { -120 }

    $mov = New-Object Windows.Media.Animation.DoubleAnimation
    $mov.To = $dx
    $mov.Duration = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds($script:MS_VUELO))
    $ease = New-Object Windows.Media.Animation.CubicEase
    $ease.EasingMode = 'EaseIn'
    $mov.EasingFunction = $ease

    $fade = New-Object Windows.Media.Animation.DoubleAnimation
    $fade.To = 0
    $fade.Duration = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds($script:MS_VUELO))
    # El Completed va en UNA sola de las dos: las dos duran lo mismo, y
    # engancharlo en ambas escribiria la base dos veces.
    $fade.Add_Completed({ Stop-VueloTarjeta })

    # BeginAnimation sobre el transform y no un Storyboard con SetTarget: sobre
    # un Freezable, SetTarget no anima nada y no tira ningun error.
    $tt.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, $mov)
    $Desde.BeginAnimation([Windows.UIElement]::OpacityProperty, $fade)
}

function Stop-VueloTarjeta {
    if (-not $script:vueloId) { return }
    $id = $script:vueloId
    $script:vueloId = ''
    try {
        Set-ArchivadoConversacion -Id $id -Archivada $script:vueloArchivar | Out-Null
    } catch {
        [Windows.MessageBox]::Show($_.Exception.Message, 'No se pudo archivar') | Out-Null
    }
    $script:selloCajon = ''
    Actualizar
}

# La tarjeta que contiene a un boton. Se sube por el arbol VISUAL y no se guarda
# en el Tag al construir: asi no depende del orden en que New-Tarjeta arma las
# cosas, que ya cambio una vez.
function Get-TarjetaDe {
    param($Elemento)
    $n = $Elemento
    while ($n) {
        if ($n -is [Windows.Controls.Border] -and $n.Tag -and $n.Tag.conv) { return $n }
        $n = [Windows.Media.VisualTreeHelper]::GetParent($n)
    }
    return $null
}
