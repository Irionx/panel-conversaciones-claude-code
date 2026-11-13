# =============================================================================
#  Nueva.ps1 - arrancar una conversacion desde el panel
# -----------------------------------------------------------------------------
#  POR QUE UN BOTON PROPIO EN LA CABECERA Y NO UNO POR TARJETA: una conversacion
#  nueva no pertenece a ninguna de las que ya estan. Colgarla de una tarjeta
#  ataria "nueva" a "en la carpeta de esta", que es solo uno de los casos.
#
#  POR QUE NO HAY SELECTOR DE CARPETAS DE WINDOWS: el FolderBrowserDialog de
#  WinForms sobre .NET Framework es el arbol viejo, claro y con otra tipografia;
#  en un panel oscuro parece que algo se rompio. Y no hace falta: el panel YA
#  conoce tus carpetas, estan en el cwd de cada tarjeta y de cada fila del
#  historial. Para la que nunca vio, se pega la ruta a mano.
#
#  POR QUE LA CONVERSACION NO QUEDA GUARDADA AL LANZARLA: no tiene uuid hasta
#  que Claude Code escribe su primer .jsonl. No hay nada que guardar todavia.
#  Nace huerfana a proposito y se sube despues desde el historial, que es
#  justamente lo que hace el boton de agregar del cajon.
# =============================================================================

# Cuantas carpetas se ofrecen. NO hay ScrollViewer en el dialogo: la barra fina
# vive en los recursos de la ventana principal y un dialogo suelto no los ve, asi
# que meter lista con scroll obligaria a duplicar ese template entero. Con las 10
# mas recientes alcanza, y para el resto esta el campo de la ruta.
$script:TOPE_CARPETAS = 10
$script:GLIFO_NUEVA = 0xE710

# --- cableado -----------------------------------------------------------------
#  Vive aca y no en gadget.ps1 por lo mismo que Connect-Cajon: el cableado del
#  boton es del boton, y gadget.ps1 tiene un tope de 600 lineas.
function Connect-Nueva {
    $script:btnNueva = $script:ventana.FindName('btnNueva')
    $script:btnNueva.Template = $script:tplPlano
    # Verde al pasar por encima: es el unico boton de la cabecera que CREA algo,
    # y conviene que se distinga de los que solo muestran u ocultan.
    $script:btnNueva.Add_MouseEnter({ $this.Foreground = Pincel '#4ADE80' })
    $script:btnNueva.Add_MouseLeave({ $this.Foreground = Pincel '#8A94A6' })
    $script:btnNueva.Add_Click({ Open-DialogoNueva })
}

# --- las carpetas que el panel ya conoce --------------------------------------
#  Las dos fuentes, y las dos hacen falta: el panel trae las carpetas de lo que
#  guardaste, y el historial las de donde trabajaste sin guardar nada -- que son
#  justo las que uno quiere retomar.
#
#  El historial se usa SOLO si ya esta cacheado. Releerlo cuesta 1,4 s medidos y
#  no se los va a pagar quien abre este dialogo para elegir entre sus proyectos
#  de siempre; si abriste el cajon alguna vez, salen tambien esas.
function Get-CarpetasConocidas {
    param(
        [object[]]$Conversaciones,
        [object[]]$Sesiones
    )
    if (-not $PSBoundParameters.ContainsKey('Conversaciones')) {
        $Conversaciones = @(Get-Conversacion)
    }
    if (-not $PSBoundParameters.ContainsKey('Sesiones')) {
        $Sesiones = @(if ($null -ne $script:discoCache) { $script:discoCache } else { @() })
    }

    # ruta normalizada en minuscula -> @{ Ruta; Fecha }. La clave va en minuscula
    # porque en Windows dos rutas que difieren en el caso son LA MISMA carpeta,
    # y se queda la escritura de la aparicion mas nueva.
    $mapa = @{}
    foreach ($fila in @(@($Conversaciones) + @($Sesiones))) {
        if (-not $fila) { continue }
        # Las dos fuentes nombran el campo distinto: cwd en la base, Cwd en disco.
        $cruda = if ($fila.PSObject.Properties.Name -contains 'Cwd') { $fila.Cwd } else { $fila.cwd }
        $ruta = ConvertTo-RutaWindows ([string]$cruda)
        if (-not $ruta) { continue }

        $cuando = [datetime]::MinValue
        try { $cuando = [datetime]$fila.Fecha } catch { }
        if ($cuando -eq [datetime]::MinValue) {
            try { $cuando = [datetime]$fila.fecha } catch { }
        }

        $clave = $ruta.ToLower()
        if (-not $mapa.ContainsKey($clave) -or $mapa[$clave].Fecha -lt $cuando) {
            $mapa[$clave] = @{ Ruta = $ruta; Fecha = $cuando }
        }
    }

    # La coma de adelante es obligatoria: en PS 5.1 un array de 0 o 1 elementos
    # se desarma al volver de una funcion y el llamador recibe $null o un string.
    , @($mapa.Values | Sort-Object { $_.Fecha } -Descending |
        Select-Object -First $script:TOPE_CARPETAS | ForEach-Object { $_.Ruta })
}

# --- el dialogo ---------------------------------------------------------------
#  Se arma sin mostrarlo, igual que New-DialogoEtiquetas: asi los tests y el
#  render a PNG lo pueden usar sin abrir una ventana en el escritorio.
function New-DialogoNueva {
    param([string[]]$Carpetas = @())

    $x = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        SizeToContent="Height" Width="360" ShowInTaskbar="False" Topmost="True"
        ResizeMode="NoResize" WindowStartupLocation="CenterOwner" FontFamily="Segoe UI">
  <Window.Resources>
    <Style x:Key="Chato" TargetType="Button">
      <Setter Property="Background" Value="#1AFFFFFF"/>
      <Setter Property="BorderBrush" Value="#2EFFFFFF"/>
      <Setter Property="Foreground" Value="#C7CEDA"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Padding" Value="15,6,15,7"/>
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
    <!-- El TextBox por defecto es blanco con borde azul: se reemplaza el template entero. -->
    <Style x:Key="Caja" TargetType="TextBox">
      <Setter Property="Background" Value="#0FFFFFFF"/>
      <Setter Property="Foreground" Value="#F2F5F9"/>
      <Setter Property="CaretBrush" Value="#F2F5F9"/>
      <Setter Property="SelectionBrush" Value="#60A5FA"/>
      <Setter Property="BorderBrush" Value="#2EFFFFFF"/>
      <Setter Property="FontSize" Value="11.5"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Border x:Name="marco" CornerRadius="7" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" Padding="8,5,8,6">
              <ScrollViewer x:Name="PART_ContentHost"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="marco" Property="BorderBrush" Value="#7A8699"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Border x:Name="tarjeta" CornerRadius="10" Background="#161A20" Margin="13"
          BorderBrush="#2EFFFFFF" BorderThickness="1" Padding="17,15,17,15">
    <Border.Effect>
      <DropShadowEffect BlurRadius="28" ShadowDepth="0" Opacity="0.6" Color="#000000"/>
    </Border.Effect>
    <StackPanel>
      <StackPanel Orientation="Horizontal" Margin="0,0,0,3">
        <TextBlock Text="&#xE710;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="#4ADE80"
                   VerticalAlignment="Center" Margin="0,0,9,0"/>
        <TextBlock Text="Conversación nueva" Foreground="#F2F5F9" FontSize="13.5" FontWeight="SemiBold"
                   VerticalAlignment="Center"/>
      </StackPanel>
      <TextBlock Text="Elegí la carpeta donde va a arrancar." Foreground="#8A94A6" FontSize="11"
                 TextWrapping="Wrap" Margin="0,0,0,12"/>

      <Border CornerRadius="8" Background="#12FFFFFF" Padding="4" Margin="0,0,0,14">
        <StackPanel>
          <StackPanel x:Name="carpetas"/>
          <TextBlock x:Name="sinCarpetas" Visibility="Collapsed"
                     Text="Todavía no conozco ninguna carpeta. Pegá una ruta acá abajo."
                     Foreground="#6B7484" FontSize="11" TextWrapping="Wrap" Margin="7,6,7,6"/>
        </StackPanel>
      </Border>

      <TextBlock Text="O pegá una ruta" Foreground="#9AA4B5" FontSize="11"
                 FontWeight="SemiBold" Margin="0,0,0,6"/>
      <TextBox x:Name="txtRuta" Style="{StaticResource Caja}"/>
      <TextBlock x:Name="error" Foreground="#F87171" FontSize="11" TextWrapping="Wrap"
                 Margin="0,8,0,0" Visibility="Collapsed"/>

      <Grid Margin="0,14,0,0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <Button x:Name="btnAbrir" Content="Abrir" Style="{StaticResource Chato}"
                HorizontalAlignment="Left"
                Background="#2F6B43" BorderBrush="#4ADE80" Foreground="#F2F5F9"/>
        <Button x:Name="btnCancelar" Grid.Column="1" Content="Cancelar" Style="{StaticResource Chato}"
                IsCancel="True"/>
      </Grid>
    </StackPanel>
  </Border>
</Window>
'@

    $dlg = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$x)))

    # El estado va en el Tag: los handlers no ven las variables de esta funcion.
    $dlg.Tag = @{ Carpetas = @($Carpetas); Elegida = '' }

    $cont = $dlg.FindName('carpetas')
    foreach ($ruta in @($Carpetas)) {
        [void]$cont.Children.Add((New-FilaCarpeta -Ruta $ruta))
    }
    $dlg.FindName('sinCarpetas').Visibility = $(if (@($Carpetas).Count) { 'Collapsed' } else { 'Visible' })

    $caja = $dlg.FindName('txtRuta')
    $caja.Add_KeyDown({
            if ($args[1].Key -eq 'Return') {
                $args[1].Handled = $true
                Invoke-AbrirNueva -Dialogo ([Windows.Window]::GetWindow($this))
            }
        })
    # Escribir a mano apaga el error anterior y desmarca la fila elegida: lo que
    # vale es lo que dice el campo.
    $caja.Add_TextChanged({
            $d = [Windows.Window]::GetWindow($this)
            $d.FindName('error').Visibility = 'Collapsed'
            $d.Tag.Elegida = ''
            Update-FilasCarpeta -Dialogo $d
        })
    $dlg.FindName('btnAbrir').Add_Click({ Invoke-AbrirNueva -Dialogo ([Windows.Window]::GetWindow($this)) })
    $dlg.FindName('tarjeta').Add_MouseLeftButtonDown({
            try { [Windows.Window]::GetWindow($this).DragMove() } catch { }
        })

    # La mas reciente viene elegida: el caso comun es volver al ultimo proyecto,
    # y asi se abre con un solo click.
    if (@($Carpetas).Count) { Select-CarpetaNueva -Dialogo $dlg -Ruta @($Carpetas)[0] }
    $dlg.Add_Loaded({ $this.FindName('txtRuta').Focus() | Out-Null })
    return $dlg
}

function New-FilaCarpeta {
    param([Parameter(Mandatory)][string]$Ruta)

    $texto = New-Object Windows.Controls.TextBlock
    $texto.Text = $Ruta
    $texto.FontSize = 11
    $texto.Foreground = Pincel '#C7CEDA'
    $texto.TextTrimming = 'CharacterEllipsis'

    $fila = New-Object Windows.Controls.Border
    $fila.CornerRadius = [Windows.CornerRadius]::new(5)
    $fila.Padding = [Windows.Thickness]::new(7, 4, 7, 5)
    $fila.Background = [Windows.Media.Brushes]::Transparent
    $fila.Cursor = 'Hand'
    $fila.ToolTip = 'Arrancar una conversación acá'
    $fila.Child = $texto
    $fila.Tag = $Ruta
    # El Down se marca: si sube hasta la tarjeta, su DragMove se come el Up y el
    # click no llega nunca (la misma trampa que en las filas de Etiquetas).
    $fila.Add_MouseLeftButtonDown({ $args[1].Handled = $true })
    $fila.Add_MouseLeftButtonUp({
            Select-CarpetaNueva -Dialogo ([Windows.Window]::GetWindow($this)) -Ruta ([string]$this.Tag)
        })
    return $fila
}

# Elegir una fila LLENA el campo de la ruta en vez de guardar la eleccion aparte:
# asi hay una sola verdad sobre que carpeta se va a abrir, la que se ve escrita.
function Select-CarpetaNueva {
    param([Parameter(Mandatory)]$Dialogo, [Parameter(Mandatory)][string]$Ruta)
    $Dialogo.FindName('txtRuta').Text = $Ruta
    # El TextChanged de arriba la borro al escribir: se repone despues.
    $Dialogo.Tag.Elegida = $Ruta
    $Dialogo.FindName('error').Visibility = 'Collapsed'
    Update-FilasCarpeta -Dialogo $Dialogo
}

function Update-FilasCarpeta {
    param([Parameter(Mandatory)]$Dialogo)
    $marcada = [string]$Dialogo.Tag.Elegida
    foreach ($fila in $Dialogo.FindName('carpetas').Children) {
        $esta = ([string]$fila.Tag -eq $marcada) -and $marcada
        $fila.Background = $(if ($esta) { Pincel '#2EFFFFFF' } else { [Windows.Media.Brushes]::Transparent })
    }
}

# --- validar y lanzar ---------------------------------------------------------
#  Devuelve la ruta lista para usar, o $null dejando el motivo a la vista. Va
#  separado de lanzar para poder probarlo sin abrir ninguna terminal.
function Get-CarpetaElegida {
    param([Parameter(Mandatory)]$Dialogo)

    $pedida = ConvertTo-RutaWindows (([string]$Dialogo.FindName('txtRuta').Text).Trim())
    if (-not $pedida) {
        Show-ErrorNueva -Dialogo $Dialogo -Texto 'Elegí una carpeta de la lista, o pegá una ruta.'
        return $null
    }
    if (-not (Test-Path -LiteralPath $pedida -PathType Container)) {
        Show-ErrorNueva -Dialogo $Dialogo -Texto "Esa carpeta no existe:`n$pedida"
        return $null
    }
    $Dialogo.FindName('error').Visibility = 'Collapsed'
    return $pedida
}

function Show-ErrorNueva {
    # Texto no es Mandatory: un [string] obligatorio vacio pide el valor por consola.
    param([Parameter(Mandatory)]$Dialogo, [string]$Texto = '')
    $aviso = $Dialogo.FindName('error')
    $aviso.Text = $Texto
    $aviso.Visibility = 'Visible'
}

function Invoke-AbrirNueva {
    param([Parameter(Mandatory)]$Dialogo)
    $donde = Get-CarpetaElegida -Dialogo $Dialogo
    if (-not $donde) { return }
    try {
        Start-ConversacionNueva -Cwd $donde | Out-Null
    } catch {
        Show-ErrorNueva -Dialogo $Dialogo -Texto $_.Exception.Message
        return
    }
    $Dialogo.Close()
}

function Open-DialogoNueva {
    try {
        $dlg = New-DialogoNueva -Carpetas (Get-CarpetasConocidas)
        $dlg.Owner = $script:ventana
        $dlg.ShowDialog() | Out-Null
    } catch { Write-Falla 'conversacion nueva' $_ }
}
