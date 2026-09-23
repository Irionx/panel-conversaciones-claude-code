# =============================================================================
#  Cuenta.ps1 - la cuenta de Claude Code logueada, y el boton para cambiarla
# -----------------------------------------------------------------------------
#  La cuenta sale de .claude.json (oauthAccount). El chip muestra el mail y el
#  click abre el selector: las cuentas por las que ya pasaste quedan guardadas
#  y se cambia entre ellas sin volver a loguearse. La logica esta en
#  lib-cuentas.ps1; aca solo se dibuja y se decide que hacer con el resultado.
# =============================================================================


# El logo de Claude, en vectores (simple-icons, datos en CC0). Es un path, o sea
# TEXTO: no entra ningun binario al repo. Lo comparten el chip de la cabecera y
# el dialogo de cuentas.
$script:PathClaude = 'm4.7144 15.9555 4.7174-2.6471.079-.2307-.079-.1275h-.2307l-.7893-.0486-2.6956-.0729-2.3375-.0971-2.2646-.1214-.5707-.1215-.5343-.7042.0546-.3522.4797-.3218.686.0608 1.5179.1032 2.2767.1578 1.6514.0972 2.4468.255h.3886l.0546-.1579-.1336-.0971-.1032-.0972L6.973 9.8356l-2.55-1.6879-1.3356-.9714-.7225-.4918-.3643-.4614-.1578-1.0078.6557-.7225.8803.0607.2246.0607.8925.686 1.9064 1.4754 2.4893 1.8336.3643.3035.1457-.1032.0182-.0728-.164-.2733-1.3539-2.4467-1.445-2.4893-.6435-1.032-.17-.6194c-.0607-.255-.1032-.4674-.1032-.7285L6.287.1335 6.6997 0l.9957.1336.419.3642.6192 1.4147 1.0018 2.2282 1.5543 3.0296.4553.8985.2429.8318.091.255h.1579v-.1457l.1275-1.706.2368-2.0947.2307-2.6957.0789-.7589.3764-.9107.7468-.4918.5828.2793.4797.686-.0668.4433-.2853 1.8517-.5586 2.9021-.3643 1.9429h.2125l.2429-.2429.9835-1.3053 1.6514-2.0643.7286-.8196.85-.9046.5464-.4311h1.0321l.759 1.1293-.34 1.1657-1.0625 1.3478-.8804 1.1414-1.2628 1.7-.7893 1.36.0729.1093.1882-.0183 2.8535-.607 1.5421-.2794 1.8396-.3157.8318.3886.091.3946-.3278.8075-1.967.4857-2.3072.4614-3.4364.8136-.0425.0304.0486.0607 1.5482.1457.6618.0364h1.621l3.0175.2247.7892.522.4736.6376-.079.4857-1.2142.6193-1.6393-.3886-3.825-.9107-1.3113-.3279h-.1822v.1093l1.0929 1.0686 2.0035 1.8092 2.5075 2.3314.1275.5768-.3218.4554-.34-.0486-2.2039-1.6575-.85-.7468-1.9246-1.621h-.1275v.17l.4432.6496 2.3436 3.5214.1214 1.0807-.17.3521-.6071.2125-.6679-.1214-1.3721-1.9246L14.38 17.959l-1.1414-1.9428-.1397.079-.674 7.2552-.3156.3703-.7286.2793-.6071-.4614-.3218-.7468.3218-1.4753.3886-1.9246.3157-1.53.2853-1.9004.17-.6314-.0121-.0425-.1397.0182-1.4328 1.9672-2.1796 2.9446-1.7243 1.8456-.4128.164-.7164-.3704.0667-.6618.4008-.5889 2.386-3.0357 1.4389-1.882.929-1.0868-.0062-.1579h-.0546l-6.3385 4.1164-1.1293.1457-.4857-.4554.0608-.7467.2307-.2429 1.9064-1.3114Z'
$script:NaranjaClaude = '#D97757'
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

    $marca = New-Object Windows.Shapes.Path
    $marca.Data = [Windows.Media.Geometry]::Parse($script:PathClaude)
    $marca.Stretch = 'Uniform'
    $marca.Width = 11
    $marca.Height = 11
    $marca.VerticalAlignment = 'Center'
    $marca.Margin = [Windows.Thickness]::new(0, 1, 5, 0)
    $marca.Fill = Pincel $script:NaranjaClaude
    [Windows.Controls.DockPanel]::SetDock($marca, 'Left')
    $panel.Children.Add($marca) | Out-Null

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
