#!/usr/bin/env bash
# =============================================================================
#  setup.sh - instala el panel de conversaciones en tu usuario.
#
#    ./setup.sh                muestra el estado de las piezas y no toca nada
#    ./setup.sh --instalar     instala lo que falte
#    ./setup.sh --desinstalar  deshace lo que instalo (NUNCA toca tus datos)
#
#  NO pide root: todo vive en ~/.local. Mismo criterio que el setup.ps1 de
#  Windows: se mide el estado REAL en cada corrida, sin marcador de "ya
#  instalado", asi mover la carpeta no rompe nada.
# =============================================================================
set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
proyecto="$aqui/Conversaciones"

BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
BIN="$BIN_DIR/conversaciones"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
DESKTOP="$APPS/conversaciones.desktop"
DATOS="${XDG_DATA_HOME:-$HOME/.local/share}/conversaciones"

# El SDK puede estar en el PATH o instalado en el usuario, que es como lo pone
# dotnet-install.sh. Se prueban los dos antes de decir que falta.
dotnet_bin() {
    if command -v dotnet >/dev/null 2>&1; then echo "dotnet"
    elif [ -x "$HOME/.dotnet/dotnet" ]; then echo "$HOME/.dotnet/dotnet"
    else echo ""; fi
}

verde()  { printf '  \033[32mok   \033[0m  %-22s %s\n' "$1" "$2"; }
falta()  { printf '  \033[33mfalta\033[0m  %-22s %s\n' "$1" "$2"; }
paso()   { printf '  \033[32minstalado\033[0m : %s\n' "$1"; }
aviso()   { printf '  \033[33maviso    \033[0m : %s\n' "$1"; }
quitado() { printf '  \033[32mquitado  \033[0m : %s\n' "$1"; }

# --- 1. el binario -----------------------------------------------------------
#  Se publica self-contained: el que lo reciba no necesita .NET instalado, y el
#  mismo archivo sirve en Arch y en Debian.
publicar() {
    local dn; dn="$(dotnet_bin)"
    [ -n "$dn" ] || { echo "Falta el SDK de .NET 10. Sin tocar el sistema:"; \
        echo "    curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel LTS"; exit 1; }
    echo "  compilando (la primera vez tarda)..."
    # IncludeNativeLibrariesForSelfExtract NO es opcional: sin eso, SQLite queda
    # como un .so suelto al lado del binario y el "archivo unico" explota apenas
    # se lo copia solo a otro lado. Medido: DllNotFoundException 'e_sqlite3'.
    "$dn" publish "$proyecto" -c Release -r linux-x64 --self-contained true \
        -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true \
        -v q --nologo -o "$aqui/publicado" >/dev/null
}

estado_binario() {
    [ -x "$BIN" ] && echo ok || echo falta
}

# --- 2. el lanzador del escritorio y el protocolo claudeconv:// --------------
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
    echo
    echo "  Instalacion del panel de conversaciones (Linux)"
    echo "  $aqui"
    echo
    [ "$(estado_binario)" = ok ] && verde "binario" "$BIN" || falta "binario" "hay que publicarlo y copiarlo a $BIN"
    [ "$(estado_desktop)" = ok ] && verde "lanzador .desktop" "$DESKTOP" || falta "lanzador .desktop" "sin crear o apuntando a otro lado"
    case "$(estado_protocolo)" in
        ok)      verde "protocolo claudeconv://" "registrado" ;;
        sin-xdg) falta "protocolo claudeconv://" "no encuentro xdg-mime: hay que asociarlo a mano" ;;
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

    [ "$(estado_path)" = ok ] || aviso "$BIN_DIR no esta en tu PATH: agregalo a ~/.profile y volve a entrar"

    echo
    echo "  Listo. Abrilo desde el menu, o con:  $BIN"
    echo "  Tus datos van a $DATOS (se crea solo)."
    echo
}

desinstalar() {
    rm -f "$BIN" && quitado "binario"
    rm -f "$DESKTOP" && quitado "lanzador del escritorio"
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" 2>/dev/null || true
    aviso "la asociacion de claudeconv:// queda sin handler; tu escritorio la olvida sola"
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
