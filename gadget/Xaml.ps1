# =============================================================================
#  Xaml.ps1 - la ventana, en XAML
# -----------------------------------------------------------------------------
#  Solo define $xaml. Lo carga gadget.ps1, que es el unico que instancia la
#  ventana. Estan aca los estilos propios de la barra de scroll: ver el
#  comentario de ScrollFino, que explica por que va superpuesta.
# =============================================================================

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
