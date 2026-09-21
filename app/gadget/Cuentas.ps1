# =============================================================================
#  Cuentas.ps1 - el selector de cuentas de Claude Code
# -----------------------------------------------------------------------------
#  Una fila por cuenta conocida y un click la pone. La logica no vive aca: esto
#  solo dibuja y llama a lib-cuentas.ps1, que es lo que esta cubierto por tests.
#
#  Las cuentas aparecen solas: Get-Cuentas archiva la que este puesta cada vez
#  que se abre el dialogo. Loguearte una vez con cada una alcanza.
# =============================================================================

$script:xamlCuentas = @'
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
                    BorderThickness="1" Padding="{TemplateBinding Padding}">
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

    <!-- La fila de una cuenta: ancha, alineada a la izquierda y con el hover
         bien marcado, porque aca el hover ES la senal de que se puede clickear. -->
    <Style x:Key="Fila" TargetType="Button">
      <Setter Property="Background" Value="#12FFFFFF"/>
      <Setter Property="BorderBrush" Value="#1FFFFFFF"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="0,0,0,7"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="SnapsToDevicePixels" Value="True"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="marco" CornerRadius="9"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="1" Padding="12,9,13,10">
              <ContentPresenter HorizontalAlignment="Stretch" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="marco" Property="Background" Value="#22FFFFFF"/>
                <Setter TargetName="marco" Property="BorderBrush" Value="#3DFFFFFF"/>
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

  <Border x:Name="tarjeta" CornerRadius="14" Background="#161A20" Margin="13"
          BorderBrush="#2EFFFFFF" BorderThickness="1" Padding="19,17,19,17">
    <Border.Effect>
      <DropShadowEffect BlurRadius="28" ShadowDepth="0" Opacity="0.6" Color="#000000"/>
    </Border.Effect>
    <StackPanel>
      <StackPanel Orientation="Horizontal" Margin="0,0,0,5">
        <TextBlock x:Name="icono" FontSize="15" VerticalAlignment="Center" Margin="0,0,10,0"
                   FontFamily="Segoe MDL2 Assets" Foreground="#8A94A6"/>
        <TextBlock Text="Cuenta de Claude Code" Foreground="#F2F5F9" FontSize="13.5"
                   FontWeight="SemiBold" VerticalAlignment="Center"/>
      </StackPanel>

      <TextBlock x:Name="explicacion" Foreground="#8A94A6" FontSize="11.5"
                 TextWrapping="Wrap" Margin="0,0,0,14"/>

      <StackPanel x:Name="lista"/>

      <TextBlock x:Name="aviso" Foreground="#8A94A6" FontSize="11.5"
                 TextWrapping="Wrap" Margin="0,4,0,15"/>

      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="btnOtra" Content="Entrar con otra cuenta"
                Style="{StaticResource Chato}" Margin="0,0,9,0"/>
        <Button x:Name="btnCerrar" Content="Cerrar" Style="{StaticResource Chato}"
                IsDefault="True" IsCancel="True"/>
      </StackPanel>
    </StackPanel>
  </Border>
</Window>
'@

# El texto de la derecha de cada fila: en que estado esta esa cuenta.
function Get-EstadoCuenta($C) {
    if ($C.Activa) { return @{ Texto = 'en uso'; Color = '#86EFAC' } }
    if ($C.Vencida) { return @{ Texto = 'vencida'; Color = '#F87171' } }
    if ($null -eq $C.Dias) { return @{ Texto = ''; Color = '#8A94A6' } }
    if ($C.Dias -le 0) { return @{ Texto = 'vence hoy'; Color = '#FBBF24' } }
    if ($C.Dias -eq 1) { return @{ Texto = 'vence mañana'; Color = '#FBBF24' } }
    if ($C.Dias -le 3) { return @{ Texto = "vence en $($C.Dias) días"; Color = '#FBBF24' } }
    return @{ Texto = "vence en $($C.Dias) días"; Color = '#8A94A6' }
}

#  La linea de abajo del mail. Una cuenta personal tiene la organizacion
#  llamada "<mail>'s Organization": repetir el mail justo abajo del mail no
#  agrega nada, asi que en ese caso queda solo el plan.
function Get-SubtituloCuenta($Cta) {
    $org = [string]$Cta.Org
    if ($org -and $Cta.Mail -and $org.ToLowerInvariant().Contains(([string]$Cta.Mail).ToLowerInvariant())) {
        $org = ''
    }
    return ((@($org, $Cta.Plan) | Where-Object { $_ }) -join '  ·  ')
}

function New-FilaCuenta($C, $Estilo) {
    $b = New-Object Windows.Controls.Button
    $b.Tag = $C.Mail
    # Sin estilo WPF le pone el boton gris de Windows, y estos textos claros
    # quedan ilegibles encima. Se pasa desde afuera porque el recurso vive en
    # la Window, y esta funcion no la ve.
    if ($Estilo) { $b.Style = $Estilo }

    # $col y no $c: en PowerShell los nombres de variable NO distinguen
    # mayusculas, asi que un $c aca adentro pisa el parametro $C y la fila sale
    # vacia. Paso de verdad, y sin un solo error en consola.
    $g = New-Object Windows.Controls.Grid
    foreach ($ancho in ([Windows.GridLength]::Auto,
            [Windows.GridLength]::new(1, [Windows.GridUnitType]::Star),
            [Windows.GridLength]::Auto)) {
        $col = New-Object Windows.Controls.ColumnDefinition
        $col.Width = $ancho
        $g.ColumnDefinitions.Add($col)
    }

    $glifo = New-Object Windows.Controls.TextBlock
    $glifo.Text = [string][char]$(if ($C.Activa) { 0xE73E } else { 0xE77B })  # tilde / persona
    $glifo.FontFamily = New-Object Windows.Media.FontFamily -ArgumentList 'Segoe MDL2 Assets'
    $glifo.FontSize = 12
    $glifo.VerticalAlignment = 'Center'
    $glifo.Margin = [Windows.Thickness]::new(0, 0, 10, 0)
    $glifo.Foreground = Pincel $(if ($C.Activa) { '#4FA878' } elseif ($C.Vencida) { '#F87171' } else { '#8A94A6' })
    [Windows.Controls.Grid]::SetColumn($glifo, 0)
    $g.Children.Add($glifo) | Out-Null

    # El mail arriba y la org abajo: el mail es lo unico que distingue de verdad
    # una cuenta de otra, el displayName se repite.
    $textos = New-Object Windows.Controls.StackPanel
    $mail = New-Object Windows.Controls.TextBlock
    $mail.Text = $C.Mail
    $mail.Foreground = Pincel '#F2F5F9'
    $mail.FontSize = 12
    $mail.TextTrimming = 'CharacterEllipsis'
    $textos.Children.Add($mail) | Out-Null

    $abajo = Get-SubtituloCuenta $C
    if ($abajo) {
        $sub = New-Object Windows.Controls.TextBlock
        $sub.Text = $abajo
        $sub.Foreground = Pincel '#8A94A6'
        $sub.FontSize = 10.5
        $sub.Margin = [Windows.Thickness]::new(0, 1, 0, 0)
        $sub.TextTrimming = 'CharacterEllipsis'
        $textos.Children.Add($sub) | Out-Null
    }
    [Windows.Controls.Grid]::SetColumn($textos, 1)
    $g.Children.Add($textos) | Out-Null

    $e = Get-EstadoCuenta $C
    $est = New-Object Windows.Controls.TextBlock
    $est.Text = $e.Texto
    $est.Foreground = Pincel $e.Color
    $est.FontSize = 10.5
    $est.VerticalAlignment = 'Center'
    $est.Margin = [Windows.Thickness]::new(12, 0, 0, 0)
    [Windows.Controls.Grid]::SetColumn($est, 2)
    $g.Children.Add($est) | Out-Null

    $b.Content = $g
    if ($C.Activa) {
        # La que ya esta puesta no se puede clickear: no hay nada que cambiar, y
        # un boton que no hace nada se siente roto.
        $b.IsHitTestVisible = $false
        $b.Focusable = $false
        $b.Opacity = 0.72
    } else {
        $b.ToolTip = "Pasar a $($C.Mail)"
        $b.Add_Click({
                $v = [Windows.Window]::GetWindow($this)
                $v.Tag = $this.Tag
                $v.DialogResult = $true
            })
    }
    return $b
}

#  Devuelve @{ Accion = 'cambiar' | 'login' | 'nada'; Mail }. No hace el cambio:
#  quien decide que hacer con eso es Show-DialogoCuenta.
function Show-SelectorCuentas($Cuentas) {
    $d = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$script:xamlCuentas)))
    $d.FindName('icono').Text = [string][char]0xE77B

    # El nombre NO es libre: gadget.ps1 tiene su propio $lista (el StackPanel del
    # panel) al alcance de todo lo que llame, y el ShowDialog de abajo sigue
    # bombeando el timer de refresco. Con un $lista local aca, ese refresco
    # borraba las cuentas y pintaba las tarjetas ADENTRO de este dialogo.
    $filas = $d.FindName('lista')
    $estilo = $d.Resources['Fila']
    foreach ($c in $Cuentas) { $filas.Children.Add((New-FilaCuenta $c $estilo)) | Out-Null }

    $expl = $d.FindName('explicacion')
    $av = $d.FindName('aviso')
    if ($Cuentas.Count -le 1) {
        $expl.Text = 'Por ahora conozco una sola cuenta. Entrá con otra y desde ese momento vas a poder saltar entre las dos sin volver a loguearte.'
        $av.Visibility = 'Collapsed'
    } else {
        $expl.Text = 'Clickeá la cuenta que quieras usar.'
        $av.Text = 'Ojo: puede afectar también a las conversaciones que ya tenés abiertas. Si estás trabajando en una, cerrala y volvé a abrirla con la cuenta que quieras.'
    }

    $d.Owner = $ventana
    $d.FindName('btnOtra').Add_Click({
            $v = [Windows.Window]::GetWindow($this)
            $v.Tag = 'login'
            $v.DialogResult = $true
        })
    $d.FindName('tarjeta').Add_MouseLeftButtonDown({
            try { [Windows.Window]::GetWindow($this).DragMove() } catch { }
        })
    $d.Add_Loaded({ $this.FindName('btnCerrar').Focus() | Out-Null })

    if ($d.ShowDialog() -ne $true) { return @{ Accion = 'nada'; Mail = '' } }
    if ($d.Tag -ceq 'login') { return @{ Accion = 'login'; Mail = '' } }
    return @{ Accion = 'cambiar'; Mail = [string]$d.Tag }
}

#  Abre una terminal para loguearse. Con -NoExit porque el login imprime una URL
#  y un codigo: si la ventana se cierra sola, no se alcanza a leer nada.
function Open-LoginClaude {
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoExit', '-Command', 'claude auth login'
        return $true
    } catch {
        [Windows.MessageBox]::Show("No pude abrir la terminal:`n`n$($_.Exception.Message)",
            'Conversaciones') | Out-Null
        return $false
    }
}
