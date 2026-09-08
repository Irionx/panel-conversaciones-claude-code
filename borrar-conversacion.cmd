@echo off
REM Atajo para borrar.ps1 desde cmd.exe y PowerShell.
REM En bash el que responde es el shim sin extension (borrar-conversacion),
REM porque Git Bash no resuelve .cmd desde el PATH.
REM
REM   borrar-conversacion test              muestra que se va y pide confirmacion
REM   borrar-conversacion test -DryRun      solo muestra, no toca nada
REM   borrar-conversacion test -y           sin preguntar
REM   borrar-conversacion -Listar           ids disponibles
REM
REM No hace falta correrlo desde el proyecto: el id ya trae la sesion y el cwd.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0borrar.ps1" %*
