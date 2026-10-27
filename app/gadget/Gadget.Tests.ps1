# =============================================================================
#  Test de carga del gadget
# -----------------------------------------------------------------------------
#  Se corre a mano:  powershell -NoProfile -File gadget\Gadget.Tests.ps1
#  Sale 0 si todo pasa, 1 si algo falla.
#
#  NO abre la ventana. Hace lo mismo que gadget.ps1 al arrancar -- cargar las
#  librerias, las piezas y el XAML -- y verifica que quede todo en pie. Eso
#  alcanza para agarrar la clase de bug que aparece al partir un archivo grande:
#  una pieza que se carga antes de la dependencia que necesita, un x:Name que se
#  quedo sin su FindName, una funcion que se perdio en el corte.
#
#  Ya atajo uno de verdad: Tarjeta.ps1 arma el ControlTemplate de los botones a
#  nivel superior, asi que necesita el Add-Type de WPF ANTES. Con el dot-source
#  puesto antes, el gadget no abria.
# =============================================================================
$ErrorActionPreference = 'Stop'

$script:fallas = 0
$script:pasados = 0
function Probar([string]$Que, [scriptblock]$Bloque) {
    try { & $Bloque; Write-Host ("  OK    {0}" -f $Que); $script:pasados++ }
    catch {
        Write-Host ("  FALLA {0}" -f $Que) -ForegroundColor Red
        Write-Host ("        {0}" -f $_.Exception.Message) -ForegroundColor Red
        $script:fallas++
    }
}
function Afirmar([bool]$Cond, [string]$Mensaje) { if (-not $Cond) { throw $Mensaje } }

$carpeta = Split-Path -Parent $PSScriptRoot

Write-Host ''
Write-Host '=== carga, en el mismo orden que gadget.ps1 ==='

# OJO: la carga va al NIVEL SUPERIOR del test y no adentro de un Probar { }.
# Un scriptblock invocado con & abre un scope nuevo, asi que dot-sourcear ahi
# adentro deja las funciones y $xaml encerradas y despues "no existe nada".
# Es la misma trampa de scoping que hay documentada en Datos.psm1.
# Las librerias y las piezas se SACAN de gadget.ps1, no se listan a mano: la
# lista duplicada se desincroniza sola. Paso: se agrego una pieza al gadget y el
# test seguia cargando las de antes, asi que probaba una carga que ya no existe.
$script:fuenteGadget = Get-Content -LiteralPath (Join-Path $carpeta 'gadget.ps1') -Raw
$libs = @([regex]::Matches($script:fuenteGadget, "\.\s+\(Join-Path \`$carpeta '([^']+\.ps1)'\)") |
    ForEach-Object { $_.Groups[1].Value })
if ($libs.Count -lt 2) { throw "no pude leer las librerias de gadget.ps1 (encontre $($libs.Count))" }
foreach ($lib in $libs) { . (Join-Path $carpeta $lib) }

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

if ($script:fuenteGadget -notmatch "foreach \(\`$pieza in ([^)]+)\) \{") {
    throw 'no pude leer la lista de piezas de gadget.ps1'
}
$piezas = @([regex]::Matches($Matches[1], "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
if ($piezas.Count -lt 5) { throw "esperaba varias piezas, lei $($piezas.Count)" }
foreach ($pieza in $piezas) { . (Join-Path $carpeta "gadget\$pieza.ps1") }
Write-Host ("  OK    {0} librerias, WPF y las {1} piezas cargaron sin explotar" -f $libs.Count, $piezas.Count)
$script:pasados++
Probar 'el ControlTemplate de los botones quedo armado' {
    # Es codigo de nivel superior en Tarjeta.ps1 y necesita WPF ya cargado: si
    # el dot-source se adelanta al Add-Type, esto queda en $null.
    Afirmar ($null -ne $script:tplPlano) 'tplPlano quedo nulo: se cargo Tarjeta.ps1 antes del Add-Type?'
}

Write-Host ''
Write-Host '=== lo que cada pieza tiene que dejar ==='

Probar 'Xaml.ps1 define $xaml y es XAML valido' {
    Afirmar ($null -ne $xaml -and $xaml.Length -gt 100) 'no quedo definido $xaml'
    $v = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$xaml)))
    Afirmar ($null -ne $v) 'el XAML no cargo'
    $script:ventanaPrueba = $v
}
Probar 'todos los x:Name que busca gadget.ps1 existen en el XAML' {
    # Se sacan del propio gadget.ps1 en vez de listarlos a mano: si manana
    # alguien agrega un FindName y se olvida del XAML, este test lo agarra.
    $txt = Get-Content -LiteralPath (Join-Path $carpeta 'gadget.ps1') -Raw
    $nombres = [regex]::Matches($txt, "FindName\('([^']+)'\)") |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    Afirmar ($nombres.Count -gt 5) "esperaba varios FindName, encontre $($nombres.Count)"
    $faltan = @($nombres | Where-Object { -not $script:ventanaPrueba.FindName($_) })
    Afirmar ($faltan.Count -eq 0) ("el XAML no tiene: " + ($faltan -join ', '))
    Write-Host ("        ({0} x:Name verificados)" -f $nombres.Count)
}
Probar 'las funciones de cada pieza estan definidas' {
    $esperadas = @{
        'Apariencia.ps1'   = 'Get-ColorTarjeta', 'Get-ColorHover', 'Pincel', 'Set-IconoVentana',
        'Write-Falla', 'New-Sombra', 'Set-Apariencia', 'Get-ColorContexto', 'Escapar', 'Set-EntradaPanel', 'Start-EntradaPanel'
        'Confirmacion.ps1' = , 'Show-Confirmacion'
        'Etiquetas.ps1'    = 'Get-ColorEtiqueta', 'New-ChipEtiqueta', 'Open-EtiquetasTarjeta',
        'Show-Etiquetas', 'New-DialogoEtiquetas'
        'Tarjeta.ps1'      = 'New-Tarjeta', 'New-TarjetaArchivada', 'Get-MarcoTarjeta'
        'Cuota.ps1'        = 'Get-CuotaReal', 'Set-Resumen'
        'Orden.ps1'        = 'Start-Arrastre', 'Move-Arrastre', 'Stop-Arrastre', 'Get-IdsDeLaLista'
        'Instalacion.ps1'  = , 'Invoke-ChequeoSetup'
        'Cuenta.ps1'       = 'Get-CuentaClaude', 'Set-ChipCuenta', 'Show-DialogoCuenta'
        'Cuentas.ps1'      = 'Show-SelectorCuentas', 'New-FilaCuenta', 'Get-EstadoCuenta',
        'Get-SubtituloCuenta', 'Open-LoginClaude'
        'Ayuda.ps1'        = 'Show-Ayuda', 'New-VentanaAyuda', 'New-TextoAyuda', 'New-GlifoAyuda'
    }
    foreach ($pieza in $esperadas.Keys) {
        foreach ($f in $esperadas[$pieza]) {
            Afirmar ([bool](Get-Command $f -ErrorAction SilentlyContinue)) "falta $f (de $pieza)"
        }
    }
}
Probar 'la capa de Datos llego a traves de la libreria' {
    # Set-OrdenConversacion incluida: es la que necesita Orden.ps1 para guardar
    # el arrastre, y si se cae del modulo el arrastre falla recien al soltar.
    foreach ($f in 'Get-Conversacion', 'Set-Conversacion', 'Remove-Conversacion',
        'Set-OrdenConversacion') {
        Afirmar ([bool](Get-Command $f -ErrorAction SilentlyContinue)) "falta $f"
    }
}

function Textos-De($Elemento) {
    $acum = @()
    if ($Elemento -is [Windows.Controls.TextBlock]) { return , @([string]$Elemento.Text) }
    $hijos = @()
    if ($Elemento -is [Windows.Controls.Panel]) { $hijos = $Elemento.Children }
    elseif ($Elemento -is [Windows.Controls.ContentControl] -and $Elemento.Content) { $hijos = @($Elemento.Content) }
    foreach ($h in $hijos) { $acum += Textos-De $h }
    return , @($acum)
}

Probar 'la fila de una cuenta lleva el mail, la org y el estado' {
    # Atajo un bug de verdad: un $c en el loop de columnas pisaba el parametro
    # $C --PowerShell no distingue mayusculas en los nombres de variable-- y la
    # fila salia VACIA, sin un solo error en consola.
    $cta = @{ Mail = 'ana@x.com'; Org = 'GIA'; Plan = 'max'; Activa = $false; Vencida = $false; Dias = 12 }
    $t = (Textos-De (New-FilaCuenta $cta $null)) -join ' | '
    Afirmar ($t -match 'ana@x\.com') "no puso el mail: $t"
    Afirmar ($t -match 'GIA') "no puso la org: $t"
    Afirmar ($t -match 'vence en 12') "no puso el estado: $t"
}
Probar 'el subtitulo no repite el mail que ya esta arriba' {
    # Una cuenta personal trae la org llamada "<mail>'s Organization", y quedaba
    # el mail dos veces, una abajo de la otra.
    $personal = @{ Mail = 'ana@gmail.com'; Org = "ana@gmail.com's Organization"; Plan = 'pro' }
    Afirmar ((Get-SubtituloCuenta $personal) -ceq 'pro') "quedo: $(Get-SubtituloCuenta $personal)"
    $laburo = @{ Mail = 'ana@gia.com'; Org = 'GIA'; Plan = 'max' }
    Afirmar ((Get-SubtituloCuenta $laburo) -match 'GIA') 'se comio una org que si aporta'
    Afirmar ((Get-SubtituloCuenta $laburo) -match 'max') 'se comio el plan'
}
Probar 'la cuenta en uso se marca y no se puede clickear' {
    $cta = @{ Mail = 'ana@x.com'; Org = 'GIA'; Plan = 'max'; Activa = $true; Vencida = $false; Dias = 12 }
    $b = New-FilaCuenta $cta $null
    Afirmar (-not $b.IsHitTestVisible) 'la cuenta activa quedo clickeable'
    Afirmar (((Textos-De $b) -join ' ') -match 'en uso') 'no dice que esta en uso'
}
Probar 'una cuenta vencida se ofrece igual, marcada como vencida' {
    $cta = @{ Mail = 'vieja@x.com'; Org = 'X'; Plan = 'max'; Activa = $false; Vencida = $true; Dias = -4 }
    $b = New-FilaCuenta $cta $null
    Afirmar ($b.IsHitTestVisible) 'no se puede elegir una cuenta vencida'
    Afirmar (((Textos-De $b) -join ' ') -match 'vencida') 'no la marca como vencida'
}

Write-Host ''
Write-Host '=== etiquetas ==='

$script:halos = @{}
function Tarjeta-Con([object[]]$Etiquetas) {
    $conv = [pscustomobject]@{
        id = 'prueba'; titulo = 'Prueba'; cwd = 'C:\no\existe'; sesion = [guid]::NewGuid().ToString()
        proyecto = 'p'; rama = 'r'; recap = $null; etiquetas = @($Etiquetas)
    }
    New-Tarjeta -C $conv -Ctx @{ Hay = $false }
}
# El WrapPanel de las etiquetas, o $null si la tarjeta no tiene.
function Chips-De($Tarjeta) {
    $fila = [Windows.LogicalTreeHelper]::FindLogicalNode($Tarjeta, 'filaDato')
    if (-not $fila) { throw 'la tarjeta no tiene el renglon filaDato' }
    $fila.Children | Where-Object { $_ -is [Windows.Controls.WrapPanel] } | Select-Object -First 1
}

Probar 'las etiquetas van abajo a la DERECHA, debajo del dato, y en orden' {
    # El dato del contexto se fue debajo de la barra, asi que este renglon
    # quedo solo para las etiquetas. Van contra el borde derecho: el rincon
    # de abajo a la izquierda se deja libre a proposito.
    $t = Tarjeta-Con @([pscustomobject]@{ id = 1; nombre = 'front'; color = 'azul' },
        [pscustomobject]@{ id = 2; nombre = 'urgente'; color = 'rojo' })
    $chips = Chips-De $t
    Afirmar ($null -ne $chips) 'no puso las etiquetas'
    $nombres = @($chips.Children | ForEach-Object { $_.Child.Text })
    Afirmar (($nombres -join ',') -eq 'front,urgente') "quedo [$($nombres -join ',')]"
    Afirmar ($chips.HorizontalAlignment -eq 'Right') "quedaron a la $($chips.HorizontalAlignment)"
    $rojo = $chips.Children[1].Background.Color.ToString()
    Afirmar ($rojo -eq '#FFF87171') "urgente no salio roja: $rojo"
}
Probar 'sin etiquetas la tarjeta no agrega nada' {
    Afirmar ($null -eq (Chips-De (Tarjeta-Con @()))) 'dibujo un panel de etiquetas vacio'
}
Probar 'un color que ya no esta en la paleta cae a gris' {
    Afirmar ((Get-ColorEtiqueta 'fucsia') -eq $script:PALETA_ETIQUETAS['gris']) 'no cayo a gris'
    Afirmar ((Get-ColorEtiqueta 'azul') -eq '#60A5FA') 'no respeto la paleta'
}
Probar 'el popup de etiquetas se arma con todo lo que busca' {
    $d = New-DialogoEtiquetas -Conversacion ([pscustomobject]@{ id = 'no-existe-en-la-base'; titulo = 'X' })
    foreach ($n in 'nombre', 'listaEtiquetas', 'vacio', 'tituloForm', 'txtNombre', 'paleta', 'error',
        'btnCrear', 'btnCancelarEdicion', 'btnListo') {
        Afirmar ($null -ne $d.FindName($n)) "falta $n"
    }
    Afirmar ($d.FindName('paleta').Children.Count -eq $script:PALETA_ETIQUETAS.Count) 'la paleta no tiene todos los colores'
    $d.Close()
}

function Descendientes($Elemento) {
    foreach ($h in [Windows.LogicalTreeHelper]::GetChildren($Elemento)) {
        if ($h -is [Windows.DependencyObject]) { $h; Descendientes $h }
    }
}
# Los tooltips de las dos salidas. Se escriben UNA vez y los usan los dos tests:
# si manana cambia el texto, hay que cambiarlo aca y nada mas.
$script:TIPS_SALIDA = 'Quitar del panel', 'Borrar la conversacion de verdad (no se puede deshacer)'

function Tips-De($Tarjeta) {
    , @(Descendientes $Tarjeta |
        Where-Object { $_ -is [Windows.Controls.Button] } |
        ForEach-Object { [string]$_.ToolTip })
}

Probar 'en el archivo la tarjeta es corta, pero se puede desarchivar Y sacar' {
    $conv = [pscustomobject]@{
        id = 'archivada'; titulo = 'Archivada'; cwd = 'C:\no\existe'; sesion = [guid]::NewGuid().ToString()
        proyecto = 'p'; rama = 'r'; recap = 'este recap no se tiene que ver'
        etiquetas = @([pscustomobject]@{ id = 1; nombre = 'front'; color = 'azul' })
    }
    $t = New-TarjetaArchivada -C $conv
    $todo = @(Descendientes $t)
    $textos = @($todo | Where-Object { $_ -is [Windows.Controls.TextBlock] } | ForEach-Object { $_.Text })
    Afirmar ($textos -notcontains 'este recap no se tiene que ver') 'se colo el recap'
    Afirmar (-not ($textos | Where-Object { $_ -match 'transcript|%' })) "se colo el contexto: $($textos -join ' | ')"
    $tips = Tips-De $t
    Afirmar ($tips.Count -eq 3) "esperaba desarchivar + las dos salidas, hay $($tips.Count): $($tips -join ' | ')"
    Afirmar (@($tips | Where-Object { $_ -match 'Desarchivar' }).Count -eq 1) "falta desarchivar: $($tips -join ' | ')"
    foreach ($tip in $script:TIPS_SALIDA) {
        Afirmar ($tips -contains $tip) "en el archivo falta '$tip': $($tips -join ' | ')"
    }
    Afirmar ($null -eq $t.Cursor) 'la tarjeta invita a clickearla y no abre nada'
    Afirmar ($textos -contains 'front') 'no muestra las etiquetas'
}
Probar 'las dos salidas dicen lo mismo en el panel que en el archivo' {
    # El punto de esto NO es que exista el boton: es que el glifo signifique lo
    # mismo en las dos vistas. Si alguien toca un texto en un solo lado, falla.
    $conv = [pscustomobject]@{
        id = 'comparar'; titulo = 'Comparar'; cwd = 'C:\no\existe'; sesion = [guid]::NewGuid().ToString()
        proyecto = 'p'; rama = 'r'; recap = $null; etiquetas = @()
    }
    $enArchivo = Tips-De (New-TarjetaArchivada -C $conv)
    $enPanel = Tips-De (Tarjeta-Con @())
    foreach ($tip in $script:TIPS_SALIDA) {
        Afirmar ($enPanel -contains $tip) "el panel ya no dice '$tip': $($enPanel -join ' | ')"
        Afirmar ($enArchivo -contains $tip) "el archivo ya no dice '$tip': $($enArchivo -join ' | ')"
    }
}



Write-Host ''
Write-Host '=== la cuenta de GitHub ==='

Probar 'lee la cuenta activa y las demas del hosts.yml de gh' {
    $yml = Join-Path $env:TEMP ("gh-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".yml")
    @"
github.com:
    git_protocol: https
    users:
        Irionx:
        skozak-GIA:
    user: skozak-GIA
"@ | Set-Content -LiteralPath $yml -Encoding UTF8
    try {
        $g = Get-CuentasGh -Hosts $yml
        Afirmar ($g.Activa -eq 'skozak-GIA') "la activa dio [$($g.Activa)]"
        Afirmar (@($g.Todas).Count -eq 2) "vio $(@($g.Todas).Count) cuentas, esperaba 2"
        Afirmar ($g.Todas -contains 'Irionx') 'no vio la otra cuenta'
        # "user:" es la clave que dice cual esta activa, NO una cuenta mas. Se
        # parece tanto a "users:" que es el error natural del parser.
        Afirmar (-not ($g.Todas -contains 'user')) 'se comio user: como si fuera una cuenta'
    } finally { Remove-Item -LiteralPath $yml -Force -ErrorAction SilentlyContinue }
}

Probar 'sin archivo, o con una ruta invalida, no explota ni inventa cuentas' {
    # GH_CONFIG_DIR lo pone el usuario y esto corre en CADA refresco: con una
    # ruta invalida Test-Path tira excepcion y se llevaria puesto el panel.
    foreach ($ruta in @((Join-Path $env:TEMP 'no-existe-gh.yml'), 'C:\ruta|invalida\x.yml')) {
        $g = Get-CuentasGh -Hosts $ruta
        Afirmar ($null -eq $g.Activa) "con [$ruta] invento una cuenta activa"
        Afirmar (@($g.Todas).Count -eq 0) "con [$ruta] invento cuentas"
    }
}

Probar 'la fila de la cuenta en uso no se puede clickear, y la otra si' {
    # Un boton que no hace nada se siente roto: la cuenta que ya esta puesta se
    # muestra apagada y sin click. Es el mismo criterio que el selector de Claude.
    $activa = New-FilaGh 'skozak-GIA' $true $null
    $otra = New-FilaGh 'Irionx' $false $null
    Afirmar (-not $activa.IsHitTestVisible) 'la cuenta en uso se deja clickear'
    Afirmar ($otra.IsHitTestVisible) 'la otra cuenta NO se deja clickear'
    Afirmar ($otra.Tag -eq 'Irionx') "la fila no lleva su login: [$($otra.Tag)]"
    Afirmar ($otra.ToolTip -match 'Pasar a Irionx') "no dice a donde va: $($otra.ToolTip)"
    $textos = @($activa.Content.Children | Where-Object { $_ -is [Windows.Controls.TextBlock] } |
        ForEach-Object { $_.Text })
    Afirmar ($textos -contains 'en uso') "la activa no dice 'en uso': [$($textos -join '|')]"
    Afirmar (@($otra.Content.Children | Where-Object { $_ -is [Windows.Shapes.Path] }).Count -eq 1) `
        'la fila no lleva el logo de GitHub'
}
Probar 'un mail largo se recorta y NO empuja al chip de GitHub fuera del renglon' {
    # El motivo del MaxWidth. Medido: las dos cuentas juntas son 233 de los 294
    # utiles, pero un mail mas largo empujaria el gato fuera de la ventana.
    $v = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$xaml)))
    $raiz = $v.Content
    $v.Content = $null
    $cuenta = [Windows.LogicalTreeHelper]::FindLogicalNode($raiz, 'btnCuenta')
    $gh = [Windows.LogicalTreeHelper]::FindLogicalNode($raiz, 'btnGitHub')

    foreach ($mail in @('seba@x.com', 'un-mail-absurdamente-largo-que-no-entra-jamas@subdominio.empresa.com')) {
        $t = New-Object Windows.Controls.TextBlock
        $t.Text = $mail; $t.FontSize = 10.5; $t.TextTrimming = 'CharacterEllipsis'
        $cuenta.Content = $t
        $gh.Content = 'skozak-GIA'
        $raiz.Width = 348
        $raiz.Measure([Windows.Size]::new(348, [double]::PositiveInfinity))
        $raiz.Arrange([Windows.Rect]::new(0, 0, 348, $raiz.DesiredSize.Height))
        $raiz.UpdateLayout()
        $der = $gh.TransformToAncestor($raiz).Transform([Windows.Point]::new(0, 0)).X + $gh.ActualWidth
        Afirmar ($gh.ActualWidth -gt 0) "con [$mail] el chip de GitHub quedo en cero"
        Afirmar ($der -le 322) "con un mail de $($mail.Length) el gato termina en $([math]::Round($der,1)), fuera del panel"
    }
}
Write-Host ''
Write-Host '=== la barra de scroll ==='

# El arbol VISUAL: lo que arma un ControlTemplate (la barra, la pastilla) no esta
# en el logico, asi que Descendientes no lo encuentra.
function Visual-Llamado($Nodo, [string]$Nombre) {
    if ($Nodo -is [Windows.FrameworkElement] -and $Nodo.Name -eq $Nombre) { return $Nodo }
    for ($i = 0; $i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($Nodo); $i++) {
        $r = Visual-Llamado ([Windows.Media.VisualTreeHelper]::GetChild($Nodo, $i)) $Nombre
        if ($r) { return $r }
    }
    return $null
}
function Izquierda($El, $Raiz) {
    $El.TransformToAncestor($Raiz).Transform([Windows.Point]::new(0, 0)).X
}

# Arma la ventana en memoria igual que gadget.ps1 y deja los controles tambien
# en $script:, no solo como locales. Hace falta de verdad: los handlers del
# cajon se disparan desde el reloj de una animacion, y ahi la resolucion por
# pila de llamadas no llega al scope de un Probar { }.
# Los nombres SE SACAN del XAML y no se listan a mano, por la misma razon que
# las piezas se sacan de gadget.ps1: una lista copiada se desincroniza sola.
function Armar-Ventana {
    # Las constantes tambien salen de gadget.ps1: copiadas, el dia que cambie un
    # padding el test seguiria probando el valor viejo.
    # Con $script: adelante, o quedan encerradas en el scope de esta funcion y
    # Set-Apariencia encuentra $PAD_NORMAL en $null.
    foreach ($linea in (Get-Content -LiteralPath (Join-Path $carpeta 'gadget.ps1'))) {
        if ($linea -match '^\$(AIRE_SOMBRA|PAD_|LOCK_|PIN_|CHEVRON_)') {
            Invoke-Expression ('$script:' + $linea.Substring(1))
        }
    }
    $v = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$xaml)))
    $script:ventana = $v
    $script:raiz = $v.Content
    $v.Content = $null
    foreach ($m in [regex]::Matches($xaml, 'x:Name="([^"]+)"')) {
        # Los que viven dentro de un ControlTemplate no estan en el arbol logico
        # y quedan en $null. No molesta: el que los necesita usa Visual-Llamado.
        Set-Variable -Name $m.Groups[1].Value -Scope Script `
            -Value ([Windows.LogicalTreeHelper]::FindLogicalNode($script:raiz, $m.Groups[1].Value))
    }
    $script:arriba = $false; $script:bloqueado = $false; $script:colapsado = $false
    $script:altoLista = 0; $script:altoPie = 0; $script:vistaCajon = ''
    return $script:raiz
}

Probar 'la pastilla del scroll va centrada en el canal, suelto y bloqueado' {
    $raiz = Armar-Ventana

    # Los dos modos, porque el canal sale del padding del panel y NO es el mismo:
    # suelto son 14 de padding; bloqueado son 2, y los otros 12 los pone el margen
    # de cada tarjeta. El hueco final tiene que dar igual en los dos.
    foreach ($modo in $false, $true) {
        $script:bloqueado = $modo
        Set-Apariencia
        # Las tarjetas se REHACEN en cada modo, que es lo que hace el candado de
        # verdad (gadget.ps1 llama a Actualizar). Reusando las de antes, el margen
        # para la sombra queda en el valor del modo anterior y la medicion miente.
        # Y van 20 para que el scroll exista: sin desborde no hay pastilla.
        $lista.Children.Clear()
        foreach ($i in 1..20) { $lista.Children.Add((Tarjeta-Con @())) | Out-Null }
        $raiz.Width = 348
        $raiz.Measure([Windows.Size]::new(348, [double]::PositiveInfinity))
        $raiz.Arrange([Windows.Rect]::new(0, 0, 348, $raiz.DesiredSize.Height))
        $raiz.UpdateLayout()

        $barra = Visual-Llamado $raiz 'PART_VerticalScrollBar'
        $pastilla = Visual-Llamado $raiz 'pastilla'
        Afirmar ($null -ne $pastilla) "no aparecio la pastilla (bloqueado=$modo)"
        # El tema de WPF le pone de MinWidth el ancho de scrollbar del sistema
        # (~17px) y MinWidth le gana a Width. Si esto vuelve a medir 17, se cayo
        # el Setter de MinWidth y la pastilla se monta sobre las tarjetas.
        Afirmar ([math]::Abs($barra.ActualWidth - 8) -lt 0.5) `
            "la barra mide $($barra.ActualWidth) y no 8 (bloqueado=$modo): volvio el MinWidth del tema"

        $tarjeta = $lista.Children[0]
        $izqPastilla = Izquierda $pastilla $raiz
        $derTarjeta = (Izquierda $tarjeta $raiz) + $tarjeta.ActualWidth
        $derFondo = (Izquierda $fondo $raiz) + $fondo.ActualWidth - $fondo.BorderThickness.Right
        $antes = $izqPastilla - $derTarjeta
        $despues = $derFondo - ($izqPastilla + $pastilla.ActualWidth)
        Afirmar ($antes -gt 2) `
            "la pastilla se monta sobre la tarjeta (bloqueado=$modo): $([math]::Round($antes,2))px"
        Afirmar ([math]::Abs($antes - $despues) -le 0.5) `
            "descentrada (bloqueado=$modo): $([math]::Round($antes,2)) de un lado, $([math]::Round($despues,2)) del otro"
    }
}

Write-Host ''
Write-Host '=== el cajon de la derecha ==='

Probar 'ningun .ps1 con acentos se quedo sin BOM' {
    # PowerShell 5.1 lee un .ps1 SIN BOM como ANSI: el "·" de un separador sale
    # "Â·" en pantalla. No falla, no avisa, y se ve recien en la ventana.
    # Se miran solo los archivos CON bytes no-ascii: los puramente ASCII dan
    # igual con BOM o sin el, y varios del repo nunca lo tuvieron.
    $sinBom = @()
    foreach ($f in (Get-ChildItem -LiteralPath (Split-Path -Parent $carpeta) -Recurse -Filter '*.ps1' -File)) {
        $bytes = [IO.File]::ReadAllBytes($f.FullName)
        if ($bytes.Length -lt 3) { continue }
        $tieneRaros = $false
        foreach ($b in $bytes) { if ($b -gt 127) { $tieneRaros = $true; break } }
        if (-not $tieneRaros) { continue }
        if ($bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) { $sinBom += $f.Name }
    }
    Afirmar ($sinBom.Count -eq 0) "tienen acentos y no tienen BOM: $($sinBom -join ', ')"
}

Probar 'todos los FindName de gadget.ps1 existen en el XAML' {
    # Un FindName que no existe devuelve $null en silencio y revienta recien al
    # primer .Add_Click, con la ventana ya abierta.
    $enXaml = @([regex]::Matches($xaml, 'x:Name="([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
    $faltan = @()
    foreach ($m in [regex]::Matches($script:fuenteGadget, "FindName\('([^']+)'\)")) {
        if ($enXaml -notcontains $m.Groups[1].Value) { $faltan += $m.Groups[1].Value }
    }
    Afirmar ($faltan.Count -eq 0) "gadget.ps1 busca controles que el XAML no tiene: $($faltan -join ', ')"
}

Probar 'el boton del cajon es un interruptor: abre, cambia de vista y cierra' {
    $null = Armar-Ventana
    # El historial lee el disco (1,4 s): se le ceba la cache para que el test no
    # dependa de lo que haya en ~/.claude/projects.
    $script:discoCache = @()
    $script:discoCacheHora = Get-Date

    Afirmar ($cajon.Visibility -eq 'Collapsed') 'el cajon arranca abierto'

    Set-Cajon -Vista 'historial'
    Afirmar ($script:vistaCajon -eq 'historial') "no abrio: '$($script:vistaCajon)'"
    Afirmar ($cajon.Visibility -eq 'Visible') 'abrio pero quedo colapsado'

    # Pedir la OTRA vista no cierra: cambia el contenido del mismo cajon.
    Set-Cajon -Vista 'archivadas'
    Afirmar ($script:vistaCajon -eq 'archivadas') 'no cambio de vista'
    Afirmar ($cajon.Visibility -eq 'Visible') 'cambiar de vista lo cerro'

    # Pedir la MISMA vista lo cierra: el boton es un interruptor.
    Set-Cajon -Vista 'archivadas'
    Afirmar ($script:vistaCajon -eq '') 'tocar la vista abierta no lo cerro'
}

Probar 'la ventana sigue al cajon y no se va de la pantalla' {
    $null = Armar-Ventana
    $wa = [Windows.SystemParameters]::WorkArea
    $script:ventana.Width = 348
    $script:ventana.Left = $wa.Right - 348        # pegado al borde derecho, como vive
    Sync-AnchoVentana -Delta 314
    Afirmar ($script:ventana.Width -eq 662) "la ventana quedo en $($script:ventana.Width), esperaba 662"
    # Creciendo contra el borde derecho, el que se corre es el IZQUIERDO.
    Afirmar (($script:ventana.Left + $script:ventana.Width) -le ($wa.Right + 0.5)) `
        "se fue de la pantalla: termina en $($script:ventana.Left + $script:ventana.Width), el area llega a $($wa.Right)"
    # El SizeChanged llega por cualquier relayout: con delta 0 no se toca nada.
    $antes = $script:ventana.Left
    Sync-AnchoVentana -Delta 0
    Afirmar ($script:ventana.Left -eq $antes) 'un delta de 0 movio la ventana'
}

Probar 'el historial lee el disco: encuentra sesiones y saltea lo que no lo es' {
    $raizFalsa = Join-Path $env:TEMP ('proj-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $proy = Join-Path $raizFalsa 'C--algun-proyecto'
    New-Item -ItemType Directory -Path $proy -Force | Out-Null
    $uuid = [guid]::NewGuid().ToString()
    $jsonl = Join-Path $proy "$uuid.jsonl"
    Set-Content -LiteralPath $jsonl -Encoding UTF8 -Value @(
        '{"type":"summary","leafUuid":"x"}',
        '{"cwd":"C:\\algun\\proyecto","aiTitle":"El titulo automatico"}')
    # Un .jsonl cuyo nombre no es un uuid NO es una sesion.
    Set-Content -LiteralPath (Join-Path $proy 'notas.jsonl') -Encoding UTF8 -Value '{}'
    # La carpeta del uuid existe al lado y su peso cuenta: se borra junto.
    $dirU = Join-Path $proy $uuid
    New-Item -ItemType Directory -Path $dirU -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $dirU 'custom-title.json') -Encoding UTF8 `
        -Value '{"customTitle":"El nombre de /rename"}'

    $viejo = $script:RaizProyectos
    try {
        $script:RaizProyectos = $raizFalsa
        $s = @(Get-SesionesEnDisco)
    } finally { $script:RaizProyectos = $viejo }

    Afirmar ($s.Count -eq 1) "esperaba 1 sesion y encontre $($s.Count)"
    Afirmar ($s[0].Sesion -eq $uuid) 'no devolvio el uuid de la sesion'
    Afirmar ($s[0].Cwd -eq 'C:\algun\proyecto') "el cwd salio mal: '$($s[0].Cwd)'"
    Afirmar ($s[0].Titulo -eq 'El nombre de /rename') `
        "el /rename tiene que ganarle al aiTitle, quedo '$($s[0].Titulo)'"
    Afirmar (-not $s[0].Guardada) 'la dio por guardada y no esta en el panel'
    Afirmar ($s[0].Bytes -gt (Get-Item -LiteralPath $jsonl).Length) `
        "el peso no sumo la carpeta del uuid: $($s[0].Bytes)"
    Remove-Item -LiteralPath $raizFalsa -Recurse -Force -ErrorAction SilentlyContinue
}

function Sesion-Falsa([string]$Titulo, [int64]$Bytes, [string]$Fecha, [bool]$Guardada, [string]$Cwd = 'C:\proy\uno') {
    [pscustomobject]@{
        Sesion = [guid]::NewGuid().ToString(); Dir = 'C:\no\existe'; Carpeta = 'C--x'
        Cwd    = $Cwd; Titulo = $Titulo; Bytes = $Bytes; Fecha = [datetime]$Fecha
        Guardada = $Guardada; Conv = $null
    }
}
# Deja el historial abierto con datos de mentira, sin tocar el disco.
function Historial-Con([object[]]$Sesiones) {
    $null = Armar-Ventana
    Connect-Cajon
    $script:discoCache = @($Sesiones)
    $script:discoCacheHora = Get-Date
    $script:vistaCajon = 'historial'
    $script:selloCajon = ''
    $script:histFiltro = ''
    $script:histOrden = 'fecha'
    $script:histSel = @{}
    Actualizar-Cajon
}
# El primer TextBlock de cada fila. Una fila puede ser un aviso suelto
# ("Nada que coincida"), que es un TextBlock y no un Border con tarjeta adentro.
function Titulos-Del-Cajon {
    , @($script:listaCajon.ItemsSource | ForEach-Object {
            if ($_ -is [Windows.Controls.TextBlock]) { return [string]$_.Text }
            $t = @(Descendientes $_ | Where-Object { $_ -is [Windows.Controls.TextBlock] })[0]
            [string]$t.Text
        })
}

Probar 'el cajon NO se rearma cuando no cambio nada' {
    # Es el arreglo de performance, y una regresion acá es invisible: la app
    # anda igual, solo que se come 609 ms cada 2 segundos. Medido.
    Historial-Con @((Sesion-Falsa 'uno' 100 '2026-10-01' $false),
        (Sesion-Falsa 'dos' 200 '2026-10-02' $true))
    $antes = $script:listaCajon.ItemsSource
    $cajas = @($script:histVistas | ForEach-Object { $_.Caja })
    Actualizar-Cajon
    Actualizar-Cajon
    Afirmar ([object]::ReferenceEquals($antes, $script:listaCajon.ItemsSource)) `
        'rearmo la lista entera sin que hubiera cambiado nada'
    Afirmar ([object]::ReferenceEquals($cajas[0], $script:histVistas[0].Caja)) `
        'rearmo las tarjetas sin que hubiera cambiado nada'
}

Probar 'el buscador filtra por nombre y por proyecto, sin rearmar tarjetas' {
    Historial-Con @((Sesion-Falsa 'planner v2' 100 '2026-10-01' $false),
        (Sesion-Falsa 'otra cosa' 200 '2026-10-02' $true -Cwd 'C:\proy\dos'))
    $caja0 = $script:histVistas[0].Caja

    $script:histFiltro = 'planner'
    Aplicar-FiltroHistorial
    Afirmar ((Titulos-Del-Cajon).Count -eq 1) 'el filtro por nombre no dejo una sola'
    Afirmar ([object]::ReferenceEquals($caja0, $script:histVistas[0].Caja)) `
        'filtrar rearmo las tarjetas en vez de solo reordenarlas'

    $script:histFiltro = 'proy\dos'
    Aplicar-FiltroHistorial
    Afirmar (((Titulos-Del-Cajon) -join '') -match 'otra cosa') 'no filtro por la ruta del proyecto'

    $script:histFiltro = 'no existe nada asi'
    Aplicar-FiltroHistorial
    Afirmar (((Titulos-Del-Cajon) -join '') -match 'Nada que coincida') 'sin resultados no avisa'

    $script:histFiltro = ''
    Aplicar-FiltroHistorial
    Afirmar ((Titulos-Del-Cajon).Count -eq 2) 'al limpiar el filtro no volvieron las dos'
}

Probar 'ordena por fecha y por peso, de mayor a menor' {
    Historial-Con @((Sesion-Falsa 'vieja y pesada' 9000 '2026-01-01' $false),
        (Sesion-Falsa 'nueva y liviana' 10 '2026-10-20' $false))
    $script:histOrden = 'fecha'
    Aplicar-FiltroHistorial
    Afirmar ((Titulos-Del-Cajon)[0] -eq 'nueva y liviana') `
        "por fecha quedo primera '$((Titulos-Del-Cajon)[0])'"
    $script:histOrden = 'peso'
    Aplicar-FiltroHistorial
    Afirmar ((Titulos-Del-Cajon)[0] -eq 'vieja y pesada') `
        "por peso quedo primera '$((Titulos-Del-Cajon)[0])'"
}

Probar 'la seleccion multiple suma el peso y respeta el filtro' {
    Historial-Con @((Sesion-Falsa 'alfa' 1000 '2026-10-01' $false),
        (Sesion-Falsa 'beta' 3000 '2026-10-02' $false))
    Afirmar ($script:cajonSeleccion.Visibility -eq 'Collapsed') 'la barra aparece sin nada tildado'

    foreach ($v in $script:histVistas) { Set-SeleccionHistorial -Sesion $v.Ses.Sesion -Tildada $true }
    Afirmar ($script:cajonSeleccion.Visibility -eq 'Visible') 'tilde dos y la barra no aparecio'
    Afirmar ($script:cajonSelTexto.Text -match '^2 tildadas') "el texto dice '$($script:cajonSelTexto.Text)'"
    Afirmar ($script:cajonSelTexto.Text -match '3,9 KB|4 KB|3,91 KB') `
        "no sumo los 4000 bytes: '$($script:cajonSelTexto.Text)'"

    # Filtrar tiene que sacar de la cuenta lo que ya no se ve: borrar "todas" no
    # puede llevarse algo que el filtro estaba escondiendo.
    $script:histFiltro = 'alfa'
    Aplicar-FiltroHistorial
    Afirmar (@(Get-SeleccionadasVisibles).Count -eq 1) `
        "con el filtro puesto siguen contando $(@(Get-SeleccionadasVisibles).Count)"

    Clear-SeleccionHistorial
    Afirmar ($script:cajonSeleccion.Visibility -eq 'Collapsed') 'destildar todas no escondio la barra'
}

Probar 'un uuid con mala forma no llega nunca a Remove-Item' {
    # Es el guardarrail que evita que un id vacio convierta el -Recurse en un
    # borrado de la carpeta del proyecto entera.
    foreach ($malo in '', '..', 'nada', '../../otra-cosa') {
        $exploto = $false
        try { Get-RastrosEn -Dir $env:TEMP -Sesion $malo | Out-Null } catch { $exploto = $true }
        Afirmar $exploto "paso de largo con el id '$malo'"
    }
}

Write-Host ''
Write-Host '=== colapsar a la cabecera ==='

Probar 'colapsado deja solo la cabecera, y al desplegar vuelve al alto de antes' {
    $raiz = Armar-Ventana
    foreach ($i in 1..5) { $lista.Children.Add((Tarjeta-Con @())) | Out-Null }

    $ancho = 348
    function Asentar {
        $raiz.Width = $ancho
        $raiz.Measure([Windows.Size]::new($ancho, [double]::PositiveInfinity))
        $raiz.Arrange([Windows.Rect]::new(0, 0, $ancho, $raiz.DesiredSize.Height))
        $raiz.UpdateLayout()
        return $raiz.DesiredSize.Height
    }

    $abierto = Asentar
    Afirmar ($abierto -gt 300) "el panel desplegado mide $abierto, esperaba bastante mas"
    $chevronAbierto = [int][char]$btnColapsar.Content

    # Sin animar: el estado final tiene que ser el mismo, y asi el test no
    # depende de que corra el dispatcher.
    $script:colapsado = $true
    Set-Colapsado -SinAnimar
    $cerrado = Asentar
    Afirmar ($scroller.Visibility -eq 'Collapsed') 'la lista sigue ocupando lugar'
    Afirmar ($pie.Visibility -eq 'Collapsed') 'el pie sigue ocupando lugar'
    Afirmar ($cerrado -lt 140) "colapsado mide ${cerrado}: tendria que quedar solo la cabecera"
    Afirmar ($chipResumen.Visibility -eq 'Visible') 'se llevo puesta la cuota, que es lo que se quiere seguir viendo'
    Afirmar ([int][char]$btnColapsar.Content -ne $chevronAbierto) 'el chevron no se dio vuelta'

    $script:colapsado = $false
    Set-Colapsado -SinAnimar
    $devuelta = Asentar
    Afirmar ($scroller.Visibility -eq 'Visible') 'la lista no volvio'
    Afirmar ([math]::Abs($devuelta - $abierto) -lt 1) "volvio a $devuelta y antes media $abierto"
    # Si el Height quedara fijado, la lista no crece mas al entrar una
    # conversacion nueva: tiene que volver a mandar el contenido.
    Afirmar ($scroller.ReadLocalValue([Windows.FrameworkElement]::HeightProperty) -eq
        [Windows.DependencyProperty]::UnsetValue) 'quedo el Height clavado: la lista no crece mas'
}
Write-Host ''
Write-Host '=== que ninguna pieza se quedo con codigo que no le toca ==='

Probar 'ninguna pieza abre la ventana principal ni crea timers' {
    # Se buscan cosas PRECISAS y sobre codigo, no sobre comentarios. La primera
    # version buscaba 'ShowDialog()' y 'Add_Tick' sueltos: marcaba el ShowDialog
    # del dialogo de confirmacion (que obviamente tiene que mostrarse) y la
    # palabra Add_Tick escrita adentro de un comentario. Un test que grita por
    # cosas que estan bien se termina ignorando, que es peor que no tenerlo.
    $prohibidos = @{
        '\$ventana\.ShowDialog' = 'abre la ventana principal'
        'DispatcherTimer'       = 'crea un timer'
        'Add-Type -AssemblyName' = 'carga assemblies'
    }
    foreach ($p in Get-ChildItem -LiteralPath (Join-Path $carpeta 'gadget') -Filter '*.ps1') {
        if ($p.Name -like '*.Tests.ps1') { continue }
        $codigo = (Get-Content -LiteralPath $p.FullName |
            ForEach-Object { ($_ -replace '#.*$', '') }) -join "`n"
        foreach ($pat in $prohibidos.Keys) {
            if ($codigo -match $pat) {
                throw "$($p.Name) $($prohibidos[$pat]): eso va en gadget.ps1, no en las piezas"
            }
        }
    }
}
Probar 'ninguna funcion usa una variable que es local de otra funcion' {
    # Atajo un bug de verdad, y de los caros: Invoke-Gh y Open-LoginGh tenian
    # pegada la linea  if (-not (Test-Path -LiteralPath $Hosts)) { return $r }
    # que es de Get-CuentasGh. $Hosts y $r no existen ahi, asi que llegaba $null
    # a Test-Path y tiraba. Como las dos funciones tienen try/catch, el error
    # salia como un cartel amable ("No pude cambiar de cuenta") y parecia un
    # problema de gh. Cambiar de cuenta de GitHub NUNCA funciono, y el boton de
    # login tampoco -- ese tiene el catch vacio, asi que no hacia nada, mudo.
    #
    # La regla es angosta a proposito: NO se marca cualquier variable que venga
    # de afuera, porque las piezas usan las del panel ($ventana, $lista, $fondo)
    # por la pila y eso es a proposito. Se marca solo cuando la variable es
    # parametro o local de OTRA funcion del MISMO archivo, que es exactamente la
    # huella de un copiar-pegar mal cortado.
    $auto = '_', 'args', 'this', 'true', 'false', 'null', 'PSItem', 'Matches',
    'PSScriptRoot', 'PSCommandPath', 'MyInvocation', 'Error', 'LASTEXITCODE',
    'PSVersionTable', 'ErrorActionPreference', 'Host', 'PWD', 'HOME', 'input'

    function Locales($fn) {
        $n = @()
        if ($fn.Parameters) { $n += $fn.Parameters.Name.VariablePath.UserPath }
        if ($fn.Body.ParamBlock) { $n += $fn.Body.ParamBlock.Parameters.Name.VariablePath.UserPath }
        $n += $fn.Body.FindAll({ $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true) |
        ForEach-Object { if ($_.Left -is [System.Management.Automation.Language.VariableExpressionAst]) { $_.Left.VariablePath.UserPath } }
        $n += $fn.Body.FindAll({ $args[0] -is [System.Management.Automation.Language.ForEachStatementAst] }, $true) |
        ForEach-Object { $_.Variable.VariablePath.UserPath }
        @($n | Where-Object { $_ })
    }

    $malas = @()
    foreach ($p in Get-ChildItem -LiteralPath (Join-Path $carpeta 'gadget') -Filter '*.ps1') {
        if ($p.Name -like '*.Tests.ps1') { continue }
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($p.FullName, [ref]$null, [ref]$null)
        $fns = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
        $porFn = @{}
        foreach ($f in $fns) { $porFn[$f.Name] = Locales $f }

        foreach ($f in $fns) {
            $propias = $porFn[$f.Name]
            # Solo las variables que usa ESTA funcion, no las de las anidadas.
            # FindAll recursivo se mete adentro de una function declarada dentro
            # de otra -- pasa en Cuota.ps1 con Pintar-Fila -- y marcaba sus
            # parametros como si Set-Resumen los usara prestados.
            $usadas = @($f.Body.FindAll({ $args[0] -is [System.Management.Automation.Language.VariableExpressionAst] }, $true) |
                Where-Object {
                    $n = $_.Parent
                    while ($n -and -not ($n -is [System.Management.Automation.Language.FunctionDefinitionAst])) { $n = $n.Parent }
                    (-not $n) -or ($n.Extent.StartOffset -eq $f.Extent.StartOffset)
                } |
                ForEach-Object { $_.VariablePath.UserPath } | Sort-Object -Unique)
            foreach ($v in $usadas) {
                if ($v -match ':') { continue }          # $script: / $global: / $env:
                if ($auto -contains $v) { continue }
                if ($propias -contains $v) { continue }
                # solo salta si es local de OTRA funcion del mismo archivo
                $duena = @($porFn.Keys | Where-Object { $_ -ne $f.Name -and $porFn[$_] -contains $v })
                if ($duena.Count) {
                    $malas += "$($p.Name): $($f.Name) usa `$$v, que es de $($duena[0])"
                }
            }
        }
    }
    Afirmar ($malas.Count -eq 0) ("`n        " + ($malas -join "`n        "))
}

Probar 'ninguna pieza le pisa el nombre a un control del panel' {
    # Bug real y visible: Show-SelectorCuentas hacia $lista = $d.FindName('lista').
    # Mientras su ShowDialog bombea el timer, Actualizar resuelve $lista por la
    # PILA DE LLAMADAS y encontraba el del dialogo: le borraba las cuentas y le
    # pintaba las tarjetas del panel adentro.
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $carpeta 'gadget.ps1'), [ref]$null, [ref]$null)

    # Solo los controles del XAML: son los nombres que un dialogo puede querer
    # reusar. $ventana se suma a mano porque no sale de un FindName.
    $controles = @{ 'ventana' = $true }
    foreach ($a in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] }, $false)) {
        if ($a.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $a.Right.Extent.Text -match '\$ventana\.FindName') {
            $controles[$a.Left.VariablePath.UserPath] = $true
        }
    }
    Afirmar ($controles.Count -gt 5) "no vi los controles de gadget.ps1 (encontre $($controles.Count))"

    foreach ($p in Get-ChildItem -LiteralPath (Join-Path $carpeta 'gadget') -Filter '*.ps1') {
        if ($p.Name -like '*.Tests.ps1') { continue }
        $t = [System.Management.Automation.Language.Parser]::ParseFile($p.FullName, [ref]$null, [ref]$null)
        foreach ($fn in $t.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
            foreach ($a in $fn.FindAll({ $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
                if ($a.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
                $n = $a.Left.VariablePath.UserPath
                if ($a.Left.VariablePath.IsGlobal -or $n -like 'script:*') { continue }
                if ($controles.ContainsKey($n)) {
                    throw "$($p.Name):$($a.Extent.StartLineNumber) $($fn.Name) declara una local `$$n, que es un control del panel: renombrala"
                }
            }
        }
    }
}
Probar 'todos los comandos que invocan las piezas EXISTEN de verdad' {
    # Este test nacio de un bug que cerraba el gadget entero: al reescribir
    # Orden.ps1 se borro Test-Arrastrando y quedo un llamador vivo en
    # Tarjeta.ps1. Al soltar una tarjeta, la excepcion escapaba del handler de
    # mouse y WPF mataba el proceso.
    #
    # El test de "las funciones de cada pieza estan definidas" NO lo agarra:
    # verifica que existan las que ESPERAMOS, no que resuelvan las que se
    # LLAMAN. Son preguntas distintas y esta es la que importa.
    #
    # Las funciones propias del proyecto se sacan de los AST, no de Get-Command,
    # por dos razones:
    #   - gadget.ps1 no se dot-sourcea en este test (abriria la ventana), asi
    #     que Actualizar y compania no estarian cargadas.
    #   - hay funciones ANIDADAS dentro de otras (Pintar-Fila vive adentro de
    #     Set-Resumen) y esas solo existen mientras corre la de afuera, asi que
    #     Get-Command nunca las ve. El FindAll recursivo si.
    $archivos = @((Join-Path $carpeta 'gadget.ps1'))
    $archivos += @(Get-ChildItem -LiteralPath (Join-Path $carpeta 'gadget') -Filter '*.ps1' |
        Where-Object { $_.Name -notlike '*.Tests.ps1' } | ForEach-Object { $_.FullName })

    $propias = @()
    foreach ($a in $archivos) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($a, [ref]$null, [ref]$null)
        $propias += @($ast.FindAll({
                    $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
            ForEach-Object { $_.Name })
    }

    $faltan = @()
    foreach ($p in Get-ChildItem -LiteralPath (Join-Path $carpeta 'gadget') -Filter '*.ps1') {
        if ($p.Name -like '*.Tests.ps1') { continue }
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $p.FullName, [ref]$null, [ref]$null)
        # Solo los que se invocan por NOMBRE literal. Un comando armado en una
        # variable no se puede verificar sin ejecutarlo, y no vale la pena.
        $cmds = @($ast.FindAll({
                    $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true) |
            ForEach-Object { $_.GetCommandName() } |
            Where-Object { $_ } | Sort-Object -Unique)
        foreach ($c in $cmds) {
            if ($propias -contains $c) { continue }
            if (Get-Command $c -ErrorAction SilentlyContinue) { continue }
            $faltan += ('{0}: {1}' -f $p.Name, $c)
        }
    }
    Afirmar ($faltan.Count -eq 0) ('comandos que no existen -> ' + ($faltan -join ', '))
}
Probar 'los llamados a funciones propias pasan los parametros obligatorios' {
    # Nacio de un click que cerraba el gadget: la tarjeta llamaba a
    # Start-Arrastre sin -Asa. Sin consola, PowerShell no puede preguntarlo.
    $archivos = @((Join-Path $carpeta 'gadget.ps1'))
    $archivos += @(Get-ChildItem -LiteralPath (Join-Path $carpeta 'gadget') -Filter '*.ps1' |
        Where-Object { $_.Name -notlike '*.Tests.ps1' } | ForEach-Object { $_.FullName })
    $asts = @{}
    foreach ($a in $archivos) {
        $asts[$a] = [System.Management.Automation.Language.Parser]::ParseFile($a, [ref]$null, [ref]$null)
    }

    # Funcion propia -> nombres de sus parametros Mandatory.
    $obligatorios = @{}
    foreach ($ast in $asts.Values) {
        foreach ($f in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
            $pars = if ($f.Body.ParamBlock) { $f.Body.ParamBlock.Parameters } else { $f.Parameters }
            $obligatorios[$f.Name] = @($pars | Where-Object {
                    @($_.Attributes | Where-Object { $_.TypeName.Name -eq 'Parameter' } |
                        ForEach-Object { $_.NamedArguments } |
                        Where-Object { $_.ArgumentName -eq 'Mandatory' -and
                            ($_.ExpressionOmitted -or $_.Argument.Extent.Text -eq '$true') }).Count
                } | ForEach-Object { $_.Name.VariablePath.UserPath })
        }
    }

    $faltan = @()
    foreach ($a in $archivos) {
        foreach ($c in $asts[$a].FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)) {
            $nom = $c.GetCommandName()
            if (-not $nom -or -not $obligatorios.ContainsKey($nom)) { continue }
            $req = @($obligatorios[$nom]); if (-not $req.Count) { continue }
            # Con splatting (@x) no se puede saber que llega: se saltea.
            if (@($c.CommandElements | Where-Object { $_.Splatted }).Count) { continue }

            $nombrados = @(); $posicionales = 0; $esperaValor = $false
            foreach ($e in @($c.CommandElements | Select-Object -Skip 1)) {
                if ($e -is [System.Management.Automation.Language.CommandParameterAst]) {
                    $nombrados += $e.ParameterName
                    $esperaValor = ($null -eq $e.Argument)
                } elseif ($esperaValor) { $esperaValor = $false }
                else { $posicionales++ }
            }
            # Un -Parametro abreviado cuenta si es prefijo del nombre real.
            $sinDar = @($req | Where-Object { $r = $_; -not @($nombrados | Where-Object { $r -like "$_*" }).Count })
            if ($sinDar.Count -gt $posicionales) {
                $faltan += ('{0}:{1} {2} sin -{3}' -f (Split-Path -Leaf $a), $c.Extent.StartLineNumber,
                    $nom, ($sinDar -join ', -'))
            }
        }
    }
    Afirmar ($faltan.Count -eq 0) ('llamados incompletos -> ' + ($faltan -join ' | '))
}
Probar 'gadget.ps1 quedo bajo 600 lineas' {
    $n = (Get-Content -LiteralPath (Join-Path $carpeta 'gadget.ps1')).Count
    Afirmar ($n -lt 600) "gadget.ps1 tiene $n lineas: volvio a crecer, hay que partirlo otra vez"
    Write-Host ("        ({0} lineas)" -f $n)
}

Write-Host ''
Write-Host '=== quien esta pensando: el registro de sesiones ==='

$script:dirSes = Join-Path $env:TEMP ("ses-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $script:dirSes -Force | Out-Null
$script:dirJobs = Join-Path $env:TEMP ("job-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $script:dirJobs -Force | Out-Null
function Sesion([hashtable]$Campos) {
    $j = @{ pid = 1; sessionId = [guid]::NewGuid().ToString(); status = 'idle'; kind = 'interactive' }
    foreach ($k in $Campos.Keys) { $j[$k] = $Campos[$k] }
    $f = Join-Path $script:dirSes ("{0}.json" -f $j.pid)
    [IO.File]::WriteAllText($f, (ConvertTo-Json $j -Compress), (New-Object Text.UTF8Encoding($false)))
    return $j.sessionId
}
function Pensando {
    Get-ActividadSesiones -Dir $script:dirSes -DirJobs $script:dirJobs `
        -EstaVivo { param($ProcId) $ProcId -lt 900 }
}
function Job([string]$Id, [string]$Tempo) {
    $d = Join-Path $script:dirJobs $Id
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $d 'state.json'),
        (ConvertTo-Json @{ state = 'blocked'; tempo = $Tempo } -Compress),
        (New-Object Text.UTF8Encoding($false)))
}
function LimpiarSesiones {
    Get-ChildItem $script:dirSes -Filter '*.json' | Remove-Item -Force
    if (Test-Path $script:dirJobs) { Remove-Item $script:dirJobs -Recurse -Force }
    New-Item -ItemType Directory -Path $script:dirJobs -Force | Out-Null
}

Probar 'una sesion normal en busy figura pensando, y en idle no' {
    LimpiarSesiones
    $ocupada = Sesion @{ pid = 1; status = 'busy' }
    $libre = Sesion @{ pid = 2; status = 'idle' }
    $m = Pensando
    Afirmar ($m.ContainsKey($ocupada.ToLower())) 'no vio la que trabaja'
    Afirmar (-not $m.ContainsKey($libre.ToLower())) 'dijo que la ociosa trabaja'
}
Probar 'un proceso muerto no cuenta aunque el json diga busy' {
    LimpiarSesiones
    $zombi = Sesion @{ pid = 999; status = 'busy' }
    Afirmar (-not (Pensando).ContainsKey($zombi.ToLower())) 'un busy fantasma quedo latiendo'
}
Probar 'una parkeada sin job vivo NO esta pensando' {
    # El bug que se vio: parkear deja el proceso VIVO y el status clavado en
    # 'busy'. El chequeo del PID no la filtra, y la tarjeta figuro pensando 150
    # minutos seguidos, sin que nadie estuviera haciendo nada.
    LimpiarSesiones
    $parkeada = Sesion @{ pid = 1; status = 'busy'; parkedJobId = 'job1' }
    Afirmar (-not (Pensando).ContainsKey($parkeada.ToLower())) 'la parkeada quedo pensando para siempre'
}
Probar 'una parkeada sigue al job: si el job trabaja, ella trabaja' {
    LimpiarSesiones
    $parkeada = Sesion @{ pid = 1; status = 'busy'; parkedJobId = 'job1' }
    Sesion @{ pid = 2; status = 'busy'; kind = 'bg'; jobId = 'job1' } | Out-Null
    Afirmar ((Pensando).ContainsKey($parkeada.ToLower())) 'no siguio al job que si trabaja'
}
Probar 'y si el job esta ocioso, ella tambien' {
    LimpiarSesiones
    $parkeada = Sesion @{ pid = 1; status = 'busy'; parkedJobId = 'job1' }
    Sesion @{ pid = 2; status = 'idle'; kind = 'bg'; jobId = 'job1' } | Out-Null
    Afirmar (-not (Pensando).ContainsKey($parkeada.ToLower())) 'siguio diciendo que trabaja con el job ocioso'
}
Probar 'el job de OTRA sesion no la despierta' {
    LimpiarSesiones
    $parkeada = Sesion @{ pid = 1; status = 'busy'; parkedJobId = 'job1' }
    Sesion @{ pid = 2; status = 'busy'; kind = 'bg'; jobId = 'otro' } | Out-Null
    Afirmar (-not (Pensando).ContainsKey($parkeada.ToLower())) 'se colgo del job equivocado'
}

Probar 'el tempo del job manda sobre el status congelado de la parkeada' {
    # La sesion parkeada dice 'busy' para siempre. La verdad de si el job esta
    # pensando o esperandote vive en jobs\<id>\state.json, campo "tempo".
    LimpiarSesiones
    $parkeada = Sesion @{ pid = 1; status = 'busy'; parkedJobId = 'job1' }
    Job 'job1' 'active'
    Afirmar ((Pensando).ContainsKey($parkeada.ToLower())) 'con el job activo no la marco'

    LimpiarSesiones
    $parkeada = Sesion @{ pid = 1; status = 'busy'; parkedJobId = 'job1' }
    Job 'job1' 'idle'
    Afirmar (-not (Pensando).ContainsKey($parkeada.ToLower())) 'con el job esperandote la dejo pensando'
}
Probar 'el tempo le gana incluso a una sesion bg que diga busy' {
    LimpiarSesiones
    $parkeada = Sesion @{ pid = 1; status = 'busy'; parkedJobId = 'job1' }
    Sesion @{ pid = 2; status = 'busy'; kind = 'bg'; jobId = 'job1' } | Out-Null
    Job 'job1' 'idle'
    Afirmar (-not (Pensando).ContainsKey($parkeada.ToLower())) 'le creyo a la sesion bg en vez del job'
}

Remove-Item -LiteralPath $script:dirJobs -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $script:dirSes -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host ("{0} pasados, {1} fallas" -f $script:pasados, $script:fallas)
exit ([int]($script:fallas -gt 0))

