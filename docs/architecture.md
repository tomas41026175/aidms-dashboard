# AIDMS Dashboard — 完整架構圖

> 面試用完整版，涵蓋 5 個層面

---

## 1. 專案整體架構（三層 Workspace）

```
aidms-dashboard/                         ← Workspace（面試題根目錄）
│
├── docs/                                ← 設計文件、面試準備
│   ├── dashboard-design.md              ← Task 1 架構設計
│   ├── chart-components-design.md       ← Task 2 三層架構設計
│   ├── test-spec.md                     ← 測試案例規格
│   └── architecture.md                 ← 本檔案
│
├── spec/                                ← Spec-driven 開發記錄
│   └── 20260312-chart-components/
│       ├── spec.md                      ← 決策 + 任務計畫
│       └── progress.md                 ← 執行進度
│
├── ChartComponents/                     ← Task 2：可重用圖表套件
│   └── (詳見第 2 節)
│
└── DashboardApp/                        ← Task 1：全端監控應用
    └── (詳見第 3、4、5 節)
```

```
依賴關係：

  ChartComponents ──────────────────────► @aidms/chart-components (npm)
                                                     │
  DashboardApp/src/ ──────── npm install ────────────┘
  （前端直接引用套件，不是相對路徑 import）
```

---

## 2. ChartComponents 套件架構（三層設計）

```
@aidms/chart-components
│
├── Layer 1: Validation（入口守衛）
│   └── validation/
│       ├── validateChartData()       ← Zod schema 驗證
│       └── schemas.ts                ← ChartData 結構定義
│
├── Layer 2: Transform（資料轉換）
│   └── transforms/
│       ├── toLineSeriesData()        ← ChartData → MUI LineSeriesType[]
│       ├── toBarSeriesData()         ← ChartData → MUI BarSeriesType[]
│       └── toGaugeValue()           ← ChartData → number (0-100)
│
├── Layer 3: Rendering（React 元件）
│   └── src/
│       ├── LineChart.tsx             ← validate → transform → <LineChart />
│       ├── BarChart.tsx              ← validate → transform → <BarChart />
│       └── GaugeChart.tsx           ← validate → transform → <Gauge />
│
└── Package Output（tsup 打包）
    ├── dist/index.esm.js            ← ESM（Vite / Bundler）
    ├── dist/index.cjs.js            ← CJS（Node.js / Jest）
    └── dist/index.d.ts              ← TypeScript 型別定義

資料流：
  外部 props (ChartData)
    │
    ▼
  [Validation Layer]  ── 失敗 ──► <ErrorFallback message="..." />
    │ 通過
    ▼
  [Transform Layer]   ── 轉換為 MUI 格式
    │
    ▼
  [Rendering Layer]   ── 渲染 @mui/x-charts 元件
```

---

## 3. 前端元件樹

```
App                                      stateful: themeMode (light/dark)
└── ThemeProvider (createAppTheme)
    └── CssBaseline
        └── ErrorBoundary               stateful: error state（class component）
            └── Dashboard               stateful: metrics, history, status
                │
                │  useSystemMetrics()   ← SSE hook（唯一 side effect）
                │  useMemo()            ← derived data 計算
                │
                ├── AppBar              pure（標題 + 連線狀態 + 主題切換）
                │   ├── ConnectionBadge  pure（Live / Reconnecting / Error）
                │   └── ThemeToggle      pure（icon button）
                │
                ├── MetricCards         pure（Grid 容器，永遠顯示）
                │   ├── MetricGauge     pure（CPU）
                │   │   └── GaugeChart ← @aidms/chart-components
                │   ├── MetricGauge     pure（記憶體）
                │   │   └── GaugeChart ← @aidms/chart-components
                │   ├── MetricGauge     pure（磁碟）
                │   │   └── GaugeChart ← @aidms/chart-components
                │   └── NetworkCard     pure（RX/TX 數字）
                │
                ├── TrendCharts         React.memo（>= 600px 才 mount）
                │   ├── TrendPanel      pure（CPU + 記憶體）
                │   │   └── LineChart  ← @aidms/chart-components
                │   └── TrendPanel      pure（網路流量）
                │       └── LineChart  ← @aidms/chart-components
                │
                └── DetailPanels        React.memo（>= 900px 才 mount）
                    ├── CpuCorePanel    pure（horizontal BarChart）
                    │   └── BarChart   ← @aidms/chart-components
                    └── DiskPanel       pure（stacked BarChart）
                        └── BarChart   ← @aidms/chart-components

State 原則：只有 3 個元件有 state（App / ErrorBoundary / Dashboard）
           其餘全部是 pure：props in → JSX out
```

### 響應式斷點

```
< 600px  (手機)  │ MetricCards (2×2 grid)
>= 600px (平板)  │ MetricCards (1×4) + TrendCharts
>= 900px (桌面)  │ MetricCards + TrendCharts + DetailPanels

實作：條件渲染（非 CSS display:none）
  原因：MUI x-charts SVG 在隱藏狀態仍計算佈局，可能出現 width=0 bug
        完全不 mount = 零資源消耗
```

---

## 4. 後端 server.js 架構

```
server.js (Node.js + Express, port 3001)
│
├── Express Routes
│   ├── GET /api/metrics/stream      ← SSE endpoint（主要）
│   ├── GET /api/metrics/latest      ← REST fallback（一次性查詢）
│   └── GET /*                       ← Vite build static files
│
├── MetricsCollector（systeminformation 套件）
│   ├── si.currentLoad()             ← CPU 整體 % + per-core %
│   ├── si.mem()                     ← total / available / swapUsed
│   ├── si.fsSize()                  ← 磁碟分區清單（過濾虛擬 fs）
│   └── si.networkStats()            ← RX/TX bytes（兩次 delta 算速率）
│
├── Ring Buffer
│   ├── history: SystemMetrics[]     ← maxLen = 150（5 分鐘）
│   └── push(metric)                 ← 超過 maxLen 自動淘汰最舊資料
│
└── SSE Manager
    ├── clients: Set<Response>        ← 管理所有 SSE 連線
    ├── 連線時：送 history event      ← 頁面立即有資料
    ├── setInterval 2s：broadcast()   ← 收集新 metric → 推送所有 client
    ├── setInterval 15s：heartbeat()  ← 送 ": keepalive\n\n" 防斷線
    └── 斷線時：clients.delete(res)   ← 清理 Set
```

### server.js 關鍵設計

```javascript
// SSE Headers（固定格式）
res.setHeader('Content-Type', 'text/event-stream')
res.setHeader('Cache-Control', 'no-cache')
res.setHeader('Connection', 'keep-alive')

// 送 named event
function sendEvent(res, eventName, data) {
  res.write(`event: ${eventName}\n`)
  res.write(`data: ${JSON.stringify(data)}\n\n`)
}

// 連線時先送歷史（解決 < 2 秒需求）
sendEvent(res, 'history', { metrics: history })

// 心跳（SSE comment，不觸發 onmessage）
res.write(': keepalive\n\n')
```

---

## 5. 全端資料流（End-to-End）

```
Browser (React App)                    server.js (port 3001)
        │                                       │
        │  [頁面載入]                             │
        │  GET /api/metrics/stream               │
        │ ──────────────────────────────────────►│
        │                                       │  collectMetrics()
        │                                       │ ──────────────────► systeminformation
        │                                       │ ◄──────────────────
        │                                       │  clients.add(res)
        │                                       │
        │  event: history                        │
        │  data: { metrics: SystemMetrics[150] } │
        │ ◄──────────────────────────────────── │  頁面立即有 5 分鐘歷史資料
        │                                       │
        │  useSystemMetrics hook:               │
        │  setHistory(metrics)                  │
        │  ──► Dashboard re-render              │
        │  ──► 圖表立即顯示                       │
        │                                       │
        │         ┌─── 每 2 秒 ───┐             │
        │         │               │             │  collectMetrics()
        │         │               │             │ ──────────────────► systeminformation
        │  event: metrics         │             │ ◄──────────────────
        │  data: SystemMetrics    │             │  history.push(metric)
        │ ◄───────┘               │             │  broadcast() 所有 clients
        │                         │             │
        │  setLatest(data)         │             │
        │  setHistory(prev => ...) │             │
        │  ──► useMemo 計算        │             │
        │      cpuAlertLevel       │             │
        │      memAlertLevel  ─────┘             │
        │      ... derived data                  │
        │                                       │
        │         ┌─── 每 15 秒 ──┐             │
        │         │               │             │
        │  (無事件，SSE comment)   │             │  ": keepalive\n\n"
        │ ◄───────┘               │             │  防 Nginx / proxy 斷線
        │                                       │
        │  [網路中斷]                            │
        │  EventSource 自動重連                  │
        │  (瀏覽器原生，不需手動實作)              │
        │ ──────────────────────────────────────►│  重新送 history
```

### 型別契約（前後端共享）

```typescript
// types/metrics.ts（前端 src/types/ 與 server.js 共用同一份型別定義）

interface SystemMetrics {
  timestamp: number          // Unix ms
  cpu: {
    usage: number            // 整體 %（1 位小數）
    cores: number[]          // per-core %
  }
  memory: {
    total: number            // bytes
    available: number        // bytes（非 free：含可回收 cache）
    usage: number            // (total - available) / total * 100
    swapUsage: number
  }
  disk: DiskPartition[]
  network: {
    rxBps: number            // bytes/sec（後端已算好速率，非累計量）
    txBps: number
  }
  loadAvg?: number[]         // Linux/Mac only，Windows 不提供
}

interface DiskPartition {
  device: string             // "/dev/sda1"
  mountpoint: string         // "/"
  totalGb: number
  usedGb: number
  usage: number              // %
}
```

---

## 架構決策摘要（面試快速回答）

| 決策 | 選擇 | WHY |
|------|------|-----|
| 後端 | Node.js + Express | PDF 明確要求 `node server.js` |
| 系統資訊 | `systeminformation` | 跨平台（Mac/Win/Linux），API 統一 |
| 推播方式 | SSE（非 WebSocket） | 監控只需單向推播；SSE 原生重連；HTTP/1.1 相容 |
| 先送歷史 | `history` event | 頁面載入立即有圖，解決 < 2 秒要求 |
| 心跳 | SSE comment 15s | 不觸發 `onmessage`，防 Nginx 60s timeout 斷線 |
| 告警邏輯 | 連續 3 點 | 單點 spike 太常見（cron/GC），連續 6 秒才是真告警 |
| 元件 state | 只有 3 個 | 單向資料流，Debug 只看 Dashboard state |
| 響應式 | 條件渲染 | MUI x-charts SVG 隱藏仍計算佈局，完全不 mount 才省資源 |
| 圖表套件 | @aidms/chart-components | 自製套件，封裝 MUI x-charts，符合 Task 2 要求 |
