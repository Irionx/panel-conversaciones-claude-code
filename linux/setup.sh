#!/usr/bin/env bash
# =============================================================================
#  setup.sh - instala el panel de conversaciones en tu usuario.
#
#    ./setup.sh                muestra el estado de las piezas y no toca nada
#    ./setup.sh --instalar     instala lo que falte, incluido el SDK de .NET
#    ./setup.sh --desinstalar  deshace lo que instalo (NUNCA toca tus datos)
#
#  NO pide root, y lo que si lo necesita no lo hace a escondidas: te da el
#  comando exacto para tu distro. Mismo criterio que el setup.ps1 de Windows: se
#  mide el estado REAL en cada corrida, sin marcador de "ya instalado".
# =============================================================================
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
proyecto="$aqui/Conversaciones"

BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
BIN="$BIN_DIR/conversaciones"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
DESKTOP="$APPS/conversaciones.desktop"
DATOS="${XDG_DATA_HOME:-$HOME/.local/share}/conversaciones"
DOTNET_DIR="$HOME/.dotnet"

verde()   { printf '  \033[32mok   \033[0m  %-24s %s\n' "$1" "$2"; }
falta()   { printf '  \033[33mfalta\033[0m  %-24s %s\n' "$1" "$2"; }
paso()    { printf '  \033[32minstalado\033[0m : %s\n' "$1"; }
quitado() { printf '  \033[32mquitado  \033[0m : %s\n' "$1"; }
aviso()   { printf '  \033[33maviso    \033[0m : %s\n' "$1"; }

# --- 1. el SDK de .NET -------------------------------------------------------
#  Puede estar en el PATH o en ~/.dotnet, que es donde lo pone el instalador
#  oficial. Si no esta, se instala SOLO y en el usuario: no hace falta root ni
#  agregar repositorios, y desinstalarlo es borrar esa carpeta.
dotnet_bin() {
    if command -v dotnet >/dev/null 2>&1; then echo "dotnet"
    elif [ -x "$DOTNET_DIR/dotnet" ]; then echo "$DOTNET_DIR/dotnet"
    else echo ""; fi
}

instalar_sdk() {
    echo "  bajando el SDK de .NET (unos cientos de MB, una sola vez)..."
    local script; script="$(mktemp)"
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$script"
    bash "$script" --channel LTS --install-dir "$DOTNET_DIR" >/dev/null
    rm -f "$script"
    [ -x "$DOTNET_DIR/dotnet" ] || { echo "  no pude instalar el SDK"; exit 1; }
    paso "SDK de .NET en $DOTNET_DIR"
}

# --- 2. las bibliotecas del sistema ------------------------------------------
#  Avalonia habla X11. En un escritorio de verdad ya estan todas; en una
#  instalacion minima suelen faltar libICE y libSM, y sin ellas la ventana ni
#  siquiera abre. Esto SI necesita root, asi que se dice y no se hace solo.
LIBS_FALTANTES=""
medir_libs() {
    LIBS_FALTANTES=""
    local l
    for l in libICE.so.6 libSM.so.6 libX11.so.6 libXext.so.6 libXrandr.so.2 \
             libXi.so.6 libXcursor.so.1 libfontconfig.so.1 libGL.so.1; do
        ldconfig -p 2>/dev/null | grep -qF "$l" || LIBS_FALTANTES="$LIBS_FALTANTES $l"
    done
}

comando_libs() {
    local id=""; [ -r /etc/os-release ] && id="$(. /etc/os-release; echo "${ID_LIKE:-$ID}")"
    case "$id" in
        *arch*)   echo "sudo pacman -S --needed libice libsm libx11 libxext libxrandr libxi libxcursor libxinerama fontconfig libglvnd" ;;
        *debian*|*ubuntu*) echo "sudo apt install -y libice6 libsm6 libx11-6 libxext6 libxrandr2 libxi6 libxcursor1 libxinerama1 libfontconfig1 libgl1 libegl1" ;;
        *fedora*|*rhel*)   echo "sudo dnf install -y libICE libSM libX11 libXext libXrandr libXi libXcursor libXinerama fontconfig mesa-libGL" ;;
        *)        echo "instala las bibliotecas X11 de tu distro: libICE libSM libX11 libXext libXrandr libXi libXcursor fontconfig libGL" ;;
    esac
}

# --- 3. el binario -----------------------------------------------------------
#  Se publica self-contained: no queda dependiendo del SDK una vez instalado.
publicar() {
    local dn; dn="$(dotnet_bin)"
    [ -n "$dn" ] && [ -x "$(command -v "$dn" 2>/dev/null || echo "$dn")" ] || { instalar_sdk; dn="$DOTNET_DIR/dotnet"; }
    echo "  compilando (la primera vez tarda)..."
    # IncludeNativeLibrariesForSelfExtract NO es opcional: sin eso, SQLite queda
    # como un .so suelto al lado del binario y el "archivo unico" explota apenas
    # se lo copia solo a otro lado. Medido: DllNotFoundException 'e_sqlite3'.
    "$dn" publish "$proyecto" -c Release -r linux-x64 --self-contained true \
        -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true \
        -v q --nologo -o "$aqui/publicado" >/dev/null
}

# --- 4. el lanzador del escritorio y el protocolo claudeconv:// --------------
#  El mismo .desktop hace las dos cosas: aparece en el menu y se declara handler
#  del esquema. En Windows esto eran dos piezas (un .lnk y una clave del
#  registro); aca es un archivo de texto.
escribir_desktop() {
    mkdir -p "$APPS"
    cat > "$DESKTOP" <<FIN
[Desktop Entry]
Type=Application
Name=Conversaciones de Claude Code
Comment=Retoma tus conversaciones de Claude Code donde las dejaste
Exec=$BIN %u
Terminal=false
Categories=Development;Utility;
MimeType=x-scheme-handler/claudeconv;
StartupWMClass=Conversaciones
FIN
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" 2>/dev/null || true
}

estado_desktop() {
    [ -f "$DESKTOP" ] && grep -q "^Exec=$BIN %u$" "$DESKTOP" && echo ok || echo falta
}

estado_protocolo() {
    command -v xdg-mime >/dev/null 2>&1 || { echo sin-xdg; return; }
    [ "$(xdg-mime query default x-scheme-handler/claudeconv 2>/dev/null)" = "conversaciones.desktop" ] \
        && echo ok || echo falta
}

estado_path() {
    case ":$PATH:" in *":$BIN_DIR:"*) echo ok ;; *) echo falta ;; esac
}

mostrar_estado() {
    medir_libs
    echo
    echo "  Instalacion del panel de conversaciones (Linux)"
    echo "  $aqui"
    echo
    if [ -n "$(dotnet_bin)" ]; then verde "SDK de .NET" "$(dotnet_bin)"
    else falta "SDK de .NET" "lo instala --instalar, en ~/.dotnet y sin root"; fi

    if [ -z "$LIBS_FALTANTES" ]; then verde "bibliotecas X11" "estan todas"
    else falta "bibliotecas X11" "faltan:$LIBS_FALTANTES"; fi

    if command -v claude >/dev/null 2>&1; then verde "Claude Code" "$(command -v claude)"
    else falta "Claude Code" "sin el, el panel no tiene conversaciones que mostrar"; fi

    [ -x "$BIN" ] && verde "binario" "$BIN" || falta "binario" "se publica y se copia a $BIN"
    [ "$(estado_desktop)" = ok ] && verde "lanzador .desktop" "$DESKTOP" || falta "lanzador .desktop" "sin crear o apuntando a otro lado"
    case "$(estado_protocolo)" in
        ok)      verde "protocolo claudeconv://" "registrado" ;;
        sin-xdg) falta "protocolo claudeconv://" "no encuentro xdg-mime: asocialo a mano" ;;
        *)       falta "protocolo claudeconv://" "sin registrar" ;;
    esac
    [ "$(estado_path)" = ok ] && verde "$BIN_DIR en el PATH" "listo" || falta "$BIN_DIR en el PATH" "agregalo a tu ~/.profile"
    echo
}

instalar() {
    [ -x "$aqui/publicado/Conversaciones" ] || publicar
    mkdir -p "$BIN_DIR"
    install -m 755 "$aqui/publicado/Conversaciones" "$BIN"
    paso "binario en $BIN"

    escribir_desktop
    paso "lanzador $DESKTOP"

    if command -v xdg-mime >/dev/null 2>&1; then
        xdg-mime default conversaciones.desktop x-scheme-handler/claudeconv
        paso "protocolo claudeconv://"
    else
        aviso "sin xdg-mime no puedo registrar claudeconv://; asocialo a mano en tu escritorio"
    fi

    medir_libs
    if [ -n "$LIBS_FALTANTES" ]; then
        echo
        aviso "faltan bibliotecas del sistema y SIN ELLAS LA VENTANA NO ABRE:$LIBS_FALTANTES"
        echo "             $(comando_libs)"
        echo "             (eso pide root, por eso no lo corro yo)"
    fi
    command -v claude >/dev/null 2>&1 || aviso "no encuentro el comando claude: el panel va a estar vacio hasta que uses Claude Code"
    [ "$(estado_path)" = ok ] || aviso "$BIN_DIR no esta en tu PATH: agregalo a ~/.profile y volve a entrar"

    echo
    echo "  Listo. Abrilo desde el menu, o con:  $BIN"
    echo "  Para guardar la charla en curso, desde la carpeta del proyecto:"
    echo "      conversaciones guardar"
    echo "  Tus datos van a $DATOS (se crea solo)."
    echo
}

desinstalar() {
    rm -f "$BIN" && quitado "binario"
    rm -f "$DESKTOP" && quitado "lanzador del escritorio"
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" 2>/dev/null || true
    aviso "la asociacion de claudeconv:// queda sin handler; tu escritorio la olvida sola"
    [ -d "$DOTNET_DIR" ] && aviso "el SDK de .NET queda en $DOTNET_DIR; si no lo usas para nada mas, borra esa carpeta"
    echo
    echo "  TUS DATOS NO SE TOCARON: siguen en $DATOS"
    echo "  Si tambien los queres borrar, borra esa carpeta a mano."
    echo
}

case "${1:-}" in
    --instalar)    mostrar_estado; instalar ;;
    --desinstalar) desinstalar ;;
    --publicar)    publicar; echo "  publicado en $aqui/publicado/Conversaciones" ;;
    "")            mostrar_estado; echo "  Para instalar:  ./setup.sh --instalar"; echo ;;
    *)             echo "uso: $0 [--instalar|--desinstalar|--publicar]"; exit 2 ;;
esac
