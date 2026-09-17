# Panel de conversaciones de Claude Code

Gadget de escritorio para Windows que lista tus conversaciones de Claude Code y
las reabre donde las dejaste, con el contexto que le queda a cada una, cuál está
pensando en este momento y la cuota de la cuenta.

- **[LEEME.md](LEEME.md)** — cómo se usa, qué hace cada archivo, cada botón.
- **[ARQUITECTURA.md](ARQUITECTURA.md)** — por qué está armado así, y qué se descartó.

## Instalarlo desde el repo

**No hace falta el instalador `.exe` ni el zip: clonar alcanza.** Lo que el
paquete trae ya armado —el lanzador `Conversaciones.exe` y el acceso directo— lo
fabrica el propio `setup.ps1`, y la base de datos se crea sola la primera vez.

```powershell
git clone https://github.com/Irionx/panel-conversaciones-claude-code.git Conversaciones
cd Conversaciones
.\setup.ps1 -Instalar
```

Después abrís **`Gadget de conversaciones.lnk`**, que el setup deja en la carpeta.

Si PowerShell se niega a correr el script por la política de ejecución:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup.ps1 -Instalar
```

Necesita Windows 10 u 11 con PowerShell 5.1 (viene con el sistema) y Claude Code.
**No pide admin:** todo se escribe en tu usuario (`HKCU` y el PATH de usuario).
Para ver qué va a tocar antes de decidirte, corré `.\setup.ps1` sin argumentos:
sólo mira y te lista las ocho piezas con su estado.

## Actualizarlo

```powershell
git pull
.\setup.ps1 -Instalar
```

El setup mide el estado real en cada corrida, sin marcador de "ya instalado":
recompila el lanzador si cambió su código, y si moviste la carpeta re-apunta todo
solo.

## Sacarlo

```powershell
.\setup.ps1 -Desinstalar
```

Deshace lo que instaló y **nunca toca `datos\`**, o sea tus conversaciones. Si
también las querés tirar, borrás esa carpeta a mano.

## Dos detalles de clonar en vez de instalar el paquete

- El build deja un archivo `VERSION` que la ⓘ del panel muestra. El clon no lo
  tiene, así que ahí no vas a ver el número de versión. Todo lo demás es igual.
- Si ya tenés otra copia instalada, **tres piezas son de slot único** en el
  sistema (el protocolo `claudeconv://`, el PATH y el skill `/save`): se las queda
  la última que instaló. `setup.ps1 -Instalar` te avisa a qué carpeta se las está
  sacando **antes** de pedirte el SI.

## Armar el paquete (opcional)

Para instalarlo en una máquina que no tiene git:

```powershell
.\dev\build.ps1          # deja un zip en dev\dist
.\dev\build.ps1 -Exe     # y además el instalador .exe (necesita Inno Setup 6)
```

Los archivos que entran salen de `git ls-files`, así que tus datos nunca pueden
colarse en un paquete. El build corre los tests **adentro** del paquete ya armado
y aborta si falla alguno.

## Si el repo es privado y tenés dos cuentas de `gh`

El `git clone` se autentica con la cuenta **activa** de `gh`, que puede no ser la
que tiene acceso —y otra terminal puede cambiártela sin avisar—. Para no depender
de eso, fijá el token en el comando:

```powershell
$env:GH_TOKEN = gh auth token --user Irionx
git clone https://github.com/Irionx/panel-conversaciones-claude-code.git
```
