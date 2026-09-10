@echo off
REM ============================================================================
REM  desinstalar.cmd - saca el panel de un doble click.
REM ----------------------------------------------------------------------------
REM  Toda la logica vive en setup.ps1 -Desinstalar; esto solo lo invoca, igual
REM  que los wrappers de bin\.
REM
REM  NO se le pasa -y a proposito: pide escribir SI. Un archivo llamado
REM  "desinstalar" al lado del panel se puede clickear por accidente, y sin
REM  confirmacion eso te saca el /save y el protocolo sin preguntar nada.
REM
REM  Y el pause del final tampoco es adorno: con doble click la ventana se
REM  cierra sola al terminar, y no se leeria ni lo que se deshizo ni los avisos.
REM ============================================================================
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" -Desinstalar
echo.
pause
