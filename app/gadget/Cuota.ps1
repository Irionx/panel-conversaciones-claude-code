# =============================================================================
#  Cuota.ps1 - la cuota real de la cuenta, en la cabecera
# -----------------------------------------------------------------------------
#  Get-CuotaReal lee el volcado del statusline; Set-Resumen lo dibuja. Son los
#  MISMOS numeros que muestra la consola: ver el comentario de Get-CuotaReal
#  para donde sale el dato y por que no hay otra fuente.
# =============================================================================

# --- cuota real de la cuenta -------------------------------------------------
#  MEDIDO EL 2026-09-08. Aca habia un comentario que decia que la cuota de la
#  cuenta "no existe en ningun archivo local". Era FALSO: el payload que Claude
#  Code le pasa al statusline por stdin trae `rate_limits`, con los porcentajes
#  que calcula el servidor. Nada de estimar.
#
#      "rate_limits": { "five_hour": { "used_percentage": 10, "resets_at": <epoch> },
#                       "seven_day": { "used_percentage": 7,  "resets_at": <epoch> } }
#
#  Lo que NO hay es un archivo que lo guarde: los transcripts no lo traen (se
#  buscó estructuralmente en los 12 mas recientes, cero hits) y el cache del HUD
#  (.usage-cache.json) solo se escribe cuando pega contra la API, que no es el
#  camino que usa aca. Y el statusline es el UNICO consumidor de ese payload.
#
#  Solucion: en settings.json el comando del statusline ahora vuelca su stdin a
#  ~/.claude/statusline-ultimo.json ANTES de pasarselo al HUD (lee todo primero,
#  escribe a un tmp y hace mv, que es atomico). Este archivo es lo que se lee.
#
#  Se guardan las DOS ventanas por separado. El HUD calcula un max(5h, 7d)
#  (render/session-line.js:169) pero en el layout que usa esta maquina dibuja
#  las dos: "Usage" es la de 5h y "Weekly" la de 7 dias (session-line.js:173-189).
#  Mostrar solo el mayor coincidiria HOY y dejaria de coincidir el dia que la
#  semanal pase a la de 5h.
#
#  Pct queda como "la mas urgente de las dos" y se usa para la barra y el color,
#  que es una sola cosa y tiene que reflejar el peor caso.
function Get-CuotaReal {
    $ruta = Join-Path $env:USERPROFILE '.claude\statusline-ultimo.json'
    $nada = [pscustomobject]@{ Hay = $false }
    if (-not (Test-Path -LiteralPath $ruta)) { return $nada }
    try {
        $arch = Get-Item -LiteralPath $ruta
        $rl = (Get-Content -LiteralPath $ruta -Raw -Encoding UTF8 | ConvertFrom-Json).rate_limits
        if (-not $rl) { return $nada }

        # -1 = "esa ventana no vino". Sirve de centinela para el Max de abajo sin
        # tener que andar con $null, que en PS 5.1 se castea a 0 y mentiria.
        [double]$p5 = -1
        [double]$p7 = -1
        if ($rl.five_hour -and $null -ne $rl.five_hour.used_percentage) { $p5 = [double]$rl.five_hour.used_percentage }
        if ($rl.seven_day -and $null -ne $rl.seven_day.used_percentage) { $p7 = [double]$rl.seven_day.used_percentage }
        if ($p5 -lt 0 -and $p7 -lt 0) { return $nada }

        # resets_at viene en SEGUNDOS epoch, no en milisegundos.
        $aFecha = {
            param($ep)
            if (-not $ep) { return $null }
            try { return [DateTimeOffset]::FromUnixTimeSeconds([int64]$ep).ToLocalTime().DateTime } catch { return $null }
        }
        return [pscustomobject]@{
            Hay      = $true
            Pct      = [math]::Round([math]::Max($p5, $p7), 1)
            Pct5h    = $(if ($p5 -ge 0) { [math]::Round($p5, 1) } else { $null })
            Pct7d    = $(if ($p7 -ge 0) { [math]::Round($p7, 1) } else { $null })
            Ventana  = $(if ($p5 -ge $p7) { 'diario' } else { 'semanal' })
            Reset5h  = & $aFecha $rl.five_hour.resets_at
            Reset7d  = & $aFecha $rl.seven_day.resets_at
            Edad     = [int]((Get-Date) - $arch.LastWriteTime).TotalMinutes
        }
    } catch {
        return $nada
    }
}

# --- resumen del panel -------------------------------------------------------
#  Muestra la cuota REAL de la cuenta, una mitad por ventana y las dos en el
#  mismo renglon. El contexto sumado de las charlas pasa al tooltip: es otra
#  cosa (cuanta ventana hay en juego) y confundia los dos numeros en el mismo
#  lugar.
function Set-Resumen {
    param([int64]$Tokens, [int64]$Limite)

    $ctxTip = if ($Limite -gt 0) {
        'Contexto en juego: {0} de {1}  ({2}%)' -f (Format-Tokens $Tokens), (Format-Tokens $Limite),
        [math]::Round(100.0 * $Tokens / $Limite, 1)
    } else { 'Contexto en juego: sin datos' }

    # Pinta una mitad: nombre, barra proporcional y a que hora resetea. Las
    # columnas de la barra van en estrellas y no en pixeles, asi se estira sola
    # cuando se ensancha la ventana.
    function Pintar-Fila($fila, [string]$nombre, $pct, $reset, [string]$formatoReset) {
        if ($null -eq $pct) {
            $fila.Nom.Text = ''
            $fila.Reset.Text = ''
            $fila.Barra.Visibility = 'Collapsed'
            return
        }
        $fila.Barra.Visibility = 'Visible'
        $fila.Nom.Text = '{0} {1}%' -f $nombre, $pct
        $fila.Reset.Text = if ($reset) { '↻ ' + ([string]::Format($formatoReset, $reset)) } else { '' }
        $lleno = [math]::Max(0.001, [math]::Min([double]$pct, 100))
        $fila.Barra.ColumnDefinitions[0].Width = New-Object Windows.GridLength ($lleno, ([Windows.GridUnitType]::Star))
        $fila.Barra.ColumnDefinitions[1].Width = New-Object Windows.GridLength ((100 - $lleno), ([Windows.GridUnitType]::Star))
        # Cada barra con el color de SU propio porcentaje: si la semanal esta en
        # rojo y la diaria en verde, hay que verlo de un vistazo.
        $fila.Lleno.Background = Pincel (Get-ColorContexto $lleno)
    }

    $q = Get-CuotaReal
    if (-not $q.Hay) {
        # El cartel tapa las dos mitades y se lleva el ancho completo: "sin
        # datos de cuota" no entra en la mitad de un panel de 348.
        $cuotaFilas.Visibility = 'Collapsed'
        $cuotaVacio.Visibility = 'Visible'
        $chipResumen.ToolTip = "No hay cuota todavia.`nLa escribe el statusline de Claude Code en`n~\.claude\statusline-ultimo.json cada vez que dibuja.`nAbri una sesion y aparece.`n`n$ctxTip"
        return
    }

    $cuotaVacio.Visibility = 'Collapsed'
    $cuotaFilas.Visibility = 'Visible'

    # La diaria resetea dentro del dia: alcanza la hora. La semanal cae otro
    # dia, asi que ahi la hora sola no dice nada y va la fecha.
    Pintar-Fila $filasCuota[0] 'diario'  $q.Pct5h $q.Reset5h '{0:HH:mm}'
    Pintar-Fila $filasCuota[1] 'semanal' $q.Pct7d $q.Reset7d '{0:dd/MM}'

    $tip = @('Cuota de la cuenta, los mismos numeros que el statusline:')
    if ($null -ne $q.Pct5h) { $tip += '   diario  (5h) = "Usage"  : {0}%' -f $q.Pct5h }
    if ($null -ne $q.Pct7d) { $tip += '   semanal (7d) = "Weekly" : {0}%' -f $q.Pct7d }
    if ($q.Reset5h) { $tip += 'La diaria resetea {0:HH:mm} del {0:dd/MM}' -f $q.Reset5h }
    if ($q.Reset7d) { $tip += 'La semanal resetea {0:HH:mm} del {0:dd/MM}' -f $q.Reset7d }
    # Si nadie dibujo statusline en un rato el dato quedo viejo: se dice, en vez
    # de mostrar un numero de hace horas como si fuera de ahora.
    $tip += if ($q.Edad -ge 10) { 'OJO: dato de hace {0} min (no hay sesion dibujando statusline)' -f $q.Edad }
    else { 'Dato de hace {0} min' -f $q.Edad }
    $tip += ''
    $tip += $ctxTip
    $chipResumen.ToolTip = $tip -join "`n"
}
