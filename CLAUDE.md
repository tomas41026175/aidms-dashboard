# AIDMS Dashboard — Workspace 配置

> 麗臺科技前端實作面試題
> 開發方式：`/spec-work` + `/pm`（細緻顆粒度）

---

## 雙層架構

```
Layer 1 (Workspace)     → 本目錄：設計、計畫、面試資料
Layer 2a (ChartComponents) → @aidms/chart-components npm 套件
Layer 2b (DashboardApp)    → React + FastAPI 全端監控儀表板
```

## 開發順序

```
Task 2（ChartComponents）→ Task 1（Dashboard Frontend）→ Task 1（FastAPI Backend）
```

理由：Dashboard 依賴 ChartComponents，先做套件再接入。

## 設計文件（開發前必讀）

| 文件 | 用途 |
|------|------|
| `docs/dashboard-design.md` | Task 1 完整架構設計 + WHY |
| `docs/chart-components-design.md` | Task 2 三層架構設計 + WHY |
| `docs/test-spec.md` | 所有測試案例（含 setup mock）|
| `docs/system-monitoring-domain.md` | psutil domain 知識 |
| `docs/chart-components-domain-research.md` | @mui/x-charts v7 API |
| `docs/chart-large-data-optimization.md` | 大量資料優化方案 |

**每個 task 開始前必須讀對應設計文件，不得憑空實作。**

## 開發規範

- @.claude/rules/spec-requirements.md

## Spec 檔案位置

```
.claude/specs/T1-dashboard/     Task 1 spec
.claude/specs/T2-chart/         Task 2 spec
```

## 快速技術參考

### 技術硬性要求

- 前端：`@mui/material` + `@mui/x-charts`（不可替換）
- 後端：FastAPI + psutil + sse-starlette
- 套件打包：tsup（ESM + CJS）

### 告警閾值（業界標準）

| 指標 | Warning | Critical |
|------|---------|----------|
| CPU | > 70% | > 85% |
| Memory | > 75% | > 90% |
| Disk | > 80% | > 90% |

### SSE 關鍵設計

- 後端 `deque(maxlen=150)` 保留 5 分鐘歷史
- 連線時先送 `history` event（頁面立刻有資料）
- 每 2 秒送 `metrics` event
- 每 15 秒送 SSE comment 心跳（防 Nginx 斷線）

### 跨平台注意事項

| 指標 | Mac | Windows | 處理 |
|------|-----|---------|------|
| `cpu_percent()` | ✅ | ✅ | 無差異 |
| Load Average | ✅ | ❌ | `loadAvg?: number[]`（optional）|
| `cpu_freq()` M 系列 | ⚠️ 回傳 None | ✅ | 不使用此欄位 |
| Python 指令 | `python3` | `python` | package.json 用 cross-env |

### 視覺主題（NVIDIA NGC 風格）

```typescript
// 色系對照
background.default: '#111217'   // Canvas
background.paper:   '#22252b'   // Cards
primary.main:       '#76b900'   // NVIDIA Green（accent）
text.primary:       'rgb(204, 204, 220)'
text.secondary:     'rgba(204, 204, 220, 0.65)'
divider:            'rgba(204, 204, 220, 0.12)'
```
