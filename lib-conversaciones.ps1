# =============================================================================
#  lib-conversaciones.ps1
#  Logica compartida entre abrir-conversacion.ps1 y gadget.ps1.
#  Se carga con dot-sourcing:  . "$PSScriptRoot\lib-conversaciones.ps1"
# =============================================================================

$script:RaizProyectos = Join-Path $env:USERPROFILE '.claude\projects'

# transcript -> { Sello (mtime|tamano); Valor }. Ver Get-ContextoSesion.
$script:cacheCtx = @{}

# --- ultimas lineas de un archivo grande, sin leerlo entero -------------------
#  `Get-Content -Tail` en PS 5.1 es catastrofico con archivos grandes: sobre un
#  transcript de 12 MB tardaba ~100 SEGUNDOS, y el gadget lo hacia en el hilo de
#  la UI en cada refresco. De ahi los cuelgues.
#
#  Esto hace un seek de verdad: lee solo el ultimo tramo y descarta la primera
#  linea, que casi seguro viene cortada al medio.
#
#  FileShare ReadWrite es obligatorio: Claude Code tiene el transcript abierto
#  para escribir mientras trabaja.
function Get-ColaArchivo {
    param(
        [Parameter(Mandatory)][string]$Ruta,
        [int]$Bytes = 524288
    )

    $desde = 0
    $buf = $null
    $leidos = 0
    try {
        $fs = [System.IO.File]::Open($Ruta, [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $len = $fs.Length
            $desde = [Math]::Max(0, $len - $Bytes)
            [void]$fs.Seek($desde, [System.IO.SeekOrigin]::Begin)
            $buf = New-Object byte[] ([int]($len - $desde))
            $leidos = $fs.Read($buf, 0, $buf.Length)
        } finally { $fs.Dispose() }
    } catch { return @() }

    if ($leidos -le 0) { return @() }

    $txt = [System.Text.Encoding]::UTF8.GetString($buf, 0, $leidos)
    $lineas = $txt -split "`n"
    # Si no arrancamos desde el principio, la primera esta partida.
    if ($desde -gt 0 -and $lineas.Count -gt 1) { $lineas = $lineas[1..($lineas.Count - 1)] }
    return @($lineas | Where-Object { $_ })
}

# --- lee conversaciones.js y devuelve el array de objetos ---------------------
function Get-Conversaciones {
    param([Parameter(Mandatory)][string]$Carpeta)

    $archivo = Join-Path $Carpeta 'conversaciones.js'
    if (-not (Test-Path $archivo)) { throw "No encuentro conversaciones.js en $Carpeta" }

    $texto = Get-Content -Path $archivo -Raw -Encoding UTF8

    $marca = $texto.IndexOf('window.CONVERSACIONES')
    if ($marca -lt 0) { throw 'conversaciones.js no define window.CONVERSACIONES' }
    $ini = $texto.IndexOf('[', $marca)
    $fin = $texto.LastIndexOf(']')
    if ($ini -lt 0 -or $fin -le $ini) { throw 'No pude leer el array de conversaciones.js' }

    $json = $texto.Substring($ini, $fin - $ini + 1)

    # Red de seguridad: si alguien pego un path de Windows con barra simple
    # ("C:\local repos") el JSON seria invalido. Se duplica todo backslash que
    # no forme parte de un escape valido. La alternancia consume primero los
    # escapes correctos, asi un "\\" ya bien escrito no se toca.
    $json = [regex]::Replace($json, '\\(["\\/bfnrtu])|\\', {
        param($m)
        if ($m.Groups[1].Success) { $m.Value } else { '\\' }
    })

    # ConvertFrom-Json en PS 5.1 emite el array como UN solo objeto, asi que un
    # "return @(...)" no se enumera al pipearlo (queda 1 item que es el array).
    # Se emiten los elementos de a uno para que el pipeline se comporte normal.
    $arr = @($json | ConvertFrom-Json)
    foreach ($item in $arr) { $item }
}

# --- reescribe conversaciones.js conservando el comentario de cabecera --------
#  Solo se reemplaza el tramo entre [ y ], asi la documentacion de arriba y el
#  wrapper window.CONVERSACIONES sobreviven intactos.
function Save-Conversaciones {
    param(
        [Parameter(Mandatory)][string]$Carpeta,
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$Conversaciones
    )

    $archivo = Join-Path $Carpeta 'conversaciones.js'
    $texto = Get-Content -Path $archivo -Raw -Encoding UTF8

    $marca = $texto.IndexOf('window.CONVERSACIONES')
    $ini = $texto.IndexOf('[', $marca)
    $fin = $texto.LastIndexOf(']')
    if ($marca -lt 0 -or $ini -lt 0 -or $fin -le $ini) { throw 'No pude ubicar el array en conversaciones.js' }

    if ($Conversaciones.Count -eq 0) {
        $cuerpo = "[]"
    } else {
        # Se serializa objeto por objeto: ConvertTo-Json en PS5.1 desarma un
        # array de un solo elemento y nos comeria los corchetes.
        $piezas = foreach ($c in $Conversaciones) {
            $j = $c | ConvertTo-Json -Depth 6
            '    ' + ($j -replace "`r`n", "`n").Replace("`n", "`n    ")
        }
        $cuerpo = "[`n" + ($piezas -join ",`n") + "`n]"
    }

    # Backup antes de pisar: un borrado siempre tiene que ser reversible.
    Copy-Item -Path $archivo -Destination "$archivo.bak" -Force -ErrorAction SilentlyContinue

    $nuevo = $texto.Substring(0, $ini) + $cuerpo + $texto.Substring($fin + 1)
    [System.IO.File]::WriteAllText($archivo, $nuevo, [System.Text.UTF8Encoding]::new($false))
}

# --- borra una conversacion por id -------------------------------------------
function Remove-Conversacion {
    param(
        [Parameter(Mandatory)][string]$Carpeta,
        [Parameter(Mandatory)][string]$Id
    )

    $todas = @(Get-Conversaciones -Carpeta $Carpeta)
    $quedan = @($todas | Where-Object { $_.id -ne $Id })

    if ($quedan.Count -eq $todas.Count) { throw "No hay ninguna conversacion con id '$Id'" }

    Save-Conversaciones -Carpeta $Carpeta -Conversaciones $quedan
    return $todas.Count - $quedan.Count
}

# --- normaliza el cwd a formato Windows --------------------------------------
function ConvertTo-RutaWindows {
    param([string]$Ruta)
    return ([string]$Ruta).Replace('/', '\').TrimEnd('\')
}

# --- codifica un cwd al nombre de carpeta que usa Claude Code ----------------
#  "C:\local repos gh\despachoviewer"  ->  "C--local-repos-gh-despachoviewer"
#  La regla es: todo caracter que no sea alfanumerico pasa a guion.
function ConvertTo-CarpetaProyecto {
    param([string]$Cwd)
    return [regex]::Replace((ConvertTo-RutaWindows $Cwd), '[^A-Za-z0-9]', '-')
}

# --- ubica el .jsonl de una sesion -------------------------------------------
function Get-RutaTranscript {
    param([string]$Cwd, [string]$Sesion)
    $dir = Join-Path $script:RaizProyectos (ConvertTo-CarpetaProyecto $Cwd)
    $f = Join-Path $dir "$Sesion.jsonl"
    if (Test-Path $f) { return $f }
    return $null
}

# --- que deja una sesion en disco --------------------------------------------
#  El .jsonl es la conversacion en si. Al lado, Claude Code deja una carpeta con
#  el mismo uuid (ahi vive custom-title.json, el nombre que puso /rename).
#  Devuelve un objeto por rastro que exista, con tamano, para poder mostrar QUE
#  se va a borrar antes de borrarlo.
function Get-RastrosSesion {
    param(
        [Parameter(Mandatory)][string]$Cwd,
        [Parameter(Mandatory)][string]$Sesion
    )

    # Guardarrail: con un uuid vacio o raro, el Remove-Item de mas abajo pasaria
    # a borrar la carpeta del proyecto entera. Se valida la forma antes de tocar
    # el disco.
    $formaUuid = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    if ($Sesion -notmatch $formaUuid) {
        throw "El id de sesion no tiene forma de uuid, no borro nada: '$Sesion'"
    }

    $dir = Join-Path $script:RaizProyectos (ConvertTo-CarpetaProyecto $Cwd)

    foreach ($cand in @(
            @{ Ruta = (Join-Path $dir "$Sesion.jsonl"); Tipo = 'transcript' },
            @{ Ruta = (Join-Path $dir $Sesion); Tipo = 'carpeta' }
        )) {
        if (-not (Test-Path -LiteralPath $cand.Ruta)) { continue }

        if ($cand.Tipo -eq 'carpeta') {
            $suma = (Get-ChildItem -LiteralPath $cand.Ruta -Recurse -File -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
        } else {
            $suma = (Get-Item -LiteralPath $cand.Ruta).Length
        }
        if (-not $suma) { $suma = 0 }

        [pscustomobject]@{
            Ruta   = $cand.Ruta
            Tipo   = $cand.Tipo
            Nombre = (Split-Path -Leaf $cand.Ruta)
            Bytes  = [int64]$suma
        }
    }
}

# --- borra la conversacion de verdad: transcript + carpeta + panel -----------
#  IRREVERSIBLE. Sin el .jsonl la sesion no se reabre con --resume y no hay
#  papelera: Remove-Item sobre un archivo no manda nada a la de Windows.
#
#  Los archivos van primero y la entrada del panel al final, a proposito: si
#  Claude Code tiene el transcript abierto Windows no lo suelta, y asi el error
#  deja todo como estaba en vez de un panel sin entrada y la charla todavia en
#  disco.
function Remove-ConversacionCompleta {
    param(
        [Parameter(Mandatory)][string]$Carpeta,
        [Parameter(Mandatory)][string]$Id
    )

    $conv = @(Get-Conversaciones -Carpeta $Carpeta | Where-Object { $_.id -eq $Id })[0]
    if (-not $conv) { throw "No hay ninguna conversacion con id '$Id'" }

    $borrados = @()
    foreach ($r in @(Get-RastrosSesion -Cwd $conv.cwd -Sesion $conv.sesion)) {
        try {
            Remove-Item -LiteralPath $r.Ruta -Recurse -Force -ErrorAction Stop
        } catch {
            throw "No pude borrar $($r.Nombre): $($_.Exception.Message)`n`nSi la conversacion esta abierta en Claude Code, cerrala y proba de nuevo. No se toco el panel."
        }
        $borrados += $r
    }

    Remove-Conversacion -Carpeta $Carpeta -Id $Id | Out-Null

    return [pscustomobject]@{
        Id       = $Id
        Titulo   = $conv.titulo
        Sesion   = $conv.sesion
        Borrados = $borrados
    }
}

# --- dato autoritativo del tamano de ventana ---------------------------------
#  El statusline de Claude Code recibe un payload con el context_window real y
#  el plugin claude-hud lo cachea en disco, indexado por el sha256 de la ruta
#  del transcript. Es LA fuente de verdad: adivinar el limite daba errores de
#  hasta 68 puntos (171k se leia 85% de 200k cuando era 17% de 1M).
$script:CacheHud = Join-Path $env:USERPROFILE '.claude\plugins\claude-hud\context-cache'

function Get-CacheContexto {
    param([string]$RutaTranscript)
    if (-not (Test-Path $script:CacheHud)) { return $null }
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $bytes = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($RutaTranscript))
        $hash = ($bytes | ForEach-Object { $_.ToString('x2') }) -join ''
        $f = Join-Path $script:CacheHud "$hash.json"
        if (-not (Test-Path $f)) { return $null }
        # -Encoding UTF8 obligatorio: sin eso PS 5.1 lee con el codepage ANSI y
        # el session_name vuelve con la ñ rota ("pestaÃ±as").
        return (Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch { return $null }
}

# --- nombre real de la sesion ------------------------------------------------
#  El que se pone con /rename dentro de Claude Code. Tres fuentes, por orden de
#  FRESCURA (no de comodidad):
#
#    1. ~/.claude/sessions/<pid>.json  -> lo escribe el propio proceso apenas
#       corres /rename. Es el unico que esta al dia al instante.
#    2. <proyecto>/<uuid>/custom-title.json -> sobrevive a la sesion cerrada.
#    3. el cache de claude-hud -> ultimo recurso.
#
#  El orden importa y costo un bug: antes se leia SOLO el cache de claude-hud,
#  que recien se entera cuando esa pestaña vuelve a renderizar su statusline. Si
#  renombrabas y dejabas la charla quieta, el gadget seguia con el nombre viejo
#  Y el click no encontraba la pestaña (que si se habia renombrado al toque).
function Get-NombreSesion {
    param([string]$Cwd, [string]$Sesion)

    # 1. sesion viva, PERO solo si el nombre lo puso el usuario con /rename.
    #    Con nameSource 'derived' el registro trae un relleno ("proyecto-12")
    #    que no es el que se ve en ningun lado: la pestaña muestra el ai-title.
    #    Tomarlo igual era el bug: el panel decia una cosa y la pestaña otra, y
    #    el click no encontraba nada.
    $derivado = $null
    $dirS = Join-Path $env:USERPROFILE '.claude\sessions'
    if (Test-Path -LiteralPath $dirS) {
        foreach ($f in (Get-ChildItem -LiteralPath $dirS -Filter '*.json' -ErrorAction SilentlyContinue)) {
            try { $j = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }
            if (-not $j.sessionId) { continue }
            if (([string]$j.sessionId).ToLower() -ne $Sesion.ToLower()) { continue }
            if ($j.name) {
                if ($j.nameSource -eq 'user') { return [string]$j.name }
                $derivado = [string]$j.name      # guardado como ultimo recurso
            }
            break
        }
    }

    # 2. el rename queda en disco aunque la sesion se cierre
    $dirUuid = Join-Path (Join-Path $script:RaizProyectos (ConvertTo-CarpetaProyecto $Cwd)) $Sesion
    $custom = Join-Path $dirUuid 'custom-title.json'
    if (Test-Path -LiteralPath $custom) {
        try {
            $ct = Get-Content -LiteralPath $custom -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($ct.customTitle) { return [string]$ct.customTitle }
        } catch { }
    }

    $t = Get-RutaTranscript -Cwd $Cwd -Sesion $Sesion

    # 3. el titulo automatico que genera Claude Code. ES EL QUE MUESTRA LA
    #    PESTAÑA del terminal, asi que usarlo es lo que hace que el panel y la
    #    pestaña digan lo mismo (y que el click la encuentre).
    if ($t) {
        $ai = Get-TituloAuto -RutaTranscript $t -Sesion $Sesion
        if ($ai) { return $ai }
    }

    # 4. el relleno del registro, mejor que nada
    if ($derivado) { return $derivado }

    # 5. lo ultimo que vio el statusline
    if (-not $t) { return $null }
    $cache = Get-CacheContexto -RutaTranscript $t
    if ($cache -and $cache.session_name) { return [string]$cache.session_name }
    return $null
}

# --- titulo automatico (ai-title) --------------------------------------------
#  Claude Code escribe en el transcript lineas
#  {"type":"ai-title","aiTitle":"...","sessionId":"..."} y ese es el texto que
#  termina en el titulo de la pestaña del terminal.
#
#  Se cachea con TTL: escanear varios transcripts de 1 MB en cada refresco seria
#  caro, y el titulo cambia poquisimo. Select-String stremea, no carga el
#  archivo entero en memoria.
$script:cacheAiTitle = @{}
$script:TtlAiTitle = 120

function Get-TituloAuto {
    param([Parameter(Mandatory)][string]$RutaTranscript, [Parameter(Mandatory)][string]$Sesion)

    $k = $Sesion.ToLower()
    $ahora = Get-Date
    if ($script:cacheAiTitle.ContainsKey($k)) {
        $e = $script:cacheAiTitle[$k]
        if (($ahora - $e.Cuando).TotalSeconds -lt $script:TtlAiTitle) { return $e.Valor }
    }

    $valor = $null
    try {
        # Solo el ARRANQUE del archivo. El ai-title se escribe apenas Claude Code
        # bautiza la conversacion, o sea temprano. Recorrer el .jsonl entero con
        # Select-String costaba ~800 ms en un transcript de 12 MB, y eso se paga
        # en el hilo de la UI cada vez que vence el cache.
        #
        # Contra: si el titulo se regenerara MUY tarde, se toma el anterior. Es
        # cosmetico y prefiero eso a un tiron de un segundo.
        $fs = [System.IO.File]::Open($RutaTranscript, [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $buf = New-Object byte[] ([int][Math]::Min(524288, $fs.Length))
            $leidos = $fs.Read($buf, 0, $buf.Length)
        } finally { $fs.Dispose() }

        if ($leidos -gt 0) {
            $txt = [System.Text.Encoding]::UTF8.GetString($buf, 0, $leidos)
            # El ultimo de esa ventana gana: el titulo se puede regenerar.
            $ult = $null
            foreach ($l in ($txt -split "`n")) {
                if ($l -like '*"type":"ai-title"*') { $ult = $l }
            }
            if ($ult) {
                $o = $ult | ConvertFrom-Json
                if ($o.aiTitle) { $valor = [string]$o.aiTitle }
            }
        }
    } catch { }

    $script:cacheAiTitle[$k] = @{ Valor = $valor; Cuando = $ahora }
    return $valor
}

# --- como mostrar una conversacion -------------------------------------------
#  Manda el nombre real de la sesion; el titulo guardado es el respaldo para
#  cuando todavia no la renombraron.
function Get-TituloMostrable {
    param($Conversacion)
    $nombre = Get-NombreSesion -Cwd $Conversacion.cwd -Sesion $Conversacion.sesion
    if ($nombre) { return $nombre }
    return [string]$Conversacion.titulo
}

# --- baja a disco el nombre de /rename ---------------------------------------
#  El gadget resuelve el nombre real en vivo, pero index.html solo ve
#  conversaciones.js: esta en file:// y no puede leer ni el cache de claude-hud
#  ni el custom-title.json. Sin esto, el panel del navegador se queda con el
#  titulo viejo para siempre.
#
#  Devuelve la lista ya actualizada, asi quien la llama no tiene que releer.
function Sync-TitulosGuardados {
    param([Parameter(Mandatory)][string]$Carpeta)

    $todas = @(Get-Conversaciones -Carpeta $Carpeta)

    $cambios = 0
    foreach ($c in $todas) {
        $real = Get-NombreSesion -Cwd $c.cwd -Sesion $c.sesion
        # Sin nombre real (sesion que nunca paso por el statusline) se respeta
        # el titulo guardado: es el respaldo, no un dato viejo.
        if ($real -and $real -ne [string]$c.titulo) {
            $c.titulo = $real
            $cambios++
        }
    }

    # Si el archivo esta tomado, no se rompe el refresco: se dibuja igual y se
    # reintenta en el proximo tick.
    if ($cambios -gt 0) {
        try { Save-Conversaciones -Carpeta $Carpeta -Conversaciones $todas } catch { }
    }

    # Se emiten de a uno, igual que Get-Conversaciones. Un "return ,$todas"
    # parece lo prolijo y es justo lo contrario: el caller recibe UN elemento
    # que es el array entero, y el @() de afuera no lo salva.
    foreach ($item in $todas) { $item }
}

# Si esta sesion no tiene cache, se toma el tamano de ventana mas frecuente
# entre las que si la tienen: para una misma cuenta y modelo es estable.
function Get-VentanaHabitual {
    if ($null -ne $script:VentanaHabitual) { return $script:VentanaHabitual }
    $script:VentanaHabitual = 0
    try {
        $tam = Get-ChildItem $script:CacheHud -Filter *.json -ErrorAction Stop |
            ForEach-Object { (Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json).context_window_size } |
            Where-Object { $_ -gt 0 }
        if ($tam) {
            $script:VentanaHabitual = ($tam | Group-Object | Sort-Object Count -Descending |
                Select-Object -First 1).Name -as [int]
        }
    } catch { }
    return $script:VentanaHabitual
}

# --- calcula el uso de contexto de una sesion --------------------------------
#  El contexto de un turno es lo que entro + lo que salio:
#    input + cache_creation + cache_read + output
#  del ULTIMO mensaje del assistant. El transcript NO guarda el limite de la
#  ventana, asi que se asume 200k y se sube a 1M si el uso ya lo paso.
function Get-ContextoSesion {
    param([string]$Cwd, [string]$Sesion, [int]$Limite = 0)

    $vacio = [pscustomobject]@{ Tokens = 0; Limite = 0; Porcentaje = 0; Hay = $false; Fuente = 'ninguna'; Fecha = $null }

    $f = Get-RutaTranscript -Cwd $Cwd -Sesion $Sesion
    if (-not $f) { return $vacio }

    # Cache por transcript: mientras el archivo no cambie, el contexto tampoco.
    # Es EL ahorro grande del refresco: de N conversaciones normalmente solo una
    # esta trabajando, y las otras devuelven al instante. Medido: 113 ms cada
    # una sin cache, y con 6 conversaciones eso congelaba la ventana casi un
    # segundo en cada tick.
    $fi = Get-Item -LiteralPath $f -ErrorAction SilentlyContinue
    $sello = if ($fi) { '{0}|{1}' -f $fi.LastWriteTimeUtc.Ticks, $fi.Length } else { '' }
    if ($sello -and $script:cacheCtx.ContainsKey($f) -and $script:cacheCtx[$f].Sello -eq $sello) {
        return $script:cacheCtx[$f].Valor
    }

    # Se lee solo la cola con seek. NO usar Get-Content -Tail: ver el comentario
    # de Get-ColaArchivo.
    $lineas = @(Get-ColaArchivo -Ruta $f)
    if ($lineas.Count -eq 0) { return $vacio }
    if ($lineas.Count -gt 60) { $lineas = $lineas[($lineas.Count - 60)..($lineas.Count - 1)] }

    $CAMPOS = 'input_tokens', 'cache_creation_input_tokens', 'cache_read_input_tokens', 'output_tokens'

    $usage = $null
    for ($i = $lineas.Count - 1; $i -ge 0; $i--) {
        $l = $lineas[$i]
        if ($l -notlike '*"type":"assistant"*') { continue }
        if ($l -notlike '*"usage"*') { continue }
        # Los turnos de subagentes (isSidechain) tienen su propio contexto chico
        # y no representan el de la conversacion principal.
        if ($l -like '*"isSidechain":true*') { continue }
        try {
            $o = $l | ConvertFrom-Json
            $u = $o.message.usage
            if (-not $u) { continue }

            # Un turno interrumpido deja un usage con los CUATRO campos en cero.
            # Existe, asi que si se lo aceptaba la tarjeta mostraba 0% con el
            # transcript lleno. Hay que seguir buscando hacia atras.
            $suma = 0
            foreach ($campo in $CAMPOS) { if ($u.$campo) { $suma += [int]$u.$campo } }
            if ($suma -le 0) { continue }

            $usage = $u
            break
        } catch { continue }
    }
    # Si en esas 60 lineas no hubo ningun turno del asistente con usage, se cae
    # al cache de claude-hud, que guarda el MISMO objeto usage del ultimo turno.
    #
    # Pasa de verdad: una conversacion cuya cola quedo con puros resultados de
    # herramientas o mensajes del usuario mostraba 0% con el transcript lleno,
    # mientras el statusline de esa misma sesion marcaba 17%.
    $fuenteUso = 'transcript'
    if (-not $usage) {
        $cacheUso = Get-CacheContexto -RutaTranscript $f
        if ($cacheUso -and $cacheUso.current_usage) {
            $usage = $cacheUso.current_usage
            $fuenteUso = 'claude-hud'
        }
    }
    if (-not $usage) { return $vacio }

    $tokens = 0
    foreach ($campo in $CAMPOS) {
        $v = $usage.$campo
        if ($v) { $tokens += [int]$v }
    }

    # El limite se resuelve por orden de confianza:
    #   1. lo que fijo el usuario en conversaciones.js
    #   2. el context_window_size real, cacheado por claude-hud  <- lo normal
    #   3. la ventana mas frecuente entre las otras sesiones
    #   4. ultimo recurso: el tier mas chico que entre
    $fuente = 'fijado'
    if ($Limite -le 0) {
        $cache = Get-CacheContexto -RutaTranscript $f
        if ($cache -and $cache.context_window_size -gt 0) {
            $Limite = [int]$cache.context_window_size
            $fuente = 'claude-hud'
        }
    }
    if ($Limite -le 0) {
        $habitual = Get-VentanaHabitual
        if ($habitual -gt 0) { $Limite = $habitual; $fuente = 'habitual' }
    }
    if ($Limite -le 0) {
        $Limite = if ($tokens -gt 200000) { 1000000 } else { 200000 }
        $fuente = 'estimado'
    }

    $resultado = [pscustomobject]@{
        Tokens     = $tokens
        Limite     = $Limite
        Porcentaje = [math]::Round(100.0 * $tokens / $Limite, 1)
        Hay        = $true
        Fuente     = $fuente
        Fecha      = if ($fi) { $fi.LastWriteTime } else { Get-Date }
    }
    if ($sello) { $script:cacheCtx[$f] = @{ Sello = $sello; Valor = $resultado } }
    return $resultado
}

# --- abre una conversacion en una terminal -----------------------------------
#  OJO: Start-Process -ArgumentList con un ARRAY no entrecomilla los elementos,
#  solo los une con espacios, y eso parte cualquier cwd que tenga espacios.
#  Por eso la linea se arma a mano como UN string con las comillas explicitas.
function Start-Conversacion {
    param(
        [Parameter(Mandatory)][string]$Cwd,
        [Parameter(Mandatory)][string]$Sesion,
        [switch]$Remoto,
        [string]$Nombre,
        [switch]$DryRun
    )

    $cwd = ConvertTo-RutaWindows $Cwd

    if ($Sesion -notmatch '^[0-9a-fA-F-]{8,64}$') { throw "El id de sesion no parece un UUID valido: $Sesion" }
    if (-not (Test-Path -LiteralPath $cwd -PathType Container)) { throw "La carpeta no existe:`n$cwd" }

    # --remote-control publica ESTA conversacion en claude.ai/code y en la app del
    # celular. Es la unica forma de llevar una conversacion VIEJA al telefono: el
    # server mode (`claude remote-control`) siempre arranca una sesion vacia, y
    # cambiar de conversacion con /resume no le manda el historial al dispositivo.
    #
    # El nombre sale del titulo de la tarjeta, que es texto libre del usuario y
    # termina dentro de una linea de comando: va por lista blanca.
    #
    # \p{L} deja pasar CUALQUIER letra Unicode, asi "Dialogo de confirmacion" no
    # pierde los acentos ni la enie. Lo que se cae es todo metacaracter de cmd:
    # comillas, & | ; < > ^ % ! ` $ ( ) — sin eso no hay nada que inyectar.
    $flagRemoto = ''
    if ($Remoto) {
        $n = ''
        if ($Nombre) {
            $n = ($Nombre -replace '[^\p{L}\p{Nd} ._-]', ' ') -replace '\s+', ' '
            $n = $n.Trim()
            if ($n.Length -gt 40) { $n = $n.Substring(0, 40).Trim() }
        }
        $flagRemoto = if ($n) { ' --remote-control "{0}"' -f $n } else { ' --remote-control' }
    }

    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($wt) {
        $exe = $wt.Source
        # -w 0 = la ventana de Windows Terminal usada mas recientemente, y ahi
        # abre una PESTAÑA. Sin ese flag cada conversacion se llevaba una ventana
        # nueva. Si no hay ninguna abierta, wt crea una: no hay que chequear.
        #
        # A proposito NO se pasa --title: eso congelaria el titulo de la pestaña
        # y Select-PestanaSesion la busca justamente por el nombre que le pone
        # Claude Code (el de /rename).
        $linea = '-w 0 new-tab -d "{0}" cmd /k claude --resume {1}{2}' -f $cwd, $Sesion, $flagRemoto
    } else {
        $exe = 'cmd.exe'
        $linea = '/k cd /d "{0}" && claude --resume {1}{2}' -f $cwd, $Sesion, $flagRemoto
    }

    if ($DryRun) { return [pscustomobject]@{ Exe = $exe; Args = $linea; Cwd = $cwd; Remoto = [bool]$Remoto } }

    Start-Process -FilePath $exe -ArgumentList $linea

    # Se deja una marca de que ESTA sesion se lanzo con el remoto. Hace falta
    # porque el registro de ~/.claude/sessions no tiene ningun campo que lo diga,
    # y claude.exe no expone sus argumentos: sin la marca no hay como distinguir
    # 'abierta' de 'remoto'. Get-EstadosSesion limpia las marcas huerfanas.
    if ($Remoto) {
        try {
            $dirM = Join-Path $PSScriptRoot '.remotos'
            if (-not (Test-Path -LiteralPath $dirM)) {
                $null = New-Item -ItemType Directory -Path $dirM -Force
                (Get-Item -LiteralPath $dirM).Attributes += 'Hidden'
            }
            Set-Content -LiteralPath (Join-Path $dirM $Sesion.ToLower()) -Value '' -NoNewline
        } catch { }      # sin marca el punto dira 'abierta': feo, no roto
    }

    return [pscustomobject]@{ Exe = $exe; Args = $linea; Cwd = $cwd; Remoto = [bool]$Remoto }
}

# --- la organizacion permite Remote Control? ---------------------------------
#  Claude Code baja la politica de la cuenta a ~/.claude/policy-limits.json y la
#  reescribe al cambiar de cuenta. Si el admin lo bloqueo, el boton de remoto
#  ofrece algo que SIEMPRE va a fallar, y encima deja la marca puesta.
#
#  Ante la duda devuelve $true: es mejor ofrecerlo y que falle a esconder algo
#  que si funciona.
function Test-RemotoPermitido {
    $f = Join-Path $env:USERPROFILE '.claude\policy-limits.json'
    if (-not (Test-Path -LiteralPath $f)) { return $true }
    try {
        $p = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
        $r = $p.restrictions.allow_remote_control
        if ($null -ne $r -and ($r.PSObject.Properties.Name -contains 'allowed')) {
            return [bool]$r.allowed
        }
    } catch { }
    return $true
}

# --- que conversaciones estan abiertas ahora mismo ---------------------------
#  Devuelve un hashtable  uuid(minuscula) -> 'remoto' | 'abierta'
#  Lo que NO esta en el hashtable, esta cerrado.
#
#  OJO, esto es un PROXY, no la verdad: detecta que hay un proceso vivo lanzado
#  con --remote-control, no que Anthropic lo tenga conectado en este segundo. Si
#  se cae la red el proceso sigue vivo y esto sigue diciendo 'remoto'.
#
#  Solo ve sesiones lanzadas con los flags en la linea de comando (las que abre
#  este panel). Si prendes el remoto tipeando /remote-control adentro de una
#  sesion ya abierta, no hay rastro en el CommandLine y aca figura 'abierta'.
function Get-EstadosSesion {
    $mapa = @{}

    # QUE ESTA ABIERTA: sale del registro que Claude Code mantiene solo, en
    # ~/.claude/sessions/<pid>.json — un archivo por proceso vivo, con sessionId,
    # cwd, nombre y status. Se lee en ~3 ms.
    #
    # La version anterior miraba la linea de comando con Win32_Process: tardaba
    # ~265 ms Y NO VEIA las sesiones que no tienen los argumentos ahi, porque
    # claude.exe no los expone. Con eso, la conversacion abierta en la propia
    # maquina figuraba 'cerrada', que es justo el caso que hay que proteger.
    $dirS = Join-Path $env:USERPROFILE '.claude\sessions'
    if (-not (Test-Path -LiteralPath $dirS)) { return $mapa }

    $vivas = @{}
    $conPuente = @{}
    foreach ($f in (Get-ChildItem -LiteralPath $dirS -Filter '*.json' -ErrorAction SilentlyContinue)) {
        try { $j = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }
        if (-not $j.sessionId -or -not $j.pid) { continue }

        # El json sobrevive si el proceso murio mal, asi que se confirma contra
        # el PID. El chequeo del nombre es por si el PID se reciclo.
        $p = Get-Process -Id $j.pid -ErrorAction SilentlyContinue
        if (-not $p -or $p.ProcessName -notmatch '^(claude|node)$') { continue }

        $u = ([string]$j.sessionId).ToLower()
        $vivas[$u] = $true

        # bridgeSessionId aparece cuando el puente con claude.ai/code esta
        # levantado DE VERDAD. Es el unico dato que lo confirma.
        if ($j.PSObject.Properties.Name -contains 'bridgeSessionId' -and $j.bridgeSessionId) {
            $conPuente[$u] = $true
        }
    }

    # QUE TIENE EL REMOTO: el registro no lo dice, asi que se usa la marca que
    # deja Start-Conversacion -Remoto. Las huerfanas (sesion ya muerta) se
    # borran aca mismo, que es el unico lugar que sabe quien sigue vivo.
    $remotas = @{}
    $dirM = Join-Path $PSScriptRoot '.remotos'
    if (Test-Path -LiteralPath $dirM) {
        foreach ($m in (Get-ChildItem -LiteralPath $dirM -File -ErrorAction SilentlyContinue)) {
            $u = $m.Name.ToLower()
            if ($vivas.ContainsKey($u)) { $remotas[$u] = $true }
            else { Remove-Item -LiteralPath $m.FullName -Force -ErrorAction SilentlyContinue }
        }
    }

    # El semaforo lo decide el PUENTE, no la marca. La marca es una PROMESA: la
    # escribe el lanzador apenas manda el comando, sin esperar a ver si el
    # remoto conecto. Un intento fallido dejaba la señal verde prendida mientras
    # la sesion viviera, mintiendo.
    #
    # Ademas asi se detecta un remoto prendido POR AFUERA del gadget, que con la
    # marca sola era invisible.
    foreach ($u in $vivas.Keys) {
        $mapa[$u] = if ($conPuente.ContainsKey($u)) { 'remoto' } else { 'abierta' }
    }

    return $mapa
}

# --- quien esta pensando ahora mismo -----------------------------------------
#  Mismo registro que Get-EstadosSesion (~/.claude/sessions/<pid>.json), pero
#  mirando otro campo: "status", que vale "busy" mientras el modelo trabaja e
#  "idle" cuando espera al humano. Es el dato real; adivinar por el mtime del
#  transcript no sirve, porque ese solo se mueve al cerrar cada mensaje.
#
#  Va aparte y no dentro de Get-EstadosSesion para no cambiarle el contrato
#  (devuelve 'abierta'/'remoto' y hay codigo que depende de eso). Si algun dia
#  se unifican, este es el candidato obvio a fusionar.
#
#  Devuelve un hashtable sessionId (minusculas) -> $true si esta pensando.
function Get-ActividadSesiones {
    $mapa = @{}
    $dirS = Join-Path $env:USERPROFILE '.claude\sessions'
    if (-not (Test-Path -LiteralPath $dirS)) { return $mapa }

    foreach ($f in (Get-ChildItem -LiteralPath $dirS -Filter '*.json' -ErrorAction SilentlyContinue)) {
        try { $j = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }
        if (-not $j.sessionId -or -not $j.pid) { continue }
        if ($j.status -ne 'busy') { continue }

        # El json sobrevive a un proceso que murio mal, y ahi el ultimo "busy"
        # quedaria latiendo para siempre. Se confirma contra el PID.
        $p = Get-Process -Id $j.pid -ErrorAction SilentlyContinue
        if (-not $p -or $p.ProcessName -notmatch '^(claude|node)$') { continue }

        $mapa[([string]$j.sessionId).ToLower()] = $true
    }

    return $mapa
}

# --- traer al frente una conversacion ya abierta -----------------------------
#  P/Invoke minimo. El guard evita re-agregar el tipo si la lib se dot-sourcea
#  dos veces en el mismo proceso (Add-Type tiraria).
if (-not ('Gia.Ventanas' -as [type])) {
    Add-Type -Namespace Gia -Name Ventanas -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
'@
}

# El terminal que hospeda una sesion no cambia mientras esa sesion vive, asi que
# el handle se cachea por pid: la consulta CIM cuesta ~300 ms y no se puede
# pagar en cada click.
$script:cacheVentanas = @{}

# --- ventana que hospeda a una sesion ----------------------------------------
#  claude.exe es una app de consola: su MainWindowHandle es 0. La ventana de
#  verdad es la del terminal que lo hospeda, y esa esta mas arriba en el arbol
#  de procesos (claude -> powershell -> WindowsTerminal). Se sube hasta dar con
#  el primero que tenga ventana.
#
#  Devuelve [IntPtr]::Zero si la sesion no esta abierta.
function Get-VentanaSesion {
    param([Parameter(Mandatory)][string]$Sesion)

    $dirS = Join-Path $env:USERPROFILE '.claude\sessions'
    if (-not (Test-Path -LiteralPath $dirS)) { return [IntPtr]::Zero }

    $pidSesion = 0
    foreach ($f in (Get-ChildItem -LiteralPath $dirS -Filter '*.json' -ErrorAction SilentlyContinue)) {
        try { $j = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }
        if (-not $j.sessionId -or -not $j.pid) { continue }
        if (([string]$j.sessionId).ToLower() -ne $Sesion.ToLower()) { continue }
        $pidSesion = [int]$j.pid
        break
    }
    if (-not $pidSesion) { return [IntPtr]::Zero }

    # Cache primero: se valida con IsWindow por si el terminal ya se cerro.
    if ($script:cacheVentanas.ContainsKey($pidSesion)) {
        $h = $script:cacheVentanas[$pidSesion]
        if ([Gia.Ventanas]::IsWindow($h)) { return $h }
        $script:cacheVentanas.Remove($pidSesion)
    }

    # UNA sola consulta CIM y despues se camina en memoria. Preguntar por cada
    # padre por separado costaba ~470 ms (hasta 6 consultas), que es medio
    # segundo de UI congelada en cada click.
    $padres = @{}
    foreach ($ci in (Get-CimInstance -ClassName Win32_Process -Property ProcessId, ParentProcessId -ErrorAction SilentlyContinue)) {
        $padres[[int]$ci.ProcessId] = [int]$ci.ParentProcessId
    }

    $actual = $pidSesion
    for ($i = 0; $i -lt 6 -and $actual -gt 0; $i++) {
        $p = Get-Process -Id $actual -ErrorAction SilentlyContinue
        if ($p -and $p.MainWindowHandle -ne 0) {
            $script:cacheVentanas[$pidSesion] = [IntPtr]$p.MainWindowHandle
            return [IntPtr]$p.MainWindowHandle
        }
        if (-not $padres.ContainsKey($actual)) { break }
        $actual = $padres[$actual]
    }

    return [IntPtr]::Zero
}

# --- selecciona la pestana correcta ------------------------------------------
#  Varias conversaciones suelen vivir en pestanas de la MISMA ventana de Windows
#  Terminal (medido: dos sesiones -> un solo hwnd), asi que enfocar la ventana
#  no alcanza: siempre ganaba la pestana activa.
#
#  Windows Terminal SI expone sus pestanas por UI Automation, y el Name de cada
#  una es el nombre de la sesion (con un icono adelante, por eso se compara por
#  contenido y no por igualdad).
#
#  Devuelve $true solo si encontro y activo la pestana. Si el terminal no es
#  Windows Terminal, no hay TabItems y devuelve $false sin romper nada.
function Select-PestanaSesion {
    param(
        [Parameter(Mandatory)][IntPtr]$Handle,
        [string]$Nombre
    )

    if ($Handle -eq [IntPtr]::Zero -or -not $Nombre) { return $false }

    try {
        Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes -ErrorAction Stop

        $raiz = [System.Windows.Automation.AutomationElement]::FromHandle($Handle)
        if (-not $raiz) { return $false }

        $cond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::TabItem)

        foreach ($tab in $raiz.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)) {
            # Contains y no -like: un nombre de sesion puede tener * o ?, que en
            # -like serian comodines y matchearian cualquier cosa.
            if (-not $tab.Current.Name.Contains($Nombre)) { continue }

            $sel = $null
            if ($tab.TryGetCurrentPattern(
                    [System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$sel)) {
                $sel.Select()
                return $true
            }
        }
    } catch { }

    return $false
}

# --- la trae al frente --------------------------------------------------------
function Show-VentanaSesion {
    param([Parameter(Mandatory)][IntPtr]$Handle)

    if ($Handle -eq [IntPtr]::Zero) { return $false }

    # Minimizada, SetForegroundWindow la trae al frente pero la deja minimizada:
    # hay que restaurarla primero.
    if ([Gia.Ventanas]::IsIconic($Handle)) {
        [void][Gia.Ventanas]::ShowWindow($Handle, 9)   # SW_RESTORE
    }
    return [Gia.Ventanas]::SetForegroundWindow($Handle)
}

# --- formatea 161513 -> "161,5k" ---------------------------------------------
function Format-Tokens {
    param([int]$N)
    if ($N -ge 1000000) { return ('{0:n1}M' -f ($N / 1000000.0)) }
    if ($N -ge 1000) { return ('{0:n1}k' -f ($N / 1000.0)) }
    return "$N"
}

# --- formatea 365796 -> "357 KB" ---------------------------------------------
function Format-Bytes {
    param([int64]$Bytes)
    if ($Bytes -ge 1MB) { return ('{0:n1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:n0} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}
