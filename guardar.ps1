# =============================================================================
#  guardar.ps1 - Guarda una conversacion en el panel con un solo comando.
#
#  Todo lo mecanico se deduce solo: UUID de la sesion, carpeta, rama de git,
#  proyecto, fecha y slug. Vos solo pones el titulo (y si queres, notas y tags).
#
#  USO
#    .\guardar.ps1 "Nivelar dev con test"
#    .\guardar.ps1 "Refactor del toolbar" -Tags ui,scss -Notas "Quedo pendiente el responsive"
#    .\guardar.ps1 "Otra cosa" -Cwd "C:\otro\proyecto"
#    .\guardar.ps1 -Listar                  # ve las sesiones de esta carpeta
#
#  UPSERT: si ya guardaste esta misma sesion, la actualiza en vez de duplicarla.
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Titulo,
    [string]$Notas = '',
    [string[]]$Tags = @(),
    [string]$Cwd,
    [string]$Sesion,
    [string]$Proyecto,
    [int]$ContextoMax = 0,
    [switch]$Listar
)

$ErrorActionPreference = 'Stop'
$carpeta = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $carpeta 'lib-conversaciones.ps1')

if (-not $Cwd) { $Cwd = (Get-Location).Path }
$Cwd = ConvertTo-RutaWindows $Cwd

if (-not (Test-Path -LiteralPath $Cwd -PathType Container)) { throw "La carpeta no existe: $Cwd" }

$dirProyecto = Join-Path $env:USERPROFILE ('.claude\projects\' + (ConvertTo-CarpetaProyecto $Cwd))
if (-not (Test-Path $dirProyecto)) {
    throw "No hay sesiones de Claude Code para esa carpeta.`nBuscaba en: $dirProyecto"
}

$sesiones = @(Get-ChildItem $dirProyecto -Filter *.jsonl | Sort-Object LastWriteTime -Descending)
if ($sesiones.Count -eq 0) { throw "No hay ningun .jsonl en $dirProyecto" }

# --- modo listar --------------------------------------------------------------
if ($Listar) {
    Write-Host "Sesiones en $Cwd`n"
    $i = 0
    foreach ($s in $sesiones | Select-Object -First 15) {
        $ctx = Get-ContextoSesion -Cwd $Cwd -Sesion $s.BaseName
        $pct = if ($ctx.Hay) { '{0,5}%' -f $ctx.Porcentaje } else { '    -' }
        Write-Host ('  {0,2}. {1}  {2:dd/MM HH:mm}  {3}  {4,7}' -f `
                ++$i, $s.BaseName, $s.LastWriteTime, $pct, (Format-Tokens $ctx.Tokens))
    }
    Write-Host "`nLa primera es la mas reciente (normalmente, la sesion en curso)."
    return
}

# --- deducir lo que falta -----------------------------------------------------
#  La sesion en curso la publica Claude Code en el entorno. Sin esto se cae al
#  "mas reciente de la carpeta", que con dos sesiones abiertas en el mismo
#  proyecto guarda la otra.
#  Se exige que el transcript este en ESTA carpeta: con -Cwd apuntando a otro
#  proyecto, la sesion en curso no vive ahi y hay que usar el mas reciente.
if (-not $Sesion -and $env:CLAUDE_CODE_SESSION_ID) {
    if (Test-Path (Join-Path $dirProyecto ('{0}.jsonl' -f $env:CLAUDE_CODE_SESSION_ID))) {
        $Sesion = $env:CLAUDE_CODE_SESSION_ID
    }
}
if (-not $Sesion) { $Sesion = $sesiones[0].BaseName }
if ($Sesion -notmatch '^[0-9a-fA-F-]{8,64}$') { throw "El id de sesion no parece un UUID: $Sesion" }
if (-not (Test-Path (Join-Path $dirProyecto "$Sesion.jsonl"))) {
    throw "No existe la sesion $Sesion en $dirProyecto"
}

if (-not $Proyecto) { $Proyecto = Split-Path -Leaf $Cwd }

$rama = ''
try {
    Push-Location $Cwd
    $rama = (git rev-parse --abbrev-ref HEAD 2>$null)
    if ($LASTEXITCODE -ne 0) { $rama = '' }
} catch { $rama = '' } finally { Pop-Location }

# Sin titulo explicito manda el nombre real de la sesion (el de /rename).
if (-not $Titulo) { $Titulo = Get-NombreSesion -Cwd $Cwd -Sesion $Sesion }
if (-not $Titulo) { $Titulo = '{0} - {1}' -f $Proyecto, (Get-Date -Format 'dd/MM/yyyy HH:mm') }

function ConvertTo-Slug {
    param([string]$T)
    # Descomponer y tirar los diacriticos: "Nivelación" -> "nivelacion"
    $s = $T.ToLowerInvariant().Normalize([Text.NormalizationForm]::FormD)
    $s = -join ($s.ToCharArray() | Where-Object {
            [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark'
        })
    $s = [regex]::Replace($s, '[^a-z0-9]+', '-').Trim('-')
    if ($s.Length -gt 48) { $s = $s.Substring(0, 48).Trim('-') }
    if (-not $s) { $s = 'conversacion' }
    return $s
}

# --- upsert por SESION: una sesion, una entrada -------------------------------
#  La identidad es el UUID. Dos entradas del mismo UUID reabrian exactamente la
#  misma charla, o sea que eran duplicados disfrazados.
#  El titulo NO es la identidad justamente porque puede cambiar: si renombras la
#  sesion con /rename, el panel muestra el nombre nuevo sin duplicar nada.
$todas = @(Get-Conversacion)
$existente = $todas | Where-Object { $_.sesion -eq $Sesion } | Select-Object -First 1
$accion = if ($existente) { 'actualizada' } else { 'agregada' }

if ($existente) {
    $id = $existente.id
    $tituloAnterior = if ($existente.titulo -ne $Titulo) { [string]$existente.titulo } else { $null }
} else {
    $id = ConvertTo-Slug $Titulo
    $base = $id; $n = 1
    while ($todas | Where-Object { $_.id -eq $id }) { $n++; $id = "$base-$n" }
    $tituloAnterior = $null
}

if ($existente) {
    # CAMBIO DE COMPORTAMIENTO, A PROPOSITO: antes se reemplazaba la entrada
    # ENTERA, asi que volver a guardar una conversacion ya guardada SIN pasar
    # -Notas te borraba las notas que tenia (y lo mismo con -Tags). Perder datos
    # por reguardar no es un comportamiento que valga la pena preservar.
    # Ahora se actualiza campo por campo y lo que no se pasa se respeta.
    $campos = @{
        Id       = $id
        Titulo   = $Titulo
        Proyecto = $Proyecto
        Cwd      = $Cwd
        Sesion   = $Sesion
        Fecha    = Get-Date -Format 'yyyy-MM-dd'
    }
    if ($rama) { $campos.Rama = $rama }
    if ($ContextoMax -gt 0) { $campos.ContextoMax = $ContextoMax }
    # Un solo Set y no uno por campo: cada uno toma el candado y reescribe.
    Set-Conversacion @campos
    if ($Tags.Count) { Set-Tag -Id $id -Tags @($Tags) }
    if ($Notas) { Set-Nota -Id $id -Texto $Notas }
} else {
    # Los opcionales vacios no se escriben: de eso se encarga Add-Conversacion.
    Add-Conversacion -Id $id -Titulo $Titulo -Cwd $Cwd -Sesion $Sesion `
        -Proyecto $Proyecto -Rama $rama -Notas $Notas -Tags $Tags -ContextoMax $ContextoMax
}

# --- verificar y reportar -----------------------------------------------------
$releida = Get-Conversacion -Id $id
if (-not $releida) { throw "Se guardo pero no pude releerla. Revisa conversaciones.js (hay respaldo en .bak)" }

$ctx = Get-ContextoSesion -Cwd $Cwd -Sesion $Sesion -Limite $ContextoMax

Write-Host ""
Write-Host "  Conversacion $accion" -ForegroundColor Green
Write-Host "    id       : $($releida.id)"
Write-Host "    titulo   : $($releida.titulo)"
Write-Host "    proyecto : $($releida.proyecto)$(if ($rama) { "  ($rama)" })"
Write-Host "    carpeta  : $($releida.cwd)"
Write-Host "    sesion   : $($releida.sesion)"
if ($ctx.Hay) {
    Write-Host ("    contexto : {0} de {1}  ({2}%)" -f (Format-Tokens $ctx.Tokens), (Format-Tokens $ctx.Limite), $ctx.Porcentaje)
}
Write-Host "    total    : $(@(Get-Conversacion).Count) en el panel"
if ($tituloAnterior) {
    Write-Host ""
    Write-Host "    Antes se llamaba: $tituloAnterior" -ForegroundColor DarkYellow
}
$nombreReal = Get-NombreSesion -Cwd $Cwd -Sesion $Sesion
if (-not $nombreReal) {
    Write-Host ""
    Write-Host "    Tip: si la renombras con /rename en Claude Code, el panel" -ForegroundColor DarkGray
    Write-Host "         va a mostrar ese nombre y se actualiza solo." -ForegroundColor DarkGray
}
Write-Host ""
