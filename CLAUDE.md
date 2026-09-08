# Panel de CONVERSACIONES

Gadget WPF de escritorio que lista las conversaciones de Claude Code guardadas y
permite reabrirlas. `gadget.ps1` es la UI, `lib-conversaciones.ps1` la libreria,
`conversaciones.js` el estado. Ver `LEEME.md` para el detalle.

## Rol "recepcion" — abrir conversaciones en remoto desde el celular

Cuando esta sesion corre con Remote Control (`claude remote-control`), sirve de
recepcion: desde el telefono se le pide abrir otra conversacion en remoto, y la
ejecuta aca, en la PC.

**Usa siempre el script. No armes el comando a mano ni leas `conversaciones.js`
por tu cuenta:**

```
powershell -NoProfile -File "C:/Users/skozak/Desktop/CONVERSACIONES/abrir-remoto.ps1" <parte del titulo>
```

Ruta completa y con barras normales, a proposito: invocado desde Bash, un
`.\abrir-remoto.ps1` pierde la barra invertida y falla con "el argumento
'.abrir-remoto.ps1' no existe".

- Sin argumentos lista todo con su estado (`[cerrada]`, `[abierta]`, `[REMOTO ]`).
- Con texto busca por titulo, id o proyecto. Si hay una sola coincidencia la abre.
- Si hay varias, imprime las opciones y **no abre nada**: pasale esa lista al
  usuario tal cual y pedile que elija. No adivines cual queria.

Repeti la salida del script como viene. Es corta a proposito, para leer en una
pantalla chica.

## Lo que hay que saber antes de responder

- **Una instancia de Claude Code = una conversacion remota.** Abrir la misma
  conversacion en una segunda terminal no prende el remoto: si la primera ya lo
  tiene, la segunda arranca con el remoto APAGADO. Por eso el script se niega a
  abrir algo que ya figura `[abierta]` o `[REMOTO ]`.
- **Prender el remoto en una sesion ya abierta** no se puede desde afuera: hay
  que escribir `/remote-control` en esa terminal.
- La conversacion abierta aparece en claude.ai/code y en la app **con el titulo
  del panel**, no con el id. Deciselo al usuario para que sepa que buscar.
- El estado sale de mirar procesos vivos, asi que es un proxy: dice que hay una
  terminal lanzada con `--remote-control`, no que Anthropic la tenga conectada
  en este segundo.

## Al tocar el panel

- Los `.ps1` van en **UTF-8 con BOM**. PowerShell 5.1 lee un `.ps1` sin BOM como
  ANSI y rompe los acentos.
- `conversaciones.js` se edita con Edit o Write, **nunca con heredoc**: en este
  entorno los heredoc de bash colapsan `\\` en `\` y rompen las rutas Windows.
- Los glifos de Segoe MDL2 hay que verificarlos antes de usarlos o sale un
  cuadradito. El Unicode comun (`0x2715`, `0x25CF`) no tiene ese riesgo.
