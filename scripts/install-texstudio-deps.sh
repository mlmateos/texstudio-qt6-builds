#!/usr/bin/env bash
#===============================================================================
# install-texstudio-deps.sh (v2.0 - Conservadora y Detallada)
# Instala dependencias para TeXstudio (AppImage Qt6 y .deb) sin borrar nada.
#===============================================================================
set -euo pipefail

#===============================================================================
# COLORES Y HELPERS (Mismo estilo que tu script de AppImage)
#===============================================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log()  { echo -e "\n${GREEN}✅ [$(date '+%H:%M:%S')]${NC} $*"; }
warn() { echo -e "\n${YELLOW}⚠️  [$(date '+%H:%M:%S')]${NC} $*" >&2; }
die()  { echo -e "\n${RED}❌ [$(date '+%H:%M:%S')] ERROR:${NC} $*" >&2; exit 1; }
info() { echo -e "${CYAN}ℹ️  [$(date '+%H:%M:%S')]${NC} $*"; }
header() { echo -e "\n${BLUE}═══════════════════════════════════════════════════${NC}"; \
           echo -e "${BLUE}  $*${NC}"; \
           echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"; }

#===============================================================================
# VERIFICACIÓN DE PERMISOS
#===============================================================================
if [[ $EUID -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        die "Este script necesita permisos de administrador. Instala 'sudo' o ejecútalo como root."
    fi
else
    SUDO=""
fi

#===============================================================================
# REGISTROS PARA EL REPORTE FINAL
#===============================================================================
declare -a ALREADY_INSTALLED=()
declare -a NEWLY_INSTALLED=()
declare -a MISSING_PACKAGES=()
declare -a FAILED_PACKAGES=()

#===============================================================================
# FUNCIÓN DE INSTALACIÓN INTELIGENTE Y SEGURA
#===============================================================================
install_pkg() {
    local pkg="$1"
    
    # 1. ¿Ya está instalado?
    if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
        ALREADY_INSTALLED+=("$pkg")
        return 0
    fi
    
    # 2. ¿Existe en los repositorios de tu distro?
    if ! apt-cache show "$pkg" >/dev/null 2>&1; then
        MISSING_PACKAGES+=("$pkg")
        return 0
    fi
    
    # 3. Intentar instalar (sin interacción y silencioso)
    if DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq "$pkg" >/dev/null 2>&1; then
        NEWLY_INSTALLED+=("$pkg")
    else
        FAILED_PACKAGES+=("$pkg")
    fi
}

install_group() {
    local group_name="$1"
    shift
    local packages=("$@")
    
    info "Procesando grupo: $group_name (${#packages[@]} paquetes)..."
    for pkg in "${packages[@]}"; do
        install_pkg "$pkg"
    done
}

#===============================================================================
# INICIO DEL SCRIPT
#===============================================================================
header "🔍 DETECCIÓN DEL SISTEMA"

if [[ ! -f /etc/os-release ]]; then
    die "No se pudo detectar la distribución (falta /etc/os-release)"
fi

source /etc/os-release
log "Sistema: ${PRETTY_NAME:-Desconocido}"
info "Arquitectura: $(uname -m) | Hilos CPU: $(nproc)"

# Actualizar listas (seguro, solo lee repos)
header "🔄 ACTUALIZANDO LISTAS DE PAQUETES"
$SUDO apt-get update -qq >/dev/null 2>&1
log "Listas actualizadas."

#===============================================================================
# DEFINICIÓN DE PAQUETES (Alineados con build-texstudio-appimage.sh)
#===============================================================================
header "📦 INSTALANDO DEPENDENCIAS"

# 1. Base y Compilación
BASE_PKGS=(build-essential cmake make git pkg-config wget curl ca-certificates coreutils)
install_group "🔨 Base y Compilación" "${BASE_PKGS[@]}"

# 2. Herramientas para empaquetado .deb
DEB_PKGS=(debhelper debhelper-compat fakeroot dpkg-dev lintian)
install_group "📦 Empaquetado .deb" "${DEB_PKGS[@]}"

# 3. Qt6 (Requerido por tu script: qmake6, etc.)
QT6_PKGS=(qt6-base-dev qt6-base-dev-tools qt6-tools-dev qt6-tools-dev-tools qt6-l10n-tools qt6-svg-dev libqt6svg6 libgl-dev libegl-dev)
install_group "🎨 Qt6 Core & Tools" "${QT6_PKGS[@]}"

# 4. Poppler-Qt6 (Requerido por tu script: pkg-config --exists poppler-qt6)
POPPLER_PKGS=(libpoppler-dev libpoppler-cpp-dev libpoppler-qt6-dev libpoppler-private-dev)
install_group "📄 Poppler (Visor PDF)" "${POPPLER_PKGS[@]}"

# 5. Librerías Extra de TeXstudio
# Nota: Incluimos ambas variantes de quazip por si tu distro usa una u otra.
EXTRA_PKGS=(zlib1g-dev libssl-dev libhunspell-dev libquazip-qt6-dev libquazip1-qt6-dev libx11-dev)
install_group "📚 Librerías Adicionales" "${EXTRA_PKGS[@]}"

# 6. Opcionales (GPG y GitHub CLI para tu script de publicación)
OPT_PKGS=(gnupg2 gpg gh)
install_group "🔐 Opcionales (GPG / GitHub)" "${OPT_PKGS[@]}"

#===============================================================================
# LIMPIEZA SEGURA (Solo caché, NO desinstala nada)
#===============================================================================
header "🧹 LIMPIEZA DE CACHÉ"
$SUDO apt-get autoclean -y -qq >/dev/null 2>&1 || true
log "Caché de descargas limpiada (no se desinstaló ningún paquete)."

#===============================================================================
# REPORTE FINAL DETALLADO
#===============================================================================
header "📊 REPORTE DE INSTALACIÓN"

echo -e "\n${GREEN}✅ YA ESTABAN INSTALADOS (${#ALREADY_INSTALLED[@]}):${NC}"
if [[ ${#ALREADY_INSTALLED[@]} -gt 0 ]]; then
    printf "   • %s\n" "${ALREADY_INSTALLED[@]}"
else
    echo "   (Ninguno)"
fi

echo -e "\n${CYAN}🆕 INSTALADOS EN ESTA SESIÓN (${#NEWLY_INSTALLED[@]}):${NC}"
if [[ ${#NEWLY_INSTALLED[@]} -gt 0 ]]; then
    printf "   • %s\n" "${NEWLY_INSTALLED[@]}"
else
    echo "   (Ninguno, tu sistema ya tenía todo lo necesario)"
fi

if [[ ${#MISSING_PACKAGES[@]} -gt 0 ]]; then
    echo -e "\n${YELLOW}⚠️  NO ENCONTRADOS EN TUS REPOS (${#MISSING_PACKAGES[@]}):${NC}"
    printf "   • %s\n" "${MISSING_PACKAGES[@]}"
    echo "   (Esto es normal en algunas distros donde los paquetes tienen otro nombre o no aplican)."
fi

if [[ ${#FAILED_PACKAGES[@]} -gt 0 ]]; then
    echo -e "\n${RED}❌ FALLARON AL INSTALAR (${#FAILED_PACKAGES[@]}):${NC}"
    printf "   • %s\n" "${FAILED_PACKAGES[@]}"
fi

#===============================================================================
# VERIFICACIÓN DE HERRAMIENTAS CRÍTICAS (Las que exige tu script de AppImage)
#===============================================================================
header "🔎 VERIFICACIÓN PARA APPIMAGE Y .DEB"

CRITICAL_OK=true
check_tool() {
    local cmd="$1"
    local pkg_hint="$2"
    if command -v "$cmd" >/dev/null 2>&1; then
        echo -e "   ${GREEN}✔${NC} $cmd"
    else
        echo -e "   ${RED}✘${NC} $cmd ${YELLOW}(Falta. Paquete sugerido: $pkg_hint)${NC}"
        CRITICAL_OK=false
    fi
}

check_tool "cmake" "cmake"
check_tool "make" "build-essential"
check_tool "git" "git"
check_tool "pkg-config" "pkg-config"
check_tool "qmake6" "qt6-base-dev"
check_tool "dpkg-buildpackage" "dpkg-dev"
check_tool "dh" "debhelper"

# Verificación específica de Poppler-Qt6 (como hace tu script)
if pkg-config --exists poppler-qt6 2>/dev/null; then
    echo -e "   ${GREEN}✔${NC} poppler-qt6 ($(pkg-config --modversion poppler-qt6))"
else
    echo -e "   ${RED}✘${NC} poppler-qt6 ${YELLOW}(Falta para el visor PDF)${NC}"
    CRITICAL_OK=false
fi

#===============================================================================
# CONCLUSIÓN
#===============================================================================
echo ""
if [[ "$CRITICAL_OK" == true ]]; then
    log "🎉 ¡ENTORNO LISTO Y SEGURO!"
    echo -e "   Tu máquina no ha sufrido alteraciones negativas."
    echo -e "   Ya puedes ejecutar tu script de AppImage o el futuro script de .deb."
else
    warn "Faltan algunas herramientas críticas. Revisa el reporte arriba."
fi
echo ""
