# =============================================================================
#  hacer-icono.ps1 - genera gadget.ico (la serpentina de Hilos de Claudio)
# -----------------------------------------------------------------------------
#  Se corre a mano, una vez. El .ico queda versionado al lado del gadget; esto
#  es la "fuente" por si algun dia hay que retocar el dibujo.
#
#  EL DIBUJO: la marca de Hilos de Claudio, redibujada en vectores a partir del logo.
#  Es UN hilo doblado dos veces -- tramo de arriba hacia la izquierda, vuelta
#  por la izquierda, tramo del medio hacia la derecha, vuelta por la derecha,
#  tramo de abajo -- y el tramo de abajo va apagado, como en el logo.
#
#  Se redibujo en vectores en vez de meter el PNG del logo porque el original
#  es un JPEG de 1774x887: a 16px se convierte en una mancha. Los colores SI
#  salen del logo, muestreados pixel a pixel, no elegidos a ojo.
#
#  EL GROSOR NO ES DECORATIVO. La serpentina tiene contraformas (los huecos
#  entre tramos) que una barra recta no tiene, y son lo primero que se cierra
#  al achicar. Medido renderizando 19/17/15/13 y mirando el marco de 16 a x5:
#  con 19 el hueco queda en 0,7px y el icono es un poroto verde; con 15 queda
#  en 1,6px y la S se lee. Con 13 se lee mejor pero ya no es la marca: el logo
#  original es un hilo grueso.
#
#  Un icono NO es una imagen: son varias. Por ser trazos con punta redonda la
#  escena es la MISMA en los 8 marcos; no hace falta simplificar en chico.
#
#  .NET no trae encoder de .ico, asi que el contenedor se escribe a mano abajo.
# =============================================================================
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# Geometry::Parse lee SIEMPRE con punto decimal, y el -f de PowerShell formatea
# con la cultura de la maquina: en una en espanol escribe "11,25" y el path no
# parsea. Con esto el script da lo mismo en cualquier idioma de Windows.
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture

$carpeta = Split-Path -Parent $MyInvocation.MyCommand.Path
# El icono es un asset de la app, asi que se escribe en app\.
$destino = Join-Path (Split-Path -Parent $carpeta) 'app\gadget.ico'

# --- paleta: muestreada del logo, no inventada -------------------------------
$VERDE_ALTO = '#2DE274'
$VERDE_BAJO = '#05D468'
# El hilo apagado del logo es #3B4648. Aclarado a proposito: sobre el fondo del
# panel (#161A20) y sobre una barra de tareas oscura, el original desaparece.
$APAGADO = '#55636B'

function Pincel([string]$hex) {
    $b = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($hex))
    $b.Freeze()
    $b
}

function Get-Degrade {
    $g = New-Object Windows.Media.LinearGradientBrush
    $g.StartPoint = [Windows.Point]::new(0, 0)
    $g.EndPoint = [Windows.Point]::new(0, 1)
    $g.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString($VERDE_ALTO), 0)))
    $g.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString($VERDE_BAJO), 1)))
    $g.Freeze()
    $g
}

# La punta redonda es lo que convierte una linea en un hilo, y la union redonda
# lo que hace que las vueltas no tengan esquina.
function Get-Hilo($brush, [double]$grosor) {
    $p = New-Object Windows.Media.Pen ($brush, $grosor)
    $p.StartLineCap = [Windows.Media.PenLineCap]::Round
    $p.EndLineCap = [Windows.Media.PenLineCap]::Round
    $p.LineJoin = [Windows.Media.PenLineJoin]::Round
    $p
}

# --- la escena, en un lienzo de 100x100 --------------------------------------
$GROSOR = 15
$Y1 = 31.0; $Y2 = 53.5; $Y3 = 76.0
# El radio de las vueltas es medio salto entre tramos: asi la vuelta es un
# semicirculo exacto y no queda ni ovalada ni con un tramo recto en el medio.
$RADIO = ($Y2 - $Y1) / 2
$CAMINO = 'M 74,{0} L 26,{0} A {3},{3} 0 0 0 26,{1} L 57,{1} A {3},{3} 0 0 1 57,{2} L 24,{2}' -f $Y1, $Y2, $Y3, $RADIO
$TRAMO_APAGADO = 'M 24,{0} L 48,{0}' -f $Y3

function Get-Escena([int]$px) {
    # Encuadre automatico: la caja del trazo depende del grosor, asi que se
    # calcula y se escala para llenar 94 de 100. Cambiar $GROSOR no descentra.
    $bx1 = 26 - $RADIO - $GROSOR / 2; $bx2 = 74 + $GROSOR / 2
    $by1 = $Y1 - $GROSOR / 2; $by2 = $Y3 + $GROSOR / 2
    $bw = $bx2 - $bx1; $bh = $by2 - $by1
    $esc = [Math]::Min(94 / $bw, 94 / $bh)

    $dv = New-Object Windows.Media.DrawingVisual
    $dc = $dv.RenderOpen()
    $dc.PushTransform((New-Object Windows.Media.ScaleTransform ($px / 100), ($px / 100)))
    $dc.PushTransform((New-Object Windows.Media.TranslateTransform `
            (50 - ($bx1 + $bw / 2) * $esc), (50 - ($by1 + $bh / 2) * $esc)))
    $dc.PushTransform((New-Object Windows.Media.ScaleTransform $esc, $esc))

    $dc.DrawGeometry($null, (Get-Hilo (Get-Degrade) $GROSOR), ([Windows.Media.Geometry]::Parse($CAMINO)))
    # El tramo apagado va ENCIMA del verde, igual que la barra de contexto de
    # la tarjeta: el verde le da la vuelta por la derecha y se ve el empalme.
    $dc.DrawGeometry($null, (Get-Hilo (Pincel $APAGADO) $GROSOR), ([Windows.Media.Geometry]::Parse($TRAMO_APAGADO)))

    $dc.Pop(); $dc.Pop(); $dc.Pop()
    $dc.Close()

    $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap (
        $px, $px, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($dv)
    $rtb
}

# --- PNG por tamano ----------------------------------------------------------
$tamanos = 16, 20, 24, 32, 48, 64, 128, 256
$marcos = foreach ($t in $tamanos) {
    $ms = New-Object IO.MemoryStream
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create((Get-Escena $t)))
    $enc.Save($ms)
    [pscustomobject]@{ Px = $t; Datos = $ms.ToArray() }
}

# --- contenedor .ico ---------------------------------------------------------
#  ICONDIR (6 bytes) + un ICONDIRENTRY de 16 bytes por marco + los PNG crudos.
#  Windows Vista+ acepta marcos PNG dentro del .ico en cualquier tamano.
#  Ojo: en el campo de ancho/alto, 256 se escribe como 0 (entra en un byte).
$fs = [IO.File]::Create($destino)
$bw = New-Object IO.BinaryWriter($fs)
try {
    $bw.Write([uint16]0)                 # reservado
    $bw.Write([uint16]1)                 # tipo 1 = icono
    $bw.Write([uint16]$marcos.Count)

    $offset = 6 + (16 * $marcos.Count)
    foreach ($m in $marcos) {
        $bw.Write([byte]($m.Px -band 0xFF))   # 256 -> 0
        $bw.Write([byte]($m.Px -band 0xFF))
        $bw.Write([byte]0)               # colores de paleta (0 = truecolor)
        $bw.Write([byte]0)               # reservado
        $bw.Write([uint16]1)             # planos
        $bw.Write([uint16]32)            # bits por pixel
        $bw.Write([uint32]$m.Datos.Length)
        $bw.Write([uint32]$offset)
        $offset += $m.Datos.Length
    }
    foreach ($m in $marcos) { $bw.Write($m.Datos) }
}
finally {
    $bw.Close()
    $fs.Dispose()
}

Write-Host ("gadget.ico OK - {0} marcos ({1}), {2:N0} bytes" -f `
        $marcos.Count, ($tamanos -join '/'), (Get-Item $destino).Length)
