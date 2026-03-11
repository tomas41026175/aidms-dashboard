# AIDMS Dashboard — Workspace

麗臺科技前端工程師面試實作題的雙層開發 Workspace。

## 架構說明

```
aidms-dashboard/                ← Layer 1: Workspace（計畫、設計、面試資料）
├── README.md                      本文件
├── CLAUDE.md                      Claude Code 工作配置
├── interview-prep.md              面試當天速查備忘錄
├── docs/                          設計文件 + Domain 知識
│   ├── dashboard-design.md        Task 1 架構設計（Dashboard）
│   ├── chart-components-design.md Task 2 架構設計（ChartComponents npm 套件）
│   ├── chart-large-data-optimization.md  大量資料優化方案
│   ├── chart-components-domain-research.md  @mui/x-charts v7 domain
│   ├── system-monitoring-domain.md  psutil + FastAPI SSE domain
│   ├── test-spec.md               完整測試規格（TDD）
│   ├── leadtek-company-research.md  公司研究報告
│   ├── aidms-product-overview.md    AIDMS 產品深度分析
│   └── interview-strategy.md        面試應對策略
│
├── ChartComponents/            ← Layer 2a: @aidms/chart-components（npm 套件）
│   └── src/
│
└── DashboardApp/               ← Layer 2b: System Monitoring Dashboard
    ├── frontend/                  React + TypeScript + MUI
    └── backend/                   FastAPI + psutil + SSE
```

| 層級 | 目的 |
|------|------|
| Layer 1 (Workspace) | 計畫、設計文件、面試準備資料 |
| Layer 2a (ChartComponents) | `@aidms/chart-components` 可重用圖表套件 |
| Layer 2b (DashboardApp) | 系統監控儀表板（前端 + 後端） |

## 面試作業說明

**Task 1**：系統監控儀表板
- 技術：React + TypeScript + MUI + FastAPI + SSE
- 功能：CPU / Memory / Disk / Network 即時監控（2s 間隔）
- 特色：Domain-aware 告警（3 態）、NVIDIA NGC 視覺風格、RWD

**Task 2**：可重用圖表元件庫
- 套件名稱：`@aidms/chart-components`
- 技術：@mui/x-charts v7 + TypeScript + Vite（tsup 打包）
- 設計：三層漸進式 API（零配置 → 進階 → escape hatch）

## 快速啟動

```bash
# 安裝依賴並啟動（前端 + 後端同步）
bash setup.sh
```

## 設計文件快速索引

| 需要了解 | 讀這個 |
|---------|--------|
| Dashboard 架構全覽 | `docs/dashboard-design.md` |
| ChartComponents API 設計 | `docs/chart-components-design.md` |
| 大量資料優化 | `docs/chart-large-data-optimization.md` |
| psutil + SSE 實作細節 | `docs/system-monitoring-domain.md` |
| 所有測試案例 | `docs/test-spec.md` |
| 公司研究 | `docs/leadtek-company-research.md` |
| 面試備忘 | `interview-prep.md`（本層根目錄） |
