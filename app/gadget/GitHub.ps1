# =============================================================================
#  GitHub.ps1 - Con que cuenta de GitHub estas parado, y saltar a la otra.
# -----------------------------------------------------------------------------
#  Existe por un problema real: la cuenta activa de gh es GLOBAL de la maquina y
#  otra sesion te la puede dar vuelta sin avisar. Paso dos veces: un repo se
#  creo en la cuenta equivocada, y un push casi sale con la otra. Verlo en el
#  panel es la diferencia entre enterarte antes o despues.
#
#  La cuenta NO se pregunta con "gh auth status": eso es un proceso nuevo en
#  cada refresco. Sale del hosts.yml de gh, que es chico y NO tiene tokens
#  adentro (van al keyring), asi que leerlo es gratis y no expone nada.
# =============================================================================

# El logo es el octicon "mark-github" de GitHub (Primer, MIT). Es un path, o
# sea TEXTO: no entra ningun binario al repo.
$script:PathGitHub = 'M6.766 11.328c-2.063-.25-3.516-1.734-3.516-3.656 0-.781.281-1.625.75-2.188-.203-.515-.172-1.609.063-2.062.625-.078 1.468.25 1.968.703.594-.187 1.219-.281 1.985-.281.765 0 1.39.094 1.953.265.484-.437 1.344-.765 1.969-.687.218.422.25 1.515.046 2.047.5.593.766 1.39.766 2.203 0 1.922-1.453 3.375-3.547 3.64.531.344.89 1.094.89 1.954v1.625c0 .468.391.734.86.547C13.781 14.359 16 11.53 16 8.03 16 3.61 12.406 0 7.984 0 3.563 0 0 3.61 0 8.031a7.88 7.88 0 0 0 5.172 7.422c.422.156.828-.125.828-.547v-1.25c-.219.094-.5.156-.75.156-1.031 0-1.64-.562-2.078-1.609-.172-.422-.36-.672-.719-.719-.187-.015-.25-.093-.25-.187 0-.188.313-.328.625-.328.453 0 .844.281 1.25.86.313.452.64.655 1.031.655s.641-.14 1-.5c.266-.265.47-.5.657-.656'

function Get-RutaHostsGh {
    if ($env:GH_CONFIG_DIR) { return (Join-Path $env:GH_CONFIG_DIR 'hosts.yml') }
    return (Join-Path $env:APPDATA 'GitHub CLI\hosts.yml')
}

# @{ Activa = 'login' o $null; Todas = @(logins) }. Parser a mano y no un modulo
# de YAML: el archivo son cuatro renglones con sangria fija y PS 5.1 no trae uno.
function Get-CuentasGh {
    param([string]$Hosts = (Get-RutaHostsGh))

    $r = @{ Activa = $null; Todas = @() }
    try {
        if (-not (Test-Path -LiteralPath $Hosts)) { return $r }
        $host_ = ''
        $enUsers = $false
        foreach ($linea in (Get-Content -LiteralPath $Hosts -ErrorAction Stop)) {
            if ($linea -match '^(\S[^:]*):\s*$') { $host_ = $Matches[1]; $enUsers = $false; continue }
            if ($host_ -ne 'github.com') { continue }
            # Cualquier clave del host corta la lista de usuarios, tambien "user:"
            if ($linea -match '^\s{1,4}\S') { $enUsers = ($linea -match '^\s{1,4}users:\s*$') }
            if ($enUsers) {
                if ($linea -match '^\s{5,}([^\s:]+):') { $r.Todas += $Matches[1] }
                continue
            }
            if ($linea -match '^\s{1,4}user:\s*(\S+)\s*$') { $r.Activa = $Matches[1] }
        }
    } catch { }
    return $r
}

# gh es de consola: sin CreateNoWindow le aparece una ventana al usuario, que es
# justo lo que el lanzador se ocupa de evitar. Devuelve '' si salio bien.
function Invoke-Gh {
    param([Parameter(Mandatory)][string[]]$Comando)
    try {
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = 'gh'
        $psi.Arguments = ($Comando | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $p = [Diagnostics.Process]::Start($psi)
        $err = $p.StandardError.ReadToEnd()
        $p.StandardOutput.ReadToEnd() | Out-Null
        $p.WaitForExit(15000) | Out-Null
        if ($p.ExitCode -ne 0) { return ($err.Trim() -split "`n")[0] }
        return ''
    } catch { return $_.Exception.Message }
}


# gh auth login es INTERACTIVO: pide elegir protocolo, abre el navegador y
# espera un codigo. Por eso este si abre una terminal visible, al reves que
# todo lo demas del panel, que se esconde a proposito.
function Open-LoginGh {
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoExit', '-Command', 'gh auth login'
    } catch { }
}
function Set-ChipGitHub {
    $g = Get-CuentasGh
    $panel = New-Object Windows.Controls.StackPanel
    $panel.Orientation = 'Horizontal'

    $gato = New-Object Windows.Shapes.Path
    $gato.Data = [Windows.Media.Geometry]::Parse($script:PathGitHub)
    $gato.Stretch = 'Uniform'
    $gato.Width = 12
    $gato.Height = 12
    $gato.VerticalAlignment = 'Center'
    $gato.Margin = [Windows.Thickness]::new(0, 1, 5, 0)
    $panel.Children.Add($gato) | Out-Null

    $texto = New-Object Windows.Controls.TextBlock
    $texto.FontSize = 10.5
    $texto.VerticalAlignment = 'Center'
    $panel.Children.Add($texto) | Out-Null

    if ($g.Activa) {
        # El mismo verde que la cuenta de Claude: son la misma clase de dato.
        $gato.Fill = Pincel '#4FA878'
        $texto.Text = $g.Activa
        $texto.Foreground = Pincel '#86EFAC'
        $otras = @($g.Todas).Count - 1
        $btnGitHub.ToolTip = "GitHub: $($g.Activa)`nOJO: la cuenta de gh es de TODA la maquina" +
        $(if ($otras -gt 0) { "`nClick para elegir entre las $($g.Todas.Count) cuentas" }
            else { "`nClick para entrar con otra" })
    } else {
        # Apagado y en gris: se ve que hay algo y que no esta puesto.
        $gato.Fill = Pincel '#6B7484'
        $texto.Text = 'iniciar sesión'
        $texto.Foreground = Pincel '#8A94A6'
        $btnGitHub.ToolTip = "No hay ninguna cuenta de GitHub logueada`nClick para entrar con una"
    }
    $btnGitHub.Content = $panel
}

# Una fila del selector: el login a la izquierda y, si es la puesta, "en uso".
function New-FilaGh($Login, $Activa, $Estilo) {
    $b = New-Object Windows.Controls.Button
    $b.Style = $Estilo
    $b.Tag = $Login
    $b.Margin = [Windows.Thickness]::new(0, 0, 0, 7)
    $b.HorizontalContentAlignment = 'Stretch'

    $g = New-Object Windows.Controls.Grid
    foreach ($ancho in 'Auto', '*', 'Auto') {
        $c = New-Object Windows.Controls.ColumnDefinition
        $c.Width = [Windows.GridLength]::new(1, $(if ($ancho -eq '*') { 'Star' } else { 'Auto' }))
        $g.ColumnDefinitions.Add($c)
    }

    $marca = New-Object Windows.Shapes.Path
    $marca.Data = [Windows.Media.Geometry]::Parse($script:PathGitHub)
    $marca.Stretch = 'Uniform'
    $marca.Width = 13
    $marca.Height = 13
    $marca.VerticalAlignment = 'Center'
    $marca.Margin = [Windows.Thickness]::new(0, 0, 9, 0)
    $marca.Fill = Pincel $(if ($Activa) { '#4FA878' } else { '#8A94A6' })
    $g.Children.Add($marca) | Out-Null

    $nom = New-Object Windows.Controls.TextBlock
    $nom.Text = [string]$Login
    $nom.FontSize = 12
    $nom.FontWeight = 'SemiBold'
    $nom.VerticalAlignment = 'Center'
    $nom.Foreground = Pincel $(if ($Activa) { '#F2F5F9' } else { '#C7CEDA' })
    [Windows.Controls.Grid]::SetColumn($nom, 1)
    $g.Children.Add($nom) | Out-Null

    $est = New-Object Windows.Controls.TextBlock
    $est.Text = if ($Activa) { 'en uso' } else { '' }
    $est.FontSize = 10.5
    $est.VerticalAlignment = 'Center'
    $est.Foreground = Pincel '#86EFAC'
    [Windows.Controls.Grid]::SetColumn($est, 2)
    $g.Children.Add($est) | Out-Null

    $b.Content = $g
    if ($Activa) {
        # La que ya esta puesta no se clickea: no hay nada que cambiar, y un
        # boton que no hace nada se siente roto.
        $b.IsHitTestVisible = $false
        $b.Focusable = $false
        $b.Opacity = 0.72
    } else {
        $b.ToolTip = "Pasar a $Login"
        $b.Add_Click({
                $v = [Windows.Window]::GetWindow($this)
                $v.Tag = $this.Tag
                $v.DialogResult = $true
            })
    }
    return $b
}

# El selector, con el MISMO dialogo que el de Claude: cambian el logo, el titulo
# y las filas. Devuelve @{ Accion = 'cambiar' | 'login' | 'nada'; Login }.
function Show-SelectorGitHub {
    $g = Get-CuentasGh
    $d = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$script:xamlCuentas)))
    $ico = $d.FindName('icono')
    $ico.Data = [Windows.Media.Geometry]::Parse($script:PathGitHub)
    $ico.Fill = Pincel '#8A94A6'
    $d.FindName('titulo').Text = 'Cuenta de GitHub'

    # $filas y no $lista: gadget.ps1 tiene su propio $lista al alcance y el
    # ShowDialog de abajo sigue bombeando el timer. Ver Cuentas.ps1.
    $filas = $d.FindName('lista')
    $estilo = $d.Resources['Fila']
    foreach ($login in @($g.Todas)) {
        $filas.Children.Add((New-FilaGh $login ($login -eq $g.Activa) $estilo)) | Out-Null
    }

    $expl = $d.FindName('explicacion')
    $av = $d.FindName('aviso')
    if (@($g.Todas).Count -eq 0) {
        $expl.Text = 'No hay ninguna cuenta de GitHub logueada. Entrá con una y desde ese momento vas a poder saltar entre las que tengas.'
        $av.Visibility = 'Collapsed'
    } elseif (@($g.Todas).Count -eq 1) {
        $expl.Text = 'Por ahora conozco una sola cuenta. Entrá con otra y desde ese momento vas a poder saltar entre las dos.'
        $av.Visibility = 'Collapsed'
    } else {
        $expl.Text = 'Clickeá la cuenta que quieras usar.'
        $av.Text = 'Ojo: la cuenta de gh es de TODA la máquina. El cambio vale para las terminales que ya tenés abiertas y para cualquier push que hagas después.'
    }

    $d.Owner = $ventana
    $d.FindName('btnOtra').Content = 'Entrar con otra cuenta'
    $d.FindName('btnOtra').Add_Click({
            $v = [Windows.Window]::GetWindow($this)
            $v.Tag = 'login'
            $v.DialogResult = $true
        })
    $d.FindName('tarjeta').Add_MouseLeftButtonDown({
            try { [Windows.Window]::GetWindow($this).DragMove() } catch { }
        })
    $d.Add_Loaded({ $this.FindName('btnCerrar').Focus() | Out-Null })

    if ($d.ShowDialog() -ne $true) { return @{ Accion = 'nada'; Login = '' } }
    if ($d.Tag -ceq 'login') { return @{ Accion = 'login'; Login = '' } }
    return @{ Accion = 'cambiar'; Login = [string]$d.Tag }
}

# Lo que se hace con el resultado. Cambiar NO pregunta de nuevo: el dialogo ya
# fue la eleccion, y el aviso de que gh es global esta ahi adentro.
function Show-DialogoGitHub {
    $r = Show-SelectorGitHub
    if ($r.Accion -eq 'login') { Open-LoginGh; return }
    if ($r.Accion -ne 'cambiar' -or -not $r.Login) { return }
    $falla = Invoke-Gh -Comando @('auth', 'switch', '--user', $r.Login)
    Set-ChipGitHub
    if ($falla) {
        [Windows.MessageBox]::Show("No pude cambiar de cuenta:`n`n$falla", 'Hilos de Claudio',
            'OK', 'Warning') | Out-Null
    }
}
