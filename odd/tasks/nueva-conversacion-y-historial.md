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

- [x] T1 · S3 · inline · `New-IdConversacion` + `ConvertTo-Slug` a
  `lib-conversaciones.ps1`; `guardar.ps1` la llama. Commit `89a1267`.
  RED: 5 fallas por función inexistente → GREEN 11/11.
- [x] T2 · S3+S1 · inline · `Get-LanzamientoTerminal` + `Start-ConversacionNueva`.
  Commit `89a1267`. Los 4 tests que fijan el comportamiento viejo ya pasaban
  ANTES del refactor, que es lo que los vuelve un guardarrail válido.
- [x] T4 · S2 · inline · abrir y agregar en la fila del historial. Commit
  `9daf1ca`. RED 3/4 (el 4to pasaba por la razón equivocada: la excepción de
  "comando no reconocido"; se apretó para exigir el motivo).
- [x] T3 · S1 · inline · `gadget/Nueva.ps1` (334 l.), `btnNueva` en el XAML,
  `Connect-Nueva` desde `gadget.ps1` (570 l., bajo el tope de 600).
  RED 9/9 → GREEN. Verificado además por render a PNG, sin abrir ventana.
- [x] T5 · S1+S2 · inline · `ARQUITECTURA.md` (dos secciones nuevas + el árbol
  remedido) y las tres filas nuevas de `Ayuda.ps1`.

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

**L5** (2026-11-13, hallazgo medido, DECISIÓN PENDIENTE): el `+` es el noveno
botón de la cabecera. Medido a 348 px (el ancho por defecto): al título le quedan
70 px y necesita 85,3, así que "Hilos de Claudio" se recortaba **en seco**, a
mitad de letra, porque ese `TextBlock` no tenía `TextTrimming`. Se le puso, así
que ahora degrada con puntos suspensivos. Entra entero desde **366 px**. Queda
para el capitán: subir el ancho por defecto del XAML, mover o sacar algún botón,
o dejarlo recortado (el nombre es decoración y se esconde al bloquear).

**L6** (2026-11-13, hallazgo previo sin resolver): el panel y el archivo comparten
UNA columna `orden`, pero `Set-OrdenConversacion` renumera sólo las tarjetas
activas, así que después de cualquier arrastre desarchivar cae en una posición
arbitraria. Fuera del alcance de esta feature; sigue esperando decisión.
