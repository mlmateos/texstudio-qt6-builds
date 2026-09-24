#!/usr/bin/env bash
#===============================================================================
# build-texstudio-appimage.sh (v2.8-Final)
# Compila TeXstudio desde fuente y genera AppImage (Qt6 + Poppler)
# v2.8: About dialog con comillas simples HTML (fix escape C++), parche
#       idempotente, bundle QuaZip+Poppler vía ldd, sync README automático
#===============================================================================
set -euo pipefail

# Ruta absoluta del directorio del script (antes de cualquier cd)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#===============================================================================
# CONFIGURACIÓN BASE
#===============================================================================
REPO_URL="https://github.com/texstudio-org/texstudio.git"
GITHUB_USER="mlmateos"
REPO_NAME="texstudio-qt6-builds"
BRANCH="master"
CLEAN_BUILD=false
ENABLE_POPPLER=false
SIGN=false
PUBLISH=false
GPG_KEY=""
MAX_RETRIES=3
RETRY_DELAY=5
KEEP_SOURCE=true
AUTO_CONFIRM=false

#===============================================================================
# DETECCIÓN INTELIGENTE DE HILOS
#===============================================================================
detect_optimal_jobs() {
    local cpu_threads total_ram_mb max_jobs_ram
    cpu_threads=$(nproc 2>/dev/null || echo 1)
    total_ram_mb=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print int($2/1024)}' || echo 8192)
    max_jobs_ram=$(( total_ram_mb / 1536 ))
    (( max_jobs_ram < 1 )) && max_jobs_ram=1
    if (( cpu_threads > max_jobs_ram )); then echo "$max_jobs_ram"; else echo "$cpu_threads"; fi
}
JOBS=$(detect_optimal_jobs)

#===============================================================================
# ARGUMENTOS
#===============================================================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean)      CLEAN_BUILD=true; shift ;;
        --branch)     BRANCH="$2"; shift 2 ;;
        --jobs)       JOBS="$2"; shift 2 ;;
        --poppler)    ENABLE_POPPLER=true; shift ;;
        --sign)       SIGN=true; shift ;;
        --publish)    PUBLISH=true; shift ;;
        --gpg-key)    GPG_KEY="$2"; shift 2 ;;
        --yes)        AUTO_CONFIRM=true; shift ;;
        --no-keep-source) KEEP_SOURCE=false; shift ;;
        --help|-h)
cat << 'HELP'
Uso: ./build-texstudio-appimage.sh [OPCIONES]

  --clean         Limpia todo antes de empezar
  --branch NAME   Rama o tag a compilar (ej: 4.9.5, 4.9.6alpha4)
  --jobs N        Hilos para compilación
  --poppler       Habilita visor PDF interno (Poppler-Qt6)
  --sign          Firma la AppImage con GPG
  --publish       Publica en GitHub Releases
  --gpg-key ID    ID de clave GPG para firmar
  --yes           No pide confirmación (modo automatizado)
  --no-keep-source No mantiene el código fuente después de compilar
  --help, -h      Muestra esta ayuda
HELP
            exit 0 ;;
        *) echo "❌ Argumento desconocido: $1" >&2; exit 1 ;;
    esac
done

#===============================================================================
# HELPERS
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
check_cmd() { command -v "$1" >/dev/null 2>&1 || die "No se encontró '$1'. Instálalo primero."; }

#===============================================================================
# FUNCIÓN DE REINTENTOS
#===============================================================================
git_with_retry() {
    local description="$1"
    shift
    local attempt=1
    while true; do
        info "🔄 $description (intento $attempt/$MAX_RETRIES)..."
        if "$@"; then return 0; fi
        if (( attempt >= MAX_RETRIES )); then return 1; fi
        warn "⚠️  Intento $attempt falló. Reintentando en ${RETRY_DELAY}s..."
        sleep "$RETRY_DELAY"
        attempt=$((attempt + 1))
    done
}

#===============================================================================
# DEPENDENCIAS
#===============================================================================
header "🔧 VERIFICANDO DEPENDENCIAS"
log "Verificando herramientas..."
for cmd in cmake make git pkg-config wget; do
    check_cmd "$cmd"
done
command -v qmake6 >/dev/null 2>&1 || die "No se encontró 'qmake6'. Instala qt6-base-dev."

if [[ "$ENABLE_POPPLER" == true ]]; then
    log "Verificando Poppler-Qt6..."
    if ! pkg-config --exists poppler poppler-cpp poppler-qt6 2>/dev/null; then
        warn "Instalando dependencias de Poppler..."
        command -v sudo >/dev/null && sudo apt update && sudo apt install -y libpoppler-dev libpoppler-cpp-dev libpoppler-qt6-dev || \
        die "Faltan: libpoppler-dev libpoppler-cpp-dev libpoppler-qt6-dev"
    fi
fi

if [[ "$SIGN" == true ]]; then
    log "Verificando GPG..."
    check_cmd gpg
fi
if [[ "$PUBLISH" == true ]]; then
    log "Verificando GitHub CLI..."
    check_cmd gh
fi

# Verificar AppImageTool
if ! command -v appimagetool >/dev/null 2>&1; then
    warn "⚠️  appimagetool no encontrado. Descargando..."
    wget -q https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage -O /tmp/appimagetool.AppImage
    chmod +x /tmp/appimagetool.AppImage
    sudo mv /tmp/appimagetool.AppImage /usr/local/bin/appimagetool
    log "✅ appimagetool instalado"
fi

#===============================================================================
# VALIDACIÓN DE GLIBC (para Qt6)
#===============================================================================
header "🔍 VALIDANDO GLIBC"
GLIBC_VERSION=""
GLIBC_RAW=$(ldd --version 2>&1 | head -n1 || echo "")
log "📋 Salida de ldd: $GLIBC_RAW"
if [[ "$GLIBC_RAW" =~ ([0-9]+\.[0-9]+) ]]; then
    GLIBC_VERSION="${BASH_REMATCH[1]}"
fi
if [[ -z "$GLIBC_VERSION" ]]; then
    warn "⚠️  No se pudo detectar la versión de glibc, asumiendo compatible"
    GLIBC_VERSION="2.34"
fi
log "📋 glibc detectada: $GLIBC_VERSION"
GLIBC_CHECK=$(printf '%s\n' "2.34" "$GLIBC_VERSION" | sort -V | head -n1)
if [[ "$GLIBC_CHECK" != "2.34" ]]; then
    warn "⚠️  glibc < 2.34. Qt6 requiere glibc ≥ 2.34."
else
    log "✅ glibc ≥ 2.34 (compatible con Qt6)"
fi

#===============================================================================
# PREPARACIÓN & CLONADO (CON REINTENTOS)
#===============================================================================
header "📥 PREPARANDO CÓDIGO FUENTE"
PROJECT_DIR="$(pwd)/texstudio-appimage"
BUILD_DIR="$PROJECT_DIR/build"
APPDIR="$PROJECT_DIR/AppDir"

if [[ "$CLEAN_BUILD" == true ]]; then
    if [[ "$KEEP_SOURCE" == true ]]; then
        log "Limpiando build anterior (manteniendo código fuente)..."
        rm -rf "$BUILD_DIR" "$APPDIR"
        rm -f "$PROJECT_DIR"/*.AppImage*
    else
        log "Limpiando todo..."
        rm -rf "$PROJECT_DIR"
    fi
fi

if [[ ! -d "$PROJECT_DIR/.git" ]]; then
    log "Clonando repositorio (rama: $BRANCH)..."
    if ! git_with_retry "git clone" git clone --branch "$BRANCH" --depth 100 "$REPO_URL" "$PROJECT_DIR"; then
        die "No se pudo clonar el repositorio tras $MAX_RETRIES intentos. Verifica tu conexión."
    fi
    cd "$PROJECT_DIR"
    git_with_retry "git fetch --tags" git fetch --tags origin || warn "⚠️  No se pudieron obtener tags..."
    cd - >/dev/null
else
    log "Actualizando repositorio..."
    cd "$PROJECT_DIR"
    git fetch --depth 100 origin "$BRANCH" 2>/dev/null || true
    git_with_retry "git fetch --tags" git fetch --tags origin || warn "⚠️  No se pudieron obtener tags, continuando con los existentes..."

    if git show-ref --tags --verify --quiet "refs/tags/$BRANCH" 2>/dev/null; then
        log "📌 Detectado TAG: $BRANCH"
        git checkout -f "$BRANCH" 2>/dev/null || git checkout -f "tags/$BRANCH"
        git reset --hard "$BRANCH"
    else
        log "📌 Detectada RAMA: $BRANCH"
        git fetch origin "$BRANCH" --depth 1 2>/dev/null || true
        if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
            git checkout -f -B "$BRANCH" "origin/$BRANCH"
            git reset --hard "origin/$BRANCH"
        else
            git checkout -f -B "$BRANCH" "FETCH_HEAD"
            git reset --hard "FETCH_HEAD"
        fi
    fi
    cd - >/dev/null
fi

mkdir -p "$BUILD_DIR" "$APPDIR/usr"

#===============================================================================
# DETECCIÓN / FORZADO DE VERSIÓN
#===============================================================================
header "🏷️ DETECTANDO VERSIÓN"
VER_GIT=""

if [[ "$BRANCH" =~ ^v?[0-9]+\.[0-9]+([.-][0-9a-zA-Z]+)*$ ]]; then
    VER_GIT="${BRANCH#v}"
    log "📌 Versión explícita desde --branch: $VER_GIT"
fi

if [[ -z "$VER_GIT" ]] && [[ -d "$PROJECT_DIR/.git" ]]; then
    VER_GIT=$(git -C "$PROJECT_DIR" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//') || VER_GIT=""
fi

if [[ -z "$VER_GIT" ]] && [[ "$BRANCH" == "master" ]]; then
    log "🔍 Detectando último tag vía GitHub API..."
    LATEST_TAG=$(curl -s "https://api.github.com/repos/texstudio-org/texstudio/tags" \
                 | grep -oP '"name":\s*"\K[0-9]+\.[0-9]+\.[0-9]+[a-zA-Z0-9]*' | head -n1) || true
    [[ -n "$LATEST_TAG" ]] && VER_GIT="$LATEST_TAG"
fi

if [[ -n "$VER_GIT" ]]; then
    log "📌 Forzando versión $VER_GIT en el código fuente..."
    CMAKE_VERSION=$(echo "$VER_GIT" | sed 's/[^0-9.]//g')
    sed -i -E "s/(project\(TeXstudio VERSION )[0-9.]+/\1${CMAKE_VERSION}/" "$PROJECT_DIR/CMakeLists.txt"
    sed -i -E "s/(add_definitions\(-DTEXSTUDIO_VERSION=\")[^\"]*/\1${VER_GIT}/" "$PROJECT_DIR/CMakeLists.txt"
    if [[ -f "$PROJECT_DIR/src/utilsVersion.h" ]]; then
        sed -i -E "s/(#define TXSVERSION \")[^\"]*/\1${VER_GIT}/" "$PROJECT_DIR/src/utilsVersion.h"
    fi
    find "$PROJECT_DIR/src" -type f \( -name "*.h" -o -name "*.cpp" \) -exec grep -l "TXSVERSION" {} + 2>/dev/null \
        | xargs -r sed -i "s\|TXSVERSION \"[^\"]*\"\|TXSVERSION \"$VER_GIT\"\|g" || true
else
    warn "⚠️  No se pudo detectar versión; se usará la del código fuente."
fi

RAW_VER="${VER_GIT:-4.9.5}"
VER=$(echo "$RAW_VER" | sed -E 's/alpha([0-9]+)/-alpha\1/; s/beta([0-9]+)/-beta\1/; s/rc([0-9]+)/-rc\1/')
log "Versión: $VER"

#===============================================================================
# DETECCIÓN TEMPRANA DE PRE-RELEASE
#===============================================================================
IS_PRERELEASE=false
if [[ "$VER" == *alpha* || "$VER" == *beta* || "$VER" == *rc* ]]; then
    IS_PRERELEASE=true
    log "🧪 Detectada versión pre-release: $VER"
else
    log "✅ Detectada versión estable: $VER"
fi

#===============================================================================
# PARCHE: URLs DE ACTUALIZACIÓN Y ABOUT DIALOG
#===============================================================================
header "🔧 APLICANDO PARCHE PERSONALIZADO"

log "Modificando URLs de actualización..."
UPDATECHECKER_FILE="$PROJECT_DIR/src/updatechecker.cpp"
if [[ -f "$UPDATECHECKER_FILE" ]]; then
    sed -i 's|https://api\.github\.com/repos/texstudio-org/texstudio/git/refs/tags|https://mlmateos.github.io/texstudio-qt6-builds/pool/update.json|g' "$UPDATECHECKER_FILE"
    sed -i 's|https://texstudio\.org|https://mlmateos.github.io/texstudio-qt6-builds|g' "$UPDATECHECKER_FILE"
    sed -i 's|https://github\.com/texstudio-org/texstudio/releases|https://github.com/mlmateos/texstudio-qt6-builds/releases|g' "$UPDATECHECKER_FILE"
    log "✅ URLs de actualización modificadas"
    grep -n "mlmateos\|update.json" "$UPDATECHECKER_FILE" | head -5 || warn "⚠️  No se encontraron modificaciones"
else
    warn "⚠️  No se encontró src/updatechecker.cpp"
fi

# Parche del About dialog: IDEMPOTENTE (reemplaza setText completa siempre).
# IMPORTANTE: los href usan comillas SIMPLES HTML para no romper el escape C++.
log "Reorganizando diálogo About..."
ABOUT_FILE="$PROJECT_DIR/src/aboutdialog.cpp"
if [[ -f "$ABOUT_FILE" ]]; then
    python3 - "$ABOUT_FILE" << 'PYTHON'
import re, sys
about_file_path = sys.argv[1]
with open(about_file_path, 'r', encoding='utf-8') as f:
    content = f.read()
new_setText = '''void AboutDialog::setText(QString latestVersion) {
QString changelogPath = findResourceFile("CHANGELOG.md");
if(changelogPath.isEmpty()){
changelogPath="https://texstudio-org.github.io/CHANGELOG.html";
}else{
if(!changelogPath.startsWith("/")){
changelogPath="/"+changelogPath;
}
changelogPath="file://"+changelogPath;
}
if (latestVersion=="") latestVersion = tr("couldn't retrieve data");
ui.textBrowser->setOpenExternalLinks(true);
ui.textBrowser->setHtml(QString("<b>%1 %2</b> (git %3)").arg(TEXSTUDIO,TXSVERSION,TEXSTUDIO_GIT_REVISION ? TEXSTUDIO_GIT_REVISION : "n/a") + "<br>" +
tr("Using Qt Version %1, compiled with Qt %2 %3").arg(qVersion(),QT_VERSION_STR,COMPILED_DEBUG_OR_RELEASE) + "<br><br>" +
"<b>TeXstudio Qt6 Build with Poppler</b><br>" +
"Custom build with Qt6 and Poppler support<br>" +
"Compiled by Manuel López Mateos<br>" +
"AI assistance provided by Qwen (Alibaba Group).<br>" +
"<a href='https://github.com/mlmateos/texstudio-qt6-builds'>https://github.com/mlmateos/texstudio-qt6-builds</a><br><br>" +
tr("Latest stable version: %1").arg(latestVersion)+"<br>" +
"<a href='"+changelogPath+"'>"+tr("Changelog")+"</a><br><br>" +
"This is an unofficial build.<br><br>" +
"TeXstudio © Benito van der Zander, Jan Sundermeyer, Daniel Braun, Tim Hoffmann.<br>" +
tr("Project home site:") + " <a href='https://texstudio.org/'>https://texstudio.org/</a><br><br>" +
"Copyright (c)<br>" +
TEXSTUDIO + ": Benito van der Zander, Jan Sundermeyer, Daniel Braun, Tim Hoffmann<br>" +
"Texmaker: Pascal Brachet<br>" +
"QCodeEdit: Luc Bruant<br>" +
tr("html conversion: ") + QString::fromUtf8("Joël Amblard</i><br>") +
tr("TeXstudio contains code from Hunspell (GPL), QtCreator (GPL, Copyright (C) Nokia), KILE (GPL) and SyncTeX (by Jerome Laurens).") + "<br>" +
tr("TeXstudio uses the PDF viewer of TeXworks.") + "<br>" +
tr("TeXstudio uses the DSingleApplication class (Author: Dima Fedorov Levit - Copyright (C) BioImage Informatics - Licence: GPL).") + "<br>" +
tr("TeXstudio uses TexTablet (MIT License, Copyright (c) 2012 Steven Lovegrove).") + "<br>" +
tr("TeXstudio uses QuaZip (LGPL, Copyright (C) 2005-2012 Sergey A. Tachenov and contributors).") + "<br>" +
tr("TeXstudio uses To Title Case (MIT License, Copyright (c) 2008-2013 David Gouch).") + "<br>" +
tr("TeXstudio contains an image by Alexander Klink.") + "<br>" +
tr("TeXstudio uses icons from the Crystal Project (LGPL), the Oxygen icon theme (CC-BY-SA 3.0) and the Colibre icon theme (CC0) of LibreOffice.") + "<br>" +
tr("TeXstudio uses flowlayout from Qt5.6 examples.") + "<br>" +
tr("TeXstudio uses adwaita-qt (GPL2) from ") + "<a href='https://github.com/FedoraQt/adwaita-qt'>https://github.com/FedoraQt/adwaita-qt</a><br>" +
"<br>" +
tr("Thanks to ") + QString::fromUtf8("Frédéric Devernay, Denis Bitouzé, Vesselin Atanasov, Yukai Chou, Jean-Côme Charpentier, Luis Silvestre, Enrico Vittorini, Aleksandr Zolotarev, David Sichau, Grigory Mozhaev, mattgk, A. Weder, Pavel Fric, András Somogyi, István Blahota, Edson Henriques, Grant McLean, Tom Jampen, Kostas Oikinimou, Lion Guillaume, ranks.nl, AI Corleone, Diego Andrés Jarrín, Matthias Pospiech, Zulkifli Hidayat, Christian Spieß, Robert Diaz, Kirill Müller, Atsushi Nakajima Yuriy Kolerov, Victor Kozyakin, Mattia Meneguzzo, Andriy Bandura, Carlos Eduardo Valencia Urbina, Koutheir Attouchi, Stefan Kraus, Bjoern Menke, Charles Brunet, François Gannaz, Marek Kurdej, Paulo Silva, Thiago de Melo, YoungFrog, Klaus Schneider-Zapp, Jakob Nixdorf, Thomas Leitz, Quoc Ho, Matthew Bertucci, geolta.<br><br>") +
tr("This program is licensed to you under the terms of the GNU General Public License Version 3 as published by the Free Software Foundation."));
}'''
pattern = r'void AboutDialog::setText\(QString latestVersion\)\s*\{.*?\n\}'
content, n = re.subn(pattern, new_setText, content, flags=re.DOTALL)
with open(about_file_path, 'w', encoding='utf-8') as f:
    f.write(content)
if n == 1:
    print("✅ Diálogo About reorganizado correctamente")
else:
    print(f"⚠️ Número de reemplazos inesperado: {n}")
    sys.exit(1)
PYTHON
    if grep -q "Custom build with Qt6" "$ABOUT_FILE"; then
        log "✅ Créditos reorganizados en el diálogo About"
    else
        warn "⚠️  El parche del About no se aplicó (¿cambió la firma de setText upstream?)"
    fi
else
    warn "⚠️  No se encontró src/aboutdialog.cpp"
fi

log "Guardando copia del código fuente parcheado..."
BACKUP_DIR="$(pwd)/patched-source-backup-appimage"
mkdir -p "$BACKUP_DIR"
cp -r "$PROJECT_DIR/src" "$BACKUP_DIR/"
log "✅ Copia guardada en $BACKUP_DIR/src/"

#===============================================================================
# COMPILACIÓN
#===============================================================================
header "🔨 COMPILANDO"
cd "$BUILD_DIR"
log "Configurando cmake..."
cmake .. \
    -DCMAKE_BUILD_TYPE=MinSizeRel \
    -DCMAKE_CXX_FLAGS="-Os -fdata-sections -ffunction-sections" \
    -DCMAKE_EXE_LINKER_FLAGS="-Wl,--gc-sections" \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DQT_VERSION=6 \
    -DTEXSTUDIO_BUILD_ADWAITA=ON \
    -DTEXSTUDIO_ENABLE_TESTS=OFF || die "Configure falló"

log "Compilando con $JOBS hilos..."
cmake --build . -j"$JOBS" || die "Compilación falló"

log "Instalando en AppDir..."
cmake --install . --prefix "$APPDIR/usr" || die "Instalación falló"
cd ..

#===============================================================================
# CREAR APPIMAGE
#===============================================================================
header "📦 CREANDO APPIMAGE"

log "Creando archivo desktop..."
cat > "$APPDIR/texstudio.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=TeXstudio
Comment=Integrated writing environment for LaTeX documents
Exec=texstudio
Icon=texstudio
Categories=Office;TextEditor;
Terminal=false
EOF

# Icono
ICON_SRC=$(find "$PROJECT_DIR/src" -type f \( -name "texstudio.png" -o -name "texteditor.png" \) 2>/dev/null | head -n1)
if [[ -n "$ICON_SRC" ]]; then
    cp "$ICON_SRC" "$APPDIR/texstudio.png"
    log "✅ Icono copiado desde el fuente"
else
    warn "⚠️  Icono no encontrado, creando placeholder..."
    echo "iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAYAAADDPmHLAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAALEwAACxMBAJqcGAAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAA"| base64 -d > "$APPDIR/texstudio.png"
fi

log "Creando AppRun..."
cat > "$APPDIR/AppRun" << 'EOF'
#!/bin/bash
HERE="$(dirname "$(readlink -f "$0")")"
export PATH="$HERE/usr/bin:$PATH"
export LD_LIBRARY_PATH="$HERE/usr/lib:$HERE/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
export QT_PLUGIN_PATH="$HERE/usr/plugins:$QT_PLUGIN_PATH"
exec "$HERE/usr/bin/texstudio" "$@"
EOF
chmod +x "$APPDIR/AppRun"

#===============================================================================
# BUNDLE DE LIBS VOLÁTILES (Poppler + QuaZip) vía ldd
#===============================================================================
header "📦 BUNDLE DE LIBS VOLÁTILES"
mkdir -p "$APPDIR/usr/lib"
for NAME in libpoppler-qt6 libpoppler-cpp libpoppler libquazip1-qt6; do
    lib_path=$(ldd "$APPDIR/usr/bin/texstudio" 2>/dev/null | awk -v n="$NAME" '$1 ~ ("^" n "\\.so(\\.[0-9]+)*$") {print $3; exit}' || true)
    if [[ -n "$lib_path" && -f "$lib_path" ]]; then
        cp -L "$lib_path" "$APPDIR/usr/lib/"
        log "   📦 Bundled: $(basename "$lib_path")"
    else
        warn "⚠️  No se encontró $NAME para empaquetar"
    fi
done

# Validar desktop file
if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate "$APPDIR/texstudio.desktop" || warn "⚠️  desktop-file-validate falló"
fi

log "Generando AppImage..."
export ARCH=x86_64
export VERSION="$VER"
APPIMAGE_NAME="texstudio-${VER}-qt6-x86_64.AppImage"
if [[ "$SIGN" == true ]]; then
    log "🔐 Firmando AppImage..."
    appimagetool --sign "$APPDIR" "$APPIMAGE_NAME" || die "appimagetool falló"
else
    appimagetool "$APPDIR" "$APPIMAGE_NAME" || die "appimagetool falló"
fi
chmod +x "$APPIMAGE_NAME"
sha256sum "$APPIMAGE_NAME" > SHA256SUMS-APPIMAGE.txt
cat SHA256SUMS-APPIMAGE.txt
log "✅ AppImage creada: $APPIMAGE_NAME"

#===============================================================================
# FIRMADO GPG
#===============================================================================
if [[ "$SIGN" == true ]]; then
    header "🔐 FIRMANDO CON GPG"
    [[ -z "$GPG_KEY" ]] && GPG_KEY=$(gpg --list-secret-keys --keyid-format long | grep "^sec" | head -n1 | awk '{print $2}' | cut -d'/' -f2)
    log "Usando clave GPG: $GPG_KEY"
    set +e
    gpg --default-key "$GPG_KEY" --detach-sign --armor "$APPIMAGE_NAME"
    set -e
    [[ -f "${APPIMAGE_NAME}.asc" ]] && log "✅ Firma generada: ${APPIMAGE_NAME}.asc"
fi

#===============================================================================
# PUBLICACIÓN EN GITHUB
#===============================================================================
if [[ "$PUBLISH" == true ]]; then
    header "🌐 PUBLICANDO EN GITHUB"
    if ! gh auth status >/dev/null 2>&1; then
        die "No autenticado en GitHub CLI. Ejecuta 'gh auth login' primero."
    fi
    FULL_REPO="${GITHUB_USER}/${REPO_NAME}"
    UPLOAD_FILES=("$APPIMAGE_NAME" "SHA256SUMS-APPIMAGE.txt")
    [[ -f "${APPIMAGE_NAME}.asc" ]] && UPLOAD_FILES+=("${APPIMAGE_NAME}.asc")

    RELEASE_EXISTS=false
    if gh release view "v${VER}" --repo "$FULL_REPO" >/dev/null 2>&1; then
        RELEASE_EXISTS=true
        log "✅ Release 'v${VER}' detectada en GitHub"
    elif gh release list --repo "$FULL_REPO" 2>/dev/null | grep -q "^v${VER}[[:space:]]"; then
        RELEASE_EXISTS=true
        log "✅ Release 'v${VER}' detectada (método alternativo)"
    fi

    if [[ "$RELEASE_EXISTS" == true ]]; then
        if [[ "$AUTO_CONFIRM" == true ]]; then CONFIRM="y"
        else log "⚠️  La release 'v${VER}' YA EXISTE."; read -r -p "¿Deseas AÑADIR la AppImage a esta release? (y/N) " CONFIRM; fi
        if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
            gh release upload "v${VER}" --clobber --repo "$FULL_REPO" "${UPLOAD_FILES[@]}"
            log "✅ AppImage AÑADIDA a la release existente"
            log "🔗 https://github.com/$FULL_REPO/releases/tag/v${VER}"
        else
            log "🛑 Publicación cancelada."
            exit 0
        fi
    else
        log "✨ Creando nueva release: v${VER}"
        if [[ "$AUTO_CONFIRM" == true ]]; then CONFIRM="y"
        else read -r -p "¿Deseas CREAR la release? (y/N) " CONFIRM; fi
        if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
            CREATE_ARGS=("v${VER}" --repo "$FULL_REPO"
                         --title "TeXstudio ${VER} (Qt6 + Poppler)"
                         --notes "AppImage portable (Qt6 + Poppler). Sin instalación: chmod +x y ejecutar.")
            if [[ "$IS_PRERELEASE" == true ]]; then
                CREATE_ARGS+=(--prerelease)
                log "📋 Release marcada como PRE-RELEASE ($VER)"
            else
                log "✅ Release marcada como STABLE ($VER)"
            fi
            gh release create "${CREATE_ARGS[@]}" "${UPLOAD_FILES[@]}"
            if [[ "$IS_PRERELEASE" == false ]]; then
                gh release edit "v${VER}" --repo "$FULL_REPO" --latest
                log "✅ Release marcada como Latest"
            fi
            log "🔗 https://github.com/$FULL_REPO/releases/tag/v${VER}"
        else
            log "📦 Publicación cancelada."
            exit 0
        fi
    fi
fi

#===============================================================================
# AUTO-ACTUALIZACIÓN DEL README (tras publicar)
#===============================================================================
if [[ "$PUBLISH" == true ]]; then
    SYNC_SCRIPT="$SCRIPT_DIR/sync-readme-versions.sh"
    if [[ -f "$SYNC_SCRIPT" ]]; then
        [[ ! -x "$SYNC_SCRIPT" ]] && chmod +x "$SYNC_SCRIPT"
        bash "$SYNC_SCRIPT" || warn "⚠️  sync-readme-versions.sh falló"
    else
        warn "⚠️  No se encontró $SYNC_SCRIPT"
    fi
fi

#===============================================================================
# RESULTADO FINAL
#===============================================================================
header "🎉 RESULTADO FINAL"
if [[ -f "$APPIMAGE_NAME" ]]; then
    log "¡ÉXITO! AppImage lista:"
    echo "   📦 $(basename "$APPIMAGE_NAME")"
    echo "   📍 $(pwd)/$APPIMAGE_NAME"
    echo "   🔧 Tamaño: $(du -h "$APPIMAGE_NAME" | cut -f1)"
    [[ -f "${APPIMAGE_NAME}.asc" ]] && echo "   🔐 Firma: $(basename "${APPIMAGE_NAME}.asc")"
    [[ -f "SHA256SUMS-APPIMAGE.txt" ]] && echo "   🔍 Checksum: SHA256SUMS-APPIMAGE.txt"
    echo ""
    echo "▶  Para ejecutar:"
    echo "   ./$(basename "$APPIMAGE_NAME")"
    echo ""
    echo "▶  Para instalar (opcional):"
    echo "   sudo mv $(basename "$APPIMAGE_NAME") /usr/local/bin/texstudio"
    echo ""
    echo "▶  Código fuente parcheado:"
    echo "   $BACKUP_DIR/src/"
else
    die "No se generó la AppImage correctamente."
fi
log "✅ Proceso completado."
