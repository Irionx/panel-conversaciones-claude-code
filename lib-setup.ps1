# =============================================================================
#  lib-setup.ps1 - Verifica y repara la instalacion del panel.
#
#  Cinco piezas independientes:
#    1. el protocolo claudeconv://        (para los enlaces claudeconv://)
#    2. la carpeta en el PATH de usuario  (para que exista el comando guardar)
#    3. la junction del skill /save       (para que exista /save en Claude Code)
#    4. los shims para bash               (para que ande desde el prompt "!")
#    5. el volcado de la cuota            (para el chip de cuota de la cabecera)
#
#  La base de datos no es una pieza: la crea sola la capa de Datos la primera
#  vez que arranca cualquier cosa. Ver ARQUITECTURA.md.
#
#  Todo en scope de USUARIO (HKCU y PATH User): nunca hace falta admin.
#
#  No se guarda ningun "ya instalado": se mide el estado real en cada corrida.
#  Asi, si moves la carpeta, la proxima vez se re-apunta solo.
#
#  Lo usan setup.ps1 (CLI) y gadget.ps1 (al arrancar).
# =============================================================================

$script:ClaveProto = 'HKCU:\Software\Classes\claudeconv'
$script:VersionShims = 3

# --- shims para bash ---------------------------------------------------------
#  Se generan desde aca y no se editan a mano, asi el setup los puede reparar.
#  La carpeta sale de BASH_SOURCE: sin rutas hardcodeadas, el shim viaja con la
#  carpeta y sigue funcionando si la moves.
function Get-TextoShim {
    param([Parameter(Mandatory)][string]$Cmd)

    return @"
#!/usr/bin/env bash
# shim v$script:VersionShims - lo genera lib-setup.ps1, no editar a mano.
#
# Existe porque Git Bash NO resuelve .cmd desde el PATH (solo el nombre exacto
# y .exe), asi que hace falta un archivo sin extension con este nombre.
aqui="`$(cd "`$(dirname "`${BASH_SOURCE[0]}")" && pwd)"
exec "`$aqui/$Cmd" "`$@"
"@
}

# --- escribe un shim con las reglas que lo hacen funcionar --------------------
#  LF obligatorio: con CRLF el shebang queda "/usr/bin/env bash\r" y no arranca.
#  Sin BOM: bash no lo entiende en la primera linea.
function Write-Shim {
    param(
        [Parameter(Mandatory)][string]$Ruta,
        [Parameter(Mandatory)][string]$Contenido
    )
    $lf = $Contenido -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($Ruta, $lf, [System.Text.UTF8Encoding]::new($false))
}

# --- los .cmd son wrappers minimos para cmd.exe y PowerShell -----------------
function Get-TextoCmd {
    param([Parameter(Mandatory)][string]$Ps1)

    return @"
@echo off
REM Wrapper generado por lib-setup.ps1 si faltaba.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0$Ps1" %*
"@
}

# --- estado de las cinco piezas ----------------------------------------------
#  Devuelve un objeto por pieza: Clave, Nombre, Ok, Detalle y un scriptblock
#  Arreglar (o $null si no se puede arreglar solo).
#
#  Los scriptblocks usan .GetNewClosure() a proposito: sin eso, al invocarlos
#  desde otro scope las variables de esta funcion no resuelven.
function Get-EstadoInstalacion {
    param(
        [string]$Carpeta = $PSScriptRoot,
        # Sale por parametro para poder probar la pieza 5 contra un settings.json
        # de mentira. Un arreglo que solo se puede probar contra el archivo de
        # verdad no se prueba nunca.
        [string]$Ajustes = (Join-Path $env:USERPROFILE '.claude\settings.json')
    )

    $Carpeta = (Resolve-Path -LiteralPath $Carpeta).Path.TrimEnd('\')

    # --- 1. protocolo claudeconv:// ------------------------------------------
    #  Se copia a una local a proposito: dentro de un .GetNewClosure() un
    #  $script:algo se resuelve contra el scope NUEVO del closure, donde no
    #  existe, y llega como $null. Las locales si se capturan.
    $claveProto = $script:ClaveProto
    $claveCmd = Join-Path $claveProto 'shell\open\command'
    $esperado = ('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}\abrir-conversacion.ps1" -Url "%1"' -f $Carpeta)
    $actual = $null
    if (Test-Path $claveCmd) { $actual = [string](Get-Item $claveCmd).GetValue('') }

    $detalleProto = if (-not $actual) { 'sin registrar' }
    elseif ($actual -ne $esperado) { 'registrado, pero apunta a otra carpeta' }
    else { 'registrado y apuntando aca' }

    [pscustomobject]@{
        Clave    = 'protocolo'
        Nombre   = 'protocolo claudeconv://'
        Ok       = ($actual -eq $esperado)
        Detalle  = $detalleProto
        Arreglar = {
            New-Item -Path $claveProto -Force | Out-Null
            Set-ItemProperty -Path $claveProto -Name '(default)' -Value 'URL:Claude Code Conversacion'
            Set-ItemProperty -Path $claveProto -Name 'URL Protocol' -Value ''
            New-Item -Path (Join-Path $claveProto 'DefaultIcon') -Force | Out-Null
            Set-ItemProperty -Path (Join-Path $claveProto 'DefaultIcon') -Name '(default)' -Value 'powershell.exe,0'
            New-Item -Path $claveCmd -Force | Out-Null
            Set-ItemProperty -Path $claveCmd -Name '(default)' -Value $esperado
        }.GetNewClosure()
    }

    # --- 2. carpeta en el PATH de usuario ------------------------------------
    $pathUser = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $enPath = @($pathUser -split ';' |
        Where-Object { $_ } |
        Where-Object { $_.Trim().TrimEnd('\') -ieq $Carpeta }).Count -gt 0

    [pscustomobject]@{
        Clave    = 'path'
        Nombre   = 'carpeta en el PATH'
        Ok       = $enPath
        Detalle  = if ($enPath) { 'ya esta en el PATH de usuario' } else { 'falta en el PATH de usuario' }
        Arreglar = {
            # NUNCA 'setx PATH "%PATH%;..."': %PATH% trae tambien el PATH de
            # maquina (lo copiaria dentro del de usuario) y setx trunca a 1024
            # caracteres. La API de .NET con scope User no tiene ninguno de los
            # dos problemas.
            $viejo = [Environment]::GetEnvironmentVariable('PATH', 'User')
            # Se vuelve a mirar aca dentro y no se confia en el chequeo de
            # afuera: asi llamarlo dos veces no deja la carpeta duplicada.
            $ya = @($viejo -split ';' |
                Where-Object { $_ } |
                Where-Object { $_.Trim().TrimEnd('\') -ieq $Carpeta }).Count -gt 0
            if ($ya) { return }
            $nuevo = if ($viejo) { $viejo.TrimEnd(';') + ';' + $Carpeta } else { $Carpeta }
            [Environment]::SetEnvironmentVariable('PATH', $nuevo, 'User')
        }.GetNewClosure()
    }

    # --- 3. junction del skill /save -----------------------------------------
    $origenSkill = Join-Path $Carpeta 'skill'
    $destinoSkill = Join-Path $env:USERPROFILE '.claude\skills\save'

    $okSkill = $false
    $detalleSkill = 'sin crear'
    $puedeSkill = $true

    if (-not (Test-Path -LiteralPath $origenSkill)) {
        $detalleSkill = 'falta la carpeta skill\ en el panel'
        $puedeSkill = $false
    } elseif (Test-Path -LiteralPath $destinoSkill) {
        $item = Get-Item -LiteralPath $destinoSkill -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            $blanco = ([string[]]$item.Target)[0]
            if ($blanco -and $blanco.TrimEnd('\') -ieq $origenSkill.TrimEnd('\')) {
                $okSkill = $true
                $detalleSkill = 'junction apuntando aca'
            } else {
                $detalleSkill = 'junction apuntando a otra carpeta'
            }
        } else {
            # Hay un skill de verdad ahi: no se pisa nada sin avisar.
            $detalleSkill = 'ya hay una carpeta real ahi, no la piso'
            $puedeSkill = $false
        }
    }

    [pscustomobject]@{
        Clave    = 'skill'
        Nombre   = 'skill /save'
        Ok       = $okSkill
        Detalle  = $detalleSkill
        Arreglar = if ($puedeSkill) {
            {
                $padre = Split-Path -Parent $destinoSkill
                if (-not (Test-Path -LiteralPath $padre)) {
                    New-Item -ItemType Directory -Force -Path $padre | Out-Null
                }
                # Si habia una junction vieja apuntando mal, se saca primero.
                #
                # OJO: NO usar Remove-Item -Recurse aca. En PowerShell 5.1 puede
                # seguir la junction y borrar el CONTENIDO del destino, o sea el
                # skill\SKILL.md original de esta carpeta. Directory::Delete borra
                # solo el punto de reparse y nunca lo atraviesa.
                if (Test-Path -LiteralPath $destinoSkill) {
                    [System.IO.Directory]::Delete($destinoSkill, $false)
                }
                # Junction y no symlink: no pide admin ni modo desarrollador.
                New-Item -ItemType Junction -Path $destinoSkill -Target $origenSkill | Out-Null
            }.GetNewClosure()
        } else { $null }
    }

    # --- 4. shims y wrappers --------------------------------------------------
    $arch = @(
        @{ Shim = 'guardar'; Cmd = 'guardar.cmd'; Ps1 = 'guardar.ps1' },
        @{ Shim = 'borrar-conversacion'; Cmd = 'borrar-conversacion.cmd'; Ps1 = 'borrar.ps1' },
        @{ Shim = 'cerrar-gadget'; Cmd = 'cerrar-gadget.cmd'; Ps1 = 'cerrar-gadget.ps1' }
    )

    $faltantes = @()
    foreach ($a in $arch) {
        $rutaShim = Join-Path $Carpeta $a.Shim
        $rutaCmd = Join-Path $Carpeta $a.Cmd

        if (-not (Test-Path -LiteralPath $rutaCmd)) { $faltantes += $a.Cmd }

        if (-not (Test-Path -LiteralPath $rutaShim)) {
            $faltantes += $a.Shim
        } else {
            $txt = [System.IO.File]::ReadAllText($rutaShim)
            if ($txt -notmatch ('shim v{0}\b' -f $script:VersionShims)) {
                $faltantes += ('{0} (desactualizado)' -f $a.Shim)
            } elseif ($txt.Contains("`r")) {
                $faltantes += ('{0} (CRLF)' -f $a.Shim)
            }
        }
    }

    [pscustomobject]@{
        Clave    = 'shims'
        Nombre   = 'comandos para bash'
        Ok       = ($faltantes.Count -eq 0)
        Detalle  = if ($faltantes.Count -eq 0) { 'los 4 archivos al dia' } else { 'faltan o estan viejos: ' + ($faltantes -join ', ') }
        Arreglar = {
            foreach ($a in $arch) {
                Write-Shim -Ruta (Join-Path $Carpeta $a.Shim) -Contenido (Get-TextoShim -Cmd $a.Cmd)
                $rutaCmd = Join-Path $Carpeta $a.Cmd
                # El .cmd solo se crea si falta: los que vienen con la carpeta
                # tienen documentacion propia y no hay por que pisarla.
                if (-not (Test-Path -LiteralPath $rutaCmd)) {
                    [System.IO.File]::WriteAllText($rutaCmd, ((Get-TextoCmd -Ps1 $a.Ps1) -replace "`n", "`r`n"), [System.Text.UTF8Encoding]::new($false))
                }
            }
        }.GetNewClosure()
    }

    # --- 5. el volcado de la cuota -------------------------------------------
    #  La cuota real de la cuenta (rate_limits) NO existe en ningun archivo:
    #  Claude Code se la pasa por stdin al comando del statusline, y el
    #  statusline es su unico consumidor. Sin este volcado, el chip de la
    #  cabecera dice "sin datos de cuota". Ver ARQUITECTURA.md seccion 7.
    #
    #  Se ENVUELVE el comando que haya, no se reemplaza: cada uno tiene el
    #  statusline que quiere y pisarselo seria una falta de respeto (y ademas
    #  romperia su HUD). Se lee todo el stdin primero (cc_pl=$(cat)) para que el
    #  consumidor no pueda matar la escritura con un SIGPIPE y dejar el archivo
    #  cortado, se escribe a un temporal y se hace mv, que es atomico.
    # Copia local: dentro de un .GetNewClosure() un parametro se captura, pero
    # conviene el nombre corto para que el codigo de abajo se lea igual.
    $ajustes = $Ajustes
    $cmdActual = $null
    $hayAjustes = Test-Path -LiteralPath $ajustes
    if ($hayAjustes) {
        try { $cmdActual = [string](Get-Content -LiteralPath $ajustes -Raw | ConvertFrom-Json).statusLine.command } catch { }
    }
    # El marcador es la propia ruta del volcado: sirva la forma que sirva, si ya
    # esta ahi es que alguien ya lo instalo. Asi es idempotente.
    $cuotaOk = $cmdActual -and $cmdActual.Contains('statusline-ultimo.json')

    $detalleCuota = if (-not $hayAjustes) { 'no encuentro settings.json de Claude Code' }
    elseif ($cuotaOk) { 'el statusline vuelca la cuota' }
    elseif ($cmdActual) { 'hay un statusline, pero no vuelca la cuota' }
    else { 'no hay statusline configurado' }

    [pscustomobject]@{
        Clave    = 'cuota'
        Nombre   = 'volcado de la cuota'
        Ok       = [bool]$cuotaOk
        Detalle  = $detalleCuota
        # Sin settings.json no hay nada que arreglar desde aca.
        Arreglar = if (-not $hayAjustes) { $null } else {
            {
                $volcado = 'cc_cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; cc_pl=$(cat); ' +
                'cc_t="$cc_cfg/.statusline.$$.tmp"; printf ''%s'' "$cc_pl" > "$cc_t" && ' +
                'mv -f "$cc_t" "$cc_cfg/statusline-ultimo.json" 2>/dev/null'

                $txt = Get-Content -LiteralPath $ajustes -Raw
                Copy-Item -LiteralPath $ajustes -Destination ($ajustes + '.bak') -Force

                if ($cmdActual) {
                    # Envolver: el comando original entra en un grupo y se le
                    # alimenta el stdin que ya se leyo.
                    $nuevo = $volcado + '; printf ''%s'' "$cc_pl" | { ' + $cmdActual + ' ; }'
                    # Reemplazo del literal JSON exacto: mucho mas seguro que
                    # reserializar todo el settings.json del usuario.
                    $de = $cmdActual | ConvertTo-Json
                    $a = $nuevo | ConvertTo-Json
                    if (-not $txt.Contains($de)) {
                        throw 'no pude ubicar el comando del statusline en settings.json; toca a mano'
                    }
                    $txt = $txt.Replace($de, $a)
                } else {
                    # No habia statusline: se agrega uno que solo vuelca y no
                    # imprime nada, asi no aparece una linea vacia.
                    $bloque = '  "statusLine": { "type": "command", "command": ' + ($volcado | ConvertTo-Json) + ' },'
                    $i = $txt.IndexOf('{')
                    if ($i -lt 0) { throw 'settings.json no parece un objeto JSON' }
                    $txt = $txt.Substring(0, $i + 1) + "`n" + $bloque + $txt.Substring($i + 1)
                }
                # Si quedo JSON invalido, no se escribe: mejor sin cuota que con
                # el settings.json roto.
                $null = $txt | ConvertFrom-Json
                [System.IO.File]::WriteAllText($ajustes, $txt, [System.Text.UTF8Encoding]::new($false))
            }.GetNewClosure()
        }
    }
}

# --- repara las piezas que esten mal -----------------------------------------
function Repair-Instalacion {
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$Piezas)

    $hechas = @()
    $errores = @()

    foreach ($p in $Piezas) {
        if ($p.Ok) { continue }
        if (-not $p.Arreglar) {
            $errores += ('{0}: {1}' -f $p.Nombre, $p.Detalle)
            continue
        }
        try {
            & $p.Arreglar
            $hechas += $p.Nombre
        } catch {
            $errores += ('{0}: {1}' -f $p.Nombre, $_.Exception.Message)
        }
    }

    return [pscustomobject]@{ Hechas = $hechas; Errores = $errores }
}

# --- huella de lo que falta --------------------------------------------------
#  Sirve para no volver a preguntar por exactamente lo mismo que ya se rechazo.
#  Si aparece algo NUEVO roto, la huella cambia y se vuelve a ofrecer.
function Get-HuellaFaltantes {
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$Piezas)
    return (($Piezas | Where-Object { -not $_.Ok } | ForEach-Object { $_.Clave } | Sort-Object) -join '|')
}
