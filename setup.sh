#!/usr/bin/env bash
# =============================================================================
# setup.sh — AIDMS Dashboard Workspace Setup
#
# 雙層架構設定腳本
#   Layer 1 (Workspace): aidms-dashboard/  ← 你現在在這裡
#   Layer 2a (Package):  ChartComponents/  ← @aidms/chart-components
#   Layer 2b (App):      DashboardApp/     ← React + FastAPI
#
# 使用方式:
#   bash setup.sh           # 安裝依賴
#   bash setup.sh --dev     # 安裝依賴 + 啟動開發環境
# =============================================================================

set -euo pipefail

DEV_MODE=false

for arg in "$@"; do
  case $arg in
    --dev) DEV_MODE=true ;;
    --help|-h)
      echo "用法: bash setup.sh [--dev]"
      echo ""
      echo "  (無參數)  安裝所有依賴"
      echo "  --dev     安裝依賴並啟動前端 + 後端開發環境"
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

# 檢測 Python 指令（Mac: python3, Windows: python）
detect_python() {
  if command -v python3 &>/dev/null; then
    echo "python3"
  elif command -v python &>/dev/null; then
    echo "python"
  else
    log_error "找不到 Python，請先安裝 Python 3.11+"
    exit 1
  fi
}

WORKSPACE_DIR="$(pwd)"
PYTHON_CMD=$(detect_python)

echo ""
echo "============================================================"
echo "  AIDMS Dashboard Workspace Setup"
echo "  Python: ${PYTHON_CMD}"
echo "============================================================"
echo ""

# ── ChartComponents ────────────────────────────────────────────────────────
if [[ -f "ChartComponents/package.json" ]]; then
  log_info "安裝 ChartComponents 依賴..."
  cd ChartComponents && npm install && cd "$WORKSPACE_DIR"
  log_success "ChartComponents 依賴安裝完成"
else
  log_warn "ChartComponents/package.json 不存在，跳過"
fi

# ── DashboardApp Frontend ──────────────────────────────────────────────────
if [[ -f "DashboardApp/frontend/package.json" ]]; then
  log_info "安裝 DashboardApp frontend 依賴..."
  cd DashboardApp/frontend && npm install && cd "$WORKSPACE_DIR"
  log_success "Frontend 依賴安裝完成"
else
  log_warn "DashboardApp/frontend/package.json 不存在，跳過"
fi

# ── DashboardApp Backend ───────────────────────────────────────────────────
if [[ -f "DashboardApp/backend/requirements.txt" ]]; then
  log_info "建立 Python 虛擬環境並安裝依賴..."
  cd DashboardApp/backend

  if [[ ! -d ".venv" ]]; then
    "$PYTHON_CMD" -m venv .venv
    log_success "虛擬環境建立完成"
  fi

  # 啟動虛擬環境
  if [[ -f ".venv/bin/activate" ]]; then
    # Mac / Linux
    source .venv/bin/activate
  elif [[ -f ".venv/Scripts/activate" ]]; then
    # Windows (Git Bash)
    source .venv/Scripts/activate
  fi

  pip install -r requirements.txt -q
  log_success "Python 依賴安裝完成"
  cd "$WORKSPACE_DIR"
else
  log_warn "DashboardApp/backend/requirements.txt 不存在，跳過"
fi

echo ""
log_success "所有依賴安裝完成"

# ── 開發模式：啟動前端 + 後端 ─────────────────────────────────────────────
if [[ "$DEV_MODE" == true ]]; then
  echo ""
  log_info "啟動開發環境..."

  if [[ ! -f "DashboardApp/frontend/package.json" ]]; then
    log_error "DashboardApp/frontend/package.json 不存在，無法啟動"
    exit 1
  fi

  if [[ ! -f "DashboardApp/backend/main.py" ]]; then
    log_error "DashboardApp/backend/main.py 不存在，無法啟動"
    exit 1
  fi

  # 後端：背景執行
  log_info "啟動 FastAPI 後端（:8000）..."
  cd DashboardApp/backend
  source .venv/bin/activate 2>/dev/null || source .venv/Scripts/activate 2>/dev/null
  uvicorn main:app --reload --port 8000 &
  BACKEND_PID=$!
  cd "$WORKSPACE_DIR"

  # 前端：前景執行（Ctrl+C 一起停）
  log_info "啟動 Vite 前端（:5173）..."
  echo ""
  echo "  前端：http://localhost:5173"
  echo "  後端：http://localhost:8000"
  echo "  API Docs：http://localhost:8000/docs"
  echo ""
  echo "  Ctrl+C 同時停止前後端"
  echo ""

  trap "kill $BACKEND_PID 2>/dev/null; exit 0" INT TERM

  cd DashboardApp/frontend
  npm run dev

  wait $BACKEND_PID
fi

echo ""
echo "============================================================"
log_success "Setup 完成"
echo ""
echo "  啟動開發環境："
echo "    bash setup.sh --dev"
echo ""
echo "  或分別啟動："
echo "    cd DashboardApp/backend && uvicorn main:app --reload"
echo "    cd DashboardApp/frontend && npm run dev"
echo "============================================================"
echo ""
