# =============================================================================
#  Etiquetas.ps1 - etiquetas de colores en la tarjeta, como las de un kanban
# -----------------------------------------------------------------------------
#  Las crea la persona y NO son los tags de /save: esos son para buscar y no se
#  ven. La base guarda la clave del color y no el hex, asi la paleta se retoca
#  aca sin migrar nada.
# =============================================================================

# Tonos 400 con texto oscuro: se leen sobre la tarjeta suelta y la bloqueada.
$script:PALETA_ETIQUETAS = [ordered]@{
    verde    = '#4ADE80'
    celeste  = '#22D3EE'
    azul     = '#60A5FA'
    violeta  = '#A78BFA'
    rosa     = '#F472B6'
    rojo     = '#F87171'
    naranja  = '#FB923C'
    amarillo = '#FACC15'
    gris     = '#94A3B8'
}

# Una clave que ya no esta en la paleta cae a gris en vez de romper la tarjeta.
function Get-ColorEtiqueta([string]$Clave) {
    if ($Clave -and $script:PALETA_ETIQUETAS.Contains($Clave)) { return $script:PALETA_ETIQUETAS[$Clave] }
    return $script:PALETA_ETIQUETAS['gris']
}

function New-ChipEtiqueta {
    param([Parameter(Mandatory)]$Etiqueta)

    $tx = New-Object Windows.Controls.TextBlock
    $tx.Text = [string]$Etiqueta.nombre
    $tx.FontSize = 9.5
    $tx.FontWeight = 'SemiBold'
    $tx.Foreground = Pincel '#10141A'

    $chip = New-Object Windows.Controls.Border
    $chip.CornerRadius = [Windows.CornerRadius]::new(4)
    $chip.Padding = [Windows.Thickness]::new(6, 1, 6, 2)
    $chip.Margin = [Windows.Thickness]::new(4, 2, 0, 0)
    $chip.Background = Pincel (Get-ColorEtiqueta $Etiqueta.color)
    $chip.Child = $tx
    return $chip
}

# La primera de la paleta que nadie usa, asi dos etiquetas nuevas no nacen iguales.
function Get-ColorLibre {
    $usados = @(@(Get-Etiqueta) | ForEach-Object { [string]$_.color })
    foreach ($k in $script:PALETA_ETIQUETAS.Keys) { if ($usados -notcontains $k) { return $k } }
    return 'verde'
}

# Lo llaman el boton y las etiquetas de la tarjeta. Redibuja solo si algo cambio.
function Open-EtiquetasTarjeta {
    param([Parameter(Mandatory)][hashtable]$Datos)
    try {
        if (Show-Etiquetas -Conversacion $Datos.conv -Titulo $Datos.titulo) { Actualizar }
    } catch { Write-Falla 'etiquetas' $_ }
}

function Show-Etiquetas {
    param([Parameter(Mandatory)]$Conversacion, [string]$Titulo = '')
    $d = New-DialogoEtiquetas -Conversacion $Conversacion -Titulo $Titulo
    $d.Owner = $ventana
    $d.ShowDialog() | Out-Null
    return [bool]$d.Tag.Cambio
}

# Arma el popup sin mostrarlo: asi los tests y el render a PNG lo pueden usar.
function New-DialogoEtiquetas {
    param([Parameter(Mandatory)]$Conversacion, [string]$Titulo = '')

    $x = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        SizeToContent="Height" Width="344" ShowInTaskbar="False" Topmost="True"
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
      <Setter Property="FontSize" Value="12"/>
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

  <Border x:Name="tarjeta" CornerRadius="14" Background="#161A20" Margin="13"
          BorderBrush="#2EFFFFFF" BorderThickness="1" Padding="17,15,17,15">
    <Border.Effect>
      <DropShadowEffect BlurRadius="28" ShadowDepth="0" Opacity="0.6" Color="#000000"/>
    </Border.Effect>
    <StackPanel>
      <StackPanel Orientation="Horizontal" Margin="0,0,0,3">
        <TextBlock Text="&#xE8EC;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="#A78BFA"
                   VerticalAlignment="Center" Margin="0,0,9,0"/>
        <TextBlock Text="Etiquetas" Foreground="#F2F5F9" FontSize="13.5" FontWeight="SemiBold"
                   VerticalAlignment="Center"/>
      </StackPanel>
      <TextBlock x:Name="nombre" Foreground="#8A94A6" FontSize="11" TextTrimming="CharacterEllipsis"
                 Margin="0,0,0,12"/>

      <Border CornerRadius="8" Background="#12FFFFFF" Padding="4" Margin="0,0,0,14">
        <StackPanel>
          <StackPanel x:Name="listaEtiquetas"/>
          <TextBlock x:Name="vacio" Text="Todavía no hay etiquetas. Creá la primera acá abajo."
                     Foreground="#6B7484" FontSize="11" TextWrapping="Wrap" Margin="7,6,7,6"/>
        </StackPanel>
      </Border>

      <TextBlock x:Name="tituloForm" Text="Nueva etiqueta" Foreground="#9AA4B5" FontSize="11"
                 FontWeight="SemiBold" Margin="0,0,0,6"/>
      <TextBox x:Name="txtNombre" Style="{StaticResource Caja}" MaxLength="24"/>
      <WrapPanel x:Name="paleta" Margin="0,9,0,0"/>
      <TextBlock x:Name="error" Foreground="#F87171" FontSize="11" TextWrapping="Wrap"
                 Margin="0,8,0,0" Visibility="Collapsed"/>

      <Grid Margin="0,14,0,0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel Orientation="Horizontal">
          <Button x:Name="btnCrear" Content="Crear" Style="{StaticResource Chato}" Margin="0,0,8,0"
                  Background="#3C4553" BorderBrush="#5A6473" Foreground="#F2F5F9"/>
          <Button x:Name="btnCancelarEdicion" Content="Cancelar" Style="{StaticResource Chato}"
                  Visibility="Collapsed"/>
        </StackPanel>
        <Button x:Name="btnListo" Grid.Column="1" Content="Listo" Style="{StaticResource Chato}"
                IsCancel="True"/>
      </Grid>
    </StackPanel>
  </Border>
</Window>
'@

    $d = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$x)))

    # Se relee de la base: el objeto de la tarjeta puede tener hasta 30 s.
    $actual = Get-Conversacion -Id ([string]$Conversacion.id)
    $marcadas = New-Object 'System.Collections.Generic.HashSet[long]'
    if ($actual) { foreach ($et in @($actual.etiquetas)) { [void]$marcadas.Add([long]$et.id) } }

    # El estado va en el Tag: los handlers no ven las variables de esta funcion.
    $d.Tag = @{
        Id       = [string]$Conversacion.id
        Marcadas = $marcadas
        Editando = $null
        Color    = (Get-ColorLibre)
        Cambio   = $false
    }
    $d.FindName('nombre').Text = $(if ($Titulo) { $Titulo } else { [string]$Conversacion.titulo })

    $txt = $d.FindName('txtNombre')
    $txt.Add_KeyDown({
            if ($args[1].Key -eq 'Return') {
                $args[1].Handled = $true
                Save-FormEtiqueta -Dialogo ([Windows.Window]::GetWindow($this))
            }
        })
    $txt.Add_TextChanged({ [Windows.Window]::GetWindow($this).FindName('error').Visibility = 'Collapsed' })
    $d.FindName('btnCrear').Add_Click({ Save-FormEtiqueta -Dialogo ([Windows.Window]::GetWindow($this)) })
    $d.FindName('btnCancelarEdicion').Add_Click({ Reset-FormEtiqueta -Dialogo ([Windows.Window]::GetWindow($this)) })
    $d.FindName('tarjeta').Add_MouseLeftButtonDown({
            try { [Windows.Window]::GetWindow($this).DragMove() } catch { }
        })
    $d.Add_Loaded({ $this.FindName('txtNombre').Focus() | Out-Null })

    Update-ListaEtiquetas -Dialogo $d
    Update-PaletaEtiquetas -Dialogo $d
    return $d
}

function Update-ListaEtiquetas {
    param([Parameter(Mandatory)]$Dialogo)
    $cont = $Dialogo.FindName('listaEtiquetas')
    $cont.Children.Clear()
    $todas = @(Get-Etiqueta)
    foreach ($et in $todas) { $cont.Children.Add((New-FilaEtiqueta -Etiqueta $et -Dialogo $Dialogo)) | Out-Null }
    $Dialogo.FindName('vacio').Visibility = $(if ($todas.Count) { 'Collapsed' } else { 'Visible' })
}

function New-FilaEtiqueta {
    param([Parameter(Mandatory)]$Etiqueta, [Parameter(Mandatory)]$Dialogo)

    $marcada = $Dialogo.Tag.Marcadas.Contains([long]$Etiqueta.id)

    $fila = New-Object Windows.Controls.Grid
    $fila.Background = [Windows.Media.Brushes]::Transparent
    $fila.Cursor = 'Hand'
    $fila.ToolTip = $(if ($marcada) { 'Sacársela a esta conversación' } else { 'Ponérsela a esta conversación' })
    foreach ($ancho in 'Auto', 'Star', 'Auto', 'Auto') {
        $columna = New-Object Windows.Controls.ColumnDefinition
        $columna.Width = $(if ($ancho -eq 'Star') {
                [Windows.GridLength]::new(1, [Windows.GridUnitType]::Star)
            } else { [Windows.GridLength]::Auto })
        $fila.ColumnDefinitions.Add($columna)
    }

    $caja = New-Object Windows.Controls.Border
    $caja.Width = 15; $caja.Height = 15
    $caja.CornerRadius = [Windows.CornerRadius]::new(4)
    $caja.BorderThickness = [Windows.Thickness]::new(1)
    $caja.Margin = [Windows.Thickness]::new(6, 0, 10, 0)
    $caja.VerticalAlignment = 'Center'
    if ($marcada) {
        $caja.Background = Pincel '#C7CEDA'
        $caja.BorderBrush = Pincel '#C7CEDA'
        $tilde = New-Object Windows.Controls.TextBlock
        $tilde.Text = [string][char]0xE73E
        $tilde.FontFamily = New-Object Windows.Media.FontFamily -ArgumentList 'Segoe MDL2 Assets'
        $tilde.FontSize = 9
        $tilde.Foreground = Pincel '#10141A'
        $tilde.HorizontalAlignment = 'Center'
        $tilde.VerticalAlignment = 'Center'
        $caja.Child = $tilde
    } else {
        $caja.BorderBrush = Pincel '#5A6473'
    }
    $fila.Children.Add($caja) | Out-Null

    $chip = New-ChipEtiqueta $Etiqueta
    $chip.Child.FontSize = 11
    $chip.Margin = [Windows.Thickness]::new(0, 5, 8, 5)
    $chip.HorizontalAlignment = 'Left'
    [Windows.Controls.Grid]::SetColumn($chip, 1)
    $fila.Children.Add($chip) | Out-Null

    $botones = @(
        @{ Glifo = 0xE70F; Tip = 'Editar nombre y color'; Hover = '#C7CEDA'; Col = 2; Borrar = $false }
        @{ Glifo = 0xE74D; Tip = 'Borrar la etiqueta'; Hover = '#F87171'; Col = 3; Borrar = $true }
    )
    foreach ($b in $botones) {
        $btn = New-Object Windows.Controls.Button
        $btn.Template = $script:tplPlano
        $btn.Content = [string][char]$b.Glifo
        $btn.FontFamily = New-Object Windows.Media.FontFamily -ArgumentList 'Segoe MDL2 Assets'
        $btn.Width = 24; $btn.Height = 24
        $btn.FontSize = 11
        $btn.Cursor = 'Hand'
        $btn.Background = [Windows.Media.Brushes]::Transparent
        $btn.Foreground = Pincel '#5A6473'
        $btn.ToolTip = $b.Tip
        $btn.Tag = @{ Etiqueta = $Etiqueta; Hover = $b.Hover }
        $btn.Add_MouseEnter({ $this.Foreground = Pincel $this.Tag.Hover })
        $btn.Add_MouseLeave({ $this.Foreground = Pincel '#5A6473' })
        if ($b.Borrar) {
            $btn.Add_Click({ Remove-EtiquetaDialogo -Dialogo ([Windows.Window]::GetWindow($this)) -Etiqueta $this.Tag.Etiqueta })
        } else {
            $btn.Add_Click({ Edit-FormEtiqueta -Dialogo ([Windows.Window]::GetWindow($this)) -Etiqueta $this.Tag.Etiqueta })
        }
        [Windows.Controls.Grid]::SetColumn($btn, $b.Col)
        $fila.Children.Add($btn) | Out-Null
    }

    $fila.Tag = [long]$Etiqueta.id
    $fila.Add_MouseEnter({ $this.Background = Pincel '#14FFFFFF' })
    $fila.Add_MouseLeave({ $this.Background = [Windows.Media.Brushes]::Transparent })
    # El Down se marca: si sube hasta la tarjeta, su DragMove se come el Up y el click no llega.
    $fila.Add_MouseLeftButtonDown({ $args[1].Handled = $true })
    $fila.Add_MouseLeftButtonUp({
            Switch-EtiquetaDialogo -Dialogo ([Windows.Window]::GetWindow($this)) -IdEtiqueta ([long]$this.Tag)
        })
    return $fila
}

function Update-PaletaEtiquetas {
    param([Parameter(Mandatory)]$Dialogo)
    $cont = $Dialogo.FindName('paleta')
    $cont.Children.Clear()
    foreach ($clave in $script:PALETA_ETIQUETAS.Keys) {
        $muestra = New-Object Windows.Controls.Border
        $muestra.Width = 22; $muestra.Height = 22
        $muestra.CornerRadius = [Windows.CornerRadius]::new(11)
        $muestra.Margin = [Windows.Thickness]::new(0, 0, 7, 0)
        $muestra.Background = Pincel $script:PALETA_ETIQUETAS[$clave]
        # Anillo claro en la elegida; las otras lo llevan del color del fondo para no cambiar de tamano.
        $muestra.BorderThickness = [Windows.Thickness]::new(2)
        $muestra.BorderBrush = Pincel $(if ($clave -eq $Dialogo.Tag.Color) { '#F2F5F9' } else { '#161A20' })
        $muestra.Cursor = 'Hand'
        $muestra.ToolTip = $clave
        $muestra.Tag = $clave
        $muestra.Add_MouseLeftButtonDown({ $args[1].Handled = $true })
        $muestra.Add_MouseLeftButtonUp({
                $dlg = [Windows.Window]::GetWindow($this)
                $dlg.Tag.Color = [string]$this.Tag
                Update-PaletaEtiquetas -Dialogo $dlg
            })
        $cont.Children.Add($muestra) | Out-Null
    }
}

function Show-ErrorEtiquetas {
    # Texto no es Mandatory: un [string] obligatorio vacio pide el valor por consola.
    param([Parameter(Mandatory)]$Dialogo, [string]$Texto = '')
    $err = $Dialogo.FindName('error')
    $err.Text = $Texto
    $err.Visibility = 'Visible'
}

function Switch-EtiquetaDialogo {
    param([Parameter(Mandatory)]$Dialogo, [Parameter(Mandatory)][long]$IdEtiqueta)
    $st = $Dialogo.Tag
    if (-not $st.Marcadas.Remove($IdEtiqueta)) { [void]$st.Marcadas.Add($IdEtiqueta) }
    try {
        Set-EtiquetaConversacion -Id $st.Id -Etiquetas @($st.Marcadas)
        $st.Cambio = $true
    } catch {
        # No se guardo: se deshace el tilde para no mostrar algo que la base no tiene.
        if (-not $st.Marcadas.Remove($IdEtiqueta)) { [void]$st.Marcadas.Add($IdEtiqueta) }
        Show-ErrorEtiquetas -Dialogo $Dialogo -Texto $_.Exception.Message
    }
    Update-ListaEtiquetas -Dialogo $Dialogo
}

function Edit-FormEtiqueta {
    param([Parameter(Mandatory)]$Dialogo, [Parameter(Mandatory)]$Etiqueta)
    $st = $Dialogo.Tag
    $st.Editando = [long]$Etiqueta.id
    $st.Color = [string]$Etiqueta.color
    $txt = $Dialogo.FindName('txtNombre')
    $txt.Text = [string]$Etiqueta.nombre
    $Dialogo.FindName('tituloForm').Text = 'Editar etiqueta'
    $Dialogo.FindName('btnCrear').Content = 'Guardar'
    $Dialogo.FindName('btnCancelarEdicion').Visibility = 'Visible'
    Update-PaletaEtiquetas -Dialogo $Dialogo
    $txt.Focus() | Out-Null
    $txt.SelectAll()
}

function Reset-FormEtiqueta {
    param([Parameter(Mandatory)]$Dialogo)
    $st = $Dialogo.Tag
    $st.Editando = $null
    $st.Color = Get-ColorLibre
    $Dialogo.FindName('txtNombre').Text = ''
    $Dialogo.FindName('tituloForm').Text = 'Nueva etiqueta'
    $Dialogo.FindName('btnCrear').Content = 'Crear'
    $Dialogo.FindName('btnCancelarEdicion').Visibility = 'Collapsed'
    $Dialogo.FindName('error').Visibility = 'Collapsed'
    Update-PaletaEtiquetas -Dialogo $Dialogo
}

function Save-FormEtiqueta {
    param([Parameter(Mandatory)]$Dialogo)
    $st = $Dialogo.Tag
    $nombre = ([string]$Dialogo.FindName('txtNombre').Text).Trim()
    if (-not $nombre) {
        Show-ErrorEtiquetas -Dialogo $Dialogo -Texto 'Ponele un nombre a la etiqueta.'
        return
    }
    try {
        if ($null -ne $st.Editando) {
            Set-Etiqueta -Id $st.Editando -Nombre $nombre -Color $st.Color
        } else {
            # Creada desde una tarjeta, ya queda puesta en esa tarjeta.
            $nueva = Add-Etiqueta -Nombre $nombre -Color $st.Color
            [void]$st.Marcadas.Add([long]$nueva)
            $st.Cambio = $true
            Set-EtiquetaConversacion -Id $st.Id -Etiquetas @($st.Marcadas)
        }
        $st.Cambio = $true
    } catch {
        Show-ErrorEtiquetas -Dialogo $Dialogo -Texto $_.Exception.Message
        Update-ListaEtiquetas -Dialogo $Dialogo
        return
    }
    Reset-FormEtiqueta -Dialogo $Dialogo
    Update-ListaEtiquetas -Dialogo $Dialogo
}

function Remove-EtiquetaDialogo {
    param([Parameter(Mandatory)]$Dialogo, [Parameter(Mandatory)]$Etiqueta)
    $usos = [int]$Etiqueta.usos
    $donde = if ($usos -eq 0) { 'Ninguna conversación la tiene puesta.' }
    elseif ($usos -eq 1) { 'Se saca de la conversación que la tiene.' }
    else { "Se saca de las $usos conversaciones que la tienen." }
    $p = @{
        Encabezado = 'Borrar etiqueta'
        Nombre     = [string]$Etiqueta.nombre
        Aviso      = "$donde Del panel queda respaldo en datos\conversaciones.db.bak"
        TextoOk    = 'Borrar'
        Peligro    = $true
    }
    if (-not (Show-Confirmacion @p)) { return }
    try {
        Remove-Etiqueta -Id ([long]$Etiqueta.id) | Out-Null
        [void]$Dialogo.Tag.Marcadas.Remove([long]$Etiqueta.id)
        $Dialogo.Tag.Cambio = $true
        if ($Dialogo.Tag.Editando -eq [long]$Etiqueta.id) { Reset-FormEtiqueta -Dialogo $Dialogo }
    } catch {
        Show-ErrorEtiquetas -Dialogo $Dialogo -Texto $_.Exception.Message
    }
    Update-ListaEtiquetas -Dialogo $Dialogo
}
