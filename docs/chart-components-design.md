# ChartComponents 設計方案（Staff Engineer 視角）

> 適用：`@aidms/chart-components` | 技術棧：@mui/material + @mui/x-charts v7
> 版本：v2.0

---

## 設計原則

1. **Consumer-first**：最常用的 case 要最簡單，零配置就能用
2. **Pit of Success**：難以誤用，錯誤在開發期大聲提示
3. **業務邏輯不進元件庫**：告警顏色、閾值是 Dashboard 的責任
4. **可測試性優先**：70% 邏輯是純函式，不需要 DOM

---

## 1. API 設計（三層漸進式）

```typescript
// Level 1：最常用（覆蓋 80% 場景，零配置）
<LineChart
  labels={timestamps}
  datasets={[
    { label: 'CPU', data: cpuHistory },
    { label: 'Memory', data: memHistory },
  ]}
/>

// Level 2：進階配置
<LineChart
  labels={timestamps}
  datasets={[...]}
  height={200}
  yRange={[0, 100]}
  curve="smooth"
  animate={false}
/>

// Level 3：escape hatch（MUI 原生能力）
<LineChart
  labels={timestamps}
  datasets={[...]}
  slotProps={{
    xAxis: { tickLabelStyle: { fontSize: 10 } },
    lineChart: { grid: { horizontal: true } },
  }}
/>
```

---

## 2. 型別定義（Public API）

```typescript
// types.ts

// 共用 Dataset
interface Dataset {
  label: string;
  data: (number | null)[];   // null = 合法缺值（折線斷點）
  color?: string;
}

// 共用基底 Props
interface ChartBaseProps {
  height?: number;           // 預設 300
  title?: string;
  animate?: boolean;         // 預設 true；SSE 即時更新時設 false
}

// LineChart
interface LineChartProps extends ChartBaseProps {
  labels: (string | number | Date)[];
  datasets: Dataset[];
  curve?: 'linear' | 'smooth' | 'step';  // smooth = monotoneX
  fill?: boolean;                          // area fill，預設 false
  yRange?: [number, number];
  connectNulls?: boolean;                  // 預設 false
  slotProps?: {
    lineChart?: Record<string, unknown>;
    xAxis?: Record<string, unknown>;
    yAxis?: Record<string, unknown>;
  };
}

// BarChart
interface BarChartProps extends ChartBaseProps {
  labels: string[];
  datasets: Dataset[];
  layout?: 'vertical' | 'horizontal';  // 預設 vertical
  stacked?: boolean;                    // 預設 false
  yRange?: [number, number];
  slotProps?: {
    barChart?: Record<string, unknown>;
    xAxis?: Record<string, unknown>;
    yAxis?: Record<string, unknown>;
  };
}

// GaugeChart（單一值，非陣列）
interface GaugeChartProps extends ChartBaseProps {
  value: number | null;                          // null = 載入中，顯示 '--'
  min?: number;                                  // 預設 0
  max?: number;                                  // 預設 100
  label?: string;
  formatValue?: (value: number) => string;       // 預設 (v) => `${v.toFixed(1)}%`
  arc?: 'full' | 'half';                         // 預設 'half'
  color?: string | ((value: number) => string);  // 靜態色或動態色函式
  slotProps?: { gauge?: Record<string, unknown> };
}
```

### 與 MUI 原生 API 的對照

| 我們的 API | MUI 原生 | 設計理由 |
|-----------|---------|---------|
| `labels` | `xAxis[0].data` | 消費者不需理解「軸配置」 |
| `datasets` | `series[]` | 更直覺的命名 |
| `curve: 'smooth'` | `curve: 'monotoneX'` | 隱藏 MUI 細節 |
| `yRange` | `yAxis[0].min/max` | 更扁平 |
| `animate` | `skipAnimation` | 語義正向（enable vs disable） |
| `color: fn` | `sx[gaugeClasses.valueArc]` | 消費者不需接觸 CSS class |
| `slotProps` | 各種 prop | Escape hatch，不卡住進階需求 |

---

## 3. 架構分層

```
Consumer
   │ labels + datasets + 簡單 props
   ▼
┌──────────────────────────────────┐
│  Rendering Layer                 │  職責：選擇渲染路徑（Skeleton / Error / Chart）
│  LineChart.tsx / BarChart.tsx    │        呼叫下方兩層，組裝 JSX
│  GaugeChart.tsx                  │
└──────────┬────────┬──────────────┘
           │        │
           ▼        ▼
┌────────────┐  ┌──────────────────────────────────┐
│ Validation │  │  Transform Layer                  │
│ Layer      │  │  transforms/to-line-props.ts      │
│            │  │  transforms/to-bar-props.ts       │
│ 純函式     │  │  transforms/to-gauge-props.ts     │
│ 無 DOM     │  │                                   │
│ 無 React   │  │  職責：我們的 API → MUI props     │
│            │  │  純函式，無 side effect            │
└────────────┘  └──────────────────────────────────┘
```

**核心設計原則：Transform Layer 是整個套件的核心價值。**

消費者寫 `labels + datasets`，Transform Layer 翻譯成 MUI 需要的 `xAxis + series`。這個翻譯是純函式，不需要 DOM，100% 可測試。

---

## 4. Transform Layer（核心邏輯）

```typescript
// transforms/to-line-props.ts

const CURVE_MAP = {
  linear: 'linear',
  smooth: 'monotoneX',
  step: 'step',
} as const;

export function toLineChartProps(props: LineChartProps) {
  const {
    labels, datasets,
    height = 300, curve = 'smooth', fill = false,
    yRange, connectNulls = false, animate = true,
    slotProps,
  } = props;

  // 自動偵測 scaleType
  const scaleType = labels[0] instanceof Date ? 'time'
    : typeof labels[0] === 'number' ? 'linear'
    : 'point';

  return {
    series: datasets.map((ds, i) => ({
      id: ds.label || `series-${i}`,
      data: ds.data,
      label: ds.label,
      color: ds.color,
      curve: CURVE_MAP[curve],
      area: fill,
      showMark: labels.length <= 30,  // 超過 30 點自動關閉 mark
      connectNulls,
    })),
    xAxis: [{ data: labels, scaleType, ...slotProps?.xAxis }],
    yAxis: [{ ...(yRange ? { min: yRange[0], max: yRange[1] } : {}), ...slotProps?.yAxis }],
    height,
    skipAnimation: !animate,
    ...slotProps?.lineChart,
  };
}
```

```typescript
// transforms/to-bar-props.ts
export function toBarChartProps(props: BarChartProps) {
  const { labels, datasets, height = 300, layout = 'vertical', stacked = false, yRange, slotProps } = props;

  const stack = stacked ? 'default' : undefined;

  const series = datasets.map((ds, i) => ({
    id: ds.label || `series-${i}`,
    data: ds.data,
    label: ds.label,
    color: ds.color,
    stack,
  }));

  // horizontal layout 需要交換軸配置
  const axisWithLabels = { data: labels, scaleType: 'band' as const, ...slotProps?.xAxis };
  const axisWithRange = { ...(yRange ? { min: yRange[0], max: yRange[1] } : {}), ...slotProps?.yAxis };

  return {
    series,
    xAxis: layout === 'vertical' ? [axisWithLabels] : [axisWithRange],
    yAxis: layout === 'vertical' ? [axisWithRange] : [axisWithLabels],
    layout,
    height,
    ...slotProps?.barChart,
  };
}
```

```typescript
// transforms/to-gauge-props.ts
const ARC_MAP = {
  half: { startAngle: -110, endAngle: 110 },
  full: { startAngle: 0, endAngle: 360 },
};

export function toGaugeProps(props: GaugeChartProps) {
  const {
    value, min = 0, max = 100,
    formatValue = (v) => `${v.toFixed(1)}%`,
    arc = 'half', color, height = 200, slotProps,
  } = props;

  const resolvedColor = typeof color === 'function' && value !== null
    ? color(value)
    : color;

  return {
    value: value !== null ? Math.min(Math.max(value, min), max) : null,  // clamp
    valueMin: min,
    valueMax: max,
    ...ARC_MAP[arc],
    text: ({ value: v }: { value: number | null }) =>
      v !== null ? formatValue(v) : '--',
    width: height,   // Gauge 保持正方形
    height,
    sx: resolvedColor ? {
      [`& .${gaugeClasses.valueArc}`]: {
        fill: resolvedColor,
        transition: 'fill 0.3s ease',
      },
    } : undefined,
    ...slotProps?.gauge,
  };
}
```

---

## 5. Validation Layer（純函式）

```typescript
// validation/validate-series.ts

type ValidationResult = { valid: true } | { valid: false; reason: string };

export function validateSeriesData(
  labels: unknown[],
  datasets: Dataset[],
): ValidationResult {
  if (datasets.length === 0)
    return { valid: false, reason: '至少需要一組數據（datasets 不能為空）' };

  const len = labels.length;
  for (const ds of datasets) {
    if (ds.data.length !== len) {
      const msg = `"${ds.label}" 資料長度 (${ds.data.length}) 與 labels 長度 (${len}) 不一致`;
      if (process.env.NODE_ENV !== 'production') console.error(`[ChartComponents] ${msg}`);
      return { valid: false, reason: msg };
    }
    if (ds.data.some(v => v !== null && !Number.isFinite(v))) {
      const msg = `"${ds.label}" 含有非有限數值（NaN 或 Infinity）`;
      if (process.env.NODE_ENV !== 'production') console.error(`[ChartComponents] ${msg}`);
      return { valid: false, reason: msg };
    }
  }
  return { valid: true };
}
```

**錯誤處理哲學：**
- 開發期：`console.error` + 視覺 fallback（雙重提醒）
- 生產期：只顯示 fallback，不洩漏內部資訊
- 永遠不 `throw`（圖表錯誤不應白屏整個頁面）
- `null` 是合法缺值，不視為錯誤

---

## 6. Rendering Layer（元件）

```typescript
// LineChart.tsx
export function LineChart(props: LineChartProps) {
  const { labels, datasets, height = 300 } = props;

  // 空資料 → Skeleton（等待 SSE 數據）
  if (datasets.every(ds => ds.data.length === 0)) {
    return <ChartSkeleton height={height} />;
  }

  // 驗證 → 失敗顯示 Error placeholder
  const validation = validateSeriesData(labels, datasets);
  if (!validation.valid) {
    return <ChartError reason={validation.reason} height={height} />;
  }

  // 轉換 → 渲染
  const muiProps = useMemo(
    () => toLineChartProps(props),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [labels, datasets, height, props.curve, props.fill, props.yRange, props.connectNulls, props.animate]
  );

  return <MuiLineChart {...muiProps} />;
}
```

**渲染決策樹：**
```
datasets 全為空陣列  →  ChartSkeleton（等待數據，非錯誤）
validateSeriesData 失敗  →  ChartError（格式問題）
通過  →  useMemo transform → MUI 元件
```

---

## 7. Fallback 元件

```typescript
// fallbacks/ChartSkeleton.tsx（空資料 → 載入中）
export function ChartSkeleton({ height }: { height: number }) {
  return <Skeleton variant="rectangular" width="100%" height={height} sx={{ borderRadius: 1 }} />;
}

// fallbacks/ChartError.tsx（格式錯誤 → 虛線框）
export function ChartError({ reason, height }: { reason?: string; height: number }) {
  return (
    <Box sx={{
      width: '100%', height,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      border: '1px dashed', borderColor: 'divider', borderRadius: 1,
    }}>
      <Typography variant="body2" color="text.disabled">
        {reason ?? '圖表資料無效'}
      </Typography>
    </Box>
  );
}
```

**為何用 placeholder 而非 Alert：** 監控儀表板是即時更新的，錯誤多為暫時性，placeholder 不干擾頁面流程。

---

## 8. 目錄結構

```
ChartComponents/src/
├── index.ts               # 具名 export，不用 export *
├── types.ts               # Public API 型別
│
├── validation/
│   ├── validate-series.ts  # Line/Bar 共用驗證（純函式）
│   └── validate-gauge.ts   # Gauge 驗證（純函式）
│
├── transforms/
│   ├── to-line-props.ts    # 我們的 API → MUI LineChart props（純函式）
│   ├── to-bar-props.ts
│   └── to-gauge-props.ts
│
├── fallbacks/
│   ├── ChartSkeleton.tsx
│   └── ChartError.tsx
│
├── LineChart.tsx            # Rendering layer（orchestrate 上方各層）
├── BarChart.tsx
└── GaugeChart.tsx
```

---

## 9. 業務邏輯邊界（重要）

元件庫**不應該**包含：
- 告警閾值（CPU 85% = Critical）
- 預設顏色語義（紅/黃/綠 對應什麼狀態）

這些由 **Dashboard 消費者側** 提供：

```typescript
// Dashboard 側（CpuSection.tsx）
import { getStatusColor } from '@/utils/alert-colors';

<GaugeChart
  value={metrics.cpu.usage}
  color={(value) => getStatusColor(value)}  // 業務邏輯在這裡
/>
```

---

## 10. Memoization 策略

**元件庫內部：** `useMemo` 包住 transform 呼叫，避免每次 re-render 都重新計算。

**消費者側（Dashboard）：** 消費者用 `useMemo` 穩定 datasets reference。

```typescript
// Dashboard 側
const cpuDatasets = useMemo(() => [{
  label: 'CPU',
  data: history.map(h => h.cpu.usage),
}], [history]);  // history 每 2 秒才變，datasets 只在 history 變時重建

<LineChart labels={timestamps} datasets={cpuDatasets} />
```

**元件庫不做 `React.memo`**：因為 SSE 推送時 datasets 每次都是新物件，淺比較永遠失敗，`React.memo` 形同虛設，反而增加複雜度。

---

## 11. Error Boundary 位置

```
App（一個 ErrorBoundary 就夠）
└── ErrorBoundary
    └── DashboardLayout
        ├── CpuSection
        │   ├── GaugeChart     ← 內部驗證處理可預期的資料問題
        │   └── BarChart       ← 內部驗證處理可預期的資料問題
        └── ...
```

元件庫不提供 ErrorBoundary（應用層的責任），但 README 建議消費者在 App 層級加一個，捕捉 MUI 內部的意外 crash。

---

## 12. TDD 測試計畫

### 測試分佈目標

```
純函式（validation + transforms）：70%  → 快、穩、無 DOM
元件測試（rendering + fallback）：30%  → 需要 DOM
```

### 測試環境 setup.ts（必要 mock）

```typescript
// ResizeObserver（jsdom 不支援）
global.ResizeObserver = vi.fn().mockImplementation(() => ({
  observe: vi.fn(), unobserve: vi.fn(), disconnect: vi.fn(),
}));

// SVGElement.getTotalLength
Object.defineProperty(SVGElement.prototype, 'getTotalLength', { value: () => 0, writable: true });

// matchMedia
Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: vi.fn().mockImplementation((query: string) => ({
    matches: false, media: query, onchange: null,
    addListener: vi.fn(), removeListener: vi.fn(),
    addEventListener: vi.fn(), removeEventListener: vi.fn(), dispatchEvent: vi.fn(),
  })),
});
```

### 測試場景

```
validation/validate-series.test.ts（純函式）:
  ✓ 空 datasets → invalid
  ✓ 長度一致 → valid
  ✓ 長度不一致 → invalid + 具體訊息
  ✓ NaN → invalid
  ✓ Infinity → invalid
  ✓ null → valid（合法缺值）
  ✓ 空 data（length 0）→ valid（由 Rendering 層處理 Skeleton）

transforms/to-line-props.test.ts（純函式）:
  ✓ Date labels → scaleType: 'time'
  ✓ string labels → scaleType: 'point'
  ✓ smooth → monotoneX
  ✓ 30+ 點 → showMark: false
  ✓ animate false → skipAnimation: true
  ✓ slotProps 合併正確

transforms/to-bar-props.test.ts（純函式）:
  ✓ stacked: true → 所有 series 有相同 stack key
  ✓ horizontal → 軸配置交換

transforms/to-gauge-props.test.ts（純函式）:
  ✓ half → startAngle: -110, endAngle: 110
  ✓ value clamp 在 min/max 之間
  ✓ color fn 正確套用

LineChart.test.tsx（元件）:
  ✓ 正常數據渲染 SVG
  ✓ 空 data → ChartSkeleton
  ✓ 長度不一致 → ChartError + 原因文字
  ✓ 開發模式驗證失敗 → console.error 被呼叫
  ✓ null 值 → 正常渲染（不是錯誤）

整合測試（題目要求）:
  scenarios/normal-rendering.test.tsx   ← 場景 1
  scenarios/error-handling.test.tsx     ← 場景 2
  scenarios/sse-reconnect.test.tsx      ← 場景 3
```

---

## 13. npm 封裝

### package.json 關鍵欄位

```json
{
  "name": "@aidms/chart-components",
  "main": "./dist/index.js",
  "module": "./dist/index.mjs",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": {
      "import": "./dist/index.mjs",
      "require": "./dist/index.js",
      "types": "./dist/index.d.ts"
    }
  },
  "files": ["dist"],
  "sideEffects": false,
  "peerDependencies": {
    "react": "^18.0.0 || ^19.0.0",
    "@mui/material": "^5.15.14 || ^6.0.0 || ^7.0.0",
    "@mui/x-charts": "^7.0.0",
    "@emotion/react": "^11.9.0",
    "@emotion/styled": "^11.8.1"
  }
}
```

### index.ts（具名 export，不用 `export *`）

```typescript
export { LineChart } from './LineChart';
export { BarChart } from './BarChart';
export { GaugeChart } from './GaugeChart';
export type { LineChartProps, BarChartProps, GaugeChartProps, Dataset } from './types';
```
