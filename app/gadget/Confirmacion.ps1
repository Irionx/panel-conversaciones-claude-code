# =============================================================================
#  Confirmacion.ps1 - el dialogo de confirmar, con la estetica del panel
# -----------------------------------------------------------------------------
#  MessageBox es el dialogo nativo de Win32: no se puede estilar y rompia la
#  estetica del gadget. Este usa la misma paleta que las tarjetas.
# =============================================================================

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
  <Border x:Name="tarjeta" CornerRadius="14" Background="#161A20" Margin="13"
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
