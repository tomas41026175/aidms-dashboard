# Chart Components Domain Research

> 版本：v1.0 | 日期：2026-03-11
> 適用：`@aidms/chart-components` npm 套件開發，基於 `@mui/x-charts` v7

---

## 1. ChartData 介面設計

### 1.1 各圖表所需數據欄位

#### LineChart（折線圖）

```typescript
// 方式 A：直接傳入 data 陣列（適合靜態資料）
interface LineSeriesItem {
  id?: string;                        // 選填，多 series 時必填以供區分
  data: (number | null)[];            // 必填，null 代表缺值（連線中斷）
  label?: string | ((location: 'tooltip' | 'legend') => string);
  color?: string;                     // 選填，不設則套用主題色序
  curve?: 'linear' | 'monotoneX' | 'monotoneY' | 'catmullRom' | 'natural' | 'step' | 'stepBefore' | 'stepAfter';
  area?: boolean;                     // 是否填滿面積
  stack?: string;                     // 同 stack key 的 series 會疊加
  connectNulls?: boolean;             // null 點是否連線，預設 false
  showMark?: boolean | ((params: ShowMarkParams) => boolean);
  valueFormatter?: (value: number | null) => string; // tooltip/legend 格式化
  xAxisId?: string;                   // 多軸時指定使用哪條 X 軸
  yAxisId?: string;                   // 多軸時指定使用哪條 Y 軸
}

// xAxis 必填（資料點對應的 X 值）
interface XAxisConfig {
  id?: string;
  data?: number[] | string[] | Date[];  // 與 series[].data 等長
  dataKey?: string;                     // 使用 dataset 時改用此方式
  scaleType?: 'linear' | 'band' | 'point' | 'time' | 'utc' | 'log';
  label?: string;
  valueFormatter?: (value: unknown) => string;
}
```

**系統監控使用情境：**
```typescript
// CPU / Memory 歷史趨勢，5 分鐘 150 點
const series: LineSeriesItem[] = [
  { id: 'cpu', data: cpuHistory, label: 'CPU %', color: '#3b82f6' },
  { id: 'mem', data: memHistory, label: 'Memory %', color: '#8b5cf6' },
];
const xAxis: XAxisConfig[] = [
  { data: timestamps, scaleType: 'time', valueFormatter: (v) => format(v, 'HH:mm:ss') }
];
```

#### BarChart（柱狀圖）

```typescript
// 方式 A：直接 data 陣列
interface BarSeriesItem {
  id?: string;
  data: (number | null)[];
  label?: string | ((location: 'tooltip' | 'legend') => string);
  color?: string;
  stack?: string;          // 相同 stack key 會疊加（必填欄位用於 stacked mode）
  layout?: 'horizontal' | 'vertical';  // 覆寫整體 layout
  stackOffset?: 'diverging' | 'expand' | 'none' | 'silhouette' | 'wiggle';
  valueFormatter?: (value: number | null) => string;
  xAxisId?: string;
  yAxisId?: string;
}

// xAxis 配置（vertical bar 的類別軸）
// scaleType: 'band'  → 類別型（最常用）
// scaleType: 'point' → 點位型（適合有序數值類別）
```

**系統監控使用情境：**
```typescript
// 各磁碟分區使用率對比
const series: BarSeriesItem[] = [
  { data: usedList, label: '已用', stack: 'disk', color: '#ef4444' },
  { data: freeList, label: '剩餘', stack: 'disk', color: '#22c55e' },
];
const xAxis: XAxisConfig[] = [
  { data: mountpoints, scaleType: 'band' }
];
```

#### GaugeChart（儀表圖）

```typescript
interface GaugeConfig {
  value: number | null;    // 必填，null 不顯示數值
  valueMin?: number;       // 預設 0
  valueMax?: number;       // 預設 100
  text?: string | ((params: { value: number | null; valueMin: number; valueMax: number }) => string | null);
  startAngle?: number;     // 弧度起始角，預設 0（完整圓）；-110 適合半圓儀表
  endAngle?: number;       // 弧度結束角，預設 360；110 搭配上方做半圓
  innerRadius?: number | string; // 預設 '80%'
  outerRadius?: number | string; // 預設 '100%'
  cornerRadius?: number;   // 預設 0，>0 弧角效果
  cx?: number | string;    // 弧心 X，預設居中
  cy?: number | string;    // 弧心 Y，預設居中
}
```

**系統監控使用情境：**
```typescript
// CPU 使用率半圓儀表（Level 1 Hero 元件）
const gaugeConfig: GaugeConfig = {
  value: 73.5,
  valueMin: 0,
  valueMax: 100,
  startAngle: -110,
  endAngle: 110,
  text: ({ value }) => `${value?.toFixed(1) ?? '--'}%`,
};
```

---

### 1.2 統一 ChartData 介面設計決策

**結論：各圖表用獨立介面，共用 base 型別。**

理由：
- GaugeChart 的資料模型（單一數值）與 LineChart/BarChart（時間序列陣列）本質不同，強行統一會造成 optional 欄位爆炸
- 系統監控 context 中，三種圖表從不同資料來源取數（即時值 vs 歷史陣列 vs 分區列表）

```typescript
// packages/chart-components/src/types.ts

/** 共用基底：系列的視覺設定 */
export interface BaseSeriesConfig {
  id?: string;
  label?: string | ((location: 'tooltip' | 'legend') => string);
  color?: string;
  valueFormatter?: (value: number | null) => string;
}

/** 折線圖系列 */
export interface LineSeriesConfig extends BaseSeriesConfig {
  data: (number | null)[];
  curve?: 'linear' | 'monotoneX' | 'monotoneY' | 'catmullRom' | 'natural' | 'step' | 'stepBefore' | 'stepAfter';
  area?: boolean;
  stack?: string;
  connectNulls?: boolean;
  showMark?: boolean;
  xAxisId?: string;
  yAxisId?: string;
}

/** 柱狀圖系列 */
export interface BarSeriesConfig extends BaseSeriesConfig {
  data: (number | null)[];
  stack?: string;
  stackOffset?: 'diverging' | 'expand' | 'none' | 'silhouette' | 'wiggle';
  xAxisId?: string;
  yAxisId?: string;
}

/** 儀表圖資料（非陣列，單一量測值） */
export interface GaugeData {
  value: number | null;
  valueMin?: number;  // default: 0
  valueMax?: number;  // default: 100
}

/** 軸配置（LineChart / BarChart 共用） */
export interface AxisConfig {
  id?: string;
  data?: (number | string | Date)[];
  dataKey?: string;
  scaleType?: 'linear' | 'band' | 'point' | 'time' | 'utc' | 'log' | 'pow' | 'sqrt';
  label?: string;
  min?: number;
  max?: number;
  valueFormatter?: (value: unknown) => string;
  reverse?: boolean;
}
```

---

### 1.3 多組數據（Multi-Series）API 設計

MUI x-charts 原生支援多 series，設計原則：

```typescript
// 方式一：series 陣列（推薦，最直觀）
<LineChart
  series={[
    { id: 'cpu', data: cpuData, label: 'CPU' },
    { id: 'mem', data: memData, label: 'Memory' },
  ]}
  xAxis={[{ data: timestamps, scaleType: 'time' }]}
/>

// 方式二：dataset + dataKey（適合後端回傳統一格式）
// dataset: [{ ts: Date, cpu: 73, mem: 61 }, ...]
<LineChart
  dataset={metricsHistory}
  series={[
    { dataKey: 'cpu', label: 'CPU' },
    { dataKey: 'mem', label: 'Memory' },
  ]}
  xAxis={[{ dataKey: 'ts', scaleType: 'time' }]}
/>
```

**系統監控建議用 方式一**：SSE 推送的 sliding window 以陣列形式維護，直接對應 `data` prop 最無縫。

---

### 1.4 必填 vs 選填邊界

| 欄位 | 狀態 | 理由 |
|---|---|---|
| `series[].data` | 必填 | 無資料無法渲染 |
| `xAxis[].data` (LineChart) | 必填 | X 軸值缺失會導致點位無法對應 |
| `xAxis[].data` (BarChart) | 必填 | 類別標籤缺失 |
| `GaugeData.value` | 必填但允許 null | null 代表「載入中/無資料」 |
| `series[].id` | 單 series 選填，多 series 必填 | MUI 內部依 id 追蹤，缺失時動畫/highlight 會錯亂 |
| `series[].label` | 選填 | 無 legend 時可省略 |
| `series[].color` | 選填 | 主題色序自動分配 |
| `xAxis[].scaleType` | 選填（預設 'linear'） | 時間軸必須明確指定 'time' 否則格式化錯誤 |
| `GaugeData.valueMin/Max` | 選填（0/100） | 大多數百分比指標不需修改 |

---

## 2. @mui/x-charts v7 API 重點

### 2.1 LineChart 正確用法

```typescript
import { LineChart } from '@mui/x-charts/LineChart';
// 或從主包 import（tree-shaking 較差，不推薦）
// import { LineChart } from '@mui/x-charts';

// 最小可用範例
<LineChart
  series={[{ data: [2, 5.5, 2, 8.5, 1.5, 5] }]}
  xAxis={[{ data: [1, 2, 3, 5, 8, 10] }]}
  height={300}
  // width 不設 → 自動填滿父容器寬度
/>

// 完整系統監控範例
<LineChart
  series={[
    {
      id: 'cpu',
      data: cpuHistory,       // (number | null)[]，長度 <= 150
      label: 'CPU',
      color: '#3b82f6',
      curve: 'monotoneX',     // 時間序列用 monotoneX 最自然
      showMark: false,        // 150 點時關閉 mark 提升效能
      connectNulls: false,    // 數據缺失時斷線（明確缺資料）
      valueFormatter: (v) => v !== null ? `${v.toFixed(1)}%` : 'N/A',
    },
  ]}
  xAxis={[{
    id: 'time',
    data: timestamps,         // Date[]
    scaleType: 'time',
    valueFormatter: (v: Date) => format(v, 'HH:mm:ss'),
  }]}
  yAxis={[{ min: 0, max: 100, label: '%' }]}
  height={200}
  grid={{ horizontal: true }}
  axisHighlight={{ x: 'line' }}  // hover 顯示垂直參考線
  skipAnimation                  // SSE 即時更新時關閉動畫
  margin={{ left: 40, right: 16, top: 16, bottom: 40 }}
/>
```

**重要：`xAxis[].data` 長度必須與 `series[].data` 長度一致**，否則 MUI 不報錯但圖表顯示異常。

---

### 2.2 BarChart：Horizontal / Vertical / Stack

```typescript
import { BarChart } from '@mui/x-charts/BarChart';

// Vertical（預設）
<BarChart
  xAxis={[{ data: ['/', '/home', '/var'], scaleType: 'band' }]}
  series={[{ data: [65, 42, 88], label: 'Used %' }]}
  height={300}
/>

// Horizontal（磁碟分區對比很適合）
<BarChart
  dataset={diskPartitions}
  yAxis={[{ dataKey: 'mountpoint', scaleType: 'band' }]}
  xAxis={[{ label: 'Usage %', min: 0, max: 100 }]}
  series={[{ dataKey: 'percent', label: 'Used %' }]}
  layout="horizontal"
  height={200}
/>

// Stacked（Used + Free = 100%）
<BarChart
  xAxis={[{ data: mountpoints, scaleType: 'band' }]}
  series={[
    { data: usedList, label: 'Used', stack: 'disk', color: '#ef4444' },
    { data: freeList, label: 'Free', stack: 'disk', color: '#22c55e' },
  ]}
  height={300}
/>
```

**Stack 機制：** 相同 `stack` 字串的 series 會疊加。`stackOffset` 預設 `'diverging'`（負值分左右）；百分比 stacked 用 `'expand'`。

---

### 2.3 Gauge 用法

```typescript
import { Gauge, gaugeClasses } from '@mui/x-charts/Gauge';

// 完整圓形儀表（預設）
<Gauge value={73} />

// 半圓儀表（系統監控常見樣式）
<Gauge
  value={73.5}
  valueMin={0}
  valueMax={100}
  startAngle={-110}
  endAngle={110}
  text={({ value, valueMax }) =>
    value !== null ? `${value.toFixed(1)}%` : '--'
  }
  sx={{
    [`& .${gaugeClasses.valueText}`]: {
      fontSize: 28,
      fontWeight: 'bold',
    },
    [`& .${gaugeClasses.valueArc}`]: {
      fill: value > 85 ? '#ef4444' : value > 70 ? '#f59e0b' : '#22c55e',
    },
  }}
/>

// Null 值（載入中）
<Gauge value={null} text={() => '載入中...'} />
```

**`text` prop 簽名：**
```typescript
text?: string | ((params: {
  value: number | null;
  valueMin: number;
  valueMax: number;
}) => string | null)
```

返回 `null` 時不顯示文字。

---

### 2.4 Responsive 設定

**核心原則：不傳 `width` → 自動填滿父容器。**

```typescript
// 方式一：只設 height，width 自動（最常用）
<Box sx={{ width: '100%' }}>
  <LineChart
    series={series}
    xAxis={xAxis}
    height={200}
    // width 省略
  />
</Box>

// 方式二：resolveSizeBeforeRender（Grid 佈局中避免初次渲染閃爍）
<LineChart
  series={series}
  xAxis={xAxis}
  height={200}
  resolveSizeBeforeRender  // 等父容器 size 確定後再渲染
/>
```

**原理：** 底層 `ResponsiveChartContainer` 透過 `ResizeObserver` 監聽父容器，動態注入 `width`。確保父容器有明確寬度（`width: '100%'` 或 `flex: 1`）。

**注意事項：**
1. 父容器必須是 block 或 flex 元素，`display: inline` 會導致寬度為 0
2. 在 CSS Grid 中建議加 `resolveSizeBeforeRender` 防止首次渲染時寬度計算錯誤
3. 若父容器本身也是 responsive，建議加 `min-width: 0` 防止 flex 子元素溢出

---

### 2.5 `sx` 樣式覆蓋

MUI x-charts 提供 CSS class 常數，搭配 `sx` prop：

```typescript
import {
  lineElementClasses,
  areaElementClasses,
  markElementClasses,
} from '@mui/x-charts/LineChart';
import { barElementClasses } from '@mui/x-charts/BarChart';
import { gaugeClasses } from '@mui/x-charts/Gauge';
import { axisClasses } from '@mui/x-charts/ChartsAxis';

// LineChart 樣式
<LineChart
  sx={{
    // 所有線條
    [`& .${lineElementClasses.root}`]: {
      strokeWidth: 2,
    },
    // 特定 series（用 data-series-id attribute）
    [`& .${lineElementClasses.root}[data-series-id="cpu"]`]: {
      stroke: '#3b82f6',
    },
    // 座標軸文字
    [`& .${axisClasses.tickLabel}`]: {
      fontSize: '11px',
      fill: '#6b7280',
    },
  }}
/>

// Gauge 狀態色（根據 value 動態調整）
<Gauge
  value={cpuPercent}
  sx={{
    [`& .${gaugeClasses.valueArc}`]: {
      fill: cpuPercent > 85 ? '#ef4444'
          : cpuPercent > 70 ? '#f59e0b'
          : '#22c55e',
      transition: 'fill 0.5s ease',
    },
    [`& .${gaugeClasses.referenceArc}`]: {
      fill: '#1e293b',
    },
  }}
/>
```

---

## 3. 錯誤處理設計

### 3.1 常見數據格式錯誤

| 錯誤類型 | 發生原因 | 後果 |
|---|---|---|
| `series[].data` 長度與 `xAxis[].data` 不一致 | SSE 推送時點數不同步 | 圖表無聲渲染錯誤，X 值對應錯誤 |
| `series[].data` 含 `undefined`（非 `null`） | TypeScript 沒嚴格把關 | MUI 內部計算報錯，整個圖白屏 |
| `series[].data` 為空陣列 `[]` | 初始化前渲染 | 圖表空白，無報錯（可接受） |
| `GaugeData.value` 超出 `valueMin/Max` 範圍 | 數值異常（> 100%） | Arc 渲染溢出 |
| 全為 `NaN` | API 回傳格式錯誤 | y-axis domain 計算失敗 |
| `xAxis[].data` 為 `Date` 但未設 `scaleType: 'time'` | 忘記設定 | X 軸顯示時間戳數字而非格式化時間 |
| 單一資料點（length === 1） | 剛連線時 | 折線圖無法畫線（只有點），不算錯誤但要預期 |

---

### 3.2 Error Boundary vs 元件內部 try/catch

**結論：兩者都要，職責分離。**

```
Error Boundary（外層）  → 捕捉 MUI 內部渲染錯誤（罕見但難以預防）
元件內部驗證（進入前）  → 攔截可預期的資料格式錯誤，給出有意義的 UI feedback
```

```typescript
// 元件內部型別驗證（進入 MUI 渲染前攔截）
function validateLineChartData(
  series: LineSeriesConfig[],
  xAxis: AxisConfig[]
): { valid: true } | { valid: false; reason: string } {
  if (series.length === 0) {
    return { valid: false, reason: 'series 不能為空陣列' };
  }
  if (xAxis.length === 0 || !xAxis[0].data) {
    return { valid: false, reason: 'xAxis[0].data 必填' };
  }

  const xLen = xAxis[0].data.length;
  for (const s of series) {
    if (s.data.length !== xLen) {
      return {
        valid: false,
        reason: `series "${s.id ?? s.label}" 長度 ${s.data.length} 與 xAxis 長度 ${xLen} 不一致`
      };
    }
    if (s.data.some((v) => v !== null && !Number.isFinite(v))) {
      return {
        valid: false,
        reason: `series "${s.id ?? s.label}" 含有非有限數值（NaN 或 Infinity）`
      };
    }
  }
  return { valid: true };
}
```

**型別驗證方案選擇：zod vs 手動 type guard**

| 方案 | 優點 | 缺點 |
|---|---|---|
| **手動 type guard** | 零依賴、bundle 小、錯誤訊息可客製 | 要自己維護 |
| **zod** | Schema 可重用、自動型別推導 | bundle +13KB（minified+gzipped），對 npm 套件有影響 |

**建議：用手動 type guard**。這是 npm 套件，要控制 bundle size；錯誤邏輯也不複雜，不需 zod 的完整驗證能力。

---

### 3.3 錯誤 UX 設計

**結論：用 placeholder（佔位元件），不用 Alert 或 Tooltip。**

理由：系統監控儀表板是即時更新的，Alert 會干擾頁面流程；錯誤多為暫時性（資料未到），佔位元件更自然。

```typescript
// ChartErrorFallback.tsx
interface ChartErrorFallbackProps {
  reason?: string;
  height: number;
  width?: string | number;
}

export function ChartErrorFallback({ reason, height, width = '100%' }: ChartErrorFallbackProps) {
  return (
    <Box
      sx={{
        width,
        height,
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        bgcolor: 'background.paper',
        border: '1px dashed',
        borderColor: 'divider',
        borderRadius: 1,
        gap: 1,
      }}
    >
      <Typography variant="body2" color="text.disabled">
        {reason ?? '圖表資料無效'}
      </Typography>
    </Box>
  );
}

// ChartLoadingFallback.tsx（資料為空時）
export function ChartLoadingFallback({ height }: { height: number }) {
  return (
    <Skeleton variant="rectangular" width="100%" height={height} sx={{ borderRadius: 1 }} />
  );
}
```

**在各圖表元件中的使用模式：**
```typescript
export function LineChartWrapper({ series, xAxis, height }: LineChartWrapperProps) {
  // 空資料 → Skeleton
  if (series.every((s) => s.data.length === 0)) {
    return <ChartLoadingFallback height={height} />;
  }

  // 格式錯誤 → Placeholder with reason
  const validation = validateLineChartData(series, xAxis);
  if (!validation.valid) {
    return <ChartErrorFallback reason={validation.reason} height={height} />;
  }

  // 正常渲染
  return <LineChart series={...} xAxis={...} height={height} />;
}
```

---

## 4. TDD 測試策略

### 4.1 測試環境設定

**主要挑戰：** MUI x-charts 渲染 SVG，React Testing Library 的語意查詢（`getByRole`, `getByText`）在 SVG 中效果有限，且 `ResizeObserver` 在 jsdom 不存在。

```typescript
// vitest.config.ts
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/test/setup.ts'],
  },
});
```

```typescript
// src/test/setup.ts
import '@testing-library/jest-dom';
import { vi } from 'vitest';

// MUI x-charts 底層使用 ResizeObserver，jsdom 不支援，必須 mock
global.ResizeObserver = vi.fn().mockImplementation(() => ({
  observe: vi.fn(),
  unobserve: vi.fn(),
  disconnect: vi.fn(),
}));

// SVGElement.getTotalLength（某些動畫效果使用）
Object.defineProperty(SVGElement.prototype, 'getTotalLength', {
  value: () => 0,
  writable: true,
});

// matchMedia（MUI 主題 breakpoint 使用）
Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: vi.fn().mockImplementation((query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: vi.fn(),
    removeListener: vi.fn(),
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    dispatchEvent: vi.fn(),
  })),
});
```

---

### 4.2 如何測試 MUI x-charts 元件

**核心策略：測試行為，不測 SVG 結構。**

MUI x-charts 的 SVG 結構不是 public API，可能在小版本更新。測試應聚焦：
1. 元件是否正常 mount（不 throw）
2. 正確的 fallback 是否顯示
3. Props 是否正確傳遞（透過 wrapper 元件的狀態）

```typescript
// src/test/helpers.ts
import { render, RenderOptions } from '@testing-library/react';
import { ThemeProvider, createTheme } from '@mui/material/styles';
import React from 'react';

const theme = createTheme();

export function renderWithTheme(ui: React.ReactElement, options?: RenderOptions) {
  return render(
    <ThemeProvider theme={theme}>{ui}</ThemeProvider>,
    options
  );
}

// SVG 元素查詢 helper（SVG 元素通常無語意 role）
export function getChartContainer(container: HTMLElement) {
  return container.querySelector('svg');
}
```

---

### 4.3 建議測試場景與範例

```typescript
// LineChartWrapper.test.tsx
import { screen } from '@testing-library/react';
import { describe, it, expect } from 'vitest';
import { LineChartWrapper } from '../LineChartWrapper';
import { renderWithTheme, getChartContainer } from '../test/helpers';

const validSeries = [{ id: 'cpu', data: [10, 20, 30], label: 'CPU' }];
const validXAxis = [{ data: [1, 2, 3] }];

describe('LineChartWrapper', () => {
  // --- 正常渲染 ---
  it('正常數據應渲染 SVG 圖表', () => {
    const { container } = renderWithTheme(
      <LineChartWrapper series={validSeries} xAxis={validXAxis} height={200} />
    );
    expect(getChartContainer(container)).toBeInTheDocument();
  });

  it('多 series 應全部渲染', () => {
    const multiSeries = [
      { id: 'cpu', data: [10, 20, 30], label: 'CPU' },
      { id: 'mem', data: [40, 50, 60], label: 'Memory' },
    ];
    const { container } = renderWithTheme(
      <LineChartWrapper series={multiSeries} xAxis={validXAxis} height={200} />
    );
    expect(getChartContainer(container)).toBeInTheDocument();
  });

  // --- 空資料 ---
  it('空 series data 應顯示 Skeleton（載入狀態）', () => {
    const emptySeries = [{ id: 'cpu', data: [], label: 'CPU' }];
    renderWithTheme(
      <LineChartWrapper series={emptySeries} xAxis={[{ data: [] }]} height={200} />
    );
    // MUI Skeleton 有 aria-busy 屬性
    expect(screen.getByRole('progressbar', { hidden: true })).toBeInTheDocument();
    // 或查詢 test-id
    // expect(screen.getByTestId('chart-loading')).toBeInTheDocument();
  });

  // --- 單一資料點 ---
  it('單一資料點不應報錯', () => {
    const singlePoint = [{ id: 'cpu', data: [73.5], label: 'CPU' }];
    expect(() =>
      renderWithTheme(
        <LineChartWrapper series={singlePoint} xAxis={[{ data: [Date.now()] }]} height={200} />
      )
    ).not.toThrow();
  });

  // --- 錯誤數據 ---
  it('series 長度與 xAxis 不一致應顯示 error fallback', () => {
    const mismatchedSeries = [{ id: 'cpu', data: [10, 20, 30], label: 'CPU' }];
    const mismatchedAxis = [{ data: [1, 2] }];  // 長度 2 vs 3
    renderWithTheme(
      <LineChartWrapper series={mismatchedSeries} xAxis={mismatchedAxis} height={200} />
    );
    expect(screen.getByText(/長度.*不一致/)).toBeInTheDocument();
  });

  it('含 NaN 數值應顯示 error fallback', () => {
    const nanSeries = [{ id: 'cpu', data: [10, NaN, 30], label: 'CPU' }];
    renderWithTheme(
      <LineChartWrapper series={nanSeries} xAxis={validXAxis} height={200} />
    );
    expect(screen.getByText(/非有限數值/)).toBeInTheDocument();
  });

  it('data 含 null（缺值）應正常渲染（不視為錯誤）', () => {
    const nullSeries = [{ id: 'cpu', data: [10, null, 30], label: 'CPU' }];
    const { container } = renderWithTheme(
      <LineChartWrapper series={nullSeries} xAxis={validXAxis} height={200} />
    );
    expect(getChartContainer(container)).toBeInTheDocument();
  });
});
```

```typescript
// GaugeChart.test.tsx
describe('GaugeChartWrapper', () => {
  it('正常值應渲染 SVG', () => {
    const { container } = renderWithTheme(
      <GaugeChartWrapper value={73.5} valueMax={100} height={200} />
    );
    expect(container.querySelector('svg')).toBeInTheDocument();
  });

  it('value 為 null 應顯示 loading text', () => {
    renderWithTheme(
      <GaugeChartWrapper value={null} height={200} />
    );
    // 依照 text prop 設定
    expect(screen.getByText('--')).toBeInTheDocument();
  });

  it('value 超過 valueMax 不應 throw（MUI 允許但視覺溢出）', () => {
    expect(() =>
      renderWithTheme(<GaugeChartWrapper value={150} valueMax={100} height={200} />)
    ).not.toThrow();
  });
});
```

---

### 4.4 Mock @mui/x-charts 的正確方式

**只在測試輔助性邏輯（不需要真實渲染）時 mock，一般不建議完全 mock 整個套件。**

```typescript
// 若需要 mock（例如測試 wrapper 的 prop 傳遞邏輯）：
vi.mock('@mui/x-charts/LineChart', () => ({
  LineChart: vi.fn(({ series, xAxis, height, 'data-testid': testId }) => (
    <div
      data-testid={testId ?? 'mocked-line-chart'}
      data-series-count={series.length}
      data-height={height}
    />
  )),
  lineElementClasses: { root: 'line-element-root' },
  areaElementClasses: { root: 'area-element-root' },
}));

// 測試 wrapper 是否正確傳遞 props
it('應將 skipAnimation prop 傳入 LineChart', () => {
  renderWithTheme(
    <LineChartWrapper series={validSeries} xAxis={validXAxis} height={200} skipAnimation />
  );
  const chart = screen.getByTestId('mocked-line-chart');
  // 驗證 prop 傳遞
  expect(chart).toHaveAttribute('data-series-count', '1');
});
```

**何時不應 mock：** 測試錯誤 fallback、空資料 Skeleton、及任何依賴真實 SVG 渲染的測試，都應使用真實元件（搭配 ResizeObserver mock）。

---

### 4.5 Responsive 行為測試

```typescript
it('width 不設時應填滿父容器（ResponsiveChartContainer 接管）', () => {
  // 設定父容器寬度
  Object.defineProperty(HTMLElement.prototype, 'clientWidth', {
    configurable: true,
    value: 800,
  });

  const { container } = renderWithTheme(
    <Box sx={{ width: 800 }}>
      <LineChartWrapper series={validSeries} xAxis={validXAxis} height={200} />
    </Box>
  );
  // SVG 應存在（ResizeObserver mock 會立即觸發 size 確定）
  expect(container.querySelector('svg')).toBeInTheDocument();
});
```

---

## 5. npm 套件封裝最佳實踐

### 5.1 Peer Dependencies 設定

```json
// ChartComponents/package.json
{
  "name": "@aidms/chart-components",
  "version": "0.1.0",
  "peerDependencies": {
    "react": "^18.0.0 || ^19.0.0",
    "react-dom": "^18.0.0 || ^19.0.0",
    "@mui/material": "^5.15.14 || ^6.0.0 || ^7.0.0",
    "@mui/system": "^5.15.14 || ^6.0.0 || ^7.0.0",
    "@emotion/react": "^11.9.0",
    "@emotion/styled": "^11.8.1",
    "@mui/x-charts": "^7.0.0"
  },
  "peerDependenciesMeta": {
    "@emotion/react": { "optional": true },
    "@emotion/styled": { "optional": true }
  },
  "devDependencies": {
    "react": "^19.0.0",
    "react-dom": "^19.0.0",
    "@mui/material": "^7.0.0",
    "@mui/system": "^7.0.0",
    "@emotion/react": "^11.9.0",
    "@emotion/styled": "^11.8.1",
    "@mui/x-charts": "^7.28.0",
    "typescript": "^5.0.0",
    "tsup": "^8.0.0",
    "vitest": "^2.0.0",
    "@testing-library/react": "^16.0.0",
    "@testing-library/jest-dom": "^6.0.0",
    "@vitejs/plugin-react": "^4.0.0"
  }
}
```

**版本範圍設計原則：**
- `react`：支援 18 和 19，用 `||` 語法
- `@mui/x-charts`：只鎖 major `^7.0.0`，不鎖 minor（讓使用者升 patch/minor）
- `@emotion/*`：標為 optional，因為使用者可能用 styled-components

---

### 5.2 Tree-shaking 支援

**關鍵：package.json 中設定 `"sideEffects": false`**

```json
{
  "sideEffects": false
}
```

這告訴 bundler（Vite/webpack）此套件所有模組都可安全 tree-shake。

**額外注意：**
```typescript
// 從子路徑 import（推薦），避免引入整個 @mui/x-charts
import { LineChart } from '@mui/x-charts/LineChart';  // ✓ 只引入 LineChart
import { LineChart } from '@mui/x-charts';             // ✗ 引入整包

// 套件自身的 index.ts 要用具名 export
export { LineChartWrapper } from './components/LineChartWrapper';
export { BarChartWrapper } from './components/BarChartWrapper';
export { GaugeChartWrapper } from './components/GaugeChartWrapper';
export type { LineSeriesConfig, BarSeriesConfig, GaugeData, AxisConfig } from './types';
// 不要用 export * from './components'（阻礙 tree-shaking 分析）
```

---

### 5.3 tsup 最佳配置

```typescript
// ChartComponents/tsup.config.ts
import { defineConfig } from 'tsup';

export default defineConfig({
  entry: ['src/index.ts'],
  format: ['esm', 'cjs'],       // 同時輸出 ESM + CJS
  dts: true,                     // 產生 .d.ts 型別宣告
  splitting: false,              // React 元件套件通常不需 code splitting
  sourcemap: true,
  clean: true,                   // 每次 build 前清空 dist/
  external: [                    // peer deps 不打包進去
    'react',
    'react-dom',
    '@mui/material',
    '@mui/system',
    '@emotion/react',
    '@emotion/styled',
    '@mui/x-charts',
    '@mui/x-charts/LineChart',
    '@mui/x-charts/BarChart',
    '@mui/x-charts/Gauge',
  ],
  esbuildOptions(options) {
    // 確保 JSX 轉換使用 React 17+ automatic runtime
    options.jsx = 'automatic';
  },
});
```

**對應的 package.json exports field：**
```json
{
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
  "sideEffects": false
}
```

---

### 5.4 本地開發即時同步（DemoApp 看到 ChartComponents 變更）

**推薦方案：tsup watch + package.json workspace**

```json
// /Users/liangxuanzhang/work/aidms-dashboard/package.json（monorepo root）
{
  "name": "aidms-dashboard",
  "private": true,
  "workspaces": ["ChartComponents", "DemoApp"]
}
```

```json
// DemoApp/package.json
{
  "dependencies": {
    "@aidms/chart-components": "workspace:*"
  }
}
```

**開發工作流（兩個 terminal）：**
```bash
# Terminal 1：ChartComponents 持續 build（watch mode）
cd ChartComponents && pnpm tsup --watch

# Terminal 2：DemoApp 啟動
cd DemoApp && pnpm dev
```

`workspace:*` 協議會讓 DemoApp 直接連結到本地 `ChartComponents/dist/`，配合 `tsup --watch` 每次儲存後自動重 build，DemoApp 的 HMR 會偵測到 dist 變更並熱更新。

**備選方案：`"main": "src/index.ts"` 直接指向源碼（開發期）**
```json
// ChartComponents/package.json（開發期暫時）
{
  "main": "src/index.ts",
  "module": "src/index.ts"
}
```
好處：不需要 build step，DemoApp 的 Vite 直接 transpile ChartComponents 源碼。壞處：發布前必須記得改回 `dist/`，容易忘記。**不推薦**，用 workspace + tsup watch 更可靠。

---

## 6. 大量資料優化快速索引

> 完整方案見 [`docs/chart-large-data-optimization.md`](./chart-large-data-optimization.md)

### 各圖表閾值一覽

| 圖表 | 正常承受量 | 降採樣觸發 | Canvas 切換 |
|------|-----------|-----------|------------|
| LineChart | 150 點（SSE sliding window） | > 300 點（LTTB） | > 10k 點 |
| BarChart | < 50 bars | 50~200（水平捲動） | > 200（虛擬化） |
| GaugeChart | 單值，無上限 | — | — |

### SSE 場景（本專案 MVP）

```
MAX_POINTS = 150，2s interval = 5min 歷史
→ 完全不需要降採樣，直接 SVG 渲染
```

### 歷史回顧場景（[MVP-CUT]，未來擴充）

```
24h @ 2s = 43,200 點  → LTTB 降採樣到 300 點
7d @ 2s  = 302,400 點 → Canvas + Worker 降採樣
```

### LTTB vs Min-Max 選擇

```
視覺保真  → LTTB（預設）
告警峰值  → minmax（保留突刺）
```

### a11y 快速檢查清單

```
☐ LineChart/BarChart: role="img" + aria-label
☐ GaugeChart: role="meter" + aria-valuenow/min/max
☐ 色彩對比度 ≥ 4.5:1（WCAG AA）
☐ DataTableFallback skip link（僅 focus 時顯示）
```

---

## 附錄：快速參考卡

### series 長度一致性防護（必裝）
```typescript
// 所有接受 series + xAxis 的地方必須加此檢查
const xLen = xAxis[0]?.data?.length ?? 0;
const isConsistent = series.every((s) => s.data.length === xLen);
```

### 空值安全渲染決策樹
```
series[].data.length === 0 → <ChartLoadingFallback>
validateData() === invalid  → <ChartErrorFallback reason={...}>
value === null (Gauge)      → 渲染 Gauge，text prop 返回 '--'
data 含 null（非 NaN）      → 正常渲染，null 點會斷線
```

### 告警色與 Gauge 動態色對應（本專案）
```typescript
// 與 system-monitoring-domain.md 第 3 節對齊
function getStatusColor(value: number): string {
  if (value > 85) return '#ef4444';  // critical
  if (value > 70) return '#f59e0b';  // warning
  return '#22c55e';                   // normal
}
```

### @mui/x-charts v7 版本資訊
- 最新穩定版：**7.28.0**（截至 2026-03-11）
- peer: `react ^17 || ^18 || ^19`
- peer: `@mui/material ^5.15.14 || ^6 || ^7`
- sideEffects: false（原始套件已支援 tree-shaking）
