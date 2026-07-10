#!/usr/bin/env bash
#===============================================================================
# install-deps.sh
# Instala todas las dependencias necesarias para compilar TeXstudio con Qt6 + Poppler
# Compatible con Debian, Ubuntu, Devuan y derivados
#===============================================================================
set -euo pipefail

# Colores para mensajes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log()  { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
info() { echo -e "${CYAN}ℹ️  $*${NC}"; }
die()  { echo -e "${RED}❌ ERROR: $*${NC}" >&2; exit 1; }

header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $*${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════${NC}\n"
}

#===============================================================================
# VERIFICACIONES PRELIMINARES
#===============================================================================
header "🔧 INSTALADOR DE DEPENDENCIAS PARA TEXSTUDIO QT6"

# Verificar que se ejecuta como root o con sudo
if [[ $EUID -eq 0 ]]; then
    SUDO=""
else
    if ! command -v sudo >/dev/null 2>&1; then
        die "Este script requiere sudo. Instálalo con: apt install sudo"
    fi
    SUDO="sudo"
fi

# Detectar distribución
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    DISTRO="$ID"
    info "Distribución detectada: $PRETTY_NAME"
else
    warn "No se pudo detectar la distribución. Asumiendo Debian/Ubuntu."
    DISTRO="debian"
fi

# Verificar que es una distribución compatible
case "$DISTRO" in
    debian|ubuntu|devuan|linuxmint|pop|elementary|zorin)
        log "Distribución compatible detectada"
        ;;
    *)
        warn "Distribución no verificada: $DISTRO"
        warn "El script está diseñado para Debian/Ubuntu/Devuan y derivados"
        read -p "¿Deseas continuar de todos modos? (s/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            die "Instalación cancelada por el usuario"
        fi
        ;;
esac

#===============================================================================
# ACTUALIZAR REPOSITORIOS
#===============================================================================
header "📦 ACTUALIZANDO REPOSITORIOS"
$SUDO apt update
log "Repositorios actualizados"

#===============================================================================
# HERRAMIENTAS BÁSICAS DE COMPILACIÓN
#===============================================================================
header "🔨 INSTALANDO HERRAMIENTAS DE COMPILACIÓN"
$SUDO apt install -y \
    build-essential \
    cmake \
    git \
    wget \
    curl \
    pkg-config \
    fakeroot \
    devscripts \
    debhelper \
    dpkg-dev \
    patchelf \
    desktop-file-utils \
    libfuse2
log "Herramientas de compilación instaladas"

#===============================================================================
# QT6 Y DEPENDENCIAS
#===============================================================================
header "🎨 INSTALANDO QT6 Y DEPENDENCIAS"
$SUDO apt install -y \
    qt6-base-dev \
    qt6-base-dev-tools \
    qt6-tools-dev \
    qt6-tools-dev-tools \
    qt6-svg-dev \
    qt6-declarative-dev \
    qt6-multimedia-dev \
    qt6-5compat-dev \
    qt6-l10n-tools || warn "⚠️  Algunos paquetes de Qt6 no se instalaron"

# Verificar que Qt6 está instalado
if command -v qmake6 >/dev/null 2>&1; then
    log "Qt6 instalado correctamente: $(qmake6 --version | head -n1)"
else
    die "Qt6 no se instaló correctamente. Se requiere qmake6."
fi

#===============================================================================
# POPPLER (VISOR PDF)
#===============================================================================
header "📖 INSTALANDO POPPLER-Qt6"
$SUDO apt install -y \
    libpoppler-dev \
    libpoppler-cpp-dev \
    libpoppler-qt6-dev \
    libpoppler-private-dev
log "Poppler-Qt6 instalado correctamente"

#===============================================================================
# OTRAS DEPENDENCIAS DE TEXSTUDIO
#===============================================================================
header " INSTALANDO DEPENDENCIAS ADICIONALES DE TEXSTUDIO"
$SUDO apt install -y \
    libhunspell-dev \
    libquazip1-qt6-dev || $SUDO apt install -y libquazip-qt6-dev || warn "⚠️  QuaZip puede no estar disponible"
$SUDO apt install -y \
    zlib1g-dev \
    libssl-dev \
    libx11-dev \
    libxkbcommon-dev \
    libgl-dev \
    libegl-dev || warn "⚠️  Algunas librerías gráficas no se instalaron"
log "Dependencias adicionales instaladas"

#===============================================================================
# GITHUB CLI (PARA PUBLICACIÓN)
#===============================================================================
header "🌐 INSTALANDO GITHUB CLI"
if command -v gh >/dev/null 2>&1; then
    info "GitHub CLI ya está instalado: $(gh --version | head -n1)"
else
    # Instalar GitHub CLI desde el repositorio oficial
    $SUDO mkdir -p -m 755 /etc/apt/keyrings
    wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | $SUDO tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
    $SUDO chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | $SUDO tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    $SUDO apt update
    $SUDO apt install -y gh
    log "GitHub CLI instalado correctamente"
fi

#===============================================================================
# GPG (PARA FIRMADO)
#===============================================================================
header "🔐 VERIFICANDO GPG"
if command -v gpg >/dev/null 2>&1; then
    info "GPG ya está instalado: $(gpg --version | head -n1)"
else
    $SUDO apt install -y gnupg2
    log "GPG instalado correctamente"
fi

#===============================================================================
# APPIMAGETOOL (PARA CREAR APPIMAGE)
#===============================================================================
header "📦 INSTALANDO APPIMAGETOOL"
if command -v appimagetool >/dev/null 2>&1; then
    info "appimagetool ya está instalado"
else
    info "Descargando appimagetool..."
    wget -q https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage -O /tmp/appimagetool.AppImage
    chmod +x /tmp/appimagetool.AppImage
    $SUDO mv /tmp/appimagetool.AppImage /usr/local/bin/appimagetool
    log "appimagetool instalado en /usr/local/bin/appimagetool"
fi

#===============================================================================
# VERIFICACIÓN FINAL
#===============================================================================
header "✅ VERIFICANDO INSTALACIÓN"

ERRORS=0

# Verificar herramientas críticas
for cmd in cmake qmake6 git gcc g++ make pkg-config patchelf appimagetool gh gpg; do
    if command -v "$cmd" >/dev/null 2>&1; then
        log "$cmd está instalado"
    else
        warn "$cmd NO está instalado"
        ERRORS=$((ERRORS + 1))
    fi
done

# Verificar Qt6
if pkg-config --exists Qt6Core Qt6Widgets Qt6Gui; then
    log "Qt6 está correctamente instalado"
else
    warn "Qt6 no se detecta correctamente"
    ERRORS=$((ERRORS + 1))
fi

# Verificar Poppler
if pkg-config --exists poppler-qt6; then
    log "Poppler-Qt6 está correctamente instalado"
else
    warn "Poppler-Qt6 no se detecta correctamente"
    ERRORS=$((ERRORS + 1))
fi

# Verificar Hunspell
if pkg-config --exists hunspell; then
    log "Hunspell está correctamente instalado"
else
    warn "Hunspell no se detecta correctamente"
    ERRORS=$((ERRORS + 1))
fi

#===============================================================================
# RESUMEN FINAL
#===============================================================================
header "🎉 RESUMEN"

if [[ $ERRORS -eq 0 ]]; then
    log "¡Todas las dependencias están instaladas correctamente!"
    echo ""
    echo "Ahora puedes compilar TeXstudio con:"
    echo ""
    echo "  📦 Para .deb:"
    echo "     cd ~/texstudio-qt6-builds/scripts"
    echo "     ./build-texstudio-deb.sh --clean --poppler --sign"
    echo ""
    echo "  📦 Para AppImage:"
    echo "     cd ~/texstudio-qt6-builds/scripts"
    echo "     ./build-texstudio-appimage.sh --clean --poppler --sign"
    echo ""
    echo "  📦 Para compilar y publicar:"
    echo "     ./build-texstudio-deb.sh --clean --poppler --sign --publish"
    echo ""
    exit 0
else
    warn "Se encontraron $ERRORS problema(s) en la instalación"
    warn "Revisa los mensajes anteriores para más detalles"
    exit 1
fi
