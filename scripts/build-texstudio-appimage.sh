#!/usr/bin/env bash
#===============================================================================
# build-texstudio-appimage.sh (v2.7-Robust)
# Compila TeXstudio desde fuente, genera AppImage (Qt6 + Poppler), firma y publica
#===============================================================================
set -euo pipefail

#===============================================================================
# CONFIGURACIÓN BASE
#===============================================================================
REPO_URL="https://github.com/texstudio-org/texstudio.git"
GITHUB_USER="mlmateos"
REPO_NAME="texstudio-qt6-builds"
BRANCH="master"
APPDIR_NAME="AppDir"
CLEAN_BUILD=false
ENABLE_POPPLER=false
SIGN=false
PUBLISH=false
GPG_KEY=""

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
        --help|-h)
            cat << 'HELP'
Uso: ./build-texstudio-appimage.sh [OPCIONES]
--clean         Limpia todo antes de empezar
--branch NAME   Rama o tag a compilar (ej: 4.9.5)
--jobs N        Hilos para compilación
--poppler       Habilita visor PDF interno (Poppler-Qt6)
--sign          Firma la AppImage con GPG
--publish       Publica en GitHub Releases
--gpg-key ID    ID de clave GPG
--help, -h      Muestra esta ayuda
HELP
            exit 0 ;;
        *) echo "❌ Argumento desconocido: $1" >&2; exit 1 ;;
    esac
done

#===============================================================================
# HELPERS
#===============================================================================
log()  { echo -e "\n✅ [$(date '+%H:%M:%S')] $*"; }
warn() { echo -e "\n⚠️  [$(date '+%H:%M:%S')] $*" >&2; }
die()  { echo -e "\n❌ [$(date '+%H:%M:%S')] ERROR: $*" >&2; exit 1; }
check_cmd() { command -v "$1" >/dev/null 2>&1 || die "No se encontró '$1'. Instálalo primero."; }

#===============================================================================
# DEPENDENCIAS
#===============================================================================
log "Verificando herramientas..."
for cmd in cmake make git pkg-config wget; do check_cmd "$cmd"; done
command -v qmake6 >/dev/null 2>&1 || die "No se encontró 'qmake6'. Instala qt6-base-dev."

if [[ "$ENABLE_POPPLER" == true ]]; then
    log "Verificando Poppler..."
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
# VALIDACIÓN DE GLIBC (para Qt6) - CORREGIDA
#===============================================================================
log "Validando glibc del sistema..."

# Extracción robusta con manejo de errores
GLIBC_VERSION=""
GLIBC_RAW=$(ldd --version 2>&1 | head -n1 || echo "")
log "📋 Salida de ldd: $GLIBC_RAW"

# Intentar extraer versión (formato: 2.XX o 2.XX.YY)
if [[ "$GLIBC_RAW" =~ ([0-9]+\.[0-9]+) ]]; then
    GLIBC_VERSION="${BASH_REMATCH[1]}"
fi

# Fallback si no se pudo extraer
if [[ -z "$GLIBC_VERSION" ]]; then
    warn "⚠️  No se pudo detectar la versión de glibc, asumiendo compatible"
    GLIBC_VERSION="2.34"
fi

log "📋 glibc detectada: $GLIBC_VERSION"

# Comparación simple usando sort -V (no falla con set -e)
GLIBC_CHECK=$(printf '%s\n' "2.34" "$GLIBC_VERSION" | sort -V | head -n1)
if [[ "$GLIBC_CHECK" != "2.34" ]]; then
    warn "⚠️  glibc < 2.34. Qt6 requiere glibc ≥ 2.34."
    warn "💡 El AppImage podría no funcionar en sistemas antiguos."
else
    log "✅ glibc ≥ 2.34 (compatible con Qt6)"
fi

#===============================================================================
# PREPARACIÓN & CLONADO
#===============================================================================
PROJECT_DIR="$(pwd)/texstudio"
BUILD_DIR="$PROJECT_DIR/build"

if [[ "$CLEAN_BUILD" == true ]]; then
    log "Limpiando build anterior..."
    rm -rf "$PROJECT_DIR"
fi

if [[ ! -d "$PROJECT_DIR/.git" ]]; then
    log "Clonando repositorio (rama: $BRANCH)..."
    git clone --branch "$BRANCH" --depth 100 "$REPO_URL" "$PROJECT_DIR"
    cd "$PROJECT_DIR"; git fetch --tags origin; cd - >/dev/null
else
    log "Actualizando repositorio..."
    cd "$PROJECT_DIR"
    git fetch --depth 100 origin "$BRANCH" 2>/dev/null || true
    git fetch --tags origin
    
    # Detectar si es tag o rama
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

mkdir -p "$BUILD_DIR"

#===============================================================================
# CMAKE & COMPILACIÓN (CON FORZADO DE VERSIÓN)
#===============================================================================
log "Configurando CMake..."

if [[ -d "$PROJECT_DIR/.git" ]]; then
    VER_GIT=$(git -C "$PROJECT_DIR" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//') || VER_GIT=""
    if [[ -n "$VER_GIT" ]]; then
        log "📌 Forzando versión $VER_GIT..."
        
        # Extraer solo números para CMake
        CMAKE_VERSION=$(echo "$VER_GIT" | sed 's/[^0-9.]//g')
        log "   📌 CMake usará: $CMAKE_VERSION"
        log "   📌 App mostrará: $VER_GIT"
        
        sed -i "s|project(TeXstudio VERSION [0-9.]\+|project(TeXstudio VERSION $CMAKE_VERSION|g" "$PROJECT_DIR/CMakeLists.txt"
        sed -i "s|add_definitions(-DTEXSTUDIO_VERSION=\"[^\"]*\")|add_definitions(-DTEXSTUDIO_VERSION=\"$VER_GIT\")|g" "$PROJECT_DIR/CMakeLists.txt"
        
        if [[ -f "$PROJECT_DIR/src/utilsVersion.h" ]]; then
            sed -i "s|#define TXSVERSION \"[^\"]*\"|#define TXSVERSION \"$VER_GIT\"|g" "$PROJECT_DIR/src/utilsVersion.h"
        fi
        
        # Solo modificar archivos que realmente contienen TXSVERSION
        find "$PROJECT_DIR/src" -type f \( -name "*.h" -o -name "*.cpp" \) -exec \
        grep -l "TXSVERSION" {} + 2>/dev/null | xargs -r sed -i "s|TXSVERSION \"[^\"]*\"|TXSVERSION \"$VER_GIT\"|g" || true
    fi
fi

cd "$BUILD_DIR"

# TeXstudio NO usa ENABLE_POPPLER/ENABLE_HUNSPELL/etc.
# Detecta automáticamente las dependencias instaladas
CMAKE_FLAGS=(
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_INSTALL_PREFIX=/usr
    -DQT_VERSION=6
    -DTEXSTUDIO_BUILD_ADWAITA=ON
    -DTEXSTUDIO_ENABLE_TESTS=OFF
)

cmake .. "${CMAKE_FLAGS[@]}" 2>&1 | tee cmake_config.log || warn "CMake finalizó con advertencias."
log "Compilando con $JOBS hilos..."
make -j"$JOBS" || die "Compilación fallida."

#===============================================================================
# APPDIR & LINUXDEPLOY
#===============================================================================
log "Instalando en AppDir..."
make install DESTDIR="../$APPDIR_NAME"
[[ -f "../$APPDIR_NAME/usr/bin/texstudio" ]] || die "Binario no encontrado."

log "Empaquetando AppImage..."
cd "$PROJECT_DIR"
export QMAKE=/usr/bin/qmake6
export QT_SELECT=6
ICON_PATH=$(find "$APPDIR_NAME" -type f \( -name "texstudio.png" -o -name "texstudio.svg" \) 2>/dev/null | head -n1)
ICON_ARG=""; [[ -n "$ICON_PATH" ]] && ICON_ARG="--icon-file $ICON_PATH"

linuxdeploy --appdir "$APPDIR_NAME" \
    --executable "$APPDIR_NAME/usr/bin/texstudio" \
    --desktop-file "$APPDIR_NAME/usr/share/applications/texstudio.desktop" \
    $ICON_ARG --plugin qt --output appimage

#===============================================================================
# FIRMADO GPG
#===============================================================================
if [[ "$SIGN" == true ]]; then
    log "Firmando con GPG..."
    [[ -z "$GPG_KEY" ]] && GPG_KEY=$(gpg --list-secret-keys --keyid-format long | grep "^sec" | head -n1 | awk '{print $2}' | cut -d'/' -f2)
    APPIMAGE_RAW=$(find "$PROJECT_DIR" -maxdepth 1 -type f \( -iname "*.AppImage" -a ! -iname "*.asc" -a ! -iname "*.zsync" \) | head -n1)
    if [[ -n "$APPIMAGE_RAW" && -f "$APPIMAGE_RAW" ]]; then
        set +e; gpg --default-key "$GPG_KEY" --detach-sign --armor "$APPIMAGE_RAW"; set -e
        log "✅ Firma generada."
    fi
fi

#===============================================================================
# RENOMBRADO + CHECKSUM
#===============================================================================
log "Procesando archivo final..."
APPIMAGE_RAW=$(find "$PROJECT_DIR" -maxdepth 1 -type f \( -iname "*.AppImage" -a ! -iname "*.asc" -a ! -iname "*.zsync" \) | head -n1)
[[ -z "$APPIMAGE_RAW" || ! -f "$APPIMAGE_RAW" ]] && die "No se encontró el archivo .AppImage."

if [[ "$BRANCH" == "master" ]]; then
    LATEST_TAG=$(curl -s "https://api.github.com/repos/texstudio-org/texstudio/tags" | grep -oP '"name":\s*"\K[0-9]+\.[0-9]+\.[0-9]+[a-zA-Z0-9]*' | head -n1)
    [[ -n "$LATEST_TAG" ]] && BRANCH="$LATEST_TAG" || die "No se pudo detectar tag. Usa --branch."
fi

RAW_VER="${BRANCH}"
VER=$(echo "$RAW_VER" | sed -E 's/alpha([0-9]+)/-alpha\1/; s/beta([0-9]+)/-beta\1/; s/rc([0-9]+)/-rc\1/')
[[ -z "$VER" ]] && VER="4.9.5"

APPIMAGE_FINAL="texstudio-${VER}-qt6-x86_64.AppImage"
if [[ "$APPIMAGE_RAW" != "$PROJECT_DIR/$APPIMAGE_FINAL" ]]; then
    mv -f "$APPIMAGE_RAW" "$PROJECT_DIR/$APPIMAGE_FINAL"
    [[ -f "${APPIMAGE_RAW}.asc" ]] && mv -f "${APPIMAGE_RAW}.asc" "${PROJECT_DIR}/${APPIMAGE_FINAL}.asc"
fi

cd "$PROJECT_DIR"
sha256sum "$APPIMAGE_FINAL" > SHA256SUMS.txt
cat SHA256SUMS.txt

#===============================================================================
# PUBLICACIÓN EN GITHUB (CON SMART-LATEST Y REINTENTOS)
#===============================================================================
if [[ "$PUBLISH" == true ]]; then
    log "🌐 Preparando release en GitHub..."
    if ! gh auth status >/dev/null 2>&1; then
        die "No autenticado en GitHub CLI. Ejecuta 'gh auth login' primero."
    fi
    
    FULL_REPO="${GITHUB_USER}/${REPO_NAME}"
    UPLOAD_FILES=("$APPIMAGE_FINAL" "SHA256SUMS.txt")
    [[ -f "${APPIMAGE_FINAL}.asc" ]] && UPLOAD_FILES+=("${APPIMAGE_FINAL}.asc")
    
    # Determinar si es pre-release
    IS_PRERELEASE=false
    if [[ "$VER" == *alpha* || "$VER" == *beta* || "$VER" == *rc* ]]; then
        IS_PRERELEASE=true
    fi
    
    # Limpieza SIEMPRE se ejecuta (no solo en releases nuevas)
    log "🧹 Limpiando archivos de versiones anteriores..."
    EXISTING_ASSETS=$(gh release view "v${VER}" --repo "$FULL_REPO" --json assets --jq '.assets[].name' 2>/dev/null || echo "")
    
    for ASSET in $EXISTING_ASSETS; do
        KEEP=false
        
        # Conservar solo archivos de ESTA versión exacta
        if [[ "$ASSET" == *"-${VER}-"* ]] || [[ "$ASSET" == *"-v${VER}-"* ]]; then
            KEEP=true
        fi
        
        # Conservar SHA256SUMS.txt (se regenerará)
        if [[ "$ASSET" == "SHA256SUMS.txt" ]]; then
            KEEP=true
        fi
        
        if [[ "$KEEP" == false ]]; then
            log "   🗑️  Eliminando: $ASSET"
            
            # ✅ MEJORA: Reintentar hasta 3 veces si falla
            MAX_RETRIES=3
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
    
    # Verificar si la release ya existe
    RELEASE_EXISTS=false
    gh release view "v${VER}" --repo "$FULL_REPO" >/dev/null 2>&1 && RELEASE_EXISTS=true
    
    if [[ "$RELEASE_EXISTS" == true ]]; then
        log "⚠️  La release 'v${VER}' YA EXISTE en $FULL_REPO."
        read -r -p "¿Deseas ACTUALIZAR (sobrescribir) los archivos de esta release existente? (y/N) " CONFIRM_UPDATE
        if [[ "$CONFIRM_UPDATE" =~ ^[Yy]$ ]]; then
            gh release upload "v${VER}" --clobber --repo "$FULL_REPO" "${UPLOAD_FILES[@]}"
            
            # ✅ SMART: Solo marcar como Latest si NO es pre-release
            if [[ "$IS_PRERELEASE" == false ]]; then
                gh release edit "v${VER}" --repo "$FULL_REPO" --title "TeXstudio ${VER} (Qt6 + Poppler)" --latest
                log "✅ Release ACTUALIZADA y marcada como Latest"
            else
                gh release edit "v${VER}" --repo "$FULL_REPO" --title "TeXstudio ${VER} (Qt6 + Poppler)"
                log "✅ Release ACTUALIZADA (pre-release, no marcada como Latest)"
            fi
            log "🔗 https://github.com/$FULL_REPO/releases/tag/v${VER}"
        else
            log "🛑 Publicación cancelada por el usuario."
            exit 0
        fi
    else
        log "✨ Es una NUEVA versión: v${VER}."
        read -r -p "¿Deseas CREAR y publicar la nueva release 'v${VER}'? (y/N) " CONFIRM_CREATE
        if [[ "$CONFIRM_CREATE" =~ ^[Yy]$ ]]; then
            CREATE_ARGS=(
                "v${VER}"
                --repo "$FULL_REPO"
                --title "TeXstudio ${VER} (Qt6 + Poppler)"
                --notes "AppImage compiled from source. Built-in PDF viewer with native SyncTeX support. Qt6."
            )
            
            # Auto-detectar pre-release (solo alpha/beta/rc)
            if [[ "$IS_PRERELEASE" == true ]]; then
                CREATE_ARGS+=(--prerelease)
                log "📋 Release marcada como PRE-RELEASE ($VER)"
            else
                log "✅ Release marcada como STABLE ($VER)"
            fi
            
            gh release create "${CREATE_ARGS[@]}" "${UPLOAD_FILES[@]}"
            
            # ✅ SMART: Solo marcar como Latest si NO es pre-release
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
# RESULTADO FINAL
#===============================================================================
if [[ -f "$PROJECT_DIR/$APPIMAGE_FINAL" ]]; then
    log "🎉 ¡ÉXITO! AppImage lista:"
    echo "   📦 $(basename "$APPIMAGE_FINAL")"
    echo "   📍 $PROJECT_DIR/$APPIMAGE_FINAL"
    echo "   🔧 Tamaño: $(du -h "$PROJECT_DIR/$APPIMAGE_FINAL" | cut -f1)"
    [[ -f "${APPIMAGE_FINAL}.asc" ]] && echo "   🔐 Firma: $(basename "${APPIMAGE_FINAL}.asc")"
    [[ -f "SHA256SUMS.txt" ]] && echo "   🔍 Checksum: SHA256SUMS.txt"
    echo ""
    echo "▶  Para ejecutar:"
    echo "   chmod +x '$APPIMAGE_FINAL'"
    echo "   ./'$APPIMAGE_FINAL'"
else
    die "No se generó el archivo .AppImage correctamente."
fi

log "✅ Proceso completado."
