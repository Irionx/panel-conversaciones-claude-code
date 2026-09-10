# =============================================================================
#  Ayuda.ps1 - la ventana de "como funciona", con la estetica del panel
# -----------------------------------------------------------------------------
#  El contenido vive en $script:AYUDA como datos, no como XAML: asi se edita
#  como texto. Entre `backticks` va lo que se escribe (comandos), en verde.
# =============================================================================

# G = el glifo que se ve en el panel (o un tipo especial: punto, borde, asa,
# barra, o un numero de paso). F = fuente: mdl2, emoji o la normal.
$script:AYUDA = @(
    @{ Titulo = 'Guardar una conversación'; Filas = @(
            @{ G = '1'; T = 'Escribí `/save` en la conversación'
                D = 'Claude la guarda en este panel con un recap corto (qué están haciendo y qué falta) y notas.' }
            @{ G = '2'; T = 'Ponele nombre con `/rename`'
                D = 'El panel muestra ese nombre, y se actualiza solo si lo cambiás.' }
            @{ G = '3'; T = 'Guardá de nuevo cuando quieras'
                D = 'Otro `/save` en la misma conversación actualiza su tarjeta, nunca la duplica. El recap se reescribe.' }
            @{ G = '4'; T = 'Atajo sin IA: `! guardar`'
                D = 'Escrito en Claude Code, guarda al instante con el nombre de `/rename`, sin recap ni notas.' }
        )
    }
    @{ Titulo = 'Cada tarjeta'; Filas = @(
            @{ G = '•'; T = 'Click en la tarjeta'
                D = 'Abre la conversación en una terminal. Si ya está abierta, trae esa terminal al frente.' }
            @{ G = [char]0x201C; T = 'Recap'
                D = 'Lo escribe `/save`. Mientras no haya, se ve tu último pedido, en cursiva.' }
            @{ G = 'barra'; T = 'Barra de contexto'
                D = 'Cuánto de la ventana de contexto lleva esa conversación. Ámbar al 60%, roja al 85%.' }
            @{ G = '~'; T = 'Ese % es exacto sólo con claude-hud'
                D = 'Ese plugin es el que sabe el tamaño real de la ventana de contexto; sin él hay que adivinarlo y el % puede errar mucho. Se instala en una terminal con `claude plugin marketplace add jarrodwatts/claude-hud` y después `claude plugin install claude-hud@claude-hud`. Reiniciá Claude Code y listo.' }
            @{ G = 'punto'; T = 'Punto azul'
                D = 'La conversación está abierta en una terminal.' }
            @{ G = 'borde'; T = 'Borde iluminado y un reflejo'
                D = 'Claude está trabajando en esa conversación: el borde se ilumina y cada tanto la cruza un reflejo.' }
            @{ G = '•'; T = 'Proyecto y rama'
                D = 'La rama es la que tenía la carpeta cuando guardaste.' }
        )
    }
    @{ Titulo = 'Botones de la tarjeta'; Filas = @(
            @{ G = [char]0xE701; F = 'mdl2'; C = '#4ADE80'; T = 'Remote Control'
                D = 'Verde: la conversación está disponible en el celular. Click para abrirla con Remote Control.' }
            @{ G = [char]0xE7B8; F = 'mdl2'; T = 'Archivar'
                D = 'La esconde del panel sin borrar nada. Se recupera desde el archivo (los libros de arriba).' }
            @{ G = [char]0x2715; T = 'Quitar del panel'
                D = 'Saca la tarjeta, pero la conversación sigue en disco: la podés volver a guardar.' }
            @{ G = [char]0xE74D; F = 'mdl2'; C = '#F87171'; T = 'Borrar'
                D = 'Borra el transcript. No se puede deshacer: después no hay `--resume`.' }
            @{ G = 'asa'; T = 'Ordenar'
                D = 'Arrastrá de los seis puntitos para cambiar el orden. El orden se guarda.' }
        )
    }
    @{ Titulo = 'La barra de arriba'; Filas = @(
            @{ G = 'barra'; T = 'Cuota de tu cuenta'
                D = 'Diario es la ventana de 5 horas y semanal la de 7 días. El ↻ marca cuándo se renueva cada una.' }
            @{ G = [char]0xE77B; F = 'mdl2'; C = '#86EFAC'; T = 'Tu cuenta'
                D = 'Click para ver el detalle o cambiarla. Es una sola para todas las conversaciones: cambiarla afecta también a las abiertas.' }
            @{ G = [char]::ConvertFromUtf32(0x1F513); F = 'emoji'; T = 'Candado'
                D = 'Fija la posición y deja el panel en modo discreto, sin fondo.' }
            @{ G = [char]0xE842; F = 'mdl2'; C = '#4ADE80'; T = 'Siempre arriba'
                D = 'Verde: el panel queda por encima de las demás ventanas.' }
            @{ G = [char]0xE8F1; F = 'mdl2'; T = 'Archivo'
                D = 'Muestra las conversaciones archivadas. Se pone ámbar mientras estás adentro.' }
        )
    }
    @{ Titulo = 'La ventana'; Filas = @(
            @{ G = '•'; T = 'Mover y estirar'
                D = 'Se mueve desde la barra del título. Los costados cambian el ancho; el borde de abajo, cuánta lista se ve.' }
            @{ G = '•'; T = 'Se actualiza sola'
                D = 'Cada 30 segundos, y apenas una conversación trae datos nuevos.' }
            @{ G = '•'; T = 'Tus datos'
                D = 'Todo vive en `datos\conversaciones.db`. Para hacer un backup, copiá ese archivo.' }
        )
    }
)

# Texto con los `comandos` en Consolas y verde.
function New-TextoAyuda([string]$Texto, [double]$Tamano, [string]$Color, [switch]$Negrita) {
    $tb = New-Object Windows.Controls.TextBlock
    $tb.TextWrapping = 'Wrap'
    $tb.FontSize = $Tamano
    $tb.Foreground = Pincel $Color
    if ($Negrita) { $tb.FontWeight = 'SemiBold' }
    $partes = $Texto -split '`'
    for ($i = 0; $i -lt $partes.Count; $i++) {
        if (-not $partes[$i]) { continue }
        $r = [Windows.Documents.Run]::new($partes[$i])
        if ($i % 2 -eq 1) {
            $r.FontFamily = New-Object Windows.Media.FontFamily -ArgumentList 'Consolas'
            $r.Foreground = Pincel '#86EFAC'
        }
        $tb.Inlines.Add($r)
    }
    return $tb
}

# El glifo de una fila: el mismo que se ve en el panel, para reconocerlo.
function New-GlifoAyuda($Fila) {
    $g = [string]$Fila.G
    switch ($g) {
        'punto' {
            $e = New-Object Windows.Shapes.Ellipse
            $e.Width = 7; $e.Height = 7; $e.Fill = Pincel '#60A5FA'
            return $e
        }
        'borde' {
            $r = New-Object Windows.Shapes.Rectangle
            $r.Width = 15; $r.Height = 11; $r.RadiusX = 3; $r.RadiusY = 3
            $r.StrokeThickness = 1.6; $r.Stroke = Pincel '#4ADE80'
            return $r
        }
        'barra' {
            $b = New-Object Windows.Controls.StackPanel
            $b.Orientation = 'Horizontal'
            foreach ($p in @(@(9, '#4ADE80'), @(7, '#33FFFFFF'))) {
                $r = New-Object Windows.Controls.Border
                $r.Width = $p[0]; $r.Height = 4; $r.CornerRadius = New-Object Windows.CornerRadius(2)
                $r.Background = Pincel $p[1]
                $b.Children.Add($r) | Out-Null
            }
            return $b
        }
        'asa' {
            $a = New-Object Windows.Controls.Grid
            $a.Width = 10; $a.Height = 15
            foreach ($fila in 0..2) {
                foreach ($col in 0..1) {
                    $p = New-Object Windows.Shapes.Ellipse
                    $p.Width = 3; $p.Height = 3; $p.Fill = Pincel '#8A94A6'
                    $p.HorizontalAlignment = 'Left'; $p.VerticalAlignment = 'Top'
                    $p.Margin = [Windows.Thickness]::new(1 + $col * 5, 1 + $fila * 5, 0, 0)
                    $a.Children.Add($p) | Out-Null
                }
            }
            return $a
        }
    }
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = $g
    $t.HorizontalAlignment = 'Center'
    if ($g -match '^\d$') {
        # Paso numerado: verde y en negrita, es la guia para empezar.
        $t.FontWeight = 'Bold'; $t.FontSize = 12; $t.Foreground = Pincel '#4ADE80'
        return $t
    }
    $t.FontSize = 12
    $t.Foreground = Pincel $(if ($Fila.C) { $Fila.C } else { '#8A94A6' })
    if ($Fila.F -eq 'mdl2') { $t.FontFamily = New-Object Windows.Media.FontFamily -ArgumentList 'Segoe MDL2 Assets' }
    elseif ($Fila.F -eq 'emoji') { $t.FontFamily = New-Object Windows.Media.FontFamily -ArgumentList 'Segoe UI Emoji'; $t.FontSize = 11 }
    return $t
}

function New-VentanaAyuda {
    $x = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        SizeToContent="Height" Width="490" ShowInTaskbar="False" Topmost="True"
        ResizeMode="NoResize" WindowStartupLocation="CenterOwner" FontFamily="Segoe UI">
  <Border CornerRadius="14" Background="#161A20" Margin="13" BorderBrush="#2EFFFFFF"
          BorderThickness="1" Padding="19,16,6,16">
    <Border.Effect>
      <DropShadowEffect BlurRadius="28" ShadowDepth="0" Opacity="0.6" Color="#000000"/>
    </Border.Effect>
    <DockPanel>
      <StackPanel x:Name="cabeza" DockPanel.Dock="Top" Orientation="Horizontal"
                  Margin="0,0,13,4" Background="Transparent" Cursor="SizeAll">
        <TextBlock Text="&#xE946;" FontFamily="Segoe MDL2 Assets" FontSize="15" Foreground="#4ADE80"
                   VerticalAlignment="Center" Margin="0,0,10,0"/>
        <TextBlock Text="Cómo funciona" Foreground="#F2F5F9" FontSize="13.5" FontWeight="SemiBold"
                   VerticalAlignment="Center"/>
      </StackPanel>
      <Button x:Name="btnOk" DockPanel.Dock="Bottom" Content="Entendido" HorizontalAlignment="Right"
              Margin="0,12,13,0" IsDefault="True" IsCancel="True" Cursor="Hand"
              Foreground="#C7CEDA" FontSize="12">
        <Button.Template>
          <ControlTemplate TargetType="Button">
            <Border x:Name="marco" CornerRadius="7" Background="#1AFFFFFF" BorderBrush="#2EFFFFFF"
                    BorderThickness="1" Padding="17,7,17,8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="marco" Property="Opacity" Value="0.78"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Button.Template>
      </Button>
      <ScrollViewer x:Name="sv" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"
                    Padding="0,0,20,0">
        <StackPanel x:Name="contenido"/>
      </ScrollViewer>
    </DockPanel>
  </Border>
</Window>
'@
    $d = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$x)))

    # La version sale del archivo VERSION que el build deja en la raiz. Corriendo
    # desde el repo ese archivo no existe y no se muestra nada: mejor sin numero
    # que con uno inventado. Es el unico lugar de la app donde se ve la version,
    # y sirve para cuando alguien escribe "no me anda" desde otra maquina.
    $ver = ''
    try {
        $fv = Join-Path $raiz 'VERSION'
        if (Test-Path -LiteralPath $fv) {
            $ver = ([string](Get-Content -LiteralPath $fv -TotalCount 1)).Trim()
        }
    } catch { }
    if ($ver) {
        $tv = New-Object Windows.Controls.TextBlock
        $tv.Text = 'v' + $ver
        $tv.Foreground = Pincel '#6B7385'
        $tv.FontSize = 11
        $tv.VerticalAlignment = 'Bottom'
        $tv.Margin = [Windows.Thickness]::new(8, 0, 0, 1)
        $d.FindName('cabeza').Children.Add($tv) | Out-Null
    }

    # La misma barra de scroll fina y superpuesta del panel, no la gris de Windows.
    $sv = $d.FindName('sv')
    $sv.Style = $ventana.Resources['ScrollSuperpuesto']
    $sv.MaxHeight = [math]::Min(560, [Windows.SystemParameters]::WorkArea.Height - 190)

    $cont = $d.FindName('contenido')
    foreach ($sec in $script:AYUDA) {
        $h = New-TextoAyuda $sec.Titulo 11.5 '#4ADE80' -Negrita
        $h.Margin = [Windows.Thickness]::new(0, 14, 0, 6)
        $cont.Children.Add($h) | Out-Null
        foreach ($f in $sec.Filas) {
            $g = New-Object Windows.Controls.Grid
            $g.Margin = [Windows.Thickness]::new(0, 0, 0, 9)
            $c0 = New-Object Windows.Controls.ColumnDefinition; $c0.Width = New-Object Windows.GridLength(28)
            $c1 = New-Object Windows.Controls.ColumnDefinition
            $g.ColumnDefinitions.Add($c0); $g.ColumnDefinitions.Add($c1)

            $gl = New-GlifoAyuda $f
            $gl.VerticalAlignment = 'Top'
            $gl.HorizontalAlignment = 'Center'
            $gl.Margin = [Windows.Thickness]::new(0, 3, 0, 0)
            $g.Children.Add($gl) | Out-Null

            $txt = New-Object Windows.Controls.StackPanel
            $txt.Children.Add((New-TextoAyuda $f.T 12 '#E6EAF0' -Negrita)) | Out-Null
            $desc = New-TextoAyuda $f.D 11 '#8A94A6'
            $desc.Margin = [Windows.Thickness]::new(0, 1, 0, 0)
            $txt.Children.Add($desc) | Out-Null
            [Windows.Controls.Grid]::SetColumn($txt, 1)
            $g.Children.Add($txt) | Out-Null
            $cont.Children.Add($g) | Out-Null
        }
    }
    # El primer titulo no necesita el aire de arriba: lo pone la cabecera.
    $cont.Children[0].Margin = [Windows.Thickness]::new(0, 6, 0, 6)

    $d.FindName('cabeza').Add_MouseLeftButtonDown({ $d.DragMove() }.GetNewClosure())
    $d.FindName('btnOk').Add_Click({ $d.Close() }.GetNewClosure())
    return $d
}

# Aparte de New-VentanaAyuda para poder armarla sin mostrarla (render, tests).
function Show-Ayuda {
    $d = New-VentanaAyuda
    $d.Owner = $ventana
    $d.ShowDialog() | Out-Null
}
