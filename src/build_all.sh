#!/bin/bash
#
# Build pasls for multiple platforms
# Usage:
#   ./build_all.sh              # Build Linux + Windows targets (without SQLite)
#   ./build_all.sh --sqlite     # Build Linux + Windows targets (with SQLite)
#   ./build_all.sh all          # Build ALL targets including darwin
#   ./build_all.sh linux        # Build Linux targets only
#   ./build_all.sh windows      # Build Windows targets only
#   ./build_all.sh darwin       # Build macOS targets only (requires macOS or osxcross)
#
# Note: darwin cross-compilation requires either:
#   - Running on macOS natively
#   - osxcross toolchain installed (provides darwin linker)
#   - GitHub Actions macos-latest runner
#

LAZBUILD="${LAZBUILD:-lazbuild}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$SCRIPT_DIR/standard/pasls.lpi"
OUTDIR="$SCRIPT_DIR/../dist"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Build targets: name=os:cpu (name format: cpu-os)
declare -A TARGETS=(
    ["x86_64-linux"]="linux:x86_64"
    ["aarch64-linux"]="linux:aarch64"
    ["i386-win32"]="win32:i386"
    ["x86_64-win64"]="win64:x86_64"
    ["x86_64-darwin"]="darwin:x86_64"
    ["aarch64-darwin"]="darwin:aarch64"
)

# Group definitions
LINUX_TARGETS="x86_64-linux aarch64-linux"
WINDOWS_TARGETS="i386-win32 x86_64-win64"
DARWIN_TARGETS="x86_64-darwin aarch64-darwin"

SUCCESS_COUNT=0
FAIL_COUNT=0
FAILED_TARGETS=""
USE_SQLITE=0

build_target() {
    local name="$1"
    local target_info="${TARGETS[$name]}"

    if [ -z "$target_info" ]; then
        echo -e "${RED}Unknown target: $name${NC}"
        ((FAIL_COUNT++))
        return 1
    fi

    local os="${target_info%%:*}"
    local cpu="${target_info##*:}"
    local output_dir="$OUTDIR/$name"
    local exe_name="pasls"

    # Windows executables have .exe extension
    if [[ "$os" == win* ]]; then
        exe_name="pasls.exe"
    fi

    echo -e "${YELLOW}Building: $name (OS=$os, CPU=$cpu)${NC}"

    # Create output directory
    mkdir -p "$output_dir"

    # Common build options
    local common_opts="--os=$os --cpu=$cpu"

    # darwin requires --ws=nogui (Carbon LCL doesn't support 64-bit)
    if [ "$os" = "darwin" ]; then
        common_opts="$common_opts --ws=nogui"
    fi

    # Build sequence:
    # 1. lspprotocol.lpk (base protocol)
    # 2. lspserver.lpk (with USE_SQLITE if enabled)
    # 3. pasls.lpi with -d (don't recompile dependencies)

    # Step 1: Build lspprotocol.lpk
    if ! $LAZBUILD "$SCRIPT_DIR/protocol/lspprotocol.lpk" \
        $common_opts \
        > /tmp/build_pasls_$$.log 2>&1; then
        echo -e "${RED}  FAILED: lspprotocol.lpk${NC}"
        tail -20 /tmp/build_pasls_$$.log
        ((FAIL_COUNT++))
        FAILED_TARGETS="$FAILED_TARGETS $name"
        return 1
    fi

    # Step 2: Build lspserver.lpk (with USE_SQLITE if enabled)
    local server_opts=""
    if [ "$USE_SQLITE" -eq 1 ]; then
        server_opts="--opt=-dUSE_SQLITE"
    fi
    if ! $LAZBUILD "$SCRIPT_DIR/serverprotocol/lspserver.lpk" \
        $common_opts $server_opts \
        > /tmp/build_pasls_$$.log 2>&1; then
        echo -e "${RED}  FAILED: lspserver.lpk${NC}"
        tail -20 /tmp/build_pasls_$$.log
        ((FAIL_COUNT++))
        FAILED_TARGETS="$FAILED_TARGETS $name"
        return 1
    fi

    # Step 3: Build pasls.lpi (-d = don't recompile dependencies)
    if $LAZBUILD "$PROJECT" \
        -d \
        --build-mode=Release \
        $common_opts \
        > /tmp/build_pasls_$$.log 2>&1; then

        # Find and move the built executable
        local built_exe="$SCRIPT_DIR/standard/lib/$cpu-$os/$exe_name"
        if [ -f "$built_exe" ]; then
            mv "$built_exe" "$output_dir/"
            echo -e "${GREEN}  SUCCESS: $output_dir/$exe_name${NC}"
            ((SUCCESS_COUNT++))
            return 0
        else
            echo -e "${RED}  FAILED: Output not found at $built_exe${NC}"
            cat /tmp/build_pasls_$$.log
            ((FAIL_COUNT++))
            FAILED_TARGETS="$FAILED_TARGETS $name"
            return 1
        fi
    else
        echo -e "${RED}  FAILED: $name${NC}"
        echo "  Build log:"
        tail -20 /tmp/build_pasls_$$.log
        ((FAIL_COUNT++))
        FAILED_TARGETS="$FAILED_TARGETS $name"
        return 1
    fi
}

build_group() {
    local targets="$1"
    for target in $targets; do
        build_target "$target"
    done
}

print_summary() {
    echo ""
    echo "========================================"
    echo -e "Build Summary: ${GREEN}${SUCCESS_COUNT} succeeded${NC}, ${RED}${FAIL_COUNT} failed${NC}"
    if [ -n "$FAILED_TARGETS" ]; then
        echo -e "${RED}Failed targets:${FAILED_TARGETS}${NC}"
    fi
    echo "Output directory: $OUTDIR/"
    if [ "$USE_SQLITE" -eq 1 ]; then
        echo "SQLite support: ENABLED"
    else
        echo "SQLite support: DISABLED"
    fi
    echo "========================================"
}

show_help() {
    echo "Usage: $0 [OPTIONS] [TARGET...]"
    echo ""
    echo "Options:"
    echo "  --sqlite    Enable SQLite support (adds -dUSE_SQLITE)"
    echo "  --help      Show this help message"
    echo ""
    echo "Target groups:"
    echo "  (default)   Build Linux + Windows targets"
    echo "  all         Build ALL targets including darwin"
    echo "  linux       Build Linux targets (x86_64, aarch64)"
    echo "  windows     Build Windows targets (i386, x86_64)"
    echo "  darwin      Build macOS targets (requires macOS or osxcross)"
    echo ""
    echo "Individual targets:"
    echo "  x86_64-linux     Linux x86_64"
    echo "  aarch64-linux    Linux ARM64"
    echo "  i386-win32       Windows 32-bit"
    echo "  x86_64-win64     Windows 64-bit"
    echo "  x86_64-darwin    macOS Intel"
    echo "  aarch64-darwin   macOS Apple Silicon"
    echo ""
    echo "Examples:"
    echo "  $0                      # Build Linux + Windows (default)"
    echo "  $0 --sqlite             # Build Linux + Windows with SQLite"
    echo "  $0 all                  # Build ALL targets including darwin"
    echo "  $0 linux                # Build Linux targets only"
    echo "  $0 --sqlite x86_64-linux x86_64-win64"
    echo ""
    echo "Environment variables:"
    echo "  LAZBUILD    Path to lazbuild (default: lazbuild)"
}

# Check lazbuild
if ! command -v $LAZBUILD &> /dev/null; then
    echo -e "${RED}Error: lazbuild not found.${NC}"
    echo "Please install Lazarus or set LAZBUILD environment variable."
    echo "Example: LAZBUILD=/path/to/lazbuild $0"
    exit 1
fi

# Parse arguments
TARGETS_TO_BUILD=""
while [ $# -gt 0 ]; do
    case "$1" in
        --sqlite)
            USE_SQLITE=1
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        all)
            TARGETS_TO_BUILD="$LINUX_TARGETS $WINDOWS_TARGETS $DARWIN_TARGETS"
            shift
            ;;
        linux)
            TARGETS_TO_BUILD="$TARGETS_TO_BUILD $LINUX_TARGETS"
            shift
            ;;
        windows|win)
            TARGETS_TO_BUILD="$TARGETS_TO_BUILD $WINDOWS_TARGETS"
            shift
            ;;
        darwin|macos|osx)
            TARGETS_TO_BUILD="$TARGETS_TO_BUILD $DARWIN_TARGETS"
            shift
            ;;
        *)
            TARGETS_TO_BUILD="$TARGETS_TO_BUILD $1"
            shift
            ;;
    esac
done

# Default to Linux + Windows targets (darwin requires special toolchain)
if [ -z "$TARGETS_TO_BUILD" ]; then
    TARGETS_TO_BUILD="$LINUX_TARGETS $WINDOWS_TARGETS"
fi

echo "Pascal Language Server - Cross-Platform Build"
echo "=============================================="
if [ "$USE_SQLITE" -eq 1 ]; then
    echo "SQLite support: ENABLED"
else
    echo "SQLite support: DISABLED (default)"
fi
echo ""

# Build targets
for target in $TARGETS_TO_BUILD; do
    build_target "$target"
done

print_summary
exit $FAIL_COUNT
