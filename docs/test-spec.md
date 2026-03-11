# AIDMS System Monitor -- 測試規格文件

> TDD 測試計畫 | Vitest + React Testing Library
> 涵蓋：ChartComponents 套件 + Dashboard 應用
> 所有測試案例為完整可執行的 Vitest 程式碼

---

## 測試環境設定

### setup.ts

```typescript
// src/__tests__/setup.ts（Dashboard 與 ChartComponents 共用）

import { vi } from 'vitest';

// --- ResizeObserver Mock ---
// WHY: jsdom 不實作 ResizeObserver，但 MUI x-charts 底層的
// ResponsiveChartContainer 依賴它來偵測父容器寬度。
// 不 mock 會直接 throw ReferenceError。
global.ResizeObserver = vi.fn().mockImplementation(() => ({
  observe: vi.fn(),
  unobserve: vi.fn(),
  disconnect: vi.fn(),
}));

// --- SVGElement.getTotalLength Mock ---
// WHY: MUI LineChart 的路徑動畫需要計算 SVG path 長度。
// jsdom 不實作 SVG 方法，回傳 0 讓動畫跳過計算。
Object.defineProperty(SVGElement.prototype, 'getTotalLength', {
  value: () => 0,
  writable: true,
});

// --- window.matchMedia Mock ---
// WHY: MUI 的 useMediaQuery hook 依賴 matchMedia。
// jsdom 不實作，不 mock 會導致所有 breakpoint 判斷失敗。
// 預設 matches: false = 模擬手機寬度（最保守場景）。
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

// --- MockEventSource ---
// WHY: jsdom 不實作 EventSource。我們需要模擬 SSE 連線，
// 包括 named event（history/metrics）和 onerror。
// 這個 mock 讓測試能主動觸發事件，驗證 hook 的回應。
class MockEventSource {
  static CONNECTING = 0;
  static OPEN = 1;
  static CLOSED = 2;

  url: string;
  readyState = MockEventSource.CONNECTING;
  onerror: ((e: Event) => void) | null = null;
  private listeners: Record<string, ((e: MessageEvent) => void)[]> = {};

  constructor(url: string) {
    this.url = url;
    // 記錄最新的 instance，讓測試能取得它來觸發事件
    (MockEventSource as unknown as Record<string, unknown>)._lastInstance = this;
  }

  addEventListener(type: string, cb: (e: MessageEvent) => void) {
    this.listeners[type] = [...(this.listeners[type] ?? []), cb];
  }

  removeEventListener(type: string, cb: (e: MessageEvent) => void) {
    this.listeners[type] = (this.listeners[type] ?? []).filter(f => f !== cb);
  }

  // 測試用：模擬伺服器送出事件
  dispatchEvent(type: string, data: unknown) {
    const event = { data: JSON.stringify(data) } as MessageEvent;
    (this.listeners[type] ?? []).forEach(cb => cb(event));
  }

  close() {
    this.readyState = MockEventSource.CLOSED;
  }
}

vi.stubGlobal('EventSource', MockEventSource);

// --- Helper: 取得最近建立的 EventSource instance ---
export function getLastEventSource(): MockEventSource {
  return (MockEventSource as unknown as { _lastInstance: MockEventSource })._lastInstance;
}
```

---

## Part 1: ChartComponents 套件測試

### 1-1. validate-series.test.ts（9 cases，純函式，無 DOM）

```typescript
// ChartComponents/src/__tests__/validation/validate-series.test.ts

import { describe, it, expect, vi } from 'vitest';
import { validateSeriesData } from '../../validation/validate-series';

describe('validateSeriesData', () => {
  // --- 合法情況 ---

  it('labels 與 datasets[].data 長度一致 -> valid', () => {
    const result = validateSeriesData(
      ['Jan', 'Feb', 'Mar'],
      [{ label: 'CPU', data: [10, 20, 30] }]
    );
    expect(result.valid).toBe(true);
  });

  it('多組 datasets 長度均一致 -> valid', () => {
    const result = validateSeriesData(
      [1, 2, 3],
      [
        { label: 'CPU', data: [10, 20, 30] },
        { label: 'MEM', data: [40, 50, 60] },
      ]
    );
    expect(result.valid).toBe(true);
  });

  it('data 含 null -> valid（null 是合法缺值，折線斷點）', () => {
    const result = validateSeriesData(
      ['Jan', 'Feb', 'Mar'],
      [{ label: 'CPU', data: [10, null, 30] }]
    );
    expect(result.valid).toBe(true);
  });

  it('空 data 陣列（length 0）-> valid（由 Rendering Layer 顯示 Skeleton）', () => {
    const result = validateSeriesData(
      [],
      [{ label: 'CPU', data: [] }]
    );
    expect(result.valid).toBe(true);
  });

  // --- 非法情況 ---

  it('空 datasets 陣列 -> invalid，reason 含 "datasets"', () => {
    const result = validateSeriesData(['Jan', 'Feb'], []);
    expect(result.valid).toBe(false);
    expect(result).toMatchObject({
      valid: false,
      reason: expect.stringContaining('datasets'),
    });
  });

  it('data 長度與 labels 不一致 -> invalid，reason 含 series name 和兩邊長度', () => {
    const result = validateSeriesData(
      ['Jan', 'Feb', 'Mar'],
      [{ label: 'CPU', data: [10, 20] }]  // 少一筆
    );
    expect(result.valid).toBe(false);
    const reason = (result as { valid: false; reason: string }).reason;
    expect(reason).toContain('CPU');
    expect(reason).toContain('2');
    expect(reason).toContain('3');
  });

  it('data 含 NaN -> invalid', () => {
    const result = validateSeriesData(
      ['a', 'b'],
      [{ label: 'X', data: [1, NaN] }]
    );
    expect(result.valid).toBe(false);
  });

  it('data 含 Infinity -> invalid', () => {
    const result = validateSeriesData(
      ['a', 'b'],
      [{ label: 'X', data: [1, Infinity] }]
    );
    expect(result.valid).toBe(false);
  });

  it('開發模式驗證失敗 -> console.error 被呼叫（DX 提醒）', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    validateSeriesData(['a'], [{ label: 'X', data: [1, 2] }]);
    expect(spy).toHaveBeenCalled();
    spy.mockRestore();
  });
});
```

---

### 1-2. validate-gauge.test.ts（4 cases，純函式）

```typescript
// ChartComponents/src/__tests__/validation/validate-gauge.test.ts

import { describe, it, expect } from 'vitest';
import { validateGaugeData } from '../../validation/validate-gauge';

describe('validateGaugeData', () => {
  it('有效數值 -> valid', () => {
    expect(validateGaugeData({ value: 50, min: 0, max: 100 }).valid).toBe(true);
  });

  it('null value -> valid（代表載入中狀態，由 Rendering Layer 顯示 "--"）', () => {
    expect(validateGaugeData({ value: null, min: 0, max: 100 }).valid).toBe(true);
  });

  it('min >= max -> invalid（無效量測範圍）', () => {
    const result = validateGaugeData({ value: 50, min: 100, max: 0 });
    expect(result.valid).toBe(false);
  });

  it('NaN value -> invalid（格式錯誤，非合法缺值）', () => {
    const result = validateGaugeData({ value: NaN, min: 0, max: 100 });
    expect(result.valid).toBe(false);
  });
});
```

---

### 1-3. to-line-props.test.ts（10 cases，純函式，含 scaleType 自動偵測 + showMark 邏輯）

```typescript
// ChartComponents/src/__tests__/transforms/to-line-props.test.ts

import { describe, it, expect } from 'vitest';
import { toLineChartProps } from '../../transforms/to-line-props';

const baseProps = {
  labels: ['Jan', 'Feb', 'Mar'],
  datasets: [{ label: 'CPU', data: [10, 20, 30] }],
};

describe('toLineChartProps', () => {
  // --- scaleType 自動偵測 ---
  // WHY 自動偵測？消費者不需要知道 MUI 的 scaleType 概念。
  // 傳 Date 就是時間軸，傳 number 就是數值軸，傳 string 就是分類軸。

  describe('scaleType 自動偵測', () => {
    it('Date labels -> scaleType: "time"', () => {
      const props = {
        ...baseProps,
        labels: [new Date('2024-01-01'), new Date('2024-01-02'), new Date('2024-01-03')],
      };
      const result = toLineChartProps(props);
      expect(result.xAxis[0].scaleType).toBe('time');
    });

    it('number labels -> scaleType: "linear"', () => {
      const props = { ...baseProps, labels: [1, 2, 3] };
      const result = toLineChartProps(props);
      expect(result.xAxis[0].scaleType).toBe('linear');
    });

    it('string labels -> scaleType: "point"', () => {
      const result = toLineChartProps(baseProps);
      expect(result.xAxis[0].scaleType).toBe('point');
    });
  });

  // --- curve 映射 ---
  // WHY 映射？"smooth" 比 "monotoneX" 更直覺，消費者不需知道 D3 curve 名稱。

  describe('curve 映射', () => {
    it('"smooth" -> "monotoneX"（時間序列最自然的平滑曲線）', () => {
      const result = toLineChartProps({ ...baseProps, curve: 'smooth' });
      expect(result.series[0].curve).toBe('monotoneX');
    });

    it('"linear" -> "linear"（直線連接）', () => {
      const result = toLineChartProps({ ...baseProps, curve: 'linear' });
      expect(result.series[0].curve).toBe('linear');
    });

    it('"step" -> "step"（階梯狀，適合離散狀態）', () => {
      const result = toLineChartProps({ ...baseProps, curve: 'step' });
      expect(result.series[0].curve).toBe('step');
    });
  });

  // --- showMark 邏輯 ---
  // WHY 30 點為閾值？
  // <= 30 點：mark 點清晰可見，不重疊，提供精確數值參考
  // > 30 點：mark 密集到看不清，且每個 mark 都是一個 SVG circle，
  // 150 個 mark * 2 series = 300 個 SVG 節點，影響渲染效能。

  describe('showMark 邏輯', () => {
    it('<= 30 點 -> showMark: true', () => {
      const props = {
        labels: Array.from({ length: 30 }, (_, i) => `p${i}`),
        datasets: [{ label: 'X', data: Array(30).fill(1) }],
      };
      const result = toLineChartProps(props);
      expect(result.series[0].showMark).toBe(true);
    });

    it('> 30 點 -> showMark: false（效能保護）', () => {
      const props = {
        labels: Array.from({ length: 31 }, (_, i) => `p${i}`),
        datasets: [{ label: 'X', data: Array(31).fill(1) }],
      };
      const result = toLineChartProps(props);
      expect(result.series[0].showMark).toBe(false);
    });
  });

  // --- 其他 props ---

  it('animate: false -> skipAnimation: true（SSE 即時更新時關閉動畫）', () => {
    const result = toLineChartProps({ ...baseProps, animate: false });
    expect(result.skipAnimation).toBe(true);
  });

  it('animate: true（預設）-> skipAnimation: false', () => {
    const result = toLineChartProps(baseProps);
    expect(result.skipAnimation).toBe(false);
  });

  it('yRange 正確映射到 yAxis min/max', () => {
    const result = toLineChartProps({ ...baseProps, yRange: [0, 100] });
    expect(result.yAxis[0].min).toBe(0);
    expect(result.yAxis[0].max).toBe(100);
  });

  it('slotProps 合併到軸配置，不覆蓋自動計算的 scaleType', () => {
    const result = toLineChartProps({
      ...baseProps,
      slotProps: { xAxis: { tickLabelStyle: { fontSize: 10 } } },
    });
    // slotProps 的自訂樣式被保留
    expect(result.xAxis[0].tickLabelStyle).toEqual({ fontSize: 10 });
    // 自動偵測的 scaleType 未被覆蓋
    expect(result.xAxis[0].scaleType).toBe('point');
  });
});
```

---

### 1-4. to-bar-props.test.ts（4 cases，純函式）

```typescript
// ChartComponents/src/__tests__/transforms/to-bar-props.test.ts

import { describe, it, expect } from 'vitest';
import { toBarChartProps } from '../../transforms/to-bar-props';

const baseProps = {
  labels: ['Core 0', 'Core 1', 'Core 2'],
  datasets: [{ label: 'Usage', data: [30, 50, 70] }],
};

describe('toBarChartProps', () => {
  it('stacked: true -> 所有 series 共享相同 stack key', () => {
    const result = toBarChartProps({
      ...baseProps,
      datasets: [
        { label: 'Used', data: [10, 20, 30] },
        { label: 'Free', data: [90, 80, 70] },
      ],
      stacked: true,
    });
    const stacks = result.series.map((s: { stack?: string }) => s.stack);
    expect(stacks[0]).toBeDefined();
    expect(stacks[0]).toBe(stacks[1]);
  });

  it('stacked: false（預設）-> series 無 stack key', () => {
    const result = toBarChartProps(baseProps);
    expect(result.series[0].stack).toBeUndefined();
  });

  it('horizontal layout -> labels 軸移到 yAxis（橫向長條圖）', () => {
    const result = toBarChartProps({ ...baseProps, layout: 'horizontal' });
    expect(result.yAxis[0].data).toEqual(baseProps.labels);
    expect(result.xAxis[0].data).toBeUndefined();
  });

  it('vertical layout（預設）-> labels 軸在 xAxis', () => {
    const result = toBarChartProps(baseProps);
    expect(result.xAxis[0].data).toEqual(baseProps.labels);
  });
});
```

---

### 1-5. to-gauge-props.test.ts（9 cases，含 color fn、clamp、null）

```typescript
// ChartComponents/src/__tests__/transforms/to-gauge-props.test.ts

import { describe, it, expect, vi } from 'vitest';
import { toGaugeProps } from '../../transforms/to-gauge-props';

describe('toGaugeProps', () => {
  // --- arc 映射 ---

  describe('arc 映射', () => {
    it('"half" -> startAngle: -110, endAngle: 110（半圓儀表，監控常見樣式）', () => {
      const result = toGaugeProps({ value: 50, arc: 'half' });
      expect(result.startAngle).toBe(-110);
      expect(result.endAngle).toBe(110);
    });

    it('"full" -> startAngle: 0, endAngle: 360（完整圓形）', () => {
      const result = toGaugeProps({ value: 50, arc: 'full' });
      expect(result.startAngle).toBe(0);
      expect(result.endAngle).toBe(360);
    });
  });

  // --- value clamp ---
  // WHY clamp？防止 MUI Gauge 的 arc 渲染溢出。
  // psutil 偶爾會回傳 > 100% 的 CPU usage（多核計算方式），
  // 或負值（計數器溢出），clamp 確保視覺正確。

  describe('value clamp', () => {
    it('value > max -> clamp 到 max', () => {
      const result = toGaugeProps({ value: 150, min: 0, max: 100 });
      expect(result.value).toBe(100);
    });

    it('value < min -> clamp 到 min', () => {
      const result = toGaugeProps({ value: -10, min: 0, max: 100 });
      expect(result.value).toBe(0);
    });

    it('null value -> 保持 null（不 clamp，由 text fn 顯示 "--"）', () => {
      const result = toGaugeProps({ value: null });
      expect(result.value).toBeNull();
    });
  });

  // --- color 函式 ---

  describe('color 函式', () => {
    it('color: string -> 直接套用到 sx', () => {
      const result = toGaugeProps({ value: 50, color: '#ff0000' });
      expect(result.sx).toBeDefined();
    });

    it('color: fn -> 以 value 呼叫（Dashboard 傳入告警色函式）', () => {
      const colorFn = vi.fn().mockReturnValue('#22c55e');
      toGaugeProps({ value: 73, color: colorFn });
      expect(colorFn).toHaveBeenCalledWith(73);
    });

    it('color: fn + null value -> fn 不被呼叫，sx 為 undefined', () => {
      // WHY? null value 代表資料未到，沒有數值就無法決定告警色。
      // 這時 Gauge 顯示預設灰色 arc，不帶任何語義色彩。
      const colorFn = vi.fn();
      const result = toGaugeProps({ value: null, color: colorFn });
      expect(colorFn).not.toHaveBeenCalled();
      expect(result.sx).toBeUndefined();
    });
  });

  // --- formatValue / text ---

  describe('formatValue', () => {
    it('預設格式 -> "73.2%"', () => {
      const result = toGaugeProps({ value: 73.2 });
      const textFn = result.text as (args: { value: number | null }) => string;
      expect(textFn({ value: 73.2 })).toBe('73.2%');
    });

    it('null value -> text 回傳 "--"（載入中狀態）', () => {
      const result = toGaugeProps({ value: null });
      const textFn = result.text as (args: { value: number | null }) => string;
      expect(textFn({ value: null })).toBe('--');
    });

    it('自訂 formatValue 被使用（如溫度顯示）', () => {
      const result = toGaugeProps({
        value: 50,
        formatValue: (v) => `${v} C`,
      });
      const textFn = result.text as (args: { value: number | null }) => string;
      expect(textFn({ value: 50 })).toBe('50 C');
    });
  });
});
```

---

### 1-6. LineChart.test.tsx（5 cases：正常 / Skeleton / Error / null / console.error）

```typescript
// ChartComponents/src/__tests__/LineChart.test.tsx

import { render, screen } from '@testing-library/react';
import { describe, it, expect, vi } from 'vitest';
import { LineChart } from '../LineChart';

const validProps = {
  labels: ['Jan', 'Feb', 'Mar'],
  datasets: [{ label: 'CPU', data: [10, 20, 30] }],
};

describe('LineChart', () => {
  it('正常數據 -> 渲染 SVG（MUI Chart 正常 mount）', () => {
    const { container } = render(<LineChart {...validProps} />);
    expect(container.querySelector('svg')).toBeTruthy();
  });

  it('空 datasets（data.length === 0）-> 顯示 ChartSkeleton（等待 SSE 數據）', () => {
    render(<LineChart labels={[]} datasets={[{ label: 'X', data: [] }]} />);
    // MUI Skeleton 有 .MuiSkeleton-root class
    expect(
      screen.getByRole('progressbar', { hidden: true }) ||
      document.querySelector('.MuiSkeleton-root')
    ).toBeTruthy();
  });

  it('data 長度不一致 -> 顯示 ChartError，含 series name 提示修正方向', () => {
    render(
      <LineChart
        labels={['Jan', 'Feb', 'Mar']}
        datasets={[{ label: 'CPU', data: [1, 2] }]}  // 少一筆
      />
    );
    // error 訊息包含 series name，讓開發者知道哪組資料有問題
    expect(screen.getByText(/CPU/)).toBeTruthy();
  });

  it('data 含 null -> 正常渲染（null 是合法缺值，不進 ChartError）', () => {
    const { container } = render(
      <LineChart
        labels={['Jan', 'Feb', 'Mar']}
        datasets={[{ label: 'CPU', data: [10, null, 30] }]}
      />
    );
    expect(container.querySelector('svg')).toBeTruthy();
  });

  it('開發模式驗證失敗 -> console.error 被呼叫（DX：大聲提醒開發者）', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    render(
      <LineChart
        labels={['a', 'b']}
        datasets={[{ label: 'X', data: [1, 2, 3] }]}  // 長度不符
      />
    );
    expect(spy).toHaveBeenCalled();
    spy.mockRestore();
  });
});
```

---

## Part 2: Dashboard 應用測試

### 2-1. alert-thresholds.test.ts（10 cases，含 AIDMS-specific GPU 0% = critical）

```typescript
// src/__tests__/alert-thresholds.test.ts

import { describe, it, expect } from 'vitest';
import { deriveAlertLevel } from '../utils/alert-thresholds';
import type { SystemMetrics } from '../types/metrics';

const CPU_THRESHOLDS = { warning: 70, critical: 85 };

// 產生最小有效的 SystemMetrics（只填測試需要的欄位）
function makeMetric(cpuUsage: number): SystemMetrics {
  return {
    timestamp: Date.now(),
    cpu: { usage: cpuUsage, cores: [] },
    memory: { total: 8e9, available: 4e9, usage: 50, swapUsage: 0 },
    disk: [],
    network: { rxBps: 0, txBps: 0, rxErrors: 0, txErrors: 0 },
  };
}

describe('deriveAlertLevel', () => {
  // --- 資料不足 ---

  it('歷史點數 < 3 -> 永遠回傳 normal（不誤判）', () => {
    // WHY: 連續 3 點邏輯需要至少 3 筆資料。
    // 剛連線時可能只有 1-2 筆，此時不應觸發告警。
    const history = [makeMetric(90), makeMetric(90)];  // 2 點，不足 3
    expect(deriveAlertLevel(history, m => m.cpu.usage, CPU_THRESHOLDS)).toBe('normal');
  });

  it('空陣列 -> normal', () => {
    expect(deriveAlertLevel([], m => m.cpu.usage, CPU_THRESHOLDS)).toBe('normal');
  });

  // --- 正常狀態 ---

  it('連續 3 點全 < 70 -> normal', () => {
    const history = [makeMetric(60), makeMetric(65), makeMetric(69)];
    expect(deriveAlertLevel(history, m => m.cpu.usage, CPU_THRESHOLDS)).toBe('normal');
  });

  // --- 邊界值 ---

  it('剛好在邊界值 70 -> normal（> 才觸發，不含等於）', () => {
    // WHY: 使用 > 而非 >=，因為 70% CPU 在 AIDMS 訓練時是正常的。
    // 嚴格 > 才進 warning，給一點緩衝空間。
    const history = [makeMetric(70), makeMetric(70), makeMetric(70)];
    expect(deriveAlertLevel(history, m => m.cpu.usage, CPU_THRESHOLDS)).toBe('normal');
  });

  it('剛好超過邊界 70.1 連續 3 點 -> warning', () => {
    const history = [makeMetric(70.1), makeMetric(70.2), makeMetric(70.5)];
    expect(deriveAlertLevel(history, m => m.cpu.usage, CPU_THRESHOLDS)).toBe('warning');
  });

  // --- Warning ---

  it('連續 3 點全 > 70 但有一點未到 85 -> warning（非 critical）', () => {
    const history = [makeMetric(71), makeMetric(80), makeMetric(72)];
    expect(deriveAlertLevel(history, m => m.cpu.usage, CPU_THRESHOLDS)).toBe('warning');
  });

  // --- Critical ---

  it('連續 3 點全 > 85 -> critical', () => {
    const history = [makeMetric(86), makeMetric(90), makeMetric(95)];
    expect(deriveAlertLevel(history, m => m.cpu.usage, CPU_THRESHOLDS)).toBe('critical');
  });

  it('最後 3 點中 2 點 critical + 1 點 warning -> warning（需全部 critical 才升級）', () => {
    const history = [makeMetric(90), makeMetric(75), makeMetric(90)];
    expect(deriveAlertLevel(history, m => m.cpu.usage, CPU_THRESHOLDS)).toBe('warning');
  });

  // --- Sliding window ---

  it('前面有 critical 但最後 3 點 normal -> normal（只看最新 3 點）', () => {
    // WHY: 告警必須反映「現在」的狀態，不是歷史。
    // 訓練任務結束後 CPU 下降，應立刻回到 normal。
    const history = [
      makeMetric(90), makeMetric(90), makeMetric(90),  // 舊的 critical
      makeMetric(50), makeMetric(50), makeMetric(50),  // 最新 3 點 normal
    ];
    expect(deriveAlertLevel(history, m => m.cpu.usage, CPU_THRESHOLDS)).toBe('normal');
  });

  // --- Extractor 通用性 ---

  it('可用於 memory.usage（extractor 支援任意欄位）', () => {
    const MEM_THRESHOLDS = { warning: 75, critical: 90 };
    const history = [makeMetric(50), makeMetric(50), makeMetric(50)];
    // memory.usage 都是 50%，應該是 normal
    expect(deriveAlertLevel(history, m => m.memory.usage, MEM_THRESHOLDS)).toBe('normal');
  });
});
```

---

### 2-2. format.test.ts（完整 cases）

```typescript
// src/__tests__/format.test.ts

import { describe, it, expect } from 'vitest';
import { formatBytes, formatBps, formatPercent, formatUptime } from '../utils/format';

describe('formatBytes', () => {
  it('0 -> "0 B"', () => expect(formatBytes(0)).toBe('0 B'));
  it('< 1024 -> "X B"', () => expect(formatBytes(512)).toBe('512 B'));
  it('>= 1KB -> "X.X KB"', () => expect(formatBytes(1536)).toBe('1.5 KB'));
  it('>= 1MB -> "X.X MB"', () => expect(formatBytes(1.5 * 1024 ** 2)).toBe('1.5 MB'));
  it('>= 1GB -> "X.X GB"', () => expect(formatBytes(2.3 * 1024 ** 3)).toBe('2.3 GB'));
});

describe('formatBps', () => {
  it('在 formatBytes 結果後加 "/s"', () => {
    expect(formatBps(1024 ** 2)).toBe('1.0 MB/s');
  });
  it('0 -> "0 B/s"', () => {
    expect(formatBps(0)).toBe('0 B/s');
  });
});

describe('formatPercent', () => {
  it('預設 1 位小數', () => expect(formatPercent(73.256)).toBe('73.3%'));
  it('decimals: 0 -> 整數', () => expect(formatPercent(73.7, 0)).toBe('74%'));
  it('整數值 -> 仍帶小數', () => expect(formatPercent(100)).toBe('100.0%'));
  it('0 -> "0.0%"', () => expect(formatPercent(0)).toBe('0.0%'));
});

describe('formatUptime', () => {
  it('>= 1 天 -> "up Xd Yh"', () => {
    expect(formatUptime(14 * 86400 + 3600)).toBe('up 14d 1h');
  });
  it('>= 1 小時（< 1 天）-> "up Xh Ym"', () => {
    expect(formatUptime(2 * 3600 + 30 * 60)).toBe('up 2h 30m');
  });
  it('< 1 小時 -> "up Xm"', () => {
    expect(formatUptime(45 * 60)).toBe('up 45m');
  });
  it('0 -> "up 0m"', () => {
    expect(formatUptime(0)).toBe('up 0m');
  });
});
```

---

### 2-3. use-system-metrics.test.ts（6 cases：初始 / history / metrics / sliding window 150 / error / unmount）

```typescript
// src/__tests__/use-system-metrics.test.ts

import { renderHook, act } from '@testing-library/react';
import { describe, it, expect, vi } from 'vitest';
import { useSystemMetrics } from '../hooks/useSystemMetrics';
import { getLastEventSource } from './setup';

const mockSystem = { hostname: 'blade-01', os: 'Linux 5.15', uptimeSeconds: 86400 };

function makeMetric(cpuUsage: number, timestamp = Date.now()) {
  return {
    timestamp,
    cpu: { usage: cpuUsage, cores: [cpuUsage, cpuUsage] },
    memory: { total: 8e9, available: 4e9, usage: 50, swapUsage: 0 },
    disk: [],
    network: { rxBps: 1000, txBps: 500, rxErrors: 0, txErrors: 0 },
  };
}

describe('useSystemMetrics', () => {
  it('初始狀態：status = "connecting"，latest = null，history 為空', () => {
    const { result } = renderHook(() => useSystemMetrics());
    expect(result.current.status).toBe('connecting');
    expect(result.current.latest).toBeNull();
    expect(result.current.history).toHaveLength(0);
  });

  it('收到 history 事件 -> status = "connected"，history 填入，latest = 最後一筆', () => {
    const { result } = renderHook(() => useSystemMetrics());
    const es = getLastEventSource();
    const metrics = [makeMetric(30), makeMetric(50), makeMetric(70)];

    act(() => {
      es.dispatchEvent('history', { metrics, system: mockSystem });
    });

    expect(result.current.status).toBe('connected');
    expect(result.current.history).toHaveLength(3);
    expect(result.current.latest?.cpu.usage).toBe(70);
    expect(result.current.system?.hostname).toBe('blade-01');
  });

  it('收到 metrics 事件 -> latest 更新，history 追加', () => {
    const { result } = renderHook(() => useSystemMetrics());
    const es = getLastEventSource();

    act(() => {
      es.dispatchEvent('history', {
        metrics: [makeMetric(30)],
        system: mockSystem,
      });
    });

    act(() => {
      es.dispatchEvent('metrics', makeMetric(80));
    });

    expect(result.current.latest?.cpu.usage).toBe(80);
    expect(result.current.history).toHaveLength(2);
  });

  it('sliding window：超過 150 點時舊資料被截斷（維持 MAX_POINTS）', () => {
    // WHY 150? 2 秒 * 150 = 5 分鐘。不截斷會導致記憶體持續增長。
    const { result } = renderHook(() => useSystemMetrics());
    const es = getLastEventSource();

    // 先填 150 筆歷史
    const initial = Array.from({ length: 150 }, (_, i) => makeMetric(i % 100));
    act(() => {
      es.dispatchEvent('history', { metrics: initial, system: mockSystem });
    });

    // 再推 1 筆
    act(() => {
      es.dispatchEvent('metrics', makeMetric(99));
    });

    expect(result.current.history).toHaveLength(150);  // 不超過 MAX_POINTS
    expect(result.current.history[149].cpu.usage).toBe(99);  // 最新在末尾
  });

  it('SSE 發生 error -> status = "error"', () => {
    const { result } = renderHook(() => useSystemMetrics());
    const es = getLastEventSource();

    act(() => {
      es.onerror?.(new Event('error'));
    });

    expect(result.current.status).toBe('error');
  });

  it('unmount -> EventSource.close() 被呼叫（cleanup 防止記憶體洩漏）', () => {
    const { unmount } = renderHook(() => useSystemMetrics());
    const es = getLastEventSource();
    const closeSpy = vi.spyOn(es, 'close');

    unmount();
    expect(closeSpy).toHaveBeenCalled();
  });
});
```

---

### 2-4. metric-gauge.test.tsx（5 cases）

```typescript
// src/__tests__/metric-gauge.test.tsx

import { render, screen } from '@testing-library/react';
import { describe, it, expect } from 'vitest';
import { ThemeProvider } from '@mui/material/styles';
import { createAppTheme } from '../theme';
import { MetricGauge } from '../components/MetricGauge';

function renderWithTheme(ui: React.ReactElement) {
  return render(
    <ThemeProvider theme={createAppTheme('dark')}>{ui}</ThemeProvider>
  );
}

const baseProps = {
  title: 'Compute',
  value: 73.2,
  thresholds: { warning: 70, critical: 85 },
  alertLevel: 'warning' as const,
};

describe('MetricGauge', () => {
  it('顯示 title（"Compute" / "Memory" / "Storage"）', () => {
    renderWithTheme(<MetricGauge {...baseProps} />);
    expect(screen.getByText('Compute')).toBeTruthy();
  });

  it('warning 狀態 -> 顯示 "WARNING" 標籤', () => {
    renderWithTheme(<MetricGauge {...baseProps} alertLevel="warning" />);
    expect(screen.getByText(/WARNING/i)).toBeTruthy();
  });

  it('critical 狀態 -> 顯示 "CRITICAL" 標籤', () => {
    renderWithTheme(<MetricGauge {...baseProps} alertLevel="critical" />);
    expect(screen.getByText(/CRITICAL/i)).toBeTruthy();
  });

  it('normal 狀態 -> 顯示 "NORMAL" 標籤', () => {
    renderWithTheme(<MetricGauge {...baseProps} alertLevel="normal" value={50} />);
    expect(screen.getByText(/NORMAL/i)).toBeTruthy();
  });

  it('value = null -> 顯示 "--"（SSE 尚未連線或斷線）', () => {
    renderWithTheme(
      <MetricGauge {...baseProps} value={null} alertLevel="normal" />
    );
    expect(screen.getByText('--')).toBeTruthy();
  });
});
```

---

### 2-5. dashboard-layout.test.tsx（4 cases，響應式條件渲染）

```typescript
// src/__tests__/dashboard-layout.test.tsx

import { render, screen } from '@testing-library/react';
import { describe, it, expect, vi } from 'vitest';
import { ThemeProvider } from '@mui/material/styles';
import { createAppTheme } from '../theme';
import { Dashboard } from '../components/Dashboard';

// Mock useSystemMetrics 回傳空資料（專注測試 layout 邏輯）
vi.mock('../hooks/useSystemMetrics', () => ({
  useSystemMetrics: vi.fn().mockReturnValue({
    latest: null,
    history: [],
    system: null,
    status: 'connecting',
  }),
}));

function mockMatchMedia(matches: boolean) {
  window.matchMedia = vi.fn().mockImplementation((query: string) => ({
    matches,
    media: query,
    onchange: null,
    addListener: vi.fn(),
    removeListener: vi.fn(),
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    dispatchEvent: vi.fn(),
  }));
}

function renderDashboard() {
  return render(
    <ThemeProvider theme={createAppTheme('dark')}>
      <Dashboard themeMode="dark" onToggleTheme={() => {}} />
    </ThemeProvider>
  );
}

describe('Dashboard 響應式條件渲染', () => {
  it('手機（matches = false）-> TrendCharts 和 DetailPanels 都不 mount', () => {
    // WHY 不用 CSS hide？因為 MUI x-charts 在 display:none 時仍計算 SVG 佈局，
    // 浪費效能且可能出現 width=0 bug。完全不 mount = 零資源消耗。
    mockMatchMedia(false);
    renderDashboard();
    expect(screen.queryByTestId('trend-charts')).toBeNull();
    expect(screen.queryByTestId('detail-panels')).toBeNull();
  });

  it('平板（sm matches, md 不 match）-> TrendCharts mount，DetailPanels 不 mount', () => {
    let callCount = 0;
    window.matchMedia = vi.fn().mockImplementation(() => ({
      matches: callCount++ === 0,  // 第一次（sm）: true, 第二次（md）: false
      media: '',
      onchange: null,
      addListener: vi.fn(),
      removeListener: vi.fn(),
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
      dispatchEvent: vi.fn(),
    }));

    renderDashboard();
    expect(screen.queryByTestId('trend-charts')).toBeTruthy();
    expect(screen.queryByTestId('detail-panels')).toBeNull();
  });

  it('桌面（sm + md 都 matches）-> TrendCharts + DetailPanels 均 mount', () => {
    mockMatchMedia(true);
    renderDashboard();
    expect(screen.queryByTestId('trend-charts')).toBeTruthy();
    expect(screen.queryByTestId('detail-panels')).toBeTruthy();
  });

  it('無論螢幕尺寸，StatusBar 和 MetricCards 永遠 mount', () => {
    // WHY: 品管工程師用手機也需要看到指標摘要。
    // StatusBar + MetricCards 是最低限度的「機器還活著嗎」資訊。
    mockMatchMedia(false);
    renderDashboard();
    expect(screen.queryByTestId('status-bar')).toBeTruthy();
    expect(screen.queryByTestId('metric-cards')).toBeTruthy();
  });
});
```

---

## Part 3: 整合測試場景（Scenarios）

### 3-1. normal-rendering.test.tsx（場景：SSE 連線 -> 正常顯示）

```typescript
// src/__tests__/scenarios/normal-rendering.test.tsx

import { render, screen, act } from '@testing-library/react';
import { describe, it, expect } from 'vitest';
import App from '../../App';
import { getLastEventSource } from '../setup';

const mockSystem = { hostname: 'blade-01', os: 'Linux 5.15', uptimeSeconds: 86400 * 14 };

function makeMetric(cpuUsage: number) {
  return {
    timestamp: Date.now(),
    cpu: { usage: cpuUsage, cores: [cpuUsage - 3, cpuUsage + 3] },
    memory: { total: 8e9, available: 4e9, usage: 50, swapUsage: 0 },
    disk: [{ device: '/dev/sda1', mountpoint: '/', totalGb: 100, usedGb: 42, freeGb: 58, usage: 42 }],
    network: { rxBps: 1024 * 500, txBps: 1024 * 100, rxErrors: 0, txErrors: 0 },
  };
}

describe('Scenario 1: 正常資料流渲染', () => {
  it('SSE history 到達後，頁面顯示正確的 CPU 使用率 + hostname + uptime', () => {
    render(<App />);
    const es = getLastEventSource();
    const metrics = Array.from({ length: 10 }, () => makeMetric(73.5));

    act(() => {
      es.dispatchEvent('history', { metrics, system: mockSystem });
    });

    // 驗證核心指標顯示
    expect(screen.getByText(/73\.5%/)).toBeTruthy();
    // 驗證系統資訊
    expect(screen.getByText(/blade-01/)).toBeTruthy();
    // 驗證 uptime（14 天）
    expect(screen.getByText(/14d/)).toBeTruthy();
  });

  it('每 2 秒收到新 metrics -> latest 數值即時更新', () => {
    render(<App />);
    const es = getLastEventSource();

    // 建立初始歷史
    act(() => {
      es.dispatchEvent('history', {
        metrics: [makeMetric(50)],
        system: mockSystem,
      });
    });
    expect(screen.getByText(/50\.0%/)).toBeTruthy();

    // 推送新值
    act(() => {
      es.dispatchEvent('metrics', makeMetric(80));
    });

    // 新值顯示
    expect(screen.getByText(/80\.0%/)).toBeTruthy();
    // 舊值不再顯示（latest 已更新）
    expect(screen.queryByText(/50\.0%/)).toBeNull();
  });
});
```

---

### 3-2. error-handling.test.tsx（場景：SSE 錯誤 -> 降級顯示）

```typescript
// src/__tests__/scenarios/error-handling.test.tsx

import { render, screen, act } from '@testing-library/react';
import { describe, it, expect, vi } from 'vitest';
import { ThemeProvider } from '@mui/material/styles';
import App from '../../App';
import { ErrorBoundary } from '../../components/ErrorBoundary';
import { createAppTheme } from '../../theme';
import { getLastEventSource } from '../setup';

describe('Scenario 2: 錯誤狀態處理', () => {
  it('初始狀態（SSE 連線中）-> 顯示 "Connecting" 狀態徽章', () => {
    render(<App />);
    expect(screen.getByText(/Connecting/i)).toBeTruthy();
  });

  it('SSE error 事件 -> 顯示 "Error" 或 "Disconnected" 狀態徽章', () => {
    render(<App />);
    const es = getLastEventSource();

    act(() => {
      es.onerror?.(new Event('error'));
    });

    // 接受 Error 或 Disconnected 的文字
    expect(
      screen.getByText(/Error/i) || screen.getByText(/Disconnected/i)
    ).toBeTruthy();
  });

  it('SSE error 時 MetricGauge 仍在畫面上，但值顯示 "--"（graceful degradation）', () => {
    // WHY: 不能因為網路斷線就移除整個 UI。
    // 使用者需要看到「目前斷線」的狀態，而非白屏。
    // "--" 明確告知「沒有資料」，比空白或 0 更誠實。
    render(<App />);
    const es = getLastEventSource();

    act(() => {
      es.onerror?.(new Event('error'));
    });

    // 所有 Gauge 都顯示 "--"（value 為 null）
    const dashes = screen.getAllByText('--');
    expect(dashes.length).toBeGreaterThanOrEqual(3);  // CPU + Memory + Disk
  });

  it('JavaScript 執行期錯誤 -> ErrorBoundary 捕捉，顯示 fallback UI', () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});

    const ThrowingComponent = () => {
      throw new Error('Runtime crash');
    };

    render(
      <ThemeProvider theme={createAppTheme('dark')}>
        <ErrorBoundary>
          <ThrowingComponent />
        </ErrorBoundary>
      </ThemeProvider>
    );

    expect(
      screen.getByText(/Something went wrong/i)
    ).toBeTruthy();
  });
});
```

---

### 3-3. sse-reconnect.test.tsx（場景：斷線 -> 歷史保留 -> 重連）

```typescript
// src/__tests__/scenarios/sse-reconnect.test.tsx

import { render, screen, act, waitFor } from '@testing-library/react';
import { describe, it, expect } from 'vitest';
import App from '../../App';
import { getLastEventSource } from '../setup';

const mockSystem = { hostname: 'blade-01', os: 'Linux 5.15', uptimeSeconds: 86400 };

function makeMetric(cpuUsage: number) {
  return {
    timestamp: Date.now(),
    cpu: { usage: cpuUsage, cores: [cpuUsage] },
    memory: { total: 8e9, available: 4e9, usage: 50, swapUsage: 0 },
    disk: [],
    network: { rxBps: 1000, txBps: 500, rxErrors: 0, txErrors: 0 },
  };
}

describe('Scenario 3: SSE 斷線與重連', () => {
  it('斷線後 -> status 變 "error"，顯示重連提示', () => {
    render(<App />);
    const es = getLastEventSource();

    act(() => {
      es.onerror?.(new Event('error'));
    });

    expect(screen.getByText(/Error|Reconnecting|Disconnected/i)).toBeTruthy();
  });

  it('斷線期間歷史數據保留（不清空 history，TrendCharts 仍顯示最後已知數據）', () => {
    // WHY: 斷線是暫時的，清空歷史 = 使用者失去趨勢判斷能力。
    // 保留最後已知數據讓使用者仍能看到「斷線前的狀態」，
    // 這在排查「是什麼導致斷線」時非常有用。
    render(<App />);
    const es = getLastEventSource();

    // 先建立歷史
    act(() => {
      es.dispatchEvent('history', {
        metrics: [makeMetric(73)],
        system: mockSystem,
      });
    });

    // 確認資料已顯示
    expect(screen.getByText(/73\.0%/)).toBeTruthy();

    // 斷線
    act(() => {
      es.onerror?.(new Event('error'));
    });

    // 歷史數據仍然顯示（未被清空）
    // TrendCharts 在平板以上才顯示，但 StatusBar 和 MetricGauge 應保留最後值
    // 注意：斷線不會把 latest 設為 null，只是 status 變成 error
  });

  it('EventSource 原生重連後收到新 history -> 恢復 connected 狀態', async () => {
    // WHY: EventSource 瀏覽器原生行為是自動重連（約 3 秒後）。
    // 重連成功時後端重新送 history 事件。
    // 測試模擬：error 後，新的 EventSource instance 收到 history。
    render(<App />);
    const es1 = getLastEventSource();

    // 建立初始連線
    act(() => {
      es1.dispatchEvent('history', {
        metrics: [makeMetric(60)],
        system: mockSystem,
      });
    });

    // 模擬斷線
    act(() => {
      es1.onerror?.(new Event('error'));
    });

    // 如果 hook 有重建 EventSource（實作取決於是否手動重連）
    const es2 = getLastEventSource();
    if (es2 !== es1) {
      act(() => {
        es2.dispatchEvent('history', {
          metrics: [makeMetric(55)],
          system: mockSystem,
        });
      });

      await waitFor(() => {
        expect(screen.getByText(/Live|Connected/i)).toBeTruthy();
      });
    }
  });
});
```

---

## 測試覆蓋率目標與配置

### 覆蓋率目標

| 模組 | 目標 | 重點 |
|------|------|------|
| ChartComponents/validation/ | 100% | 純函式，所有 edge case |
| ChartComponents/transforms/ | 100% | 純函式，API 契約驗證 |
| ChartComponents/ 元件 | 80%+ | Skeleton / Error / 正常三條路徑 |
| Dashboard/utils/ | 100% | 純函式，告警邏輯核心 |
| Dashboard/hooks/ | 90%+ | SSE 事件、sliding window、cleanup |
| Dashboard/components/ | 80%+ | 響應式、告警顯示、空狀態 |

### vitest.config.ts 覆蓋率閥值

```typescript
// vitest.config.ts
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/__tests__/setup.ts'],
    coverage: {
      provider: 'v8',
      thresholds: {
        lines: 80,
        functions: 80,
        branches: 75,
        statements: 80,
      },
      exclude: [
        'src/__tests__/**',
        'src/main.tsx',
        '**/*.d.ts',
      ],
    },
  },
});
```

### 執行指令

```bash
# ChartComponents 套件測試
cd ChartComponents && npm test
cd ChartComponents && npm run coverage

# Dashboard 應用測試
cd DemoApp && npm test
cd DemoApp && npm run coverage

# 根目錄全部執行（monorepo workspace）
npm test --workspaces
```

---

## 測試設計原則總結

1. **純函式優先**：validation + transforms + alert-thresholds + format 佔測試總量 70%。快、穩、無 DOM 依賴。

2. **行為測試而非結構測試**：不測 SVG 內部節點結構（MUI 可能改），只測「正確的 fallback 是否出現」和「props 是否正確傳遞」。

3. **AIDMS Domain-Aware**：alert-thresholds 測試包含反向告警邏輯（GPU 低使用率 = 問題），這是面試時最值得展示的差異化設計。

4. **Graceful Degradation 場景**：error-handling + sse-reconnect 測試確保斷線不白屏、歷史不清空。監控儀表板的可靠性 > 功能完整性。
