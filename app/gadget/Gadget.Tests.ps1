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
Probar 'en el archivo la tarjeta es corta: sin recap ni contexto, y solo desarchiva' {
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
    $botones = @($todo | Where-Object { $_ -is [Windows.Controls.Button] })
    Afirmar ($botones.Count -eq 1 -and $botones[0].ToolTip -match 'Desarchivar') `
        "esperaba solo el de desarchivar, hay $($botones.Count)"
    Afirmar ($null -eq $t.Cursor) 'la tarjeta invita a clickearla y no abre nada'
    Afirmar ($textos -contains 'front') 'no muestra las etiquetas'
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
Write-Host '=== colapsar a la cabecera ==='

Probar 'colapsado deja solo la cabecera, y al desplegar vuelve al alto de antes' {
    # Las constantes SE SACAN de gadget.ps1 y no se copian: copiadas, el dia que
    # cambie un padding el test seguiria probando el valor viejo.
    foreach ($linea in (Get-Content -LiteralPath (Join-Path $carpeta 'gadget.ps1'))) {
        if ($linea -match '^\$(AIRE_SOMBRA|PAD_|LOCK_|PIN_|CHEVRON_)') { Invoke-Expression $linea }
    }
    $ventana = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$xaml)))
    $raiz = $ventana.Content
    $ventana.Content = $null
    foreach ($n in 'fondo', 'cabecera', 'chipResumen', 'filaCuentas', 'btnCuenta', 'btnGitHub', 'chipBotones', 'chipTitulo', 'scroller', 'lista',
        'pie', 'btnCandado', 'btnArriba', 'btnArchivadas', 'btnColapsar', 'gripIzq', 'gripDer',
        'gripAbajo', 'barraTitulo') {
        Set-Variable -Name $n -Value ([Windows.LogicalTreeHelper]::FindLogicalNode($raiz, $n))
    }
    $script:arriba = $false; $script:verArchivadas = $false; $script:bloqueado = $false
    $script:colapsado = $false; $script:altoLista = 0; $script:altoPie = 0
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

