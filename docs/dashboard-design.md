# Dashboard 設計方案

> Task 1 — 系統監控儀表板
> React/TypeScript + Node.js (Express) + @mui/material + @mui/x-charts

---

## 0. 需求確認（PDF 原文）

```
✅ 使用 React/TypeScript 開發前端介面
✅ 後端使用 Node.js，提供 CPU、記憶體、磁碟使用率（啟動指令：node server.js）
✅ 數據可視化（響應式設計）
✅ 頁面載入時間 < 2 秒
✅ 至少 3 個測試場景
```

**AIDMS 角度的設計選擇**（不增加功能，只影響視覺和命名）：
- 主題：Dark-first（AIDMS/Grafana 工業風格）
- 標籤名稱：沿用 PDF 的 CPU、記憶體、磁碟（不換成 "Compute Utilization" 等）
- 加入 Network 作為第四指標（PDF 說「等」，合理延伸）

---

## 1. 頁面佈局

### 整體結構

```
┌─────────────────────────────────────────────────────────────┐
│  AppBar                                                      │
│  ┌──────────────────────────┬────────────────────────────┐  │
│  │ AIDMS System Monitor     │ [● Live] [Dark/Light]       │  │
│  └──────────────────────────┴────────────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Level 1: Metric Cards（永遠顯示）                            │
│  ┌──────────┬──────────┬──────────┬──────────┐              │
│  │ CPU      │ 記憶體   │ 磁碟     │ 網路     │              │
│  │ 73.2%    │ 61%      │ 42%      │ 1.2 MB/s │              │
│  │ [Gauge]  │ [Gauge]  │ [Gauge]  │ RX/TX    │              │
│  └──────────┴──────────┴──────────┴──────────┘              │
│                                                              │
│  Level 2: Trend Charts（>= 600px 平板以上）                   │
│  ┌───────────────────────┬────────────────────────┐         │
│  │ CPU + 記憶體趨勢       │ 網路流量趨勢             │         │
│  │ [LineChart, 5min]     │ [LineChart, 5min]       │         │
│  └───────────────────────┴────────────────────────┘         │
│                                                              │
│  Level 3: Detail（>= 900px 桌面以上）                         │
│  ┌───────────────────────┬────────────────────────┐         │
│  │ Per-Core CPU          │ 磁碟分區                 │         │
│  │ [BarChart horizontal] │ [BarChart stacked]      │         │
│  └───────────────────────┴────────────────────────┘         │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 響應式邏輯

**為什麼用條件渲染而非 CSS `display: none`**：MUI x-charts 的 SVG 在隱藏狀態下仍計算佈局，浪費效能且可能出現 `width=0` bug。完全不 mount = 零資源消耗。

```typescript
const isTabletUp = useMediaQuery(theme.breakpoints.up('sm'));   // >= 600px
const isDesktopUp = useMediaQuery(theme.breakpoints.up('md'));  // >= 900px

return (
  <>
    <AppBar />
    <MetricCards />                          {/* 永遠 */}
    {isTabletUp && <TrendCharts />}          {/* 平板+ */}
    {isDesktopUp && <DetailPanels />}        {/* 桌面+ */}
  </>
);
```

| 斷點 | 裝置 | 顯示內容 |
|------|------|---------|
| < 600px | 手機 | MetricCards（2×2 grid） |
| >= 600px | 平板 | + TrendCharts（MetricCards 變 1×4） |
| >= 900px | 桌面 | + DetailPanels |

---

## 2. 元件樹

```
App                                     stateful（themeMode）
└── ThemeProvider
    └── CssBaseline
        └── ErrorBoundary              stateful（error state）
            └── Dashboard              stateful（metrics, history）
                ├── AppBar             pure（標題 + 連線狀態 + 主題切換）
                ├── MetricCards        pure（Grid 容器）
                │   ├── MetricGauge    pure（CPU）
                │   │   └── GaugeChart *
                │   ├── MetricGauge    pure（記憶體）
                │   │   └── GaugeChart *
                │   ├── MetricGauge    pure（磁碟）
                │   │   └── GaugeChart *
                │   └── NetworkCard    pure（RX/TX 數字）
                ├── TrendCharts        React.memo
                │   ├── TrendPanel     pure（CPU + 記憶體）
                │   │   └── LineChart *
                │   └── TrendPanel     pure（網路）
                │       └── LineChart *
                └── DetailPanels       React.memo
                    ├── CpuCorePanel   pure（horizontal BarChart）
                    │   └── BarChart *
                    └── DiskPanel      pure（stacked BarChart）
                        └── BarChart *

* = 來自 @aidms/chart-components
```

**核心原則：只有 3 個元件有 state（App、ErrorBoundary、Dashboard），其餘全部是 pure props-in/JSX-out。**

理由：單向資料流讓 Debug 可預測——出問題只看 Dashboard 的 state 和 derived data 就夠了。

---

## 3. TypeScript 型別

```typescript
// types/metrics.ts

interface SystemMetrics {
  timestamp: number;          // Unix ms
  cpu: {
    usage: number;            // 整體 %（1 位小數）
    cores: number[];          // per-core %
  };
  memory: {
    total: number;            // bytes
    available: number;        // bytes — 用 available 而非 free
                              // 原因：Linux 的 free 不含可回收 cache，
                              //       available 才是「實際可用量」
    usage: number;            // (total - available) / total * 100
    swapUsage: number;
  };
  disk: DiskPartition[];
  network: {
    rxBps: number;            // bytes/sec（後端已算好速率）
    txBps: number;
    rxErrors: number;
    txErrors: number;
  };
}

interface DiskPartition {
  device: string;             // e.g. "/dev/sda1"
  mountpoint: string;         // e.g. "/"
  totalGb: number;
  usedGb: number;
  freeGb: number;
  usage: number;              // %
}

type AlertLevel = 'normal' | 'warning' | 'critical';

// SSE event payload
interface HistoryPayload {
  metrics: SystemMetrics[];   // 最多 150 筆
}
```

---

## 4. 資料流

```
Node.js Express server.js (port 3001)
  │
  │  SSE event "history"  ← 連線時送 150 筆歷史（頁面立即有資料）
  │  SSE event "metrics"  ← 每 2 秒推送 1 筆
  │  SSE comment          ← 每 15 秒心跳（防 Nginx/proxy 斷線）
  │
  ▼
useSystemMetrics()                     ← 唯一的 SSE hook
  │
  │  latest: SystemMetrics | null
  │  history: SystemMetrics[]          ← MAX_POINTS = 150（5 分鐘）
  │  status: 'connecting'|'connected'|'error'
  │
  ▼
Dashboard（useMemo 計算 derived data）
  │
  ├── cpuAlertLevel    = deriveAlertLevel(history, m => m.cpu.usage, CPU_THRESHOLDS)
  ├── memAlertLevel    = deriveAlertLevel(history, m => m.memory.usage, MEM_THRESHOLDS)
  ├── diskAlertLevel   = deriveAlertLevel(history, m => worstDisk(m), DISK_THRESHOLDS)
  │
  ├── timestamps       = history.map(h => new Date(h.timestamp))
  ├── cpuDatasets      = [{ label: 'CPU %', data: history.map(h => h.cpu.usage) }]
  ├── memDatasets      = [{ label: '記憶體 %', data: history.map(h => h.memory.usage) }]
  ├── networkDatasets  = [RX series, TX series]
  ├── coreLabels       = ['C0', 'C1', ...]
  ├── coreDatasets     = [{ label: '使用率', data: latest.cpu.cores }]
  ├── diskLabels       = latest.disk.map(d => d.mountpoint)
  └── diskDatasets     = [used GB series, free GB series]
```

### useSystemMetrics Hook

```typescript
// hooks/useSystemMetrics.ts

const MAX_POINTS = 150;  // 2s × 150 = 5 分鐘

export function useSystemMetrics() {
  const [latest, setLatest] = useState<SystemMetrics | null>(null);
  const [history, setHistory] = useState<SystemMetrics[]>([]);
  const [status, setStatus] = useState<'connecting' | 'connected' | 'error'>('connecting');

  useEffect(() => {
    const es = new EventSource('/api/metrics/stream');

    // 連線時先送歷史，頁面立即有圖可看（解決 < 2s 需求）
    es.addEventListener('history', (e: MessageEvent) => {
      const { metrics }: HistoryPayload = JSON.parse(e.data);
      setHistory(metrics);
      setLatest(metrics[metrics.length - 1] ?? null);
      setStatus('connected');
    });

    // 每 2 秒更新
    es.addEventListener('metrics', (e: MessageEvent) => {
      const data: SystemMetrics = JSON.parse(e.data);
      setLatest(data);
      setHistory(prev => {
        // 用 spread + slice 而非 push：React 需要新 reference 才觸發 re-render
        const next = [...prev, data];
        return next.length > MAX_POINTS ? next.slice(-MAX_POINTS) : next;
      });
    });

    // EventSource 瀏覽器原生自動重連，不需要手動實作
    es.onerror = () => setStatus('error');

    return () => es.close();  // cleanup：元件卸載時關閉連線
  }, []);

  return { latest, history, status };
}
```

---

## 5. 告警系統

### 閾值

```typescript
// utils/alert-thresholds.ts

const CPU_THRESHOLDS  = { warning: 70, critical: 85 };
const MEM_THRESHOLDS  = { warning: 75, critical: 90 };
const DISK_THRESHOLDS = { warning: 80, critical: 90 };
const SWAP_THRESHOLDS = { warning: 10, critical: 50 };
```

### 連續 3 點邏輯（純函式）

```typescript
const CONSECUTIVE = 3;

// 為什麼連續 3 點才觸發？
// CPU spike 極為常見（cron job、GC）。單點告警會造成 alert storm，
// 使用者很快就會無視所有告警。3 點 = 6 秒，過濾短暫 spike 但不延遲真告警。
export function deriveAlertLevel(
  recentHistory: SystemMetrics[],
  extractor: (m: SystemMetrics) => number,
  thresholds: { warning: number; critical: number },
): AlertLevel {
  if (recentHistory.length < CONSECUTIVE) return 'normal';

  const lastN = recentHistory.slice(-CONSECUTIVE);
  const classify = (v: number): AlertLevel =>
    v > thresholds.critical ? 'critical'
    : v > thresholds.warning ? 'warning'
    : 'normal';

  const levels = lastN.map(m => classify(extractor(m)));

  if (levels.every(l => l === 'critical')) return 'critical';
  if (levels.every(l => l !== 'normal')) return 'warning';
  return 'normal';
}
```

---

## 6. 視覺主題

### Clean Dark 風格

參考：Vercel Dashboard、Linear、Raycast。
核心原則：**大量留白、細節克制、層次靠亮度差異而非邊框**。

```
色階層次（由深到淺）：
Canvas  #09090b  ← 最底層背景（zinc-950）
Surface #111113  ← 卡片底色（略亮）
Overlay #1c1c1f  ← hover / elevated 狀態
Border  rgba(255,255,255,0.07)  ← 極細、幾乎隱形的分隔

Accent: #a78bfa（violet-400）— 柔和紫，現代感強、不刺眼
Normal state: #34d399（emerald-400）
Warning:      #fbbf24（amber-400）
Critical:     #f87171（red-400）

Text primary:   #fafafa（zinc-50）
Text secondary: rgba(250,250,250,0.45)
Text muted:     rgba(250,250,250,0.28)
```

```typescript
// theme.ts
// Clean Dark — Vercel/Linear 風格
// 層次靠亮度差異（zinc 色階），不靠重邊框
export function createAppTheme(mode: 'light' | 'dark') {
  return createTheme({
    palette: {
      mode,
      ...(mode === 'dark' ? {
        primary: { main: '#a78bfa' },          // violet-400 — accent
        background: {
          default: '#09090b',                  // zinc-950 canvas
          paper:   '#111113',                  // zinc-900 surface
        },
        divider: 'rgba(255, 255, 255, 0.07)',  // 極細分隔線
        text: {
          primary:   '#fafafa',                // zinc-50
          secondary: 'rgba(250, 250, 250, 0.45)',
        },
      } : {
        primary: { main: '#7c3aed' },          // violet-700 亮色變體
        background: { default: '#f4f4f5', paper: '#ffffff' },
        divider: 'rgba(0, 0, 0, 0.08)',
        text: { primary: '#09090b', secondary: '#71717a' },
      }),
    },
    shape: {
      borderRadius: 12,                        // 圓角統一 12px，現代感
    },
    typography: {
      fontFamily: '"Inter", system-ui, sans-serif',
      // 數字顯示用 tabular nums 避免跳動（在元件層 sx 設定）
    },
    components: {
      MuiCard: {
        styleOverrides: {
          root: {
            backgroundImage: 'none',
            backgroundColor: '#111113',
            border: '1px solid rgba(255, 255, 255, 0.07)',
            boxShadow: 'none',                 // 不用陰影，靠色差製造層次
            borderRadius: 12,
          },
        },
      },
      MuiAppBar: {
        styleOverrides: {
          root: {
            backgroundColor: 'rgba(9, 9, 11, 0.85)', // 半透明 + backdrop blur
            backdropFilter: 'blur(12px)',
            borderBottom: '1px solid rgba(255, 255, 255, 0.07)',
            boxShadow: 'none',
          },
        },
      },
      MuiChip: {
        styleOverrides: {
          root: { borderRadius: 6 },
        },
      },
    },
  });
}
```

### 數字顯示（tabular nums）

圖表數值、百分比用 `fontVariantNumeric: 'tabular-nums'` 避免數字更新時版面跳動：

```typescript
<Typography sx={{ fontVariantNumeric: 'tabular-nums', fontWeight: 600 }}>
  {value.toFixed(1)}%
</Typography>
```

### 告警色系調整

Clean Dark 下告警用**飽和度中等的柔和色**，不用過飽和螢光色：

| 狀態 | 顏色 | 說明 |
|------|------|------|
| Normal | `#34d399` emerald-400 | 清爽綠，讀得出「良好」 |
| Warning | `#fbbf24` amber-400 | 暖黃，不刺眼 |
| Critical | `#f87171` red-400 | 柔紅，搭配 pulse glow |

```typescript
// App.tsx — 預設 dark（只有明確設定 light 的系統才用 light）
const [mode, setMode] = useState<'light' | 'dark'>(() =>
  window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark'
);
```

---

## 7. 告警視覺化

```typescript
// components/MetricGauge.tsx

// Critical 狀態用 box-shadow glow pulse：靜態紅框容易被忽略（banner blindness），
// 柔和脈衝在不打斷工作的前提下持續提醒
const pulseAnimation = keyframes`
  0%, 100% { box-shadow: 0 0 0 0 rgba(248, 113, 113, 0.4); }
  50%       { box-shadow: 0 0 0 8px rgba(248, 113, 113, 0); }
`;

<Card sx={{
  border: '1px solid',
  borderColor: alertLevel === 'normal' ? 'divider' : alertColor.main,
  animation: alertLevel === 'critical' ? `${pulseAnimation} 2s ease-out infinite` : 'none',
}}>
  <Typography variant="overline">{title}</Typography>
  <GaugeChart
    value={value}
    color={(v) => getAlertColor(classifyValue(v, thresholds)).main}
  />
  <Typography variant="caption">
    {alertLevel.toUpperCase()}   {/* NORMAL / WARNING / CRITICAL */}
  </Typography>
</Card>
```

---

## 8. Memoization 策略

| 元件 | memo | 理由 |
|------|------|------|
| `MetricCards` + 子元件 | 否 | 每 2 秒 `latest` 必定變，memo 無意義 |
| `TrendCharts` | `React.memo` | `history` 不變時（同一個 2s 週期內多次 render）可跳過 |
| `DetailPanels` | `React.memo` | 桌面才 mount，保護 |

**最重要的效能優化不是 memo，而是：**
1. 手機不 mount Level 2/3（條件渲染）
2. LineChart 關閉動畫 `animate={false}`（150 點的 SVG path 動畫很重）
3. SSE 先送 history event，頁面立即有資料，不需等第一個 2 秒 tick

---

## 9. 完整檔案清單

```
src/
├── main.tsx
├── App.tsx                      # ThemeProvider + mode state
├── theme.ts                     # createAppTheme(mode)
├── types/
│   └── metrics.ts               # SystemMetrics, DiskPartition, AlertLevel, HistoryPayload
├── hooks/
│   └── useSystemMetrics.ts      # SSE 連線 + sliding window
├── utils/
│   ├── alert-thresholds.ts      # 閾值 + deriveAlertLevel()（純函式）
│   ├── alert-colors.ts          # getAlertColor(level)（純函式）
│   └── format.ts                # formatBytes / formatBps / formatPercent（純函式）
├── components/
│   ├── Dashboard.tsx            # 核心：useSystemMetrics + useMemo + 條件渲染
│   ├── ErrorBoundary.tsx
│   ├── AppBar.tsx               # 標題 + ConnectionBadge + ThemeToggle
│   ├── ConnectionBadge.tsx      # Live / Reconnecting / Error
│   ├── ThemeToggle.tsx
│   ├── MetricCards.tsx          # Grid 容器
│   ├── MetricGauge.tsx          # Card + GaugeChart + 告警
│   ├── NetworkCard.tsx          # RX/TX 數字卡片
│   ├── TrendCharts.tsx          # React.memo Grid 容器
│   ├── TrendPanel.tsx           # Card + LineChart
│   ├── DetailPanels.tsx         # React.memo Grid 容器
│   ├── CpuCorePanel.tsx         # horizontal BarChart
│   └── DiskPanel.tsx            # stacked BarChart
└── __tests__/
    ├── setup.ts
    ├── alert-thresholds.test.ts # 10 cases（最核心）
    ├── format.test.ts
    ├── use-system-metrics.test.ts
    ├── metric-gauge.test.tsx
    ├── dashboard-layout.test.tsx
    └── scenarios/
        ├── normal-rendering.test.tsx   # 場景 1（PDF 要求：至少 3 個）
        ├── error-handling.test.tsx     # 場景 2
        └── sse-reconnect.test.tsx      # 場景 3
```

---

## 10. 載入時間分析（< 2 秒）

```
Vite bundle (MUI + x-charts):  ~200ms
React mount:                    ~50ms
首次 paint（空殼）:              ~100ms
SSE 連線建立:                    ~10ms
history event 到達 + 渲染:      ~150ms
────────────────────────────────
Total:                          ~510ms  ✓

風險控制：
  MUI 全量引入   → 具名 import（import { Card } from '@mui/material'）
  x-charts 太大  → 子路徑 import（import { Gauge } from '@mui/x-charts/Gauge'）
  手機圖表太多   → 條件渲染，手機只 mount 4 個 GaugeChart
  SSE 歷史太大   → deque(maxlen=150)，JSON < 50KB

驗證：
  npm run build && npm run preview
  Chrome DevTools → Network + Performance
```
