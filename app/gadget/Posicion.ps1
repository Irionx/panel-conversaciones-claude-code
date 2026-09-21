# =============================================================================
#  Posicion.ps1 - Donde queda la ventana, y como vuelve a quedar ahi.
#
#  Salio de gadget.ps1 cuando paso las 600 lineas. Son las dos puntas de lo
#  mismo: leer gadget-posicion.json al arrancar y escribirlo al cerrar. Separadas
#  se desincronizan solas -- un campo nuevo se agrega de un lado y se olvida del
#  otro -- asi que viven juntas.
# =============================================================================

function Restore-Posicion {
    if (Test-Path $archivoPos) {
        try {
            $p = Get-Content $archivoPos -Raw | ConvertFrom-Json
            $l = [double]$p.left
            $t = [double]$p.top
            if (-not [double]::IsNaN($l) -and $l -ge -50 -and $l -lt $area.Right -and $t -ge -50 -and $t -lt $area.Bottom) {
                $ventana.Left = $l
                $ventana.Top = $t
                $script:posOk = $true
            }
            if ($null -ne $p.bloqueado) { $script:bloqueado = [bool]$p.bloqueado }
            if ($null -ne $p.arriba) { $script:arriba = [bool]$p.arriba }
            if ($null -ne $p.colapsado) { $script:colapsado = [bool]$p.colapsado }
            if ($p.ancho -and [double]$p.ancho -ge $ANCHO_MIN -and [double]$p.ancho -le $ANCHO_MAX) {
                $ventana.Width = [double]$p.ancho
            }
            if ($p.alto -and [double]$p.alto -ge $ALTO_MIN -and [double]$p.alto -le $ALTO_MAX) {
                $scroller.MaxHeight = [double]$p.alto
            }
        } catch { }
    }
}

function Save-Posicion {
    try {
        # Minimizada, Left/Top valen -32000 (donde Windows estaciona las
        # ventanas minimizadas) y ActualWidth 0: guardar eso deja el gadget
        # fuera de pantalla en el proximo arranque. RestoreBounds tiene el
        # rectangulo de cuando estaba desplegada, que es el que interesa.
        $r = if ($ventana.WindowState -eq 'Normal') {
            [pscustomobject]@{ Left = $ventana.Left; Top = $ventana.Top; Width = $ventana.ActualWidth }
        } else {
            $ventana.RestoreBounds
        }
        @{
            left      = $r.Left
            top       = $r.Top
            ancho     = $r.Width
            # El alto es del ScrollViewer, no de la ventana: no lo afecta
            # que este minimizada, asi que va directo.
            alto      = $scroller.MaxHeight
            bloqueado = $script:bloqueado
            arriba    = $script:arriba
            colapsado = $script:colapsado
        } | ConvertTo-Json | Set-Content -Path $archivoPos -Encoding UTF8
    } catch { }
}
