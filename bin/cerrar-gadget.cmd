@echo off
REM Atajo para app\cerrar-gadget.ps1.
REM
REM   cerrar-gadget            cierra el gadget, aunque este trabado
REM   cerrar-gadget -Listar    muestra los que hay corriendo, sin cerrar
REM
REM Es cierre forzado: NO guarda la posicion de la ventana.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\app\cerrar-gadget.ps1" %*
