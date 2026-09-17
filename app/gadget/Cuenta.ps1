# =============================================================================
#  Cuenta.ps1 - la cuenta de Claude Code logueada, y el boton para cambiarla
# -----------------------------------------------------------------------------
#  La cuenta sale de .claude.json (oauthAccount). El chip muestra el mail y el
#  click abre el selector: las cuentas por las que ya pasaste quedan guardadas
#  y se cambia entre ellas sin volver a loguearse. La logica esta en
#  lib-cuentas.ps1; aca solo se dibuja y se decide que hacer con el resultado.
# =============================================================================

$script:cacheCuenta = $null

# El objeto oauthAccount de ~/.claude.json, o $null si no hay sesion. Se
# re-parsea solo cuando el archivo cambio: ~20 ms en caliente.
function Get-CuentaClaude {
    $ruta = Get-RutaAjustesClaude
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
    $btnCuenta.ToolTip = "Cuenta de Claude Code: $(Get-NombreCuenta $c)$org`nEs una sola para todas las conversaciones`nClick para cambiar de cuenta"
}

#  Sin sesion iniciada no hay nada que elegir: se va derecho al login.
function Show-DialogoCuenta {
    $cuentas = @(Get-Cuentas)

    if ($cuentas.Count -eq 0) {
        $pedir = @{
            Encabezado = 'No hay una sesión iniciada'
            Aviso      = 'Se abre una terminal con "claude auth login". Cuando entres, el panel se guarda esa cuenta y después vas a poder cambiar entre las que uses, sin loguearte de nuevo.'
            TextoOk    = 'Iniciar sesión'
            Icono      = 'engranaje'
        }
        if (Show-Confirmacion @pedir) { Open-LoginClaude | Out-Null }
        return
    }

    $r = Show-SelectorCuentas $cuentas
    if ($r.Accion -ceq 'login') { Open-LoginClaude | Out-Null; return }
    if ($r.Accion -cne 'cambiar') { return }

    $res = Switch-Cuenta -Mail $r.Mail
    Set-ChipCuenta

    if (-not $res.Ok) {
        Show-Confirmacion -Encabezado 'No pude cambiar de cuenta' -SoloAceptar `
            -Icono 'engranaje' -Aviso ($res.Avisos -join ' ') | Out-Null
        return
    }
    # Vencida: se pone igual (el mail y la org ya quedan bien) y se abre el
    # login, que es lo unico que puede arreglarla.
    if ($res.Vencida) { Open-LoginClaude | Out-Null }
}
