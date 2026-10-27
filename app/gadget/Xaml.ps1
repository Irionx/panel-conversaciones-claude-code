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
        Title="Hilos de Claudio" Width="348" SizeToContent="Height"
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
      <!-- MinWidth 0 NO es de adorno: el tema de WPF le pone de MinWidth el
           ancho de scrollbar del sistema (~17px), y MinWidth le gana a Width.
           Sin esto la barra mide 17 aunque el Setter de arriba pida 8, y como
           la pastilla va centrada DENTRO de la barra, termina montada sobre las
           tarjetas en vez de quedar en el canal. -->
      <Setter Property="MinWidth" Value="0"/>
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
    <!-- El tilde del historial. Chico y oscuro: la casilla de Windows es clara
         y sobre el panel parece un agujero. -->
    <Style x:Key="ChkFino" TargetType="CheckBox">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <Border x:Name="caja" Width="13" Height="13" CornerRadius="3"
                    Background="#12FFFFFF" BorderBrush="#3A4150" BorderThickness="1">
              <TextBlock x:Name="tilde" Text="&#xE73E;" FontFamily="Segoe MDL2 Assets" FontSize="9"
                         Foreground="#0B0F14" HorizontalAlignment="Center" VerticalAlignment="Center"
                         Visibility="Collapsed"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="caja" Property="Background" Value="#4ADE80"/>
                <Setter TargetName="caja" Property="BorderBrush" Value="#4ADE80"/>
                <Setter TargetName="tilde" Property="Visibility" Value="Visible"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="caja" Property="BorderBrush" Value="#8A94A6"/>
              </Trigger>
            </ControlTemplate.Triggers>
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
                         HorizontalAlignment="Right" Margin="0,2,3,2"
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
    <Border x:Name="fondo" CornerRadius="10" Background="#161A20" Margin="12"
            BorderBrush="#2EFFFFFF" BorderThickness="1" Padding="14,12,14,12">
      <StackPanel>
        <StackPanel x:Name="cabecera" Margin="0,0,0,10">
          <!-- BARRA DE TITULO, estilo Windows: icono y nombre a la izquierda,
               botones a la derecha. De ACA se arrastra la ventana. Antes el
               arrastre estaba en toda la cabecera, asi que para mover el panel
               habia que agarrarlo justo de las barritas de la cuota.
               El Background="Transparent" NO es de adorno: sin pincel el hueco
               del medio no recibe el mouse y solo se podria arrastrar apoyando
               el cursor exactamente sobre el texto. -->
          <Grid x:Name="barraTitulo" Background="Transparent">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <!-- Bloqueado esto se esconde (lo hace Set-Apariencia): el nombre es
                 decoracion, y sobre el escritorio pelado no se leeria. -->
            <DockPanel x:Name="chipTitulo" Grid.Column="0" VerticalAlignment="Center">
              <!-- El Source lo pone Set-IconoVentana: es el MISMO bitmap que el
                   icono de la ventana, no se decodifica el .ico dos veces. -->
              <Image x:Name="logo" DockPanel.Dock="Left" Width="14" Height="14" Margin="1,0,7,0"/>
              <TextBlock DockPanel.Dock="Left" Text="Hilos de Claudio" FontSize="11.5" FontWeight="SemiBold"
                         Foreground="#C6CEDA" VerticalAlignment="Center"/>
            </DockPanel>
            <!-- Bloqueado, los botones quedan flotando sobre el escritorio y no
                 se leen. Este Border se convierte en una tarjeta miniatura para
                 darles fondo; desbloqueado queda invisible. Lo maneja
                 Set-Apariencia. -->
            <Border x:Name="chipBotones" Grid.Column="1" CornerRadius="9">
              <StackPanel Orientation="Horizontal">
                <Button x:Name="btnCandado" Content="&#128275;" Width="22" Height="22" Margin="2,0,0,0"
                        ToolTip="Bloquear posicion" Cursor="Hand" FontFamily="Segoe UI Emoji"
                        Background="Transparent" BorderThickness="0" Foreground="#8A94A6" FontSize="11"/>
                <Button x:Name="btnArriba" Width="22" Height="22" Margin="2,0,0,0"
                        Cursor="Hand" FontFamily="Segoe MDL2 Assets"
                        Background="Transparent" BorderThickness="0" Foreground="#8A94A6" FontSize="11"/>
                <!-- E8F1 = los libros del archivo. Alterna entre el panel normal y
                     las archivadas; se enciende cuando estas en el archivo. -->
                <Button x:Name="btnArchivadas" Content="&#xE8F1;" Width="22" Height="22" Margin="2,0,0,0"
                        Cursor="Hand" FontFamily="Segoe MDL2 Assets"
                        Background="Transparent" BorderThickness="0" Foreground="#8A94A6" FontSize="11"/>
                <!-- E81C = el reloj de la historia. Todas las conversaciones de
                     Claude que hay en disco, esten guardadas en el panel o no.
                     Comparte el cajon con el archivo: uno abre y el otro cierra. -->
                <Button x:Name="btnHistorial" Content="&#xE81C;" Width="22" Height="22" Margin="2,0,0,0"
                        Cursor="Hand" FontFamily="Segoe MDL2 Assets"
                        Background="Transparent" BorderThickness="0" Foreground="#8A94A6" FontSize="11"/>
                <!-- Info en lugar de refrescar: el panel ya se actualiza solo. -->
                <Button x:Name="btnInfo" Content="&#xE946;" Width="22" Height="22" Margin="2,0,0,0"
                        ToolTip="Cómo funciona" Cursor="Hand" FontFamily="Segoe MDL2 Assets"
                        Background="Transparent" BorderThickness="0" Foreground="#8A94A6" FontSize="12"/>
                <!-- Colapsar: deja solo la cabecera, sin irse a la barra de
                     tareas. El glifo lo da vuelta Set-Apariencia. -->
                <Button x:Name="btnColapsar" Content="&#xE70E;" Width="22" Height="22" Margin="2,0,0,0"
                        Cursor="Hand" FontFamily="Segoe MDL2 Assets"
                        Background="Transparent" BorderThickness="0" Foreground="#8A94A6" FontSize="10"/>
                <Button x:Name="btnMinimizar" Content="&#xE921;" Width="22" Height="22" Margin="2,0,0,0"
                        ToolTip="Minimizar a la barra de tareas" Cursor="Hand" FontFamily="Segoe MDL2 Assets"
                        Background="Transparent" BorderThickness="0" Foreground="#8A94A6" FontSize="10"/>
                <Button x:Name="btnCerrar" Content="&#10005;" Width="22" Height="22" Margin="2,0,0,0"
                        ToolTip="Cerrar" Cursor="Hand"
                        Background="Transparent" BorderThickness="0" Foreground="#8A94A6" FontSize="11"/>
              </StackPanel>
            </Border>
          </Grid>

          <!-- LAS DOS CUENTAS con las que estas trabajando, juntas y a la
               izquierda. Antes la de Claude vivia en la barra de titulo y un
               mail largo peleaba con los siete botones. La de gh esta porque es
               GLOBAL de la maquina y otra sesion te la puede dar vuelta: verla
               es enterarte antes y no despues.
               MaxWidth en la de Claude y no columnas elasticas: medido, las dos
               juntas son 233 de los 294 utiles, pero un mail mas largo empujaria
               al gato fuera del renglon. Con el techo, recorta el mail (lo hace
               el DockPanel de Set-ChipCuenta) y el gato no se mueve. -->
          <Grid x:Name="filaCuentas" Margin="0,7,0,0">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <Button x:Name="btnCuenta" Grid.Column="0" Cursor="Hand" VerticalAlignment="Center"
                    HorizontalAlignment="Left" MaxWidth="190"
                    Background="Transparent" BorderThickness="0"/>
            <Button x:Name="btnGitHub" Grid.Column="1" Cursor="Hand" VerticalAlignment="Center"
                    HorizontalAlignment="Left" Margin="12,0,0,0"
                    Background="Transparent" BorderThickness="0"/>
          </Grid>
          <!-- La cuota real de la cuenta: las dos ventanas, diario (5h) y semanal
               (7d), UNA AL LADO DE LA OTRA en un solo renglon. Las dos y no
               solo la mayor, porque son los dos numeros que muestra el
               statusline y asi no hay forma de que dejen de coincidir. Lo llena
               Set-Resumen en cada refresco. -->
          <Border x:Name="chipResumen" CornerRadius="9" Margin="0,8,0,0">
            <Grid>
              <!-- Las dos mitades y el cartel de "sin datos" comparten la celda
                   y se muestra una cosa o la otra: el cartel necesita el ancho
                   COMPLETO, que es justo lo que no tiene una mitad. -->
              <Grid x:Name="cuotaFilas">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="14"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <!-- Cada mitad: nombre con el %, la barra, y a que hora
                     resetea. La barra va en la columna * , asi se estira sola
                     al ensanchar la ventana y es lo primero que cede cuando el
                     panel se angosta (el texto no se recorta nunca). -->
                <Grid Grid.Column="0">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>
                  <TextBlock x:Name="cuotaNom1" Grid.Column="0" FontSize="11"
                             FontWeight="SemiBold" Foreground="#F2F5F9" VerticalAlignment="Center"/>
                  <Grid x:Name="cuotaBarra1" Grid.Column="1" Height="4" MinWidth="10"
                        VerticalAlignment="Center" Margin="6,1,6,0">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="0.001*"/>
                      <ColumnDefinition Width="100*"/>
                    </Grid.ColumnDefinitions>
                    <Border x:Name="cuotaLleno1" Grid.Column="0" CornerRadius="2" Background="#4ADE80"/>
                    <Border Grid.Column="1" CornerRadius="2" Background="#22FFFFFF" Margin="1,0,0,0"/>
                  </Grid>
                  <TextBlock x:Name="cuotaReset1" Grid.Column="2" FontSize="9.5"
                             Foreground="#6B7484" VerticalAlignment="Center"/>
                </Grid>

                <Grid Grid.Column="2">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>
                  <TextBlock x:Name="cuotaNom2" Grid.Column="0" FontSize="11"
                             FontWeight="SemiBold" Foreground="#F2F5F9" VerticalAlignment="Center"/>
                  <Grid x:Name="cuotaBarra2" Grid.Column="1" Height="4" MinWidth="10"
                        VerticalAlignment="Center" Margin="6,1,6,0">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="0.001*"/>
                      <ColumnDefinition Width="100*"/>
                    </Grid.ColumnDefinitions>
                    <Border x:Name="cuotaLleno2" Grid.Column="0" CornerRadius="2" Background="#4ADE80"/>
                    <Border Grid.Column="1" CornerRadius="2" Background="#22FFFFFF" Margin="1,0,0,0"/>
                  </Grid>
                  <TextBlock x:Name="cuotaReset2" Grid.Column="2" FontSize="9.5"
                             Foreground="#6B7484" VerticalAlignment="Center"/>
                </Grid>
              </Grid>

              <TextBlock x:Name="cuotaVacio" Text="sin datos de cuota" FontSize="11"
                         FontWeight="SemiBold" Foreground="#8A94A6"
                         VerticalAlignment="Center" Visibility="Collapsed"/>
            </Grid>
          </Border>
        </StackPanel>

        <!-- MaxHeight y no Height: con SizeToContent="Height" la ventana se
             ajusta al contenido, asi que esto es "hasta donde puede crecer".
             Lo mueve el grip de abajo y se guarda en gadget-posicion.json. -->
        <!-- El CANAL de la barra de scroll sale del padding derecho del PANEL,
             no del ancho de las tarjetas: el margen negativo estira el
             ScrollViewer hasta el borde y el Padding le devuelve el lugar al
             contenido. Asi las tarjetas terminan donde termina la cabecera.
             Antes el canal se le cobraba al contenido (Padding 20 sin margen) y
             las tarjetas quedaban 20px mas cortas que el titulo, la cuota y el
             pie: un escalon visible en todo el lado derecho.
             Los dos valores los reescribe Set-Apariencia, porque el padding del
             panel cambia entre suelto y bloqueado. -->
        <!-- EL CAJON. El archivo y el historial NO reemplazan la lista: se abren
             a la derecha y se ven las dos a la vez. La columna izquierda es la
             de siempre; la derecha nace en 0 y la abre Set-Cajon animando a la
             par el ancho del cajon y el de la ventana.
             El Margin="14" del cajon es el MISMO canal donde vive la barra de
             scroll de la izquierda (el Margin -14 del scroller lo invade a
             proposito), asi que abrir el cajon no mueve ni un pixel la lista. -->
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>

          <ScrollViewer x:Name="scroller" Grid.Column="0" MaxHeight="520" Margin="0,0,-14,0" Padding="0,0,14,0"
                        VerticalScrollBarVisibility="Auto"
                        HorizontalScrollBarVisibility="Disabled"
                        Style="{StaticResource ScrollSuperpuesto}">
            <StackPanel x:Name="lista"/>
          </ScrollViewer>

          <!-- ClipToBounds: mientras el ancho se anima desde 0, el contenido ya
               mide lo suyo y sin recorte se desbordaria sobre la lista. -->
          <Grid x:Name="cajon" Grid.Column="1" Width="0" Visibility="Collapsed" ClipToBounds="True">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>   <!-- titulo -->
              <RowDefinition Height="Auto"/>   <!-- buscador y orden -->
              <RowDefinition Height="Auto"/>   <!-- las tildadas -->
              <RowDefinition Height="*"/>      <!-- la lista -->
            </Grid.RowDefinitions>
            <!-- El canal de 14 va ADENTRO del ancho animado, no en un Margin del
                 cajon: un Margin no entra en ActualWidth, asi que al pasar de
                 Collapsed a Visible la ventana pegaria un salto seco de 14px
                 antes de que la animacion arranque. -->
            <Grid Grid.Row="0" Margin="14,0,0,8">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <TextBlock x:Name="cajonTitulo" Grid.Column="0" Foreground="#C6CEDA" FontSize="11"
                         FontWeight="SemiBold" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
              <Button x:Name="btnCajonCerrar" Grid.Column="1" Content="&#10005;" Width="18" Height="18"
                      ToolTip="Cerrar el cajón" Cursor="Hand" Background="Transparent"
                      BorderThickness="0" Foreground="#5A6473" FontSize="10"/>
            </Grid>
            <!-- BUSCADOR Y ORDEN, solo para el historial. -->
            <Grid x:Name="cajonBarra" Grid.Row="1" Margin="14,0,0,8" Visibility="Collapsed">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <Border Grid.Column="0" Background="#12FFFFFF" CornerRadius="7" Padding="7,3,7,3">
                <Grid>
                  <TextBlock x:Name="cajonBuscarGuia" Text="Buscar por nombre…" Foreground="#5A6473"
                             FontSize="11" IsHitTestVisible="False" VerticalAlignment="Center"/>
                  <TextBox x:Name="cajonBuscar" Background="Transparent" BorderThickness="0"
                           Foreground="#C7CEDA" CaretBrush="#4ADE80" FontSize="11" VerticalAlignment="Center"/>
                </Grid>
              </Border>
              <!-- E8CB = ordenar. El que esta activo se enciende. -->
              <Button x:Name="btnOrdenFecha" Content="&#xE787;" Width="22" Height="22" Margin="5,0,0,0"
                      ToolTip="Ordenar por fecha" Cursor="Hand" FontFamily="Segoe MDL2 Assets"
                      Grid.Column="1" Background="Transparent" BorderThickness="0" Foreground="#8A94A6" FontSize="11"/>
              <Button x:Name="btnOrdenPeso" Content="&#xE9F9;" Width="22" Height="22" Margin="2,0,0,0"
                      ToolTip="Ordenar por tamaño" Cursor="Hand" FontFamily="Segoe MDL2 Assets"
                      Grid.Column="2" Background="Transparent" BorderThickness="0" Foreground="#8A94A6" FontSize="11"/>
            </Grid>

            <!-- Aparece sola cuando hay algo tildado. -->
            <Border x:Name="cajonSeleccion" Grid.Row="2" Margin="14,0,0,8" Visibility="Collapsed"
                    Background="#1AEF4444" CornerRadius="7" Padding="8,4,5,4">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock x:Name="cajonSelTexto" Grid.Column="0" Foreground="#C7CEDA" FontSize="11"
                           VerticalAlignment="Center"/>
                <Button x:Name="btnSelNada" Grid.Column="1" Content="Ninguna" Cursor="Hand" FontSize="10"
                        Background="Transparent" BorderThickness="0" Foreground="#8A94A6" Margin="0,0,6,0"/>
                <Button x:Name="btnSelBorrar" Grid.Column="2" Content="&#xE74D;" Width="22" Height="22"
                        ToolTip="Borrar todas las tildadas" Cursor="Hand" FontFamily="Segoe MDL2 Assets"
                        Background="Transparent" BorderThickness="0" Foreground="#F87171" FontSize="11"/>
              </Grid>
            </Border>

            <!-- ListBox y NO un StackPanel adentro de un ScrollViewer: el
                 StackPanel no virtualiza, asi que con 100 sesiones media y
                 dibujaba las 100 para mostrar 8. Medido: 68 ms por relayout, o
                 sea 15 fps de techo mientras el cajon se abre.
                 El ListBox trae VirtualizingStackPanel y su propio ScrollViewer,
                 que es lo que la virtualizacion necesita: un ItemsControl
                 adentro de un ScrollViewer externo recibe alto infinito y no
                 virtualiza nada. El Template le pone NUESTRA barra fina. -->
            <ListBox x:Name="listaCajon" Grid.Row="3" MaxHeight="520" Margin="14,0,0,0"
                     Background="Transparent" BorderThickness="0" Focusable="False"
                     VirtualizingStackPanel.IsVirtualizing="True"
                     VirtualizingStackPanel.VirtualizationMode="Recycling"
                     ScrollViewer.CanContentScroll="True">
              <ListBox.Template>
                <ControlTemplate TargetType="ListBox">
                  <ScrollViewer Style="{StaticResource ScrollSuperpuesto}" CanContentScroll="True"
                                Padding="0,0,8,0" VerticalScrollBarVisibility="Auto"
                                HorizontalScrollBarVisibility="Disabled">
                    <ItemsPresenter/>
                  </ScrollViewer>
                </ControlTemplate>
              </ListBox.Template>
              <!-- Sin el chrome del ListBoxItem: la seleccion la llevan los
                   tildes de cada tarjeta, no el resaltado del sistema. -->
              <ListBox.ItemContainerStyle>
                <Style TargetType="ListBoxItem">
                  <Setter Property="Padding" Value="0"/>
                  <Setter Property="Margin" Value="0"/>
                  <Setter Property="Focusable" Value="False"/>
                  <Setter Property="Template">
                    <Setter.Value>
                      <ControlTemplate TargetType="ListBoxItem">
                        <ContentPresenter/>
                      </ControlTemplate>
                    </Setter.Value>
                  </Setter>
                </Style>
              </ListBox.ItemContainerStyle>
            </ListBox>
          </Grid>
        </Grid>

        <TextBlock x:Name="pie" Foreground="#6B7484" FontSize="10" Margin="0,8,0,0"/>
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
