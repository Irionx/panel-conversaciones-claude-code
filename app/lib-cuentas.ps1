# =============================================================================
#  lib-cuentas.ps1 - cambiar de cuenta de Claude Code sin volver a loguearse
# -----------------------------------------------------------------------------
#  Medido sobre claude.exe 2.1.270: la sesion son DOS archivos separados. El par
#  de tokens vive en <claude>\.credentials.json, y la identidad (mail, org,
#  plan) en .claude.json bajo "oauthAccount". Cambiar de cuenta es intercambiar
#  las dos cosas a la vez; con una sola, el panel miente o Claude no entra.
#
#  Cada cuenta conocida queda archivada en <claude>\cuentas\<mail>.json. Se
#  archiva SOLA: cada vez que se miran las cuentas, si la credencial viva no es
#  igual a la guardada se vuelve a copiar. Loguearte una vez con cada cuenta
#  alcanza para que aparezcan las dos en la lista, y la copia nunca envejece.
#
#  El refresh token dura ~30 dias y se renueva sobre el archivo vivo. Por eso se
#  re-archiva antes de cada cambio: si guardaramos una foto vieja, al volver a
#  esa cuenta el token ya podria estar rotado y habria que loguearse igual.
#
#  Lo que NO hace: no toca el resto de .claude.json. Ese archivo tiene el estado
#  de todos tus proyectos y un ConvertTo-Json de ida y vuelta lo reescribe
#  entero (y en PS 5.1 colapsa arrays vacios). Se empalma SOLO el tramo de las
#  dos claves, por conteo de llaves, y el resto del archivo queda byte a byte.
# =============================================================================

# --- donde vive todo ---------------------------------------------------------

#  Claude respeta CLAUDE_CONFIG_DIR: verificado apuntandolo a una carpeta vacia,
#  donde se creo su propio .claude.json, projects\ y sessions\. Sin la variable
#  la config es ~\.claude y el .claude.json queda AL LADO, no adentro.
function Get-DirClaude {
    if ($env:CLAUDE_CONFIG_DIR) { return $env:CLAUDE_CONFIG_DIR }
    return (Join-Path $env:USERPROFILE '.claude')
}

function Get-RutaAjustesClaude {
    if ($env:CLAUDE_CONFIG_DIR) { return (Join-Path $env:CLAUDE_CONFIG_DIR '.claude.json') }
    return (Join-Path $env:USERPROFILE '.claude.json')
}

#  Cuando se pasa una carpeta explicita (perfiles, y sobre todo los tests) el
#  .claude.json de ESA carpeta manda. Sin eso, un llamado con -Claude y sin
#  -Ajustes iria a leer y escribir la configuracion real del usuario.
function Resolve-RutaAjustes([string]$Claude, [string]$Ajustes) {
    if ($Ajustes) { return $Ajustes }
    if ($Claude) {
        $propio = Join-Path $Claude '.claude.json'
        if (Test-Path -LiteralPath $propio) { return $propio }
    }
    return (Get-RutaAjustesClaude)
}

function Get-RutaCredencial([string]$Claude) {
    if (-not $Claude) { $Claude = Get-DirClaude }
    return (Join-Path $Claude '.credentials.json')
}

function Get-DirCuentas([string]$Claude) {
    if (-not $Claude) { $Claude = Get-DirClaude }
    return (Join-Path $Claude 'cuentas')
}

# --- lectura y escritura seguras ---------------------------------------------

function Read-Texto([string]$Ruta) {
    if (-not (Test-Path -LiteralPath $Ruta)) { return $null }
    try { return [System.IO.File]::ReadAllText($Ruta) } catch { return $null }
}

#  ConvertFrom-Json con entrada nula NO devuelve $null: tira un error de
#  binding que se escapa del try cuando ErrorActionPreference es Continue, que
#  es como corre el gadget. Medido: ensuciaba la consola en el primer archivado.
function ConvertFrom-JsonSeguro([string]$Texto) {
    if ([string]::IsNullOrWhiteSpace($Texto)) { return $null }
    try { return ($Texto | ConvertFrom-Json) } catch { return $null }
}

#  Temp + Move y no un WriteAllText directo: si el proceso se corta a la mitad,
#  un .credentials.json truncado te deja sin sesion y sin copia.
function Write-TextoAtomico([string]$Ruta, [string]$Texto) {
    $dir = Split-Path -Parent $Ruta
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $tmp = "$Ruta.tmp-$PID"
    [System.IO.File]::WriteAllText($tmp, $Texto, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $Ruta -Force
}

# --- cirugia sobre el JSON ----------------------------------------------------

#  Devuelve @{ Inicio; Largo; Json } con el TRAMO EXACTO que ocupa el valor de
#  una clave, o $null. Si la clave no esta, o aparece mas de una vez, devuelve
#  $null a proposito: preferimos no tocar nada antes que empalmar el lugar
#  equivocado de un archivo de 90 KB que no es nuestro.
function Get-TramoJson([string]$Texto, [string]$Clave) {
    if (-not $Texto) { return $null }
    $patron = '"' + [regex]::Escape($Clave) + '"\s*:\s*'
    $m = [regex]::Matches($Texto, $patron)
    if ($m.Count -ne 1) { return $null }

    $i = $m[0].Index + $m[0].Length
    if ($i -ge $Texto.Length) { return $null }
    $c = $Texto[$i]

    if ($c -eq '{' -or $c -eq '[') {
        $cierre = if ($c -eq '{') { '}' } else { ']' }
        $nivel = 0
        $enTexto = $false
        $escape = $false
        for ($j = $i; $j -lt $Texto.Length; $j++) {
            $ch = $Texto[$j]
            if ($escape) { $escape = $false; continue }
            if ($ch -eq '\') { if ($enTexto) { $escape = $true }; continue }
            if ($ch -eq '"') { $enTexto = -not $enTexto; continue }
            if ($enTexto) { continue }
            if ($ch -eq $c) { $nivel++ }
            elseif ($ch -eq $cierre) {
                $nivel--
                if ($nivel -eq 0) {
                    $largo = $j - $i + 1
                    return @{ Inicio = $i; Largo = $largo; Json = $Texto.Substring($i, $largo) }
                }
            }
        }
        return $null
    }

    if ($c -eq '"') {
        $escape = $false
        for ($j = $i + 1; $j -lt $Texto.Length; $j++) {
            $ch = $Texto[$j]
            if ($escape) { $escape = $false; continue }
            if ($ch -eq '\') { $escape = $true; continue }
            if ($ch -eq '"') {
                $largo = $j - $i + 1
                return @{ Inicio = $i; Largo = $largo; Json = $Texto.Substring($i, $largo) }
            }
        }
        return $null
    }

    # Numero, true, false o null: hasta la coma o el cierre del objeto.
    for ($j = $i; $j -lt $Texto.Length; $j++) {
        if ($Texto[$j] -match '[,}\]\s]') {
            $largo = $j - $i
            return @{ Inicio = $i; Largo = $largo; Json = $Texto.Substring($i, $largo) }
        }
    }
    return $null
}

#  Reemplaza el valor de una clave dejando TODO el resto del texto intacto.
#  Devuelve $null si no se pudo ubicar sin ambiguedad.
function Set-TramoJson([string]$Texto, [string]$Clave, [string]$Json) {
    $t = Get-TramoJson -Texto $Texto -Clave $Clave
    if (-not $t) { return $null }
    return $Texto.Substring(0, $t.Inicio) + $Json + $Texto.Substring($t.Inicio + $t.Largo)
}

# --- la cuenta que esta puesta ahora -----------------------------------------

function ConvertTo-SlugCuenta([string]$Mail) {
    if (-not $Mail) { return 'sin-mail' }
    return ($Mail.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
}

#  La identidad viva: mail, org y plan salen de .claude.json; los vencimientos,
#  de la credencial. Devuelve $null si no hay sesion iniciada.
function Get-CuentaViva {
    param([string]$Claude, [string]$Ajustes)
    if (-not $Claude) { $Claude = Get-DirClaude }
    $Ajustes = Resolve-RutaAjustes $Claude $Ajustes

    $txtAj = Read-Texto $Ajustes
    $tramo = Get-TramoJson -Texto $txtAj -Clave 'oauthAccount'
    if (-not $tramo) { return $null }

    $cuenta = ConvertFrom-JsonSeguro $tramo.Json
    if (-not $cuenta -or -not $cuenta.emailAddress) { return $null }

    $tramoId = Get-TramoJson -Texto $txtAj -Clave 'userID'
    $txtCred = Read-Texto (Get-RutaCredencial $Claude)

    return @{
        Mail          = [string]$cuenta.emailAddress
        Nombre        = [string]$cuenta.displayName
        Org           = [string]$cuenta.organizationName
        Plan          = [string]$cuenta.billingType
        CuentaTexto   = $tramo.Json
        UserIdTexto   = $(if ($tramoId) { $tramoId.Json } else { $null })
        CredencialTexto = $txtCred
    }
}

#  Los dos vencimientos de una credencial. El que manda es el del REFRESH: el
#  access dura horas y Claude lo renueva solo mientras el refresh siga vivo.
function Get-VencimientoCredencial([string]$TextoCredencial) {
    $vacio = @{ Vence = $null; Vencida = $true; Dias = $null }
    if (-not $TextoCredencial) { return $vacio }
    $o = (ConvertFrom-JsonSeguro $TextoCredencial).claudeAiOauth
    if (-not $o) { return $vacio }

    $ms = $o.refreshTokenExpiresAt
    if (-not $ms) { $ms = $o.expiresAt }
    if (-not $ms) { return $vacio }

    $vence = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$ms).LocalDateTime
    $dias = [math]::Floor(($vence - (Get-Date)).TotalDays)
    return @{ Vence = $vence; Vencida = ($vence -le (Get-Date)); Dias = $dias }
}

# --- el archivo de cada cuenta -----------------------------------------------

#  Archiva la cuenta que esta puesta ahora. Se guardan los TEXTOS crudos y no
#  objetos: al restaurar se escriben tal cual, byte a byte, sin que un
#  ConvertTo-Json de por medio pueda cambiarles una coma.
#
#  No reescribe si ya esta igual: esto corre en cada refresco del panel.
function Save-CuentaViva {
    param([string]$Claude, [string]$Ajustes)
    if (-not $Claude) { $Claude = Get-DirClaude }

    $viva = Get-CuentaViva -Claude $Claude -Ajustes $Ajustes
    if (-not $viva -or -not $viva.CredencialTexto) { return $null }

    $ruta = Join-Path (Get-DirCuentas $Claude) ((ConvertTo-SlugCuenta $viva.Mail) + '.json')
    $previo = ConvertFrom-JsonSeguro (Read-Texto $ruta)
    if ($previo -and $previo.credencialTexto -ceq $viva.CredencialTexto -and
        $previo.cuentaTexto -ceq $viva.CuentaTexto) {
        return $ruta
    }

    $guardar = [ordered]@{
        mail            = $viva.Mail
        guardada        = (Get-Date).ToString('o')
        cuentaTexto     = $viva.CuentaTexto
        userIdTexto     = $viva.UserIdTexto
        credencialTexto = $viva.CredencialTexto
    }
    Write-TextoAtomico $ruta (ConvertTo-Json $guardar -Depth 5)
    return $ruta
}

#  Todas las cuentas conocidas, la activa primero. Archiva la viva de paso, asi
#  la lista siempre incluye la cuenta con la que estas trabajando ahora.
function Get-Cuentas {
    param([string]$Claude, [string]$Ajustes)
    if (-not $Claude) { $Claude = Get-DirClaude }

    Save-CuentaViva -Claude $Claude -Ajustes $Ajustes | Out-Null
    $viva = Get-CuentaViva -Claude $Claude -Ajustes $Ajustes
    $mailVivo = $(if ($viva) { $viva.Mail } else { $null })

    $dir = Get-DirCuentas $Claude
    if (-not (Test-Path -LiteralPath $dir)) { return @() }

    $salida = @()
    foreach ($f in (Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        $o = ConvertFrom-JsonSeguro (Read-Texto $f.FullName)
        if (-not $o -or -not $o.mail) { continue }

        $cu = ConvertFrom-JsonSeguro $o.cuentaTexto
        $v = Get-VencimientoCredencial $o.credencialTexto

        # El plan sale de subscriptionType de la credencial ("max", "pro"), no
        # del billingType de la cuenta, que es un dato de facturacion interno:
        # mostraba "stripe_subscription", que no le dice nada a nadie.
        $cred = ConvertFrom-JsonSeguro $o.credencialTexto
        $plan = [string]$cred.claudeAiOauth.subscriptionType
        if (-not $plan) { $plan = [string]$cu.billingType }

        $salida += @{
            Mail     = [string]$o.mail
            Nombre   = [string]$cu.displayName
            Org      = [string]$cu.organizationName
            Plan     = $plan
            Archivo  = $f.FullName
            Activa   = ($mailVivo -and $o.mail -ceq $mailVivo)
            Vence    = $v.Vence
            Vencida  = $v.Vencida
            Dias     = $v.Dias
            Guardada = [string]$o.guardada
        }
    }
    # Se devuelve el array PELADO, sin la coma que fuerza el envoltorio: quien
    # llama pone @(). Las dos protecciones juntas se cancelan -- el @() de
    # afuera termina con UN elemento que ES la lista, y la fila sale con los dos
    # mails pegados y "System.Object[]" de organizacion. Paso de verdad.
    return @($salida | Sort-Object @{ E = { -not $_.Activa } }, @{ E = { $_.Mail } })
}

# --- el cambio ----------------------------------------------------------------

#  Pone la cuenta pedida. Devuelve @{ Ok; Mail; Vencida; Avisos }.
#
#  Primero re-archiva la que estaba: su token se pudo haber renovado desde la
#  ultima copia, y perder eso es justamente lo que te obliga a re-loguear.
function Switch-Cuenta {
    param(
        [Parameter(Mandatory)][string]$Mail,
        [string]$Claude,
        [string]$Ajustes
    )
    if (-not $Claude) { $Claude = Get-DirClaude }
    $Ajustes = Resolve-RutaAjustes $Claude $Ajustes
    $avisos = @()

    $ruta = Join-Path (Get-DirCuentas $Claude) ((ConvertTo-SlugCuenta $Mail) + '.json')
    $o = ConvertFrom-JsonSeguro (Read-Texto $ruta)
    if (-not $o -or -not $o.credencialTexto) {
        return @{ Ok = $false; Mail = $Mail; Vencida = $true
            Avisos = @("No tengo guardada la cuenta $Mail.")
        }
    }

    Save-CuentaViva -Claude $Claude -Ajustes $Ajustes | Out-Null

    Write-TextoAtomico (Get-RutaCredencial $Claude) $o.credencialTexto

    # La identidad. Si no se puede empalmar sin ambiguedad se deja como esta: la
    # credencial ya manda, y Claude reescribe el bloque en el proximo arranque.
    $txt = Read-Texto $Ajustes
    if ($txt) {
        $nuevo = Set-TramoJson -Texto $txt -Clave 'oauthAccount' -Json $o.cuentaTexto
        if ($nuevo -and $o.userIdTexto) {
            $conId = Set-TramoJson -Texto $nuevo -Clave 'userID' -Json $o.userIdTexto
            if ($conId) { $nuevo = $conId }
        }
        if ($nuevo) { Write-TextoAtomico $Ajustes $nuevo }
        else { $avisos += 'No pude actualizar la identidad en .claude.json; se corrige sola al abrir Claude Code.' }
    }

    $v = Get-VencimientoCredencial $o.credencialTexto
    if ($v.Vencida) { $avisos += "El token guardado de $Mail esta vencido: hay que volver a loguearse." }

    return @{ Ok = $true; Mail = $Mail; Vencida = $v.Vencida; Avisos = $avisos }
}

function Remove-CuentaGuardada {
    param([Parameter(Mandatory)][string]$Mail, [string]$Claude)
    $ruta = Join-Path (Get-DirCuentas $Claude) ((ConvertTo-SlugCuenta $Mail) + '.json')
    if (-not (Test-Path -LiteralPath $ruta)) { return $false }
    Remove-Item -LiteralPath $ruta -Force
    return $true
}
