# =============================================================================
#  Instalacion.ps1 - el chequeo de instalacion al arrancar el gadget
# -----------------------------------------------------------------------------
#  Una sola funcion, y vive aparte por dos razones:
#    1. gadget.ps1 es arranque y cableado; esto es una politica ("que hacer si
#       falta una pieza") con su propio dialogo y su propia marca en disco.
#    2. gadget.ps1 tiene un tope de 600 lineas que un test verifica, y esta
#       funcion sola son ~60.
#
#  La logica de MEDIR y REPARAR no esta aca: vive en app\lib-setup.ps1, que la
#  comparte con setup.ps1. Aca solo esta el "cuando preguntar y como".
# =============================================================================

# --- chequeo de instalacion --------------------------------------------------
#  Se mide el estado real en cada arranque, sin marcador de "ya instalado": asi,
#  si moves la carpeta, la proxima vez se re-apunta solo.
function Invoke-ChequeoSetup {
    # La instalacion se mide contra la RAIZ del proyecto, no contra app\.
    $piezas = @(Get-EstadoInstalacion -Carpeta $raiz)
    if (@($piezas | Where-Object { -not $_.Ok }).Count -eq 0) { return }

    # Si ya dijo que no a exactamente esto, no se vuelve a preguntar. Si aparece
    # algo NUEVO roto la huella cambia, y se ofrece de nuevo.
    $huella = Get-HuellaFaltantes -Piezas $piezas
    $marca = Join-Path $raiz 'datos\setup-omitido.json'
    if (Test-Path $marca) {
        try {
            if ((Get-Content $marca -Raw | ConvertFrom-Json).huella -eq $huella) { return }
        } catch { }
    }

    $filas = foreach ($p in $piezas) {
        @{ Texto = $p.Nombre; Dato = $(if ($p.Ok) { 'ok' } else { 'falta' }) }
    }

    $pedir = @{
        Encabezado = 'Falta completar la instalación'
        Nombre     = 'Hasta que esté completa, el panel anda a medias.'
        Filas      = @($filas)
        Aviso      = 'Se escribe sólo en tu usuario (HKCU y PATH de usuario): no hace falta admin.'
        TextoOk    = 'Instalar'
        Icono      = 'engranaje'
    }
    if (-not (Show-Confirmacion @pedir)) {
        try {
            @{ huella = $huella; cuando = (Get-Date -Format 'o') } |
                ConvertTo-Json | Set-Content -Path $marca -Encoding UTF8
        } catch { }
        return
    }

    $tocoPath = @($piezas | Where-Object { -not $_.Ok -and $_.Clave -eq 'path' }).Count -gt 0
    $r = Repair-Instalacion -Piezas $piezas
    Remove-Item -LiteralPath $marca -Force -ErrorAction SilentlyContinue

    $hechas = @()
    foreach ($h in $r.Hechas) { $hechas += @{ Texto = $h; Dato = 'instalado' } }
    foreach ($e in $r.Errores) { $hechas += @{ Texto = $e; Dato = 'error' } }

    $avisoFinal = if ($r.Errores.Count -gt 0) {
        'Quedó algo sin instalar. Corré .\setup.ps1 en una terminal para ver el detalle.'
    } elseif ($tocoPath) {
        'El PATH cambió: los comandos aparecen en las terminales que abras de ahora en más. Las ya abiertas, Claude Code incluido, siguen con el PATH viejo.'
    } else { '' }

    $avisar = @{
        Encabezado  = $(if ($r.Errores.Count -gt 0) { 'Instalación incompleta' } else { 'Instalación lista' })
        Filas       = @($hechas)
        Aviso       = $avisoFinal
        TextoOk     = 'Listo'
        Icono       = $(if ($r.Errores.Count -gt 0) { 'engranaje' } else { 'tilde' })
        SoloAceptar = $true
    }
    Show-Confirmacion @avisar | Out-Null
    Actualizar
}
