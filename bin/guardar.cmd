@echo off
REM Atajo para app\guardar.ps1 desde cualquier terminal (cmd, bash, Claude Code).
REM
REM   guardar "Titulo de la charla"
REM   guardar "Titulo" -Tags git,ci -Notas "Que quedo pendiente"
REM   guardar -Listar
REM
REM Se ejecuta desde la carpeta del proyecto: de ahi deduce la sesion.
REM
REM Esta carpeta (bin\) ya la pone en el PATH el instalador: corre setup.ps1
REM desde la raiz del proyecto. NO uses setx para esto: %PATH% trae mezclado el
REM PATH de maquina y te lo copiaria dentro del de usuario, y ademas setx trunca
REM a 1024 caracteres.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\app\guardar.ps1" %*
