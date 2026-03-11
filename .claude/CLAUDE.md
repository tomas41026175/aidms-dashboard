# AIDMS Dashboard — 專案配置

> 麗臺科技前端實作面試題
> 本專案採用 `/pm`（細緻顆粒度）+ `/spec-work` 進行開發

---

## 專案性質

面試實作題，包含兩個 Task：
- **Task 1**：系統監控儀表板（React/TypeScript + FastAPI + SSE）
- **Task 2**：可重用圖表組件庫（`@aidms/chart-components` npm 套件）

技術硬性要求：`@mui/material` + `@mui/x-charts`

---

## 設計文件（開發前必讀）

| 文件 | 用途 |
|------|------|
| `docs/dashboard-design.md` | Task 1 完整架構設計 + WHY |
| `docs/chart-components-design.md` | Task 2 三層架構設計 + WHY |
| `docs/test-spec.md` | 所有測試案例（含 setup mock）|
| `docs/system-monitoring-domain.md` | psutil domain 知識（告警閾值、API 用法）|
| `docs/chart-components-domain-research.md` | @mui/x-charts v7 API 研究 |

**每個 task 開始前必須讀對應設計文件**，不得憑空實作。

---

## 開發規範

- @rules/spec-requirements.md

---

## Spec 開發順序

```
Task 2（ChartComponents）→ Task 1（Dashboard）→ Task 1 Backend（FastAPI）
```

理由：Dashboard 依賴 ChartComponents，先做套件再接入。

---

## 快速技術參考

### 跨平台注意事項

| 指標 | Mac | Windows | 處理 |
|------|-----|---------|------|
| `cpu_percent()` | ✅ | ✅ | 無差異 |
| Load Average | ✅ | ❌ | `loadAvg?: number[]`（optional）|
| `cpu_freq()` Mac M 系列 | ⚠️ 回傳 None | ✅ | 不使用此欄位 |
| 磁碟 fstype 過濾 | `apfs/hfs` | `NTFS/FAT32` | EXCLUDE_FSTYPES 含兩者 |
| Python 指令 | `python3` | `python` / `py` | `package.json` 用 cross-env |

### 告警閾值（業界標準）

| 指標 | Warning | Critical |
|------|---------|----------|
| CPU | > 70% | > 85% |
| Memory | > 75% | > 90% |
| Disk | > 80% | > 90% |
| Swap | > 10% | > 50% |

### SSE 關鍵設計

- 後端 `deque(maxlen=150)` 保留 5 分鐘歷史
- 連線時先送 `history` event（頁面立刻有資料），再每 2 秒送 `metrics` event
- 每 15 秒送 SSE comment 心跳（防 Nginx 斷線）
- 前端 EventSource 原生自動重連，不需手動實作
