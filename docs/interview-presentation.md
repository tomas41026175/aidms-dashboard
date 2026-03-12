# AIDMS Dashboard — 面試技術簡報

> 適用場景：技術面試、Design Review、Code Walkthrough
> 涵蓋：架構設計、技術亮點、代碼難點、元件設計、大資料優化、參數設計、擴充性、可維護性

---

## 一、專案整體架構

### 雙層架構設計（Monorepo）

```
aidms-dashboard/                    ← Workspace
├── ChartComponents/                ← @aidms/chart-components（可重用 npm 套件）
│   ├── src/
│   │   ├── LineChart.tsx           ← 折線圖（Rendering Layer）
│   │   ├── BarChart.tsx            ← 柱狀圖（Rendering Layer）
│   │   ├── GaugeChart.tsx          ← 儀表圖（Rendering Layer）
│   │   ├── transforms/             ← Transform Layer（純函式）
│   │   ├── validation/             ← Validation Layer（純函式）
│   │   └── fallbacks/              ← Skeleton / Error 佔位元件
│   └── dist/                       ← tsup 打包：ESM + CJS + .d.ts
│
└── DashboardApp/                   ← 系統監控儀表板（全端）
    ├── server.js                   ← Node.js + Express + SSE 後端
    └── src/
        ├── hooks/                  ← useSystemMetrics（SSE 連線）
        ├── utils/                  ← 告警邏輯、格式化（純函式）
        ├── types/                  ← SystemMetrics 等型別定義
        └── components/             ← UI 元件（13 個）
```

**設計動機**：先做套件再接入 Dashboard，強迫解耦——套件層不知道 Dashboard 存在，Dashboard 像一個普通消費者使用 npm 套件。

---

### 資料流全景圖

```
[systeminformation]
       ↓ 2s interval
[Node.js server.js]
  ├─ ring buffer (maxLen=150)   ← 5 分鐘歷史，O(n) push 可接受
  ├─ SSE "history" event        ← 連線時一次送 150 筆
  └─ SSE "metrics" event        ← 每 2 秒推 1 筆
       ↓
[useSystemMetrics Hook]
  ├─ latest: SystemMetrics | null
  ├─ history: SystemMetrics[]    ← 前端維護 sliding window（MAX=150）
  └─ status: connecting | connected | error
       ↓
[Dashboard.tsx]  useMemo 計算 derived data
  ├─ cpuAlertLevel / memAlertLevel / diskAlertLevel
  ├─ timestamps / cpuDatasets / memDatasets
  ├─ networkDatasets / coreLabels / diskLabels
       ↓
[Pure Components]  props-in / JSX-out
  ├─ MetricGauge × 3 ──→ GaugeChart（@aidms/chart-components）
  ├─ TrendPanel × 2  ──→ LineChart（@aidms/chart-components）
  └─ CpuCorePanel / DiskPanel ─→ BarChart（@aidms/chart-components）
```

**關鍵決策**：只有 3 個元件有 State（App、ErrorBoundary、Dashboard），其餘全為 Pure 元件。出問題只看 Dashboard 的 state 即可定位。

---

## 二、技術亮點

### 亮點 1：SSE 架構 — history event 解決首屏空白

**問題**：SSE 每 2 秒才送一次資料。用戶開啟頁面時，若等待第一個 tick，會看到 2 秒空殼。

**解法**：後端維護 ring buffer（maxLen=150），連線時**立即**送 `history` event，包含最多 150 筆歷史資料。頁面 mount 後 < 200ms 就有完整圖形。

```
後端連線流程：
  client connect
       ↓ 立即
  res.write("event: history\n")  ← 150 筆歷史，頁面立即有資料
  res.write("event: metrics\n")  ← 每 2 秒推送（新資料進來才會看到跳動）
  res.write(": keepalive\n")     ← 每 15 秒心跳（防 Nginx 60s timeout 斷線）
```

**效果**：頁面首次 paint 後 ~150ms 即有完整圖形，遠低於 PDF 要求的 2 秒。

---

### 亮點 2：Transform Layer — 隔離 MUI API 變化風險

ChartComponents 的核心創新是 **Transform Layer**：

```typescript
// 消費者寫這個（直覺）
<LineChart
  labels={timestamps}            // 不需要理解 "xAxis"
  datasets={[{ label: 'CPU', data: cpuData }]}
  curve="smooth"                 // 不需要知道 MUI 叫 "monotoneX"
  yRange={[0, 100]}             // 不需要設 yAxis[0].min/max
/>

// Transform Layer 自動翻譯成 MUI 需要的格式
{
  series: [{ id: 'CPU', data: [...], curve: 'monotoneX', ... }],
  xAxis: [{ data: timestamps, scaleType: 'time' }],
  yAxis: [{ min: 0, max: 100 }],
  skipAnimation: false,
}
```

**好處**：
1. **@mui/x-charts v8 升級**時只需改 transforms，消費者側零改動
2. **Transform 是純函式**，100% 可測試（不需要 DOM、不需要 React）
3. **隱藏 MUI 複雜度**：`scaleType` 自動偵測（Date → 'time'，string → 'point'）

---

### 亮點 3：連續 3 點告警 — 防 Alert Storm

```typescript
const CONSECUTIVE = 3  // 6 秒

export function deriveAlertLevel(
  recentHistory: SystemMetrics[],
  extractor: (m: SystemMetrics) => number,
  thresholds: Thresholds,
): AlertLevel {
  const lastN = recentHistory.slice(-CONSECUTIVE)
  const levels = lastN.map(m => classifyValue(extractor(m), thresholds))

  if (levels.every(l => l === 'critical')) return 'critical'
  if (levels.every(l => l !== 'normal')) return 'warning'
  return 'normal'
}
```

**設計理由**：CPU spike 在系統監控中極為常見（cron job、GC pause、burst）。單點觸發 alert 會造成 alert storm，用戶很快開始無視所有告警（cry wolf effect）。連續 3 個 2 秒採樣點（= 6 秒）確認才升告警，過濾短暫 spike 同時不明顯延遲真正的告警。

---

### 亮點 4：RWD 用條件渲染而非 CSS hidden

```typescript
const isTabletUp = useMediaQuery(theme.breakpoints.up('sm'))  // >= 600px
const isDesktopUp = useMediaQuery(theme.breakpoints.up('md')) // >= 900px

return (
  <>
    <MetricCards />                          {/* 永遠 mount */}
    {isTabletUp && <TrendCharts />}          {/* 平板+ 才 mount */}
    {isDesktopUp && <DetailPanels />}        {/* 桌面+ 才 mount */}
  </>
)
```

**為何不用 `display: none`**：MUI x-charts 的 SVG 用 `ResizeObserver` 偵測容器寬度。在 `display: none` 下 `clientWidth = 0`，SVG 以 width=0 渲染，後續顯示時會產生空白問題。條件渲染 = 零資源消耗，無 bug 風險。

**測試驗證**：16 個 RWD 測試，用 `vi.spyOn(window, 'matchMedia')` 模擬三種斷點，確認各層只在對應尺寸才 mount。

---

### 亮點 5：Critical 告警 — Pulse Glow 動畫

```typescript
// 設計決策：靜態紅框容易引發 banner blindness（操作人員視覺疲勞後忽略）
// Pulse glow = 柔和脈衝，在不打斷工作的前提下持續引起注意
const pulseAnimation = keyframes`
  0%, 100% { box-shadow: 0 0 0 0   rgba(248, 113, 113, 0.4); }
  50%       { box-shadow: 0 0 0 8px rgba(248, 113, 113, 0); }
`

// 注意：@media (prefers-reduced-motion) 不能寫在 keyframes 內（CSS 規格限制）
// 必須在元件的 sx prop 處理
<Card sx={{
  animation: alertLevel === 'critical'
    ? `${pulseAnimation} 2s ease-out infinite`
    : 'none',
  '@media (prefers-reduced-motion: reduce)': { animation: 'none' },
}}>
```

---

### 亮點 6：Vite resolve.dedupe — 解決 Monorepo 雙實例問題

**問題**：`@aidms/chart-components` 以 `file:../ChartComponents` 連結，Vite 預設允許它有獨立的 `ChartComponents/node_modules/@mui/x-charts`。這個獨立實例不在 DashboardApp 的 `ThemeProvider` context 中，導致圖表用 MUI 預設 light theme（黑色文字在深色背景 = 不可見）。

```typescript
// vite.config.ts
resolve: {
  dedupe: [
    'react', 'react-dom',
    '@mui/material', '@mui/x-charts',
    '@emotion/react', '@emotion/styled',
  ],
}
// 強制所有模組（含 file: 連結的套件）共用同一份 MUI 實例
// 確保 ThemeProvider context 正確傳遞到 ChartComponents
```

---

## 三、代碼難點

### 難點 1：isValidMetrics Runtime 型別守衛

SSE 的 `MessageEvent.data` 是 `string`，`JSON.parse` 後是 `unknown`。TypeScript 的型別只在編譯期有效，Runtime 若後端傳來格式異常的資料，直接存入 state 會讓 UI 崩潰。

```typescript
function isValidMetrics(data: unknown): data is SystemMetrics {
  if (typeof data !== 'object' || data === null) return false
  const d = data as Record<string, unknown>
  // 逐欄位驗證必要路徑
  if (typeof (d.cpu as Record<string, unknown>)?.usage !== 'number') return false
  if (typeof (d.memory as Record<string, unknown>)?.usage !== 'number') return false
  if (!Array.isArray(d.disk)) return false
  if (typeof (d.network as Record<string, unknown>)?.rxBps !== 'number') return false
  return true
}

// 使用
es.addEventListener('metrics', (e: MessageEvent) => {
  const data: unknown = JSON.parse(e.data)
  if (!isValidMetrics(data)) return  // 靜默丟棄，不更新 state
  setLatest(data)                    // TypeScript 現在知道是 SystemMetrics
})
```

**難點**：如何在「不用 `any`」的前提下做 Runtime 型別檢查，且讓 TypeScript 理解 narrowing 後的型別。解法是 type predicate `data is SystemMetrics`。

---

### 難點 2：Memory 用 `available` 而非 `free`

```typescript
// Linux 的 free memory 並不代表「實際可用」
// 作業系統會把閒置記憶體用作 disk cache（加速 I/O），這部分在 free 中不計入
// 但需要時 kernel 可立即回收，所以對用戶來說是「可用的」

memory: {
  available: number,  // ✅ total - used - cache_reclaimable
  // free: number     // ❌ 不用：只算未分配，低估實際可用量
  usage: number,      // (total - available) / total * 100
}
```

這個細節在 `systeminformation` 的文件中有說明，但容易踩坑——naive 實作會用 `os.freemem()` 導致記憶體使用率虛高。

---

### 難點 3：Gauge Width = 0 Bug

`@mui/x-charts` 的 `Gauge` 元件用 `ResizeObserver` 動態設定 SVG 寬度。當父容器有 `display: flex` 時，`Gauge` 的 `<div role="meter">` 沒有顯性寬度，`ResizeObserver` 觀測到 `0px`，SVG 渲染為不可見。

```typescript
// ❌ 錯誤：flex 容器讓 Gauge 寬度坍塌
<Box sx={{ display: 'flex', justifyContent: 'center', my: 1 }}>
  <GaugeChart value={value} />
</Box>

// ✅ 正確：移除 flex，讓 GaugeChart 自然填滿 block 寬度
<Box sx={{ my: 1 }}>
  <GaugeChart value={value} />
</Box>
```

**教訓**：MUI x-charts 的 SVG 元件都依賴 ResizeObserver，在 flex/grid 子項中使用時，必須確保容器有明確寬度，或讓元件自然填滿 block flow。

---

### 難點 4：BarChart horizontal layout 的軸交換

```typescript
// 水平柱狀圖需要把 labels 從 xAxis 移到 yAxis
const axisWithLabels = { data: labels, scaleType: 'band' as const }
const axisWithRange  = { min: yRange?.[0], max: yRange?.[1] }

return {
  // 直向：x 軸放類別 labels，y 軸放數值範圍
  xAxis: layout === 'vertical' ? [axisWithLabels] : [axisWithRange],
  yAxis: layout === 'vertical' ? [axisWithRange]  : [axisWithLabels],
  layout,
}
```

不理解 MUI x-charts API 的設計者很容易只改 `layout` prop，忘記交換軸配置，導致水平柱狀圖 label 方向錯誤。

---

### 難點 5：SliderWindow — Immutable Array 更新

```typescript
// ❌ 錯誤：push 不產生新 reference，React 不觸發 re-render
setHistory(prev => {
  prev.push(data)
  return prev
})

// ✅ 正確：spread 建立新 array，同時用 slice 控制最大長度
setHistory(prev => {
  const next = [...prev, data]
  return next.length > MAX_POINTS ? next.slice(-MAX_POINTS) : next
})
```

`slice(-MAX_POINTS)` 確保 sliding window 行為：永遠保留最近 N 筆，舊資料自動丟棄。

---

## 四、ChartComponents API 設計考量

### 三層漸進式 API（Progressive Disclosure）

```typescript
// Level 1：零配置（覆蓋 80% 場景）
<LineChart labels={timestamps} datasets={datasets} />

// Level 2：常用進階配置（20% 場景需要）
<LineChart
  labels={timestamps}
  datasets={datasets}
  height={240}
  yRange={[0, 100]}
  curve="smooth"
  animate={false}     // SSE 即時更新時關閉動畫，避免每 2 秒重播
/>

// Level 3：Escape Hatch（1% 場景，保留進入 MUI 原生能力的入口）
<LineChart
  labels={timestamps}
  datasets={datasets}
  slotProps={{
    xAxis: { tickLabelStyle: { fontSize: 10 } },
    lineChart: { margin: { left: 60 } },
  }}
/>
```

**設計哲學**：API 應該讓常見的事情簡單，讓不常見的事情可能。`slotProps` 是安全閥——不讓 API 成為 MUI 的薄薄包裝，也不讓消費者被完全鎖死。

---

### 與 MUI 原生 API 的對照設計

| 我們的 API | MUI 原生 | 設計理由 |
|-----------|---------|---------|
| `labels` | `xAxis[0].data` | 消費者不需理解「軸」的概念 |
| `datasets` | `series[]` | 更接近 Chart.js 等通行命名 |
| `curve: 'smooth'` | `curve: 'monotoneX'` | 隱藏 D3 術語 |
| `yRange` | `yAxis[0].min/max` | 扁平化，不需要嵌套物件 |
| `animate` | `skipAnimation` | 語義正向（啟用 vs 停用，避免雙重否定） |
| `color: fn` | `sx[gaugeClasses.valueArc]` | 消費者不需接觸 CSS-in-JS class |

---

### null 值設計 — 合法缺值

```typescript
// Dataset 的 data 允許 null（null ≠ 錯誤）
interface Dataset {
  data: (number | null)[]  // null = 合法缺值（折線斷點、載入中）
}
```

**場景**：網路 metrics 在剛連線時還沒有第一次採樣，值為 null。圖表在這段時間顯示斷點（折線中斷）而非崩潰。`connectNulls?: boolean` 控制是否跨越斷點連線。

---

### GaugeChart 色彩函式設計

```typescript
// 靜態色：始終顯示藍色
<GaugeChart value={73} color="#3b82f6" />

// 動態色：根據當前值決定顏色
<GaugeChart
  value={73}
  color={(value) => {
    if (value > 85) return '#f87171'   // critical red
    if (value > 70) return '#fbbf24'   // warning amber
    return '#34d399'                   // normal green
  }}
/>
```

**關鍵設計**：`color` 是函式時，接收的是**當前值**（已經過 clamp 的值）。套件不預設任何告警閾值——告警是業務邏輯，屬於 Dashboard 的責任，不應洩漏進元件庫。

---

## 五、大資料效能優化

### 現行規格與風險

| 情境 | 資料量 | 現況 |
|------|--------|------|
| 5 分鐘監控（MVP） | 150 點 × 2 series | SVG 直接渲染，< 8ms |
| 24 小時歷史回顧 | 43,200 點 | SVG 卡頓（~380ms/render） |
| 7 天歷史 | 302,400 點 | 瀏覽器凍結 |

### 三層優化策略

```
< 300 點   ──→  SVG 直接渲染（MUI x-charts 預設）
300~10k 點 ──→  LTTB 降採樣 → 壓縮到 < 300 點，再 SVG 渲染
> 10k 點   ──→  Canvas 渲染 + Web Worker 降採樣
```

### LTTB 演算法（Largest Triangle Three Buckets）

```
傳統降採樣（等距取樣）的問題：
  原始: ─────∧──────────/──
         spike         trend
  等距: ──   ─   ─   ─  ─   ← spike 可能被取到空白處！

LTTB 的方法：
  把資料分成 N 個 bucket，每個 bucket 選出「三角形面積最大」的點
  A = 前一個選中點
  B = 候選點（當前 bucket 每個點）
  C = 下一個 bucket 的平均點（作為「未來趨勢」的代理）
  選 max(area(A, B, C)) ← 面積最大代表視覺上最重要
```

**為什麼 LTTB 適合時間序列**：它保留「視覺上可辨別」的點——峰、谷、轉折——丟棄視覺上重疊的冗餘點。比等距取樣更「誠實」地呈現資料形狀。

**告警場景改用 Min-Max**：LTTB 可能遺漏短暫 CPU spike（若 spike 在 bucket 中面積不大）。Min-Max 降採樣每個 bucket 保留最小值和最大值，確保異常峰值不被抹除。

### Canvas 渲染 vs SVG

| | SVG（MUI x-charts） | Canvas（自訂） |
|-|---------------------|---------------|
| Tooltip | 原生支援 | 需手動計算最近點 |
| a11y | 有限支援 | 需手動 ARIA |
| > 10k 點 | ~380ms（卡頓） | ~12ms |
| 高 DPI | 自動 | 需手動 `devicePixelRatio` |

**Canvas 路徑設計**：
1. `React.lazy()` 懶載入 CanvasLineChart，不影響初始 bundle 大小
2. 高 DPI 處理：`canvas.width = width * devicePixelRatio`，`ctx.scale(dpr, dpr)`
3. 判斷閾值：`totalPoints > 10,000` 才切換路徑，因為 SVG 在 < 10k 點時互動性更好

### Web Worker 非同步降採樣

```typescript
// 超過 5,000 點才啟動 Worker（避免 postMessage 序列化本身的開銷）
const WORKER_THRESHOLD = 5_000

// 使用 id 機制防止過期回應（快速連續更新時可能有多個 in-flight）
const id = crypto.randomUUID()
pendingIdRef.current = id
workerRef.current.postMessage({ id, strategy, data, threshold })

workerRef.current.onmessage = (e) => {
  if (e.data.id === pendingIdRef.current) {  // 只接受最新的回應
    setSampledData(e.data.result)
  }
}
```

### MVP 實作的效能優化（已在現行代碼中）

```typescript
// 1. LineChart：超過 30 點自動關閉 mark（點標記），減少 SVG DOM 數量
showMark: labels.length <= 30

// 2. 關閉動畫：SSE 每 2 秒更新，動畫播放中又來新資料 = 視覺跳動
// 消費者明確傳 animate={false}
skipAnimation: !animate

// 3. useMemo 穩定 datasets reference，避免每次 Dashboard re-render 都重建物件
const cpuDatasets = useMemo(() => [
  { label: 'CPU %', data: history.map(h => h.cpu.usage) }
], [history])  // history 每 2 秒才變，不是每個 render cycle 都重建
```

---

## 六、Memoization 策略

### Dashboard 層

| 元件 | 策略 | 理由 |
|------|------|------|
| `MetricCards` 及子元件 | 不 memo | 每 2 秒 `latest` 必定變，memo 無意義（memo 本身也有開銷）|
| `TrendCharts` | `React.memo` | `history` 同一個 2s 週期內不變，可跳過中間的 render |
| `DetailPanels` | `React.memo` | 桌面才 mount，保護 BarChart 的 heavy render |

### ChartComponents 層

```typescript
// Transform 計算用 useMemo 包裹，避免每次 re-render 重跑
const muiProps = useMemo(
  () => toLineChartProps(props),
  [labels, datasets, height, curve, fill, yRange, connectNulls, animate]
)
```

**元件庫不做 React.memo**：SSE 推送時 datasets 是新物件（每次 `[...prev, data]`），淺比較永遠失敗，`React.memo` 形同虛設。讓消費者端用 `useMemo` 穩定 reference 才是正確位置。

---

## 七、擴充性設計

### 新增圖表類型

```typescript
// 1. 在 ChartComponents/src/ 新增元件
// PieChart.tsx（Rendering Layer）
// transforms/to-pie-props.ts（Transform Layer）
// validation/validate-gauge.ts 可複用

// 2. 在 index.ts 加入 export
export { PieChart } from './PieChart'
export type { PieChartProps } from './types'

// 3. Dashboard 側直接使用，不需改動套件核心邏輯
```

### 新增監控指標

```typescript
// 1. 在 types/metrics.ts 擴充 SystemMetrics
interface SystemMetrics {
  // 現有欄位...
  gpu?: {          // optional：不是所有機器都有 GPU
    usage: number
    vram: { total: number; used: number }
    temperature: number
  }
}

// 2. 在 server.js 新增採集邏輯（systeminformation 支援 GPU）
// 3. 在 utils/alert-thresholds.ts 新增 GPU_THRESHOLDS
// 4. 新增 GpuCard 元件，接入 Dashboard 的 useMemo derived data
```

### 告警閾值動態化

```typescript
// 現在是靜態常數
export const CPU_THRESHOLDS = { warning: 70, critical: 85 }

// 擴充為使用者可配置（最小改動）
export const CPU_THRESHOLDS = {
  warning: parseInt(import.meta.env.VITE_CPU_WARNING_THRESHOLD ?? '70'),
  critical: parseInt(import.meta.env.VITE_CPU_CRITICAL_THRESHOLD ?? '85'),
}
// 或從後端 /api/config 取得，不需要改 deriveAlertLevel 邏輯
```

### 歷史資料回顧（時間選擇器）

架構已預留擴充點：

```typescript
// useSystemMetrics 目前只處理 SSE 即時流
// 擴充方向：增加 useHistoricalMetrics hook，接入 /api/metrics/history?start=&end=
// 圖表元件完全相同，只是 datasets 來源從 SSE 改成 REST API
<LineChart
  labels={historicalTimestamps}   // 結構相同，透明替換
  datasets={historicalDatasets}
  maxPoints={300}                 // 啟用 LTTB 降採樣
/>
```

---

## 八、可維護性設計

### 純函式佔比 70%

| 層級 | 純函式 | 有副作用 |
|------|--------|---------|
| Transform Layer | ✅ `toLineChartProps` / `toBarChartProps` / `toGaugeProps` | — |
| Validation Layer | ✅ `validateSeriesData` / `validateGauge` | — |
| Utils（Dashboard） | ✅ `deriveAlertLevel` / `formatBytes` / `classifyValue` | — |
| Hooks | — | `useSystemMetrics`（SSE 副作用） |
| Components | 大多數 Pure | `Dashboard`（state）、`App`（theme state） |

**好處**：純函式測試不需要 DOM，不需要 React，執行快（不需要 jsdom overhead）。

### 錯誤邊界策略

```
App（唯一的 ErrorBoundary）
└── Dashboard
    ├── MetricGauge ← 內部驗證處理資料問題，不 throw
    ├── LineChart   ← 驗證失敗顯示 ChartError placeholder，不 throw
    └── BarChart    ← 同上
```

元件庫的原則：**永不 throw**。資料問題用 placeholder 處理，MUI 內部意外 crash 交給外層 ErrorBoundary。

### 型別安全邊界

```typescript
// 外部資料的邊界（SSE 傳來的 JSON）用 Runtime 守衛
function isValidMetrics(data: unknown): data is SystemMetrics { ... }

// 套件 API 邊界用 TypeScript 型別
interface LineChartProps {
  labels: (string | number | Date)[]  // 三種合法輸入，TypeScript 強制
  datasets: Dataset[]
}

// 內部邏輯全為 TypeScript strict mode
// tsconfig.json: "strict": true，禁止 any
```

### 開發期 vs 生產期的錯誤訊息分層

```typescript
// 開發期：verbose（幫助 Debug）
if (process.env.NODE_ENV !== 'production') {
  console.error(`[ChartComponents] "${ds.label}" 資料長度不一致:
    labels=${labels.length}, data=${ds.data.length}`)
}

// 生產期：只顯示 fallback UI，不洩漏內部資訊
return <ChartError reason="圖表資料無效" height={height} />
```

---

## 九、測試策略

### 測試分佈（81 個測試 / 8 個檔案）

| 測試類型 | 數量 | 特點 |
|---------|------|------|
| 純函式（告警邏輯、格式化） | 22 | 最快，無 DOM，無 React |
| Hook（useSystemMetrics） | 18 | MockEventSource 模擬 SSE |
| 元件（MetricGauge） | 14 | Testing Library + Theme |
| 場景（RWD、SSE、錯誤） | 27 | 整合測試，接近真實使用 |

### 關鍵 Mock 設計

```typescript
// MockEventSource：模擬 SSE 連線
class MockEventSource {
  private listeners = new Map<string, ((e: MessageEvent) => void)[]>()

  emit(type: string, payload: unknown) {
    const data = JSON.stringify(payload)
    this.listeners.get(type)?.forEach(h =>
      h(new MessageEvent(type, { data }))
    )
  }

  triggerError() {
    if (this.onerror) this.onerror(new Event('error'))
  }
}

// 測試中的使用
await act(async () => {
  getLastEventSource().emit('history', { metrics: [makeMetric()] })
})
expect(result.current.status).toBe('connected')
```

### RWD 測試技巧

```typescript
// matchMedia mock — 模擬不同斷點
vi.spyOn(window, 'matchMedia').mockImplementation((query: string) => {
  let matches = false
  if (query.includes('600')) matches = isTabletUp    // sm breakpoint
  if (query.includes('900')) matches = isDesktopUp   // md breakpoint
  return { matches, media: query, ... } as MediaQueryList
})

// 驗證條件渲染（非 CSS hidden）
await renderWithData(false, false)  // 手機
expect(screen.queryAllByTestId('line-chart')).toHaveLength(0)  // 完全不 mount

await renderWithData(true, false)   // 平板
expect(screen.queryAllByTestId('line-chart').length).toBeGreaterThanOrEqual(1)
```

---

## 十、常見面試問題準備

### Q：為什麼選 SSE 而不是 WebSocket？

A：系統監控是**單向資料流**（Server → Client），WebSocket 的雙向能力是浪費。SSE 的優點：
1. 瀏覽器原生自動重連（不需要手寫 reconnect 邏輯）
2. 基於 HTTP，穿透 proxy 更容易
3. 文字協定，Debug 更直觀（curl 就能看）
缺點：若需要前端控制（如 pause/resume、filter），WebSocket 更合適。

### Q：history event 設計的取捨？

A：150 筆 × ~200 bytes/筆 ≈ 30KB JSON。代價是初次連線 payload 較大，但換來「頁面載入後立即有完整圖形」，用戶體驗更好（尤其是在手機或慢速網路下）。若要優化可以壓縮（gzip SSE）或減少 buffer 長度。

### Q：為什麼把 Transform Layer 設計成純函式？

A：三個好處：
1. 100% 可測試（不需要 DOM、不需要 React render 環境，毫秒級完成）
2. 未來升級 MUI x-charts 版本時只需改這一層，消費者零改動
3. 強迫解耦：Transform Layer 只認識我們的 API 型別和 MUI 的 prop 型別，無其他依賴

### Q：為什麼 CONSECUTIVE = 3 而不是 5 或 10？

A：這是 domain knowledge（系統監控領域）的決策：
- 太少（1 點）：alert storm，用戶疲勞
- 太多（5~10 點 = 10~20 秒）：真告警延遲太久，可能錯過窗口
- 3 點（= 6 秒）：業界監控系統的常見設定，如 Grafana 的預設 evaluation interval

### Q：ChartComponents 的 slotProps 設計思路？

A：這是 API 設計的「閘道」概念。我們不可能預測所有消費者需求，但又不想讓套件成為 MUI 的薄薄透傳。`slotProps` 讓消費者在確實需要時可以直達 MUI，而不需要等套件升版。代價是消費者需要知道底層 MUI API，但這是他們的自由選擇（escape hatch 不是主線 API）。

### Q：為什麼不在 ChartComponents 內做 React.memo？

A：SSE 每 2 秒推送，Dashboard 用 `[...prev, data]` 更新 history，這個 spread 每次都產生新陣列 reference。React.memo 的淺比較在這裡永遠失敗（reference 變了），memo 開銷反而成本大於收益。正確的 memoization 位置是 Dashboard 端：`useMemo(() => datasets, [history])` 確保 datasets 只在 history 真的變化時才重建。

---

## 附錄：關鍵數字速查

| 項目 | 數值 |
|------|------|
| SSE 推送間隔 | 2 秒 |
| Ring buffer 大小 | 150 筆（= 5 分鐘） |
| 心跳間隔 | 15 秒（防 Nginx 60s timeout）|
| CPU warning 閾值 | > 70% |
| CPU critical 閾值 | > 85% |
| 告警觸發條件 | 連續 3 點（= 6 秒）|
| RWD 斷點 sm | >= 600px（平板）|
| RWD 斷點 md | >= 900px（桌面）|
| LTTB 降採樣閾值 | > 300 點 |
| Canvas 切換閾值 | > 10,000 點 |
| Web Worker 閾值 | > 5,000 點 |
| 測試數量 | 81 個測試 / 8 個檔案 |
| Bundle 後首屏時間 | ~510ms（遠 < 2 秒）|
| Critical 動畫週期 | 2 秒 pulse glow |
