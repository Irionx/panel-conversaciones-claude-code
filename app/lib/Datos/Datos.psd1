@{
    RootModule        = 'Datos.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'b1f4a7c2-9d3e-4a56-8b21-6c0f5e2d1a83'
    Author            = 'Sebastian A. Kozak'
    Description       = 'Capa de acceso a datos de Hilos de Claudio. La unica que sabe donde y como se guardan.'
    PowerShellVersion = '5.1'

    # Esta lista es la frontera, no un listado informativo. Todo lo que NO esta
    # aca (Read-Almacen, Write-Almacen, Invoke-ConBloqueo, Get-RutaAlmacen) queda
    # inalcanzable desde afuera del modulo. Es lo que hace que el paso 2
    # (cambiar el .js por SQLite) no pueda romper a nadie: si la interfaz nunca
    # pudo llamar a Read-Almacen, no hay nada que arreglar cuando desaparezca.
    FunctionsToExport = @(
        'Initialize-Datos'
        'Backup-Datos'
        'Get-Conversacion'
        'Find-Conversacion'
        'Get-Nota'
        'Get-Tag'
        'Add-Conversacion'
        'Set-Conversacion'
        'Remove-Conversacion'
        'Set-Nota'
        'Set-Tag'
        'Set-OrdenConversacion'
        'Set-ArchivadoConversacion'
        'Get-Etiqueta'
        'Add-Etiqueta'
        'Set-Etiqueta'
        'Remove-Etiqueta'
        'Set-EtiquetaConversacion'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
