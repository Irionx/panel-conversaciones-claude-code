# Hilos de Claudio

Panel de escritorio que lista las conversaciones de Claude Code y permite
retomarlas donde quedaron. Muestra en vivo el contexto consumido por cada una,
cuál está trabajando en este momento y la cuota disponible de la cuenta.

- **Windows** — gadget WPF sobre PowerShell 5.1, sin dependencias externas.
- **Linux** — aplicación nativa en C# con Avalonia. En desarrollo.

Documentación: [LEEME.md](LEEME.md) para el uso diario y
[ARQUITECTURA.md](ARQUITECTURA.md) para las decisiones de diseño.

## Requisitos

- Windows 10 u 11. La instalación corre sobre **Windows PowerShell 5.1**, incluido en el sistema; PowerShell 7 no sirve.
- Claude Code instalado.
- No requiere privilegios de administrador: todo se registra en el usuario.

## Instalación

```powershell
git clone https://github.com/Irionx/panel-conversaciones-claude-code.git Conversaciones
cd Conversaciones
.\setup.ps1 -Instalar
```

El instalador registra ocho piezas —el protocolo `claudeconv://`, los comandos
de terminal, el skill `/save`, el volcado de la cuota, el lanzador y el acceso
directo, entre otras— y deja `Hilos de Claudio.lnk` en la carpeta.

`.\setup.ps1` sin argumentos muestra el estado de cada pieza sin modificar nada.
Si la política de ejecución bloquea el script:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup.ps1 -Instalar
```

### Actualización

```powershell
git pull
.\setup.ps1 -Instalar
```

El estado se mide en cada ejecución, sin marcadores persistentes: la carpeta se
puede mover y la instalación vuelve a apuntar sola.

### Desinstalación

```powershell
.\setup.ps1 -Desinstalar
```

Deshace lo instalado y no toca `datos\`, donde viven las conversaciones.

## Linux

La versión de Linux es una aplicación separada, en [`linux/`](linux), que
comparte el formato de datos con la de Windows pero no el código.

Estado actual: guarda la conversación en curso con `conversaciones guardar`,
lista lo guardado con su contexto, lo reabre en la terminal del escritorio y
atiende los enlaces `claudeconv://`. El skill `/save` funciona igual que en
Windows. Pendientes las funciones de organización del panel (reordenar,
archivar, cuota).

```bash
# el SDK de .NET 10, en el usuario y sin privilegios
curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel LTS

linux/setup.sh --instalar
```

El instalador publica un binario autocontenido —no requiere .NET en la máquina
de destino— y lo registra en `~/.local`: el ejecutable, una entrada de menú y la
asociación del protocolo por `xdg-mime`. `linux/setup.sh` sin argumentos muestra
el estado, y `--desinstalar` lo deshace sin tocar los datos.

Las dependencias de sistema y el detalle del estado están en
[linux/LEEME.txt](linux/LEEME.txt).

## Paquete distribuible

Para instalar en equipos sin git:

```powershell
.\dev\build.ps1          # genera un zip en dev\dist
.\dev\build.ps1 -Exe     # además del zip, un instalador .exe (requiere Inno Setup 6)
```

Los archivos incluidos se toman de `git ls-files`, y el build ejecuta la suite
de tests dentro del paquete ya armado antes de publicarlo. El paquete incorpora
un archivo `VERSION` que la clonación directa no tiene; es el único dato que la
ventana de ayuda no puede mostrar cuando se trabaja desde el repositorio.

## Datos

Las conversaciones se guardan en una base SQLite: `datos\conversaciones.db` en
Windows y `~/.local/share/conversaciones/` en Linux. El esquema es el mismo en
ambas plataformas. La desinstalación nunca borra esa base.
