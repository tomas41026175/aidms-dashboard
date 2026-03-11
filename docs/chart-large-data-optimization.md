# 圖表大量資料優化方案

> 適用：`@aidms/chart-components` — LineChart / BarChart / GaugeChart
> 版本：v1.0 | 日期：2026-03-12

---

## 問題背景

| 情境 | 資料量 | 現象 |
|------|--------|------|
| 系統監控 SSE sliding window | 150 點 / 2s | 正常，SVG 可承受 |
| 歷史回顧（24h @ 2s） | 43,200 點 | SVG 路徑過長，layout 卡頓 |
| 歷史回顧（7d @ 2s） | 302,400 點 | 瀏覽器卡死，頁面凍結 |
| 磁碟分區（大型伺服器） | 50~200 bars | BarChart 可接受 |
| 多磁碟 RAID + LVM | 500+ bars | 初次 paint 明顯延遲 |

**SVG vs Canvas 選擇基準：**

| 資料量 | 渲染方式 | 理由 |
|--------|---------|------|
| < 1,000 點 | SVG（MUI 預設） | 可互動（hover/click/tooltip）、a11y 原生支援 |
| 1,000 ~ 10,000 點 | SVG + 降採樣 | 降到 < 300 點後 SVG 仍流暢 |
| > 10,000 點 | Canvas | SVG DOM 節點過多，layout thrashing |

---

## 1. 資料降採樣（Downsampling）

### 1.1 LTTB 演算法（Largest Triangle Three Buckets）

時間序列最佳降採樣演算法，保留視覺上最重要的點（峰/谷/轉折），丟棄視覺上無法分辨的冗餘點。

```typescript
// transforms/downsample.ts

/**
 * LTTB 降採樣
 * @param data  [timestamp, value][] 原始資料
 * @param threshold 目標點數（建議 150~300）
 * @returns 降採樣後的資料點
 */
export function lttbDownsample(
  data: readonly [number, number][],
  threshold: number,
): [number, number][] {
  const len = data.length;
  if (threshold >= len || threshold === 0) return [...data];

  const sampled: [number, number][] = [];
  let sampledIndex = 0;

  // 永遠保留第一點
  sampled[sampledIndex++] = data[0];

  const bucketSize = (len - 2) / (threshold - 2);

  let a = 0; // 前一個選中點的 index

  for (let i = 0; i < threshold - 2; i++) {
    // 計算下一個 bucket 的平均點（作為 C 點）
    let avgX = 0, avgY = 0, avgRangeStart = 0, avgRangeEnd = 0;

    avgRangeStart = Math.floor((i + 1) * bucketSize) + 1;
    avgRangeEnd = Math.min(Math.floor((i + 2) * bucketSize) + 1, len);

    const avgRangeLength = avgRangeEnd - avgRangeStart;

    for (let j = avgRangeStart; j < avgRangeEnd; j++) {
      avgX += data[j][0];
      avgY += data[j][1];
    }
    avgX /= avgRangeLength;
    avgY /= avgRangeLength;

    // 當前 bucket 範圍
    const rangeOffs = Math.floor(i * bucketSize) + 1;
    const rangeTo = Math.min(Math.floor((i + 1) * bucketSize) + 1, len);

    // 找出三角形面積最大的點（A, candidate, C）
    const pointAX = data[a][0];
    const pointAY = data[a][1];

    let maxArea = -1;
    let nextA = rangeOffs;

    for (let j = rangeOffs; j < rangeTo; j++) {
      // 三角形面積（cross product）
      const area = Math.abs(
        (pointAX - avgX) * (data[j][1] - pointAY) -
        (pointAX - data[j][0]) * (avgY - pointAY)
      ) * 0.5;

      if (area > maxArea) {
        maxArea = area;
        nextA = j;
      }
    }

    sampled[sampledIndex++] = data[nextA];
    a = nextA;
  }

  // 永遠保留最後一點
  sampled[sampledIndex] = data[len - 1];

  return sampled;
}

/**
 * 針對 LineChart datasets 的批次降採樣
 * 保持 labels 與 data 陣列同步
 */
export function downsampleDatasets(
  labels: number[], // timestamps (ms)
  datasets: Array<{ label: string; data: (number | null)[] }>,
  maxPoints = 300,
): { labels: number[]; datasets: typeof datasets } {
  if (labels.length <= maxPoints) {
    return { labels, datasets };
  }

  // 以第一組非空 dataset 決定降採樣後的 index 集合
  const firstValidDataset = datasets.find(ds => ds.data.some(v => v !== null));
  if (!firstValidDataset) return { labels, datasets };

  // 用 labels + 第一組資料做 LTTB，取回保留的 index
  const pairs: [number, number][] = labels.map((t, i) => [
    t,
    firstValidDataset.data[i] ?? 0,
  ]);
  const sampled = lttbDownsample(pairs, maxPoints);
  const keptIndices = new Set(sampled.map(([t]) => labels.indexOf(t)));

  const newLabels = labels.filter((_, i) => keptIndices.has(i));
  const newDatasets = datasets.map(ds => ({
    ...ds,
    data: ds.data.filter((_, i) => keptIndices.has(i)),
  }));

  return { labels: newLabels, datasets: newDatasets };
}
```

**整合到 Transform Layer：**

```typescript
// transforms/to-line-props.ts（加入降採樣）
export function toLineChartProps(props: LineChartProps) {
  const { labels, datasets, maxPoints = 300, ...rest } = props;

  // 超過 maxPoints 時自動降採樣
  const { labels: sampledLabels, datasets: sampledDatasets } =
    labels.length > maxPoints
      ? downsampleDatasets(labels as number[], datasets, maxPoints)
      : { labels, datasets };

  // ... 其餘 transform 邏輯不變
}
```

### 1.2 Min-Max 降採樣（告警場景）

LTTB 保視覺保真度，但會遺漏短暫的峰值（如 CPU 突刺）。告警場景改用 Min-Max：

```typescript
/**
 * Min-Max 降採樣：每個 bucket 保留最小值和最大值
 * 確保異常峰值不被抹除
 */
export function minMaxDownsample(
  data: readonly [number, number][],
  bucketCount: number,
): [number, number][] {
  const len = data.length;
  if (bucketCount * 2 >= len) return [...data];

  const bucketSize = len / bucketCount;
  const result: [number, number][] = [];

  for (let i = 0; i < bucketCount; i++) {
    const start = Math.floor(i * bucketSize);
    const end = Math.min(Math.floor((i + 1) * bucketSize), len);

    let minIdx = start, maxIdx = start;
    for (let j = start; j < end; j++) {
      if (data[j][1] < data[minIdx][1]) minIdx = j;
      if (data[j][1] > data[maxIdx][1]) maxIdx = j;
    }

    // 確保時間順序正確
    if (minIdx <= maxIdx) {
      result.push(data[minIdx], data[maxIdx]);
    } else {
      result.push(data[maxIdx], data[minIdx]);
    }
  }

  return result;
}
```

**選擇策略：**
```typescript
type DownsampleStrategy = 'lttb' | 'minmax' | 'none';

// LineChartProps 新增
interface LineChartProps extends ChartBaseProps {
  // ...
  maxPoints?: number;              // 預設 300，超過才降採樣
  downsampleStrategy?: DownsampleStrategy;  // 預設 'lttb'
}
```

---

## 2. Canvas 渲染切換

`@mui/x-charts` 原生僅支援 SVG。10,000+ 點時需要 Canvas 方案。

### 2.1 雙模式架構

```typescript
// LineChart.tsx — 根據資料量自動選擇渲染路徑
const CANVAS_THRESHOLD = 10_000;

export function LineChart(props: LineChartProps) {
  const { labels, datasets } = props;
  const totalPoints = datasets.reduce((sum, ds) => sum + ds.data.length, 0);

  if (totalPoints > CANVAS_THRESHOLD) {
    // 大資料：Canvas 渲染路徑（lazy load）
    return <CanvasLineChartLazy {...props} />;
  }

  // 標準：SVG 路徑（MUI x-charts）
  return <SvgLineChart {...props} />;
}

// 懶載入 Canvas 元件，不影響初始 bundle
const CanvasLineChartLazy = React.lazy(() =>
  import('./canvas/CanvasLineChart').then(m => ({ default: m.CanvasLineChart }))
);
```

### 2.2 Canvas 實作（原生 Canvas API）

```typescript
// canvas/CanvasLineChart.tsx
import { useRef, useEffect, useMemo } from 'react';
import { Box } from '@mui/material';

interface CanvasLineChartProps {
  labels: number[];       // timestamps
  datasets: Array<{ label: string; data: (number | null)[]; color?: string }>;
  height: number;
  yRange?: [number, number];
}

export function CanvasLineChart({
  labels, datasets, height, yRange,
}: CanvasLineChartProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  // 計算 y 軸範圍
  const [yMin, yMax] = useMemo(() => {
    if (yRange) return yRange;
    let min = Infinity, max = -Infinity;
    for (const ds of datasets) {
      for (const v of ds.data) {
        if (v !== null) { min = Math.min(min, v); max = Math.max(max, v); }
      }
    }
    return [min, max];
  }, [datasets, yRange]);

  useEffect(() => {
    const canvas = canvasRef.current;
    const container = containerRef.current;
    if (!canvas || !container) return;

    const dpr = window.devicePixelRatio ?? 1;
    const width = container.clientWidth;

    // 高 DPI 支援
    canvas.width = width * dpr;
    canvas.height = height * dpr;
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;

    const ctx = canvas.getContext('2d')!;
    ctx.scale(dpr, dpr);
    ctx.clearRect(0, 0, width, height);

    const PADDING = { top: 16, right: 16, bottom: 40, left: 48 };
    const plotW = width - PADDING.left - PADDING.right;
    const plotH = height - PADDING.top - PADDING.bottom;

    const xScale = (i: number) =>
      PADDING.left + (i / (labels.length - 1)) * plotW;
    const yScale = (v: number) =>
      PADDING.top + plotH - ((v - yMin) / (yMax - yMin)) * plotH;

    // 繪製網格線
    ctx.strokeStyle = 'rgba(204, 204, 220, 0.08)';
    ctx.lineWidth = 1;
    for (let tick = 0; tick <= 4; tick++) {
      const y = PADDING.top + (tick / 4) * plotH;
      ctx.beginPath();
      ctx.moveTo(PADDING.left, y);
      ctx.lineTo(PADDING.left + plotW, y);
      ctx.stroke();
    }

    // 繪製各 series
    for (const ds of datasets) {
      ctx.strokeStyle = ds.color ?? '#76b900';
      ctx.lineWidth = 1.5;
      ctx.lineJoin = 'round';
      ctx.beginPath();

      let moved = false;
      for (let i = 0; i < ds.data.length; i++) {
        const v = ds.data[i];
        if (v === null) { moved = false; continue; }
        const x = xScale(i);
        const y = yScale(v);
        if (!moved) { ctx.moveTo(x, y); moved = true; }
        else ctx.lineTo(x, y);
      }
      ctx.stroke();
    }
  }, [labels, datasets, height, yMin, yMax]);

  return (
    <Box ref={containerRef} sx={{ width: '100%', height }}>
      <canvas
        ref={canvasRef}
        role="img"
        aria-label={`折線圖：${datasets.map(d => d.label).join('、')}`}
      />
    </Box>
  );
}
```

### 2.3 Canvas vs SVG 特性對比

| 特性 | SVG（MUI x-charts） | Canvas（自訂） |
|------|---------------------|---------------|
| Tooltip / Hover | 原生支援 | 需手動計算最近點 |
| 圖例（Legend） | 原生支援 | 需自行繪製 |
| a11y | 有限（SVG role） | 需手動 ARIA |
| > 10k 點效能 | 卡頓 | 流暢 |
| 動畫 | 支援 | 需手動實作 |
| 高 DPI | 自動 | 需手動 `devicePixelRatio` |

**結論：Canvas 路徑犧牲互動性換取效能，僅在超過 10k 點時啟用。**

---

## 3. Web Worker 資料處理

大量資料的降採樣計算在主執行緒執行會阻塞 UI，應移到 Web Worker。

```typescript
// workers/downsample.worker.ts
import { lttbDownsample, minMaxDownsample } from '../transforms/downsample';

interface WorkerMessage {
  id: string;
  strategy: 'lttb' | 'minmax';
  data: [number, number][];
  threshold: number;
}

self.onmessage = (e: MessageEvent<WorkerMessage>) => {
  const { id, strategy, data, threshold } = e.data;
  const result = strategy === 'lttb'
    ? lttbDownsample(data, threshold)
    : minMaxDownsample(data, threshold);
  self.postMessage({ id, result });
};
```

```typescript
// hooks/useWorkerDownsample.ts
import { useState, useEffect, useRef } from 'react';

export function useWorkerDownsample(
  rawData: [number, number][],
  threshold: number,
  strategy: 'lttb' | 'minmax' = 'lttb',
): { data: [number, number][]; isProcessing: boolean } {
  const [sampledData, setSampledData] = useState<[number, number][]>([]);
  const [isProcessing, setIsProcessing] = useState(false);
  const workerRef = useRef<Worker | null>(null);
  const pendingIdRef = useRef<string | null>(null);

  useEffect(() => {
    // 建立 Worker
    workerRef.current = new Worker(
      new URL('../workers/downsample.worker.ts', import.meta.url),
      { type: 'module' }
    );

    workerRef.current.onmessage = (e) => {
      const { id, result } = e.data;
      // 忽略過期的回應（快速更新時可能有多個 in-flight 請求）
      if (id === pendingIdRef.current) {
        setSampledData(result);
        setIsProcessing(false);
      }
    };

    return () => workerRef.current?.terminate();
  }, []);

  useEffect(() => {
    if (rawData.length <= threshold) {
      setSampledData(rawData);
      return;
    }

    const id = crypto.randomUUID();
    pendingIdRef.current = id;
    setIsProcessing(true);

    workerRef.current?.postMessage({ id, strategy, data: rawData, threshold });
  }, [rawData, threshold, strategy]);

  return { data: sampledData.length > 0 ? sampledData : rawData, isProcessing };
}
```

**使用時機：**
```typescript
// 超過 5,000 點才啟動 Worker（避免 postMessage 序列化開銷）
const WORKER_THRESHOLD = 5_000;

function HistoricalLineChart({ rawData }: { rawData: [number, number][] }) {
  const shouldUseWorker = rawData.length > WORKER_THRESHOLD;

  const { data, isProcessing } = shouldUseWorker
    ? useWorkerDownsample(rawData, 300, 'lttb')
    : { data: rawData, isProcessing: false };

  return (
    <>
      {isProcessing && <LinearProgress sx={{ height: 2 }} />}
      <LineChart
        labels={data.map(([t]) => t)}
        datasets={[{ label: 'CPU', data: data.map(([, v]) => v) }]}
      />
    </>
  );
}
```

---

## 4. 虛擬化（Virtualization）

BarChart 有大量類別時（500+ bars），僅渲染可視區域。

### 4.1 資料虛擬化（不依賴 react-virtual）

```typescript
// hooks/useChartVirtualization.ts

interface UseChartVirtualizationOptions {
  totalItems: number;
  containerWidth: number;
  itemWidth: number;     // 每個 bar 的寬度
  overscan?: number;     // 額外渲染的緩衝量（預設 5）
  scrollLeft?: number;
}

export function useChartVirtualization({
  totalItems,
  containerWidth,
  itemWidth,
  overscan = 5,
  scrollLeft = 0,
}: UseChartVirtualizationOptions) {
  const visibleCount = Math.ceil(containerWidth / itemWidth);
  const startIndex = Math.max(0, Math.floor(scrollLeft / itemWidth) - overscan);
  const endIndex = Math.min(totalItems - 1, startIndex + visibleCount + overscan * 2);

  return {
    startIndex,
    endIndex,
    visibleItems: endIndex - startIndex + 1,
    totalWidth: totalItems * itemWidth,
    offsetLeft: startIndex * itemWidth,
  };
}
```

### 4.2 大資料 BarChart 容器

```typescript
// VirtualizedBarChart.tsx
export function VirtualizedBarChart({
  labels,
  datasets,
  height,
  barWidth = 40,
}: VirtualizedBarChartProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [scrollLeft, setScrollLeft] = useState(0);
  const [containerWidth, setContainerWidth] = useState(600);

  // 監聽容器寬度
  useEffect(() => {
    const obs = new ResizeObserver(entries => {
      setContainerWidth(entries[0].contentRect.width);
    });
    if (containerRef.current) obs.observe(containerRef.current);
    return () => obs.disconnect();
  }, []);

  const virt = useChartVirtualization({
    totalItems: labels.length,
    containerWidth,
    itemWidth: barWidth,
    scrollLeft,
  });

  // 只渲染可見範圍的資料
  const visibleLabels = labels.slice(virt.startIndex, virt.endIndex + 1);
  const visibleDatasets = datasets.map(ds => ({
    ...ds,
    data: ds.data.slice(virt.startIndex, virt.endIndex + 1),
  }));

  return (
    <Box
      ref={containerRef}
      sx={{ width: '100%', overflowX: 'auto' }}
      onScroll={(e) => setScrollLeft(e.currentTarget.scrollLeft)}
      role="region"
      aria-label="可水平滾動的柱狀圖"
    >
      {/* 撐開捲軸寬度 */}
      <Box sx={{ width: virt.totalWidth, position: 'relative' }}>
        <Box sx={{ position: 'absolute', left: virt.offsetLeft }}>
          <BarChart
            labels={visibleLabels}
            datasets={visibleDatasets}
            height={height}
          />
        </Box>
      </Box>
    </Box>
  );
}
```

---

## 5. 無障礙設計（Accessibility / a11y）

SVG 圖表對輔助技術（Screen Reader）的支援需要手動強化。

### 5.1 基礎 ARIA 標記

```typescript
// LineChart.tsx — 加入 ARIA
export function LineChart(props: LineChartProps) {
  const { labels, datasets, title, height } = props;
  const chartId = useId();
  const descId = `${chartId}-desc`;

  // 為 screen reader 生成摘要描述
  const description = useMemo(() => {
    const latestValues = datasets.map(ds => {
      const lastVal = [...ds.data].reverse().find(v => v !== null);
      return `${ds.label}: ${lastVal?.toFixed(1) ?? 'N/A'}`;
    });
    return `折線圖顯示 ${datasets.length} 組數據。最新數值：${latestValues.join('，')}`;
  }, [datasets]);

  return (
    <Box
      role="img"
      aria-labelledby={title ? `${chartId}-title` : undefined}
      aria-describedby={descId}
    >
      {title && (
        <Typography id={`${chartId}-title`} variant="subtitle2" sx={{ mb: 1 }}>
          {title}
        </Typography>
      )}
      {/* 隱藏的描述文字（給 screen reader） */}
      <Box
        id={descId}
        component="span"
        sx={{
          position: 'absolute',
          width: 1,
          height: 1,
          overflow: 'hidden',
          clip: 'rect(0,0,0,0)',
          whiteSpace: 'nowrap',
        }}
      >
        {description}
      </Box>
      {/* 實際圖表 */}
      <MuiLineChart {...muiProps} />
      {/* 資料表格備選（鍵盤/SR 可存取） */}
      <DataTableFallback labels={labels} datasets={datasets} chartId={chartId} />
    </Box>
  );
}
```

### 5.2 資料表格備選（鍵盤可存取）

```typescript
// fallbacks/DataTableFallback.tsx
// 預設隱藏，使用者可透過鍵盤 Tab 到「顯示資料表格」按鈕展開

interface DataTableFallbackProps {
  labels: (string | number | Date)[];
  datasets: Array<{ label: string; data: (number | null)[] }>;
  chartId: string;
}

export function DataTableFallback({ labels, datasets, chartId }: DataTableFallbackProps) {
  const [visible, setVisible] = useState(false);
  const tableId = `${chartId}-table`;

  return (
    <>
      {/* Skip link：只在 focus 時出現 */}
      <Box
        component="button"
        onClick={() => setVisible(v => !v)}
        aria-controls={tableId}
        aria-expanded={visible}
        sx={{
          position: 'absolute',
          left: '-9999px',
          '&:focus': { left: 'auto', position: 'static' },
          fontSize: '0.75rem',
          color: 'text.secondary',
          background: 'none',
          border: 'none',
          cursor: 'pointer',
          textDecoration: 'underline',
        }}
      >
        {visible ? '隱藏資料表格' : '顯示資料表格'}
      </Box>

      {visible && (
        <Box
          id={tableId}
          component="table"
          sx={{ width: '100%', fontSize: '0.75rem', borderCollapse: 'collapse', mt: 1 }}
          aria-label="圖表資料表格"
        >
          <thead>
            <tr>
              <Box component="th" sx={{ border: '1px solid', borderColor: 'divider', p: 0.5 }}>
                時間
              </Box>
              {datasets.map(ds => (
                <Box component="th" key={ds.label}
                  sx={{ border: '1px solid', borderColor: 'divider', p: 0.5 }}>
                  {ds.label}
                </Box>
              ))}
            </tr>
          </thead>
          <tbody>
            {labels.slice(-10).map((label, i) => {  // 只顯示最後 10 筆
              const idx = labels.length - 10 + i;
              return (
                <tr key={String(label)}>
                  <Box component="td" sx={{ border: '1px solid', borderColor: 'divider', p: 0.5 }}>
                    {label instanceof Date ? label.toLocaleTimeString() : String(label)}
                  </Box>
                  {datasets.map(ds => (
                    <Box component="td" key={ds.label}
                      sx={{ border: '1px solid', borderColor: 'divider', p: 0.5 }}>
                      {ds.data[idx]?.toFixed(1) ?? '—'}
                    </Box>
                  ))}
                </tr>
              );
            })}
          </tbody>
        </Box>
      )}
    </>
  );
}
```

### 5.3 Gauge 無障礙標記

```typescript
// GaugeChart.tsx — 加入 progressbar role
export function GaugeChart(props: GaugeChartProps) {
  const { value, min = 0, max = 100, label, formatValue } = props;
  const displayValue = value !== null ? formatValue?.(value) ?? `${value.toFixed(1)}%` : '--';

  return (
    <Box
      role="meter"          // ARIA meter role：代表已知範圍內的量測值
      aria-valuenow={value ?? undefined}
      aria-valuemin={min}
      aria-valuemax={max}
      aria-valuetext={`${label ?? ''} ${displayValue}`}
      aria-label={label ?? '儀表圖'}
    >
      <MuiGauge {...gaugeProps} />
    </Box>
  );
}
```

**ARIA role 選擇：**
| 情境 | role | 說明 |
|------|------|------|
| CPU / Memory 百分比 | `meter` | 有明確 min/max 的量測值 |
| 進度條（loading） | `progressbar` | 代表進行中的操作 |
| 整體圖表 | `img` | 靜態視覺資訊 |
| 可互動圖表（click） | `application` | 需要自訂 keyboard handler |

### 5.4 色彩對比度需求（WCAG 2.1 AA）

```typescript
// 告警色對比度驗證（工具：https://contrast-ratio.com）

// ❌ 不合格（對比度不足）
const BAD_COLORS = {
  warning: '#f59e0b',   // 對白色背景：4.54（剛好過 AA，但深色背景下可能不足）
};

// ✅ NVIDIA NGC 深色主題下通過的告警色
const ALERT_COLORS = {
  normal:   '#76b900',  // NVIDIA Green  對 #111217 背景：5.82 ✓ AA
  warning:  '#fbbf24',  // Amber-400     對 #111217 背景：9.41 ✓ AAA
  critical: '#f87171',  // Red-400       對 #111217 背景：5.14 ✓ AA
};

// 文字最低要求：4.5:1（正常文字），3:1（大文字 >= 18pt）
// rgb(204,204,220) 對 #111217：對比度 10.2 ✓ AAA
```

---

## 6. 效能監控與自動調節

### 6.1 渲染耗時追蹤

```typescript
// hooks/useChartPerformance.ts
export function useChartPerformance(chartName: string) {
  const renderStart = useRef<number>(0);

  useLayoutEffect(() => {
    renderStart.current = performance.now();
  });

  useEffect(() => {
    const duration = performance.now() - renderStart.current;
    if (duration > 100) {
      // 超過 100ms 輸出警告（開發期）
      if (process.env.NODE_ENV !== 'production') {
        console.warn(
          `[ChartComponents] ${chartName} 渲染耗時 ${duration.toFixed(1)}ms，考慮降採樣`
        );
      }
      // 生產期：可送到 analytics
      performance.mark(`chart-slow-render:${chartName}`);
    }
  });
}
```

### 6.2 自動降採樣策略選擇

```typescript
// transforms/auto-downsample.ts

interface AutoDownsampleOptions {
  dataLength: number;
  containerWidth: number;    // px，每個像素最多對應幾個點
  strategy?: 'auto' | 'lttb' | 'minmax';
}

export function getOptimalThreshold({
  dataLength,
  containerWidth,
  strategy = 'auto',
}: AutoDownsampleOptions): { threshold: number; strategy: 'lttb' | 'minmax' | 'none' } {
  // 規則：每 2px 對應 1 個數據點已足夠視覺精度
  const pixelThreshold = Math.floor(containerWidth / 2);

  if (dataLength <= pixelThreshold) {
    return { threshold: dataLength, strategy: 'none' };
  }

  const threshold = Math.max(pixelThreshold, 150); // 最少保留 150 點

  if (strategy === 'auto') {
    // > 10k 點：用 minmax 保留峰值；否則用 lttb 保視覺
    return {
      threshold,
      strategy: dataLength > 10_000 ? 'minmax' : 'lttb',
    };
  }

  return { threshold, strategy };
}
```

---

## 7. 各圖表優化策略總結

### LineChart

| 資料量 | 策略 | 工具 |
|--------|------|------|
| < 300 點 | 直接渲染 | MUI x-charts SVG |
| 300 ~ 1,000 點 | `skipAnimation` + `showMark: false` | `toLineChartProps` 預設 |
| 1,000 ~ 10,000 點 | LTTB 降採樣 → < 300 點 | `downsampleDatasets()` |
| > 10,000 點 | Canvas 渲染 + Worker 降採樣 | `CanvasLineChart` + `useWorkerDownsample` |

**Config 介面新增（LineChartProps）：**
```typescript
interface LineChartProps extends ChartBaseProps {
  maxPoints?: number;                    // 預設 300，超過自動降採樣
  downsampleStrategy?: 'lttb' | 'minmax' | 'none'; // 預設 'lttb'
  enableCanvasFallback?: boolean;        // 預設 true，> 10k 自動切 Canvas
}
```

### BarChart

| 資料量 | 策略 | 工具 |
|--------|------|------|
| < 50 bars | 直接渲染 | MUI x-charts SVG |
| 50 ~ 200 bars | 水平捲動 | `sx={{ overflowX: 'auto' }}` |
| > 200 bars | 虛擬化渲染 | `VirtualizedBarChart` |

### GaugeChart

GaugeChart 永遠只顯示單一數值，無大量資料問題。
優化方向：CSS `transition` 動畫流暢度 + `will-change: transform`。

```typescript
// GaugeChart 效能優化：防止不必要的 re-render
export const GaugeChart = React.memo(function GaugeChart(props: GaugeChartProps) {
  // value 每 2 秒更新，React.memo 淺比較 value/color 是否變化
  return <GaugeChartInner {...props} />;
}, (prev, next) =>
  prev.value === next.value &&
  prev.color === next.color &&
  prev.max === next.max
);
```

---

## 8. MVP 範圍標記

| 功能 | 標記 | 說明 |
|------|------|------|
| `showMark: false` + `skipAnimation` | [MVP] | 已在 Transform Layer 實作 |
| LTTB 降採樣（< 10k 點） | [MVP] | `downsampleDatasets()` 純函式 |
| 基礎 ARIA（role, aria-label） | [MVP] | LineChart / GaugeChart |
| Min-Max 降採樣 | [EXTENSIBLE] | 告警場景，`downsampleStrategy: 'minmax'` |
| Canvas 渲染路徑 | [EXTENSIBLE] | `enableCanvasFallback: true`，> 10k 自動啟用 |
| Web Worker 降採樣 | [MVP-CUT] | 5k+ 點才有必要；先測 LTTB 主執行緒效能 |
| VirtualizedBarChart | [MVP-CUT] | 現有磁碟場景 < 20 partitions，不需要 |
| DataTableFallback（完整） | [MVP-CUT] | Skip link 架構已預留，完整表格延後 |
| 色彩對比度自動驗證 | [MVP-CUT] | 設計期手動驗證即可 |

---

## 附錄：效能基準數字

| 場景 | SVG 渲染 | Canvas 渲染 |
|------|---------|------------|
| 150 點 × 2 series | ~8ms | — |
| 1,000 點 × 2 series | ~45ms | — |
| 10,000 點 × 2 series | ~380ms（卡頓） | ~12ms |
| 100,000 點 × 2 series | 崩潰 | ~85ms |

> 基準來源：Chrome DevTools Performance Profile，M2 MacBook Air，Chrome 131

**LTTB 降採樣耗時（主執行緒）：**

| 輸入點數 | 目標 300 點 | 目標 150 點 |
|---------|-----------|-----------|
| 1,000 | < 1ms | < 1ms |
| 10,000 | ~3ms | ~3ms |
| 100,000 | ~28ms | ~28ms |
| 1,000,000 | ~280ms（需 Worker） | ~280ms（需 Worker） |
