# =============================================================================
#  hacer-icono.ps1 - genera gadget.ico (el globo de chat del panel)
# -----------------------------------------------------------------------------
#  Se corre a mano, una vez. El .ico queda versionado al lado del gadget; esto
#  es la "fuente" por si algun dia hay que retocar el dibujo.
#
#  Un icono NO es una imagen: son varias. A 16px el dibujo detallado se hace
#  papilla, asi que hay tres niveles de detalle segun el tamano (ver Get-Escena).
#  .NET no trae encoder de .ico, asi que el contenedor se escribe a mano abajo.
# =============================================================================
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$carpeta = Split-Path -Parent $MyInvocation.MyCommand.Path
# El icono es un asset de la app, asi que se escribe en app\.
$destino = Join-Path (Split-Path -Parent $carpeta) 'app\gadget.ico'

# --- paleta: la del propio gadget --------------------------------------------
#  Verde = el de la barra de contexto y los puntitos del latido (#4ADE80).
#  El slate y el verde se ven los dos sobre barra clara Y oscura; blanco o
#  navy desaparecerian en una de las dos.
function Pincel([string]$hex) {
    (New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($hex)))
}
$VERDE_ALTO = '#6EE79A'
$VERDE_BAJO = '#35C46E'
$SLATE = '#64748B'
$PUNTO = '#16202A'

function Get-Degrade {
    $g = New-Object Windows.Media.LinearGradientBrush
    $g.StartPoint = [Windows.Point]::new(0, 0)
    $g.EndPoint = [Windows.Point]::new(0, 1)
    $g.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString($VERDE_ALTO), 0)))
    $g.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString($VERDE_BAJO), 1)))
    $g.Freeze()
    $g
}

function Get-Globo([double]$x, [double]$y, [double]$w, [double]$h, [double]$r, [string]$cola) {
    $cuerpo = New-Object Windows.Media.RectangleGeometry ([Windows.Rect]::new($x, $y, $w, $h), $r, $r)
    if (-not $cola) { return $cuerpo }
    $t = [Windows.Media.Geometry]::Parse($cola)
    New-Object Windows.Media.CombinedGeometry ([Windows.Media.GeometryCombineMode]::Union, $cuerpo, $t)
}

# --- la escena, en un lienzo de 100x100 --------------------------------------
#  Tres niveles de detalle. La regla: cuanto mas chico, mas silueta y menos
#  adorno. A 16px lo unico que se lee es el contorno.
#
#  El corte va en 20 y no en 24 a proposito: la barra de tareas de Windows 11
#  pide el marco de 24 a 100% de escalado. Si 24 fuera silueta de un globo, en
#  la barra verias UN globo y en Alt+Tab (32) DOS. Medido, no supuesto.
if (-not $script:CORTE_SILUETA) { $script:CORTE_SILUETA = 20 }
function Get-Escena([int]$px) {
    $dv = New-Object Windows.Media.DrawingVisual
    $dc = $dv.RenderOpen()
    $dc.PushTransform((New-Object Windows.Media.ScaleTransform ($px / 100), ($px / 100)))

    if ($px -le $script:CORTE_SILUETA) {
        # CHICO: un solo globo, grande y centrado. Silueta pura.
        $dc.DrawGeometry((Get-Degrade), $null,
            (Get-Globo 8 16 84 56 19 'M 30,68 L 25,95 L 59,71 Z'))
    }
    else {
        # MEDIANO y GRANDE: dos globos = "conversaciones", en plural.
        # El slate va primero para que quede DETRAS del verde.
        $dc.DrawGeometry((Pincel $SLATE), $null,
            (Get-Globo 48 6 48 36 13 $null))
        $dc.DrawGeometry((Get-Degrade), $null,
            (Get-Globo 4 26 76 52 17 'M 24,74 L 19,98 L 50,77 Z'))

        if ($px -ge 48) {
            # GRANDE: los tres puntitos del latido, calados sobre el verde.
            $p = Pincel $PUNTO
            foreach ($cx in 21, 42, 63) {
                $dc.DrawEllipse($p, $null, [Windows.Point]::new($cx, 52), 6, 6)
            }
        }
    }

    $dc.Pop()
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
