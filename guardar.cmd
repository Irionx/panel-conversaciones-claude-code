@echo off
REM Atajo para guardar.ps1 desde cualquier terminal (cmd, bash, Claude Code).
REM
REM   guardar "Titulo de la charla"
REM   guardar "Titulo" -Tags git,ci -Notas "Que quedo pendiente"
REM   guardar -Listar
REM
REM Se ejecuta desde la carpeta del proyecto: de ahi deduce la sesion.
REM Para tenerlo a mano en cualquier lado, agrega esta carpeta al PATH:
REM   setx PATH "%PATH%;%USERPROFILE%\Desktop\CONVERSACIONES"
REM (abri una terminal nueva despues de correrlo)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0guardar.ps1" %*
