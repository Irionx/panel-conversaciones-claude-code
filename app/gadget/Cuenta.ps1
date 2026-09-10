# =============================================================================
#  Cuenta.ps1 - la cuenta de Claude Code logueada, y el boton para cambiarla
# -----------------------------------------------------------------------------
#  La cuenta sale de ~/.claude.json (oauthAccount). Cambiarla es cosa del login
#  de Claude Code, no de este panel: el boton abre una terminal con
#  'claude auth login' y el chip se actualiza solo al proximo refresco.
# =============================================================================

$script:cacheCuenta = $null

# El objeto oauthAccount de ~/.claude.json, o $null si no hay sesion. Se
# re-parsea solo cuando el archivo cambio: ~20 ms en caliente.
function Get-CuentaClaude {
    $ruta = Join-Path $env:USERPROFILE '.claude.json'
    $fi = Get-Item -LiteralPath $ruta -ErrorAction SilentlyContinue
    if (-not $fi) { return $null }

    $sello = '{0}|{1}' -f $fi.LastWriteTimeUtc.Ticks, $fi.Length
    if ($script:cacheCuenta -and $script:cacheCuenta.Sello -eq $sello) { return $script:cacheCuenta.Valor }

    $valor = $null
    try { $valor = ([System.IO.File]::ReadAllText($ruta) | ConvertFrom-Json).oauthAccount } catch { }
    $script:cacheCuenta = @{ Sello = $sello; Valor = $valor }
    return $valor
}

# El nombre de la cuenta, para el dialogo. El chip muestra el MAIL, que es lo
# que distingue una cuenta de otra: el displayName se puede repetir.
function Get-NombreCuenta($Cuenta) {
    if (-not $Cuenta) { return 'sin sesión' }
    foreach ($campo in 'displayName', 'fullName') {
        if ($Cuenta.$campo) { return [string]$Cuenta.$campo }
    }
    return 'cuenta'
}

function Set-ChipCuenta {
    $c = Get-CuentaClaude
    # DockPanel y no StackPanel: un StackPanel horizontal le da ancho infinito al
    # texto y el TextTrimming nunca se activaria.
    $panel = New-Object Windows.Controls.DockPanel

    $glifo = New-Object Windows.Controls.TextBlock
    $glifo.Text = [char]0xE77B                    # persona, de Segoe MDL2 Assets
    $glifo.FontFamily = New-Object Windows.Media.FontFamily -ArgumentList 'Segoe MDL2 Assets'
    $glifo.FontSize = 10
    $glifo.VerticalAlignment = 'Center'
    $glifo.Margin = [Windows.Thickness]::new(0, 1, 5, 0)
    $glifo.Foreground = Pincel '#4FA878'
    [Windows.Controls.DockPanel]::SetDock($glifo, 'Left')
    $panel.Children.Add($glifo) | Out-Null

    $mail = New-Object Windows.Controls.TextBlock
    $mail.Text = if ($c -and $c.emailAddress) { [string]$c.emailAddress } else { Get-NombreCuenta $c }
    $mail.FontSize = 10.5
    $mail.VerticalAlignment = 'Center'
    $mail.Foreground = Pincel '#86EFAC'
    $mail.TextTrimming = 'CharacterEllipsis'
    $panel.Children.Add($mail) | Out-Null

    $btnCuenta.Content = $panel
    $org = if ($c -and $c.organizationName) { "`n" + [string]$c.organizationName } else { '' }
    $btnCuenta.ToolTip = "Cuenta de Claude Code: $(Get-NombreCuenta $c)$org`nEs una sola para todas las conversaciones`nClick para ver el detalle o cambiarla"
}

function Show-DialogoCuenta {
    $c = Get-CuentaClaude
    $filas = @()
    if ($c) {
        $filas += @{ Texto = 'Nombre'; Dato = (Get-NombreCuenta $c) }
        if ($c.emailAddress) { $filas += @{ Texto = 'Mail'; Dato = [string]$c.emailAddress } }
        if ($c.organizationName) { $filas += @{ Texto = 'Organización'; Dato = [string]$c.organizationName } }
        if ($c.billingType) { $filas += @{ Texto = 'Plan'; Dato = [string]$c.billingType } }
    }
    $pedir = @{
        Encabezado = $(if ($c) { 'Cuenta de Claude Code' } else { 'No hay una sesión iniciada' })
        Filas      = $filas
        # Medido: las credenciales son UN archivo (~/.claude/.credentials.json)
        # que leen todas las sesiones, asi que el login cambia la cuenta de
        # todas, incluso las que ya estaban abiertas.
        Aviso      = 'Se abre una terminal con "claude auth login". La cuenta es una sola para todo Claude Code: al cambiarla, TODAS las conversaciones pasan a la nueva, también las que ya están abiertas y trabajando.'
        TextoOk    = $(if ($c) { 'Cambiar de cuenta' } else { 'Iniciar sesión' })
        Icono      = 'engranaje'
    }
    if (-not (Show-Confirmacion @pedir)) { return }

    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoExit', '-Command', 'claude auth login'
    } catch {
        [Windows.MessageBox]::Show("No pude abrir la terminal:`n`n$($_.Exception.Message)",
            'Conversaciones') | Out-Null
    }
}
