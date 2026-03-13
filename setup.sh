#!/usr/bin/env bash
# =============================================================================
# setup.sh — AIDMS Dashboard Workspace Setup
#
# 三層 Git 架構設定腳本
#   Layer 1 (Workspace):     aidms-dashboard/          ← 你現在在這裡
#   Layer 2a (Package):      ChartComponents/          ← @aidms/chart-components
#   Layer 2b (App):          DashboardApp/             ← React + Node.js (Express)
#
# 使用方式:
#   bash setup.sh              # clone/pull inner repos + 安裝依賴
#   bash setup.sh --install    # 同上（明確指定安裝）
#   bash setup.sh --dev        # 安裝依賴 + 啟動開發環境
# =============================================================================

set -euo pipefail

CHART_REPO="${AIDMS_CHART_REPO:-https://github.com/tomas41026175/aidms-chart-components.git}"
APP_REPO="${AIDMS_APP_REPO:-https://github.com/tomas41026175/aidms-dashboard-app.git}"
CHART_DIR="ChartComponents"
APP_DIR="DashboardApp"
DEV_MODE=false
INSTALL_DEPS=true

for arg in "$@"; do
  case $arg in
    --dev)     DEV_MODE=true ;;
    --install) INSTALL_DEPS=true ;;
    --no-install) INSTALL_DEPS=false ;;
    --help|-h)
      echo "用法: bash setup.sh [選項]"
      echo ""
      echo "  (無參數)     clone/pull inner repos + 安裝依賴"
      echo "  --dev        安裝依賴並啟動前端 + 後端開發環境"
      echo "  --no-install 只 clone/pull，不安裝依賴"
      echo ""
      echo "環境變數:"
      echo "  AIDMS_CHART_REPO   @aidms/chart-components repo URL"
      echo "  AIDMS_APP_REPO     Dashboard App repo URL"
      exit 0
      ;;
  esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# 檢測 Python 指令
detect_python() {
  if command -v python3 &>/dev/null; then echo "python3"
  elif command -v python &>/dev/null; then echo "python"
  else log_error "找不到 Python，請先安裝 Python 3.11+"; exit 1
  fi
}

WORKSPACE_DIR="$(pwd)"
PYTHON_CMD=$(detect_python)

echo ""
echo "============================================================"
echo "  AIDMS Dashboard Workspace Setup"
echo "  Workspace:  ${WORKSPACE_DIR}"
echo "  Python:     ${PYTHON_CMD}"
echo "============================================================"
echo ""

# ── clone / pull inner repos ──────────────────────────────────────────────

clone_or_pull() {
  local dir="$1" repo="$2" name="$3"

  if [[ -d "${dir}/.git" ]]; then
    log_info "更新 ${name}..."
    git -C "$dir" pull origin main
    log_success "${name} 已更新"
  else
    log_info "Clone ${name}..."
    # 保留已有的 .gitignore（本地建立的）
    local tmp_gitignore=""
    if [[ -f "${dir}/.gitignore" ]]; then
      tmp_gitignore=$(cat "${dir}/.gitignore")
    fi

    git clone --branch main "$repo" "${dir}_tmp"
    rsync -a --ignore-existing "${dir}_tmp/" "${dir}/"
    rm -rf "${dir}_tmp"

    # 恢復 .gitignore（如果 clone 沒帶）
    if [[ -n "$tmp_gitignore" && ! -f "${dir}/.gitignore" ]]; then
      echo "$tmp_gitignore" > "${dir}/.gitignore"
    fi

    log_success "${name} clone 完成"
  fi
}

clone_or_pull "$CHART_DIR" "$CHART_REPO" "@aidms/chart-components"
clone_or_pull "$APP_DIR"   "$APP_REPO"   "DashboardApp"

# ── 安裝依賴 ─────────────────────────────────────────────────────────────

if [[ "$INSTALL_DEPS" == true ]]; then
  echo ""
  log_info "安裝依賴..."

  # ChartComponents
  if [[ -f "${CHART_DIR}/package.json" ]]; then
    log_info "  ChartComponents pnpm install..."
    cd "$CHART_DIR" && pnpm install --silent && cd "$WORKSPACE_DIR"
    log_success "  ChartComponents 完成"
  fi

  # DashboardApp（單層結構：前後端共用同一 package.json，後端為 server.js）
  if [[ -f "${APP_DIR}/package.json" ]]; then
    log_info "  DashboardApp pnpm install..."
    cd "$APP_DIR" && pnpm install --silent && cd "$WORKSPACE_DIR"
    log_success "  DashboardApp 完成"
  fi
fi

# ── 開發模式 ─────────────────────────────────────────────────────────────

if [[ "$DEV_MODE" == true ]]; then
  echo ""
  log_info "啟動開發環境..."

  if [[ ! -f "${APP_DIR}/package.json" ]]; then
    log_error "${APP_DIR}/package.json 不存在，請先執行 bash setup.sh"
    exit 1
  fi
  if [[ ! -f "${APP_DIR}/server.js" ]]; then
    log_error "${APP_DIR}/server.js 不存在"
    exit 1
  fi

  # 後端背景執行（Node.js + Express）
  log_info "啟動後端 server.js（:3000）..."
  cd "$APP_DIR"
  node server.js &
  BACKEND_PID=$!
  cd "$WORKSPACE_DIR"

  trap "kill $BACKEND_PID 2>/dev/null; exit 0" INT TERM

  echo ""
  echo "  前端：http://localhost:5173"
  echo "  後端：http://localhost:3000"
  echo ""
  echo "  Ctrl+C 同時停止前後端"
  echo ""

  cd "$APP_DIR" && pnpm start
  wait $BACKEND_PID
fi

# ── 完成摘要 ─────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
log_success "Setup 完成"
echo ""
echo "  Repos:"
echo "    Workspace:   https://github.com/tomas41026175/aidms-dashboard"
echo "    ChartPkg:    https://github.com/tomas41026175/aidms-chart-components"
echo "    DashboardApp: https://github.com/tomas41026175/aidms-dashboard-app"
echo ""
echo "  啟動開發環境:"
echo "    bash setup.sh --dev"
echo "============================================================"
echo ""
