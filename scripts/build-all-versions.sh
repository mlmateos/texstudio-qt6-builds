#!/usr/bin/env bash
#===============================================================================
# build-all-versions.sh
# Compila todas las versiones de TeXstudio en orden
#===============================================================================
set -euo pipefail

VERSIONS=(
    "4.9.5"
    "4.9.6alpha1"
    "4.9.6alpha3"
    "4.9.6alpha4"
)

echo "═══════════════════════════════════════════════════"
echo "  COMPILANDO TODAS LAS VERSIONES DE TEXSTUDIO"
echo "═══════════════════════════════════════════════════"
echo ""
echo "Versiones a compilar: ${#VERSIONS[@]}"
for i in "${!VERSIONS[@]}"; do
    echo "  $((i+1)). ${VERSIONS[$i]}"
done
echo ""
echo "️  Tiempo estimado: ~2-3 horas"
echo "💾 Espacio requerido: ~5GB"
echo ""
read -p "¿Deseas continuar? (s/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    echo "❌ Cancelado por el usuario"
    exit 0
fi

START_TIME=$(date +%s)

for VER in "${VERSIONS[@]}"; do
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "  🔨 Compilando: TeXstudio $VER"
    echo "═══════════════════════════════════════════════════"
    echo "Hora de inicio: $(date '+%H:%M:%S')"
    echo ""
    
    VER_START=$(date +%s)
    
    # Ejecutar compilación
    ./build-texstudio-deb.sh --clean --branch "$VER" --poppler --sign --publish --yes
    
    VER_END=$(date +%s)
    VER_DURATION=$((VER_END - VER_START))
    
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "  ✅ Versión $VER completada"
    echo "  ⏱️  Tiempo: $((VER_DURATION / 60))m $((VER_DURATION % 60))s"
    echo "═══════════════════════════════════════════════════"
    echo ""
done

END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))

echo "═══════════════════════════════════════════════════"
echo "  🎉 TODAS LAS VERSIONES COMPILADAS"
echo "═══════════════════════════════════════════════════"
echo ""
echo "Total de versiones: ${#VERSIONS[@]}"
echo "Tiempo total: $((TOTAL_DURATION / 3600))h $(((TOTAL_DURATION % 3600) / 60))m"
echo ""
echo "📦 Releases en GitHub:"
echo "   https://github.com/mlmateos/texstudio-qt6-builds/releases"
echo ""
