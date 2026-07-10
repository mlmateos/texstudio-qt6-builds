#!/usr/bin/env bash
#===============================================================================
# build-texstudio-deb.sh (v1.3-Patched)
# Compila TeXstudio desde fuente, genera paquete .deb (Qt6 + Poppler),
# firma y publica en GitHub Releases junto con la AppImage
# v1.3: Añade parches para URLs de actualización y créditos, integra con APT repo
#===============================================================================
set -euo pipefail
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
PKG_REVISION="1"
MAX_RETRIES=3
RETRY_DELAY=5
APT_REPO_URL="https://mlmateos.github.io/texstudio-qt6-builds"
APT_REPO_GITHUB="https://github.com/mlmateos/texstudio-qt6-builds"
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
        --revision)   PKG_REVISION="$2"; shift 2 ;;
        --help|-h)
            cat << 'HELP'
Uso: ./build-texstudio-deb.sh [OPCIONES]

  --clean         Limpia todo antes de empezar
  --branch NAME   Rama o tag a compilar (ej: 4.9.5)
  --jobs N        Hilos para compilación
  --poppler       Habilita visor PDF interno (Poppler-Qt6)
  --sign          Firma el .deb con GPG
  --publish       Publica en GitHub Releases (misma release que AppImage)
  --gpg-key ID    ID de clave GPG para firmar
  --revision N    Revisión Debian (default: 1)
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
        if "$@"; then
            return 0
        fi
        if (( attempt >= MAX_RETRIES )); then
            return 1
        fi
        warn "⚠️  Intento $attempt falló. Reintentando en ${RETRY_DELAY}s..."
        sleep "$RETRY_DELAY"
        attempt=$((attempt + 1))
    done
}

curl_with_retry() {
    local description="$1"
    shift
    local attempt=1
    while true; do
        if curl --silent --fail --connect-timeout 15 --max-time 30 "$@"; then
            return 0
        fi
        if (( attempt >= MAX_RETRIES )); then
            return 1
        fi
        warn "⚠️  $description - intento $attempt falló. Reintentando en ${RETRY_DELAY}s..."
        sleep "$RETRY_DELAY"
        attempt=$((attempt + 1))
    done
}

#===============================================================================
# DEPENDENCIAS
#===============================================================================
header "🔧 VERIFICANDO DEPENDENCIAS"
log "Verificando herramientas..."
for cmd in cmake make git pkg-config wget dpkg-buildpackage dh fakeroot; do
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
    warn "💡 El .deb podría no funcionar en sistemas antiguos."
else
    log "✅ glibc ≥ 2.34 (compatible con Qt6)"
fi
#===============================================================================
# PREPARACIÓN & CLONADO (CON REINTENTOS)
#===============================================================================
header "📥 PREPARANDO CÓDIGO FUENTE"
PROJECT_DIR="$(pwd)/texstudio-deb"
BUILD_DIR="$PROJECT_DIR/build"

if [[ "$CLEAN_BUILD" == true ]]; then
    log "Limpiando build anterior..."
    rm -rf "$PROJECT_DIR"
fi

if [[ ! -d "$PROJECT_DIR/.git" ]]; then
    log "Clonando repositorio (rama: $BRANCH)..."
    if ! git_with_retry "git clone" git clone --branch "$BRANCH" --depth 100 "$REPO_URL" "$PROJECT_DIR"; then
        die "No se pudo clonar el repositorio tras $MAX_RETRIES intentos. Verifica tu conexión."
    fi
    cd "$PROJECT_DIR"
    if ! git_with_retry "git fetch --tags" git fetch --tags origin; then
        warn "⚠️  No se pudieron obtener tags tras $MAX_RETRIES intentos, continuando sin ellos..."
    fi
    cd - >/dev/null
else
    log "Actualizando repositorio..."
    cd "$PROJECT_DIR"
    git fetch --depth 100 origin "$BRANCH" 2>/dev/null || true
    
    if ! git_with_retry "git fetch --tags" git fetch --tags origin; then
        warn "⚠️  No se pudieron obtener tags, continuando con los existentes..."
    fi

    if git show-ref --tags --verify --quiet "refs/tags/$BRANCH" 2>/dev/null; then
        log "📌 Detectado TAG: $BRANCH"
        git checkout -f "$BRANCH" 2>/dev/null || git checkout -f "tags/$BRANCH"
        git reset --hard "$BRANCH"
    else
        log "📌 Detectada RAMA: $BRANCH"
        git checkout -f "$BRANCH"
        git reset --hard "origin/$BRANCH"
    fi
    cd - >/dev/null
fi

# Eliminar cualquier estructura debian/ que venga del upstream
rm -rf "$PROJECT_DIR/debian"

mkdir -p "$BUILD_DIR"
#===============================================================================
# DETECCIÓN / FORZADO DE VERSIÓN (idéntico al script de AppImage)
#===============================================================================
header "🏷️  DETECTANDO VERSIÓN"
if [[ -d "$PROJECT_DIR/.git" ]]; then
    VER_GIT=$(git -C "$PROJECT_DIR" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//') || VER_GIT=""
    if [[ -n "$VER_GIT" ]]; then
        log "📌 Forzando versión $VER_GIT..."
        CMAKE_VERSION=$(echo "$VER_GIT" | sed 's/[^0-9.]//g')
        log "   📌 CMake usará: $CMAKE_VERSION"
        log "   📌 App mostrará: $VER_GIT"
        sed -i "s|project(TeXstudio VERSION [0-9.]\+|project(TeXstudio VERSION $CMAKE_VERSION|g" "$PROJECT_DIR/CMakeLists.txt"
        sed -i "s|add_definitions(-DTEXSTUDIO_VERSION=\"[^\"]*\")|add_definitions(-DTEXSTUDIO_VERSION=\"$VER_GIT\")|g" "$PROJECT_DIR/CMakeLists.txt"
        if [[ -f "$PROJECT_DIR/src/utilsVersion.h" ]]; then
            sed -i "s|#define TXSVERSION \"[^\"]*\"|#define TXSVERSION \"$VER_GIT\"|g" "$PROJECT_DIR/src/utilsVersion.h"
        fi
        find "$PROJECT_DIR/src" -type f \( -name "*.h" -o -name "*.cpp" \) -exec \
            grep -l "TXSVERSION" {} + 2>/dev/null | xargs -r sed -i "s|TXSVERSION \"[^\"]*\"|TXSVERSION \"$VER_GIT\"|g" || true
    fi
fi

# Si es master, detectar último tag remoto (CON REINTENTOS)
if [[ "$BRANCH" == "master" && -z "${VER_GIT:-}" ]]; then
    log "🔍 Detectando último tag vía GitHub API..."
    LATEST_TAG=""
    if API_RESPONSE=$(curl_with_retry "GitHub API" "https://api.github.com/repos/texstudio-org/texstudio/tags"); then
        LATEST_TAG=$(echo "$API_RESPONSE" | grep -oP '"name":\s*"\K[0-9]+\.[0-9]+\.[0-9]+[a-zA-Z0-9]*' | head -n1)
    fi
    [[ -n "$LATEST_TAG" ]] && VER_GIT="$LATEST_TAG" || die "No se pudo detectar tag tras $MAX_RETRIES intentos. Usa --branch."
fi

RAW_VER="${VER_GIT:-4.9.5}"
VER=$(echo "$RAW_VER" | sed -E 's/alpha([0-9]+)/-alpha\1/; s/beta([0-9]+)/-beta\1/; s/rc([0-9]+)/-rc\1/')
DEB_VER=$(echo "$VER" | sed 's/-alpha/~alpha/g; s/-beta/~beta/g; s/-rc/~rc/g')
log "Versión final para .deb: ${DEB_VER}-${PKG_REVISION}"
#===============================================================================
# PARCHE: MODIFICAR URLs DE ACTUALIZACIÓN Y AÑADIR CRÉDITOS
#===============================================================================
header "🔧 APLICANDO PARCHE PERSONALIZADO"
log "Modificando URLs de actualización..."

# Parchear src/updatechecker.cpp
if [[ -f "$PROJECT_DIR/src/updatechecker.cpp" ]]; then
    # Cambiar URL de API de GitHub a nuestro update.json
    sed -i 's|https://api.github.com/repos/texstudio-org/texstudio/git/refs/tags|'"$APT_REPO_URL"'/pool/update.json|g' "$PROJECT_DIR/src/updatechecker.cpp"
    
    # Cambiar URLs de descarga
    sed -i 's|https://texstudio.org|'"$APT_REPO_URL"'|g' "$PROJECT_DIR/src/updatechecker.cpp"
    sed -i 's|https://github.com/texstudio-org/texstudio/releases|'"$APT_REPO_GITHUB"'/releases|g' "$PROJECT_DIR/src/updatechecker.cpp"
    
    log "✅ URLs de actualización modificadas en src/updatechecker.cpp"
else
    warn "⚠️  No se encontró src/updatechecker.cpp, omitiendo parche de URLs"
fi

# Añadir créditos en el diálogo About
log "Añadiendo créditos al diálogo About..."
ABOUT_FILE="$PROJECT_DIR/src/aboutdialog.cpp"
if [[ -f "$ABOUT_FILE" ]]; then
    # Buscar el texto "TeXstudio" y añadir créditos después
    if ! grep -q "Custom build with Qt6" "$ABOUT_FILE"; then
        # Crear texto de créditos en inglés
        CREDITS_TEXT='<p><b>TeXstudio Qt6 Build with Poppler<\/b><br>Custom build with Qt6 and Poppler support<br>Compiled by Manuel López Mateos<br><a href="https:\/\/github.com\/mlmateos\/texstudio-qt6-builds">https:\/\/github.com\/mlmateos\/texstudio-qt6-builds<\/a><\/p><p><i>This is an unofficial build. TeXstudio © Benito van der Zander, Jan Sundermeyer, Daniel Braun, Tim Hoffmann.<\/i><\/p>'
        
        # Insertar después de la primera mención de TeXstudio
        sed -i '/<h2>TeXstudio<\/h2>/a \        aboutText += "'"$CREDITS_TEXT"'";' "$ABOUT_FILE"
        
        log "✅ Créditos añadidos al diálogo About"
    else
        log "ℹ️  Créditos ya presentes, omitiendo"
    fi
else
    warn "⚠️  No se encontró src/aboutdialog.cpp, omitiendo créditos"
fi

#===============================================================================
# CREAR ESTRUCTURA DEBIAN
#===============================================================================
header "📦 GENERANDO ESTRUCTURA DEBIAN"
mkdir -p "$PROJECT_DIR/debian/source"

# debian/control
cat <<EOF > "$PROJECT_DIR/debian/control"
Source: texstudio
Section: editors
Priority: optional
Maintainer: Manuel Mateos <manuel@mateos.dev>
Build-Depends: debhelper-compat (= 13),
               cmake,
               qt6-base-dev,
               qt6-base-dev-tools,
               qt6-tools-dev,
               qt6-svg-dev,
               libpoppler-qt6-dev,
               libquazip-qt6-dev | libquazip1-qt6-dev,
               zlib1g-dev,
               libssl-dev,
               libhunspell-dev,
               pkg-config,
               qt6-tools-dev-tools
Standards-Version: 4.6.2
Homepage: https://www.texstudio.org/
Rules-Requires-Root: no

Package: texstudio
Architecture: any
Depends: \${shlibs:Depends}, \${misc:Depends}
Recommends: texlive-latex-base, texlive-binaries, texlive-latex-recommended
Suggests: texlive-full, biber, latexmk
Description: Integrated writing environment for creating LaTeX documents
 TeXstudio is an integrated writing environment for creating LaTeX documents.
 The goal is to provide a feature-rich editor with low system overhead.
 .
 Features include:
  * Syntax highlighting
  * Integrated LaTeX editor with auto-completion
  * Built-in PDF viewer with SyncTeX support (Poppler-Qt6)
  * Spell checking (Hunspell)
  * Live preview
  * Built on Qt6 for modern UI/UX
 .
 This is a custom build with Qt6 and Poppler support by Manuel López Mateos.
EOF

# debian/rules
cat <<'EOF' > "$PROJECT_DIR/debian/rules"
#!/usr/bin/make -f
export DH_VERBOSE = 1
export QT_SELECT = qt6

%:
	dh $@ --buildsystem=cmake

override_dh_auto_configure:
	dh_auto_configure -- \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DQT_VERSION=6 \
		-DTEXSTUDIO_BUILD_ADWAITA=ON \
		-DTEXSTUDIO_ENABLE_TESTS=OFF

override_dh_auto_test:
	# Tests deshabilitados para acelerar el build
EOF
chmod +x "$PROJECT_DIR/debian/rules"

# debian/changelog
FECHA=$(date -R)
cat <<EOF > "$PROJECT_DIR/debian/changelog"
texstudio (${DEB_VER}-${PKG_REVISION}) unstable; urgency=medium

  * Compiled from upstream source tag ${VER_GIT:-$RAW_VER}.
  * Built with Qt6 and Poppler-Qt6 for PDF preview.
  * Custom build with patched update URLs.

 -- Manuel Mateos <manuel@mateos.dev>  ${FECHA}
EOF

# debian/source/format
echo "3.0 (quilt)" > "$PROJECT_DIR/debian/source/format"

# debian/copyright
cat <<'EOF' > "$PROJECT_DIR/debian/copyright"
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: texstudio
Upstream-Contact: https://github.com/texstudio-org/texstudio
Source: https://github.com/texstudio-org/texstudio

Files: *
Copyright: 2003-2024 TeXstudio developers
License: GPL-3+
Comment: Custom build with Qt6 and Poppler by Manuel López Mateos.
EOF

log "✅ Estructura debian/ creada."
#===============================================================================
# COMPILACIÓN DEL .DEB
#===============================================================================
header "🔨 COMPILANDO PAQUETE .DEB"
cd "$PROJECT_DIR"
log "Compilando con $JOBS hilos..."

# Siempre usar -us -uc para que dpkg-buildpackage no intente firmar
# La firma del .deb la hace el script después con gpg directamente
BUILD_ARGS=(-b -us -uc -j"$JOBS")

if [[ "$SIGN" == true ]]; then
    log "🔐 Modo firmado activado (firma posterior con gpg)"
fi

dpkg-buildpackage "${BUILD_ARGS[@]}" 2>&1 | tee ../build-deb.log || die "Compilación fallida. Revisa ../build-deb.log"

cd ..
#===============================================================================
# LOCALIZAR Y RENOMBRAR ARCHIVOS
#===============================================================================
header "📦 PROCESANDO ARCHIVOS"

DEB_FILE=$(ls texstudio_${DEB_VER}-${PKG_REVISION}_*.deb 2>/dev/null | head -n1)
[[ -z "$DEB_FILE" || ! -f "$DEB_FILE" ]] && die "No se generó el archivo .deb"

DEB_FINAL="texstudio-${VER}-qt6-$(dpkg --print-architecture).deb"
if [[ "$DEB_FILE" != "$DEB_FINAL" ]]; then
    mv -f "$DEB_FILE" "$DEB_FINAL"
    log "Renombrado: $DEB_FILE → $DEB_FINAL"
fi

sha256sum "$DEB_FINAL" > SHA256SUMS-DEB.txt
cat SHA256SUMS-DEB.txt

log "Archivos generados:"
ls -lh texstudio_${DEB_VER}-${PKG_REVISION}_* 2>/dev/null | awk '{print "   " $NF " (" $5 ")"}'
ls -lh "$DEB_FINAL" 2>/dev/null | awk '{print "   " $NF " (" $5 ")"}'
#===============================================================================
# FIRMADO GPG DEL .DEB
#===============================================================================
if [[ "$SIGN" == true ]]; then
    header "🔐 FIRMANDO CON GPG"
    [[ -z "$GPG_KEY" ]] && GPG_KEY=$(gpg --list-secret-keys --keyid-format long | grep "^sec" | head -n1 | awk '{print $2}' | cut -d'/' -f2)
    log "Usando clave GPG: $GPG_KEY"
    set +e
    gpg --default-key "$GPG_KEY" --detach-sign --armor "$DEB_FINAL"
    set -e
    [[ -f "${DEB_FINAL}.asc" ]] && log "✅ Firma generada: ${DEB_FINAL}.asc"
fi
#===============================================================================
# PUBLICACIÓN EN GITHUB (CON SMART-LATEST Y REINTENTOS)
#===============================================================================
if [[ "$PUBLISH" == true ]]; then
    header "🌐 PUBLICANDO EN GITHUB RELEASES"
    if ! gh auth status >/dev/null 2>&1; then
        die "No autenticado en GitHub CLI. Ejecuta 'gh auth login' primero."
    fi

    FULL_REPO="${GITHUB_USER}/${REPO_NAME}"
    UPLOAD_FILES=("$DEB_FINAL" "SHA256SUMS-DEB.txt")
    [[ -f "${DEB_FINAL}.asc" ]] && UPLOAD_FILES+=("${DEB_FINAL}.asc")

    IS_PRERELEASE=false
    if [[ "$VER" == *alpha* || "$VER" == *beta* || "$VER" == *rc* ]]; then
        IS_PRERELEASE=true
    fi

    # Limpieza de assets antiguos con reintentos
    log "🧹 Limpiando archivos .deb de versiones anteriores..."
    EXISTING_ASSETS=$(gh release view "v${VER}" --repo "$FULL_REPO" --json assets --jq '.assets[].name' 2>/dev/null || echo "")
    for ASSET in $EXISTING_ASSETS; do
        KEEP=false
        if [[ "$ASSET" == *"-${VER}-"* ]] || [[ "$ASSET" == *"-v${VER}-"* ]]; then
            KEEP=true
        fi
        if [[ "$ASSET" == "SHA256SUMS-DEB.txt" ]]; then
            KEEP=true
        fi
        if [[ "$KEEP" == false ]]; then
            log "   🗑️  Eliminando: $ASSET"
            RETRY_COUNT=0
            SUCCESS=false
            while [[ $RETRY_COUNT -lt $MAX_RETRIES && "$SUCCESS" == false ]]; do
                if gh release delete-asset "v${VER}" "$ASSET" --repo "$FULL_REPO" --yes >/dev/null 2>&1; then
                    SUCCESS=true
                    log "      ✅ Eliminado exitosamente"
                else
                    RETRY_COUNT=$((RETRY_COUNT + 1))
                    if [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; then
                        warn "      ⚠️  Intento $RETRY_COUNT falló, reintentando en 2s..."
                        sleep 2
                    else
                        warn "      ❌ No se pudo eliminar después de $MAX_RETRIES intentos: $ASSET"
                    fi
                fi
            done
        fi
    done

    # Verificar si la release ya existe (detección mejorada)
    RELEASE_EXISTS=false
    if gh release view "v${VER}" --repo "$FULL_REPO" >/dev/null 2>&1; then
        RELEASE_EXISTS=true
        log "✅ Release 'v${VER}' detectada en GitHub"
    else
        # Método alternativo: buscar en la lista de releases
        if gh release list --repo "$FULL_REPO" 2>/dev/null | grep -q "^v${VER}[[:space:]]"; then
            RELEASE_EXISTS=true
            log "✅ Release 'v${VER}' detectada (método alternativo)"
        else
            # Método alternativo 2: verificar si el tag existe
            if git ls-remote --tags "$REPO_URL" 2>/dev/null | grep -q "refs/tags/v${VER}$"; then
                RELEASE_EXISTS=true
                log "✅ Release 'v${VER}' detectada (tag existe)"
            fi
        fi
    fi

    if [[ "$RELEASE_EXISTS" == true ]]; then
        log "⚠️  La release 'v${VER}' YA EXISTE en $FULL_REPO."
        read -r -p "¿Deseas AÑADIR el .deb a esta release existente? (y/N) " CONFIRM_UPDATE
        if [[ "$CONFIRM_UPDATE" =~ ^[Yy]$ ]]; then
            gh release upload "v${VER}" --clobber --repo "$FULL_REPO" "${UPLOAD_FILES[@]}"
            gh release edit "v${VER}" --repo "$FULL_REPO" --title "TeXstudio ${VER} (Qt6 + Poppler)"
            log "✅ .deb AÑADIDO a la release existente"
            log "🔗 https://github.com/$FULL_REPO/releases/tag/v${VER}"
        else
            log "🛑 Publicación cancelada por el usuario."
            exit 0
        fi
    else
        log "✨ Es una NUEVA versión: v${VER}."
        read -r -p "¿Deseas CREAR la release 'v${VER}' con el .deb? (y/N) " CONFIRM_CREATE
        if [[ "$CONFIRM_CREATE" =~ ^[Yy]$ ]]; then
            CREATE_ARGS=(
                "v${VER}"
                --repo "$FULL_REPO"
                --title "TeXstudio ${VER} (Qt6 + Poppler)"
                --notes "Debian package (.deb) compiled from source. Built-in PDF viewer with native SyncTeX support. Qt6."
            )
            if [[ "$IS_PRERELEASE" == true ]]; then
                CREATE_ARGS+=(--prerelease)
                log "📋 Release marcada como PRE-RELEASE ($VER)"
            else
                log "✅ Release marcada como STABLE ($VER)"
            fi
            gh release create "${CREATE_ARGS[@]}" "${UPLOAD_FILES[@]}"
            if [[ "$IS_PRERELEASE" == false ]]; then
                gh release edit "v${VER}" --repo "$FULL_REPO" --latest
                log "✅ Release PUBLICADA y marcada como Latest"
            else
                log "✅ Release PUBLICADA (pre-release, no marcada como Latest)"
            fi
            log "🔗 https://github.com/$FULL_REPO/releases/tag/v${VER}"
        else
            log "📦 Publicación cancelada por el usuario."
            exit 0
        fi
    fi

    # Verificación post-publicación
    log "🔍 Verificando publicación..."
    sleep 2
    FINAL_ASSETS=$(gh release view "v${VER}" --repo "$FULL_REPO" --json assets --jq '.assets[].name' 2>/dev/null || echo "")
    log "📦 Assets finales en la release:"
    for ASSET in $FINAL_ASSETS; do
        echo "   ✅ $ASSET"
    done
fi
#===============================================================================
# INTEGRACIÓN CON REPOSITORIO APT
#===============================================================================
header "📦 INTEGRANDO CON REPOSITORIO APT"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APT_REPO_DIR="$REPO_ROOT"

log "Copiando archivos al repositorio APT..."
cd "$APT_REPO_DIR"

# Cambiar a rama apt-repo
git checkout apt-repo 2>/dev/null || die "No se pudo cambiar a rama apt-repo"

# Copiar archivos a pool/
cp "$REPO_ROOT/scripts/$DEB_FINAL" pool/
[[ -f "$REPO_ROOT/scripts/${DEB_FINAL}.asc" ]] && cp "$REPO_ROOT/scripts/${DEB_FINAL}.asc" pool/

# Crear update.json para verificación de actualizaciones
log "Creando update.json..."
cat > pool/update.json << EOF
{
  "version": "$VER",
  "download_url": "$APT_REPO_GITHUB/releases",
  "release_notes": "TeXstudio $VER with Qt6 and Poppler support"
}
EOF

# Actualizar índice Packages
log "Actualizando índice Packages..."
dpkg-scanpackages pool /dev/null | gzip -9c > pool/Packages.gz
dpkg-scanpackages pool /dev/null > pool/Packages

# Commit y push
git add -f pool/
git commit -m "Add TeXstudio $VER to APT repository" || log "ℹ️  No hay cambios para commitear"
git push origin apt-repo

# Volver a master
git checkout master

log "✅ Archivos añadidos al repositorio APT"
log "🔗 URL: $APT_REPO_URL/pool/$DEB_FINAL"

#===============================================================================
# RESULTADO FINAL
#===============================================================================
header "🎉 RESULTADO FINAL"

# Buscar el .deb en scripts/ (donde realmente está)
DEB_PATH="$REPO_ROOT/scripts/$DEB_FINAL"

if [[ -f "$DEB_PATH" ]]; then
    log "¡ÉXITO! Paquete .deb listo:"
    echo "   📦 $(basename "$DEB_FINAL")"
    echo "   📍 $DEB_PATH"
    echo "   🔧 Tamaño: $(du -h "$DEB_PATH" | cut -f1)"
    [[ -f "${DEB_PATH}.asc" ]] && echo "   🔐 Firma: $(basename "${DEB_FINAL}.asc")"
    [[ -f "$REPO_ROOT/scripts/SHA256SUMS-DEB.txt" ]] && echo "   🔍 Checksum: SHA256SUMS-DEB.txt"
    echo ""
    echo "▶  Para instalar desde APT:"
    echo "   sudo apt update && sudo apt install texstudio"
    echo ""
    echo "▶  Para instalar manualmente:"
    echo "   sudo apt install $DEB_PATH"
    echo ""
    echo "▶  Para desinstalar:"
    echo "   sudo apt remove texstudio"
    echo ""
    echo "▶  Repositorio APT:"
    echo "   $APT_REPO_URL"
else
    die "No se generó el archivo .deb correctamente en $DEB_PATH"
fi
log "✅ Proceso completado."
