# =============================================================================
#  Orden.ps1 - arrastrar una tarjeta, con animacion, para reordenar el panel
# -----------------------------------------------------------------------------
#  Se agarra de un ASA, no de cualquier parte de la tarjeta. Un asa explicita
#  cambia el problema: sin ella hay que adivinar la intencion con umbrales de
#  pixeles ("¿quiso mover o quiso abrir?") y siempre se equivoca en algun caso.
#  Con asa la intencion es inequivoca, y el click en la tarjeta vuelve a ser un
#  click limpio que abre la conversacion.
#
#  POR QUE A MANO Y NO CON EL DRAG&DROP DE WPF: DoDragDrop abre un bucle modal
#  propio, se come el resto de los eventos del hilo y pide un DataObject mas un
#  DropTarget por tarjeta. Aca alcanza con mover el elemento de lugar en
#  $lista.Children.
#
#  LA ANIMACION, que son dos cosas distintas:
#    1. La tarjeta agarrada SIGUE al mouse con un TranslateTransform. No lleva
#       DoubleAnimation a proposito: el mouse ya provee el movimiento continuo, y
#       una animacion encima competiria con el cursor y se sentiria elastica.
#    2. La vecina desplazada SI se anima (140 ms): sale de donde estaba y se
#       desliza a su lugar nuevo, en vez de teletransportarse. Es lo que hace
#       que el reordenamiento se lea.
#  Las dos animaciones son de UNA pasada, nunca RepeatBehavior.Forever, asi que
#  sus relojes se liberan al terminar y no hay que pararlos a mano como el halo.
#
#  El orden se PERSISTE recien al soltar, y solo si cambio de verdad
#  (Set-OrdenConversacion, una sola transaccion). Mientras arrastras no se toca
#  la base: si el gadget se cierra a mitad de un arrastre, no queda un orden a
#  medio escribir.
# =============================================================================

$script:arrastre = $null

# Los ids de las tarjetas en el orden en que estan AHORA en la lista.
# El Where descarta lo que no sea tarjeta: el refresco puede haber dejado un
# TextBlock de error o el cartel de "no hay nada".
#
# La coma del return es para que un array de cero o un elemento no se desarme.
# CONSECUENCIA: hay que llamarla asignando ($x = Get-IdsDeLaLista), nunca
# envuelta en @(), que la anidaria. Misma trampa documentada en Get-Tag.
function Get-IdsDeLaLista {
    $ids = @()
    foreach ($h in $lista.Children) {
        if ($h.Tag -and $h.Tag.conv) { $ids += [string]$h.Tag.conv.id }
    }
    return , $ids
}

# Desliza un elemento desde un desfasaje hasta su lugar (0).
function Animar-Deslizar {
    param($Elemento, [double]$Desde)

    $tr = New-Object Windows.Media.TranslateTransform
    $tr.Y = $Desde
    $Elemento.RenderTransform = $tr

    $an = New-Object Windows.Media.Animation.DoubleAnimation
    $an.From = $Desde
    $an.To = 0
    $an.Duration = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(140))
    $an.EasingFunction = New-Object Windows.Media.Animation.CubicEase
    $tr.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $an)
}

function Start-Arrastre {
    param(
        [Parameter(Mandatory)]$Tarjeta,
        # El asa. Es quien CAPTURA el mouse: ver el comentario de mas abajo.
        [Parameter(Mandatory)]$Asa
    )

    # Bloqueado no se reordena, igual que no se mueve ni se ensancha. Y en la
    # vista de archivadas tampoco: el orden es del PANEL, y renumerar las
    # archivadas pisaria los numeros de las activas.
    if ($script:bloqueado -or $script:verArchivadas) { return }

    $tr = New-Object Windows.Media.TranslateTransform
    $Tarjeta.RenderTransform = $tr
    # Por encima de las vecinas mientras viaja, o pasa por debajo de la de al
    # lado y parece que se mete abajo.
    [Windows.Controls.Panel]::SetZIndex($Tarjeta, 10)
    $Tarjeta.Effect = New-Sombra -Blur 18 -Prof 5 -Op 0.55

    $script:arrastre = @{
        tarjeta = $Tarjeta
        tr      = $tr
        y0      = [System.Windows.Forms.Cursor]::Position.Y
        # Cuanto se corrio la tarjeta por los intercambios YA hechos. Se le
        # resta al delta del mouse para que la tarjeta quede quieta bajo el
        # cursor cuando cambia de ranura: son las vecinas las que se mueven, no
        # ella. Sin esto pega un salto de una tarjeta de alto en cada cruce.
        salto   = 0.0
        orden0  = (Get-IdsDeLaLista)
        asa     = $Asa
    }

    # LA CAPTURA VA EN EL ASA Y NO EN LA TARJETA, y no es un detalle de estilo:
    # el elemento que captura el mouse es el que recibe el MouseLeftButtonUp.
    # Con la captura en la tarjeta, soltar despues de arrastrar disparaba SU
    # handler, que es justo el que abre la conversacion. Con la captura en el
    # asa el Up llega al asa, que lo marca Handled y corta el burbujeo: soltar
    # el asa no abre nada y la tarjeta vuelve a ser un click limpio.
    $Asa.CaptureMouse() | Out-Null
}

function Move-Arrastre {
    if (-not $script:arrastre) { return }
    $a = $script:arrastre
    $cursor = [System.Windows.Forms.Cursor]::Position

    $delta = ($cursor.Y - $a.y0) / $script:escala
    $a.tr.Y = $delta - $a.salto

    # PointFromScreen traduce pixeles de pantalla al sistema de coordenadas de
    # la lista y resuelve el DPI solo: aca no hace falta dividir por
    # $script:escala a mano como en los grips de redimensionar.
    $y = $lista.PointFromScreen((New-Object Windows.Point($cursor.X, $cursor.Y))).Y

    $iActual = $lista.Children.IndexOf($a.tarjeta)
    if ($iActual -lt 0) { return }

    # A que ranura corresponde la altura donde esta el cursor. Se compara contra
    # el CENTRO de cada tarjeta y no contra su borde: asi el intercambio ocurre
    # cuando ya cruzaste la mitad de la vecina, que es lo que se siente natural
    # y no rebota cuando dos tarjetas miden distinto.
    #
    # OJO: se mide con las ranuras, no con la posicion visual. La tarjeta
    # agarrada esta corrida por el TranslateTransform, pero su ranura sigue
    # ocupando lugar en el StackPanel y ActualHeight no cambia.
    $destino = $iActual
    $acum = 0.0
    for ($i = 0; $i -lt $lista.Children.Count; $i++) {
        $h = $lista.Children[$i]
        $alto = $h.ActualHeight + $h.Margin.Top + $h.Margin.Bottom
        if ($y -lt ($acum + $alto / 2)) { $destino = $i; break }
        $destino = $i
        $acum += $alto
    }
    if ($destino -eq $iActual) { return }

    $vecina = $lista.Children[$destino]
    $altoTarjeta = $a.tarjeta.ActualHeight + $a.tarjeta.Margin.Top + $a.tarjeta.Margin.Bottom
    $altoVecina = $vecina.ActualHeight + $vecina.Margin.Top + $vecina.Margin.Bottom
    $bajando = ($destino -gt $iActual)

    $lista.Children.Remove($a.tarjeta)
    $lista.Children.Insert($destino, $a.tarjeta)

    # La ranura de la tarjeta se movio: se compensa en el mismo tick para que no
    # se vea el salto.
    $a.salto += $(if ($bajando) { $altoVecina } else { -$altoVecina })
    $a.tr.Y = $delta - $a.salto

    # Y la vecina se desliza desde donde estaba. Si la tarjeta bajo, la vecina
    # subio: arranca abajo (+alto) y viaja hasta 0.
    Animar-Deslizar -Elemento $vecina -Desde $(if ($bajando) { $altoTarjeta } else { - $altoTarjeta })
}

function Stop-Arrastre {
    if (-not $script:arrastre) { return }
    $a = $script:arrastre
    # Se limpia ANTES de cualquier cosa que pueda fallar. Si quedara puesto, el
    # refresco -que se saltea mientras hay un arrastre- no volveria a correr y
    # el panel quedaria congelado.
    $script:arrastre = $null

    # Se suelta el ASA, que es la que capturo (ver Start-Arrastre).
    try { $a.asa.ReleaseMouseCapture() } catch { }
    $a.tarjeta.Effect = $null
    [Windows.Controls.Panel]::SetZIndex($a.tarjeta, 0)

    # Se asienta en su ranura en vez de saltar de golpe.
    if ([math]::Abs($a.tr.Y) -gt 0.5) {
        $an = New-Object Windows.Media.Animation.DoubleAnimation
        $an.From = $a.tr.Y
        $an.To = 0
        $an.Duration = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(160))
        $an.EasingFunction = New-Object Windows.Media.Animation.CubicEase
        $a.tr.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $an)
    } else {
        $a.tr.Y = 0
    }

    # Solo se escribe si el orden CAMBIO. Con un asa no hace falta umbral de
    # pixeles: agarrarla y soltarla en el mismo lugar simplemente no toca nada.
    $ahora = Get-IdsDeLaLista
    if (($ahora -join '|') -eq ($a.orden0 -join '|')) { return }

    try {
        Set-OrdenConversacion -Ids $ahora | Out-Null
        # NO se llama a Actualizar: la lista en pantalla ya coincide con la base,
        # y rearmarla cortaria la animacion de asentado justo al final.
    } catch {
        [Windows.MessageBox]::Show(
            "No pude guardar el orden nuevo:`n`n$($_.Exception.Message)",
            'Conversaciones') | Out-Null
        # Aca SI: si no se guardo, la pantalla esta mintiendo y hay que volver
        # al orden real de la base.
        Actualizar
    }
}
