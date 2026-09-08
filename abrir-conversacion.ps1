# =============================================================================
#  abrir-conversacion.ps1
#  Handler del protocolo claudeconv://  -->  claudeconv://abrir?id=<slug>
#                                            claudeconv://abrir?id=<slug>&remoto=1
#
#  Con remoto=1 la conversacion se abre con --remote-control: queda disponible
#  en claude.ai/code y en la app del celular, con su historial.
#
#  SEGURIDAD: de la URL solo se acepta un id (slug corto, lista blanca de
#  caracteres) y un flag remoto que se compara contra el literal "1". La carpeta
#  y el UUID salen de conversaciones.js, que es un archivo local de confianza.
#  El comando ejecutado esta fijo en la libreria.
#  Una pagina web maliciosa no puede inyectar ni rutas ni comandos.
#
#  Para probar sin abrir nada:
#    powershell -File abrir-conversacion.ps1 -Url "claudeconv://abrir?id=<slug>" -DryRun
# =============================================================================

param([string]$Url, [switch]$DryRun)

$ErrorActionPreference = 'Stop'

# El popup se autocierra a los 30s: un handler de protocolo NUNCA puede quedar
# esperando un click, porque corre con la ventana oculta y colgaria invisible.
function Avisar([string]$texto) {
    try { [Console]::Error.WriteLine($texto) } catch { }
    if ($DryRun) { return }
    try { (New-Object -ComObject WScript.Shell).Popup($texto, 30, 'Conversaciones - Claude Code', 48) | Out-Null }
    catch { }
}

try {
    $carpeta = Split-Path -Parent $MyInvocation.MyCommand.Path
    . (Join-Path $carpeta 'lib-conversaciones.ps1')

    # --- 1. extraer el id de la URL -----------------------------------------
    if ($Url -notmatch 'id=([^&/]+)') { throw "URL sin parametro id: $Url" }
    $id = [uri]::UnescapeDataString($Matches[1])

    if ($id -notmatch '^[A-Za-z0-9._-]{1,64}$') {
        throw "El id '$id' tiene caracteres no permitidos."
    }

    # Se compara contra el literal: cualquier otro valor de remoto = apagado.
    # Ojo, va DESPUES de leer $id: cada -match pisa $Matches.
    $remoto = [bool]($Url -match '[?&]remoto=1(&|$)')

    # --- 2. buscar la entrada ------------------------------------------------
    $c = Get-Conversacion -Id $id
    if (-not $c) { throw "No hay ninguna conversacion con id '$id' en el panel" }

    # --- 3. lanzar -----------------------------------------------------------
    $r = Start-Conversacion -Cwd $c.cwd -Sesion $c.sesion -Remoto:$remoto -Nombre $c.titulo -DryRun:$DryRun

    if ($DryRun) {
        Write-Host "OK  id     : $id"
        Write-Host "    titulo : $($c.titulo)"
        Write-Host "    remoto : $($r.Remoto)"
        Write-Host "    cwd    : $($r.Cwd)"
        Write-Host "    exe    : $($r.Exe)"
        Write-Host "    args   : $($r.Args)"
        $ctx = Get-ContextoSesion -Cwd $c.cwd -Sesion $c.sesion
        if ($ctx.Hay) {
            Write-Host ("    ctx    : {0} / {1}  ({2}%)" -f (Format-Tokens $ctx.Tokens), (Format-Tokens $ctx.Limite), $ctx.Porcentaje)
        } else {
            Write-Host "    ctx    : sin transcript"
        }
    }
}
catch {
    Avisar("No se pudo abrir la conversacion.`n`n" + $_.Exception.Message)
    exit 1
}
