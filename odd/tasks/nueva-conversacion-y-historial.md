# Nueva conversación desde el panel, y abrir/agregar desde el historial

Objetivo: que el panel pueda ARRANCAR una conversación (eligiendo carpeta) y que
el cajón de "todas las conversaciones" pueda abrir una fila o subirla al panel.
Rama: `feat/nueva-conversacion-y-historial` · Entrega: ask-on-risk
Runner: `powershell -NoProfile -File <suite>.Tests.ps1` (4 suites, 161 verdes de base)

## Specs

### S1 — Conversación nueva, separada, eligiendo la carpeta

Pedido textual: *"la posibilidad de iniciar una conversacion nueva desde aqui, no
se puede jaja"* y *"conversacion nueva seria separado, y que permita elegir la
carpeta"*.

- Un botón propio en la cabecera, no colgado de una tarjeta ("separado").
- Abre un diálogo con la MISMA pinta que `Etiquetas.ps1` / `Confirmacion.ps1`
  (marco propio, `WindowStyle="None"`, el `TextBox` con template reemplazado).
  No se usa `FolderBrowserDialog`: sobre .NET Framework es el árbol viejo y en un
  panel oscuro parece que algo se rompió.
- El diálogo ofrece **las carpetas que el panel ya conoce**: los `cwd` de las
  tarjetas y los `cwd` del historial en disco, sin repetidos, la más reciente
  arriba.
- Además un campo para pegar una ruta que el panel nunca vio.
- La carpeta se valida contra disco ANTES de lanzar.
- Lanza `claude` SIN `--resume`: una conversación nueva no tiene uuid hasta que
  Claude Code escribe su primer `.jsonl`, así que no se puede guardar en el panel
  en el momento de lanzarla. Nace huérfana a propósito; se sube después con S2.

Aceptación: con el diálogo armado en memoria, la lista de carpetas trae los `cwd`
conocidos sin repetir; una ruta inexistente no lanza y muestra el error en el
diálogo; la línea de comando generada no lleva `--resume`.

### S2 — Desde el historial: abrir, o agregar a la lista

Pedido textual: *"desde \"todas las conversaciones\" la posibilidad de abrirla o
agregarla a la lista (lo que sea mas coherente)"*.

Decisión de coherencia: **las dos**, pero no como botones gemelos. Abrir es
"¿qué era esto?"; agregar es "esto me sirve, que viva en el panel". El punto que
ya pinta `Guardada` da la regla: si la fila ya está en el panel, el botón de
agregar no va — queda sólo abrir.

- Abrir usa el mismo camino que el click en una tarjeta del panel
  (`Start-Conversacion -Cwd -Sesion`), con los datos que la fila del historial ya
  trae.
- Agregar inserta la conversación en el panel con el id que genera el MISMO
  algoritmo que `guardar.ps1` (slug + sufijo numérico si choca).
- Después de agregar, la fila pasa a verse como guardada sin reabrir el cajón.

Aceptación: una fila no guardada tiene los dos botones; una guardada sólo el de
abrir; agregar deja la conversación en la base con el id esperado y el punto pasa
a verde.

### S3 — Una sola verdad para lo compartido (invariante, no pedido del usuario)

Supuesto marcado como tal: para no dejar dos implementaciones de lo mismo,
- el armado de la línea de Windows Terminal (con su trampa de comillas y el
  fallback a `cmd.exe`) se comparte entre `--resume` y la conversación nueva;
- el slug + id único sale de `guardar.ps1` a `lib-conversaciones.ps1`, así el
  panel y `/save` generan exactamente el mismo id.

Aceptación: `Start-Conversacion -DryRun` devuelve byte por byte lo mismo que
antes del cambio, para los cuatro llamadores que ya existen.

## Tasks

- [ ] T1 · S3 · inline · extraer `New-IdConversacion` (slug + único) a
  `lib-conversaciones.ps1` y usarla desde `guardar.ps1`. Test: mismo id que la
  versión anterior para una batería de títulos.
- [ ] T2 · S3+S1 · inline · extraer el armado de la línea de terminal y agregar
  `Start-ConversacionNueva -Cwd`. Test: `Start-Conversacion -DryRun` sin cambios;
  la nueva no lleva `--resume`.
- [ ] T3 · S1 · inline · `gadget/Nueva.ps1`: el diálogo, las carpetas conocidas,
  el campo de ruta y la validación. Botón en el XAML + una línea en `gadget.ps1`
  (queda 31 líneas de presupuesto bajo el tope de 600).
- [ ] T4 · S2 · inline · botones de abrir y agregar en la fila del historial
  (`Cajon.ps1`), con la regla del punto verde.
- [ ] T5 · S1+S2 · inline · `ARQUITECTURA.md`.

## Log

**L1** (2026-11-13, pedido original, textual): "necesitamos pensar en agregar 2
funcionalidades nuevas 1: la posibilidad de iniciar una conversacion nueva desde
aqui, no se puede jaja y 2: desde "todas las conversaciones" la posibilidad de
abrirla o agregarla a la lista (lo que sea mas coherente)"

**L2** (2026-11-13, decisión del usuario, textual): "mmm conversacion nueva seria
separado, y que permita elegir la carpeta, no se que recomiendas para esto jaja"

**L3** (2026-11-13): "ok adelante" — autorizada la implementación.

**L4** (2026-11-13, estado de partida): el repo estaba en `main` con el arreglo de
fluidez del cajón sin commitear, en los mismos archivos que toca esta feature. Se
abrió la rama y ese arreglo quedó en su propio commit (`a414999`) para no
mezclarlo. Línea base: 161 tests verdes, `gadget.ps1` en 568 líneas.

**L5** (2026-11-13, hallazgo previo sin resolver): el panel y el archivo comparten
UNA columna `orden`, pero `Set-OrdenConversacion` renumera sólo las tarjetas
activas, así que después de cualquier arrastre desarchivar cae en una posición
arbitraria. Fuera del alcance de esta feature; sigue esperando decisión.
