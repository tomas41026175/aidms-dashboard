# AIDMS Dashboard — 面試速查備忘錄

> 專案：aidms-dashboard — 系統監控儀表板 + @aidms/chart-components
> 技術棧：React + TypeScript + MUI + @mui/x-charts + FastAPI + SSE
> 詳細文件：`docs/leadtek-interview-prep.md`、`docs/interview-strategy.md`

---

## 一句話定位

> 「我在面試前研究了 AIDMS 和 GDMS 的產品形態，發現核心挑戰在於 domain-aware 的告警邏輯——通用監控和 AI 訓練監控的指標語義完全不同。GPU 100% 在通用監控是告警，在 AIDMS 是正常運作。所以我針對這個場景設計了監控 Dashboard，並把圖表元件抽成獨立 npm 套件，設計了三層漸進式 API。」

---

## 專案亮點（面試時可主動提）

| 亮點 | 說明 |
|------|------|
| Domain-aware 告警 | GPU 100% = 正常；通用指標用 consecutive 3 點才觸發 |
| SSE vs WebSocket | 單向推送不需雙向通訊，更輕量；EventSource 自動重連免手工 |
| 三層漸進式 API | Level 1 零配置、Level 2 進階、Level 3 escape hatch |
| Transform Layer | 純函式 `toLineChartProps()` — 70% 邏輯無 DOM，100% 可測 |
| LTTB 降採樣 | 大量資料保視覺保真度，O(n) 演算法 |
| NVIDIA NGC 風格 | 工程師工具鏈慣用深色系，與 Grafana / NGC 視覺語言一致 |
| TDD | RED → GREEN → REFACTOR，80%+ coverage |

---

## 高頻問題 × STAR

### Q1. 如何設計即時監控 UI？為何選 SSE 而非 WebSocket？

**Situation**：系統監控需要每 2 秒推送 CPU/Memory/Disk 數據給瀏覽器，且是**單向**（Server → Browser）。

**Task**：選擇即時通訊方式，要求簡單可靠、自動重連。

**Action**：
```python
# FastAPI SSE + MetricsBroadcaster
async def event_stream():
    queue = asyncio.Queue()
    broadcaster.subscribe(queue)
    # 先送 history event（頁面立刻有資料）
    yield {"event": "history", "data": json.dumps(broadcaster.history)}
    async for metrics in queue:
        yield {"event": "metrics", "data": json.dumps(metrics)}
```

```typescript
// 前端 sliding window
const MAX_POINTS = 150;  // 5 分鐘 @ 2s interval
const source = new EventSource('/api/metrics/stream');
source.addEventListener('metrics', (e) => {
  setHistory(prev => [...prev.slice(-(MAX_POINTS - 1)), JSON.parse(e.data)]);
});
// EventSource 原生自動重連，不需手動實作
```

**Result**：SSE 比 WebSocket 簡單 50%（無握手、HTTP/2 復用、原生重連）。監控場景不需雙向通訊，SSE 是最適合的選擇。

---

### Q2. @aidms/chart-components 的三層 API 設計為何這樣設計？

**Situation**：圖表元件需要讓不同熟練度的消費者都能用，同時不能犧牲 MUI x-charts 的進階能力。

**Task**：設計一個 Consumer-first 的 API，80% 場景零配置，20% 進階場景也能處理。

**Action**：
```typescript
// Level 1：零配置（80% 場景）
<LineChart labels={timestamps} datasets={[{ label: 'CPU', data: cpuHistory }]} />

// Level 2：進階配置
<LineChart labels={timestamps} datasets={...} yRange={[0, 100]} animate={false} />

// Level 3：escape hatch（不卡住任何 MUI 能力）
<LineChart labels={timestamps} datasets={...} slotProps={{ xAxis: { tickLabelStyle: { fontSize: 10 } } }} />
```

Transform Layer 把我們的 API 翻譯成 MUI 需要的格式——這個翻譯是**純函式**，無 DOM、無 React，100% 可用 Vitest 直接測試。

**Result**：70% 邏輯是純函式（validation + transforms），測試快且穩。

---

### Q3. 為何採用 consecutive 3 點告警，而非即時觸發？

**Situation**：CPU 瞬間 spike 到 90% 又立刻降回 60%（常見於 batch job 短暫佔用），若立即觸發 Critical 會造成 alert fatigue（告警疲勞）。

**Task**：設計符合 AI 訓練場景語義的告警邏輯。

**Action**：
```typescript
export function deriveAlertLevel(
  history: number[],
  thresholds: { warning: number; critical: number },
  consecutiveCount = 3
): AlertLevel {
  const recent = history.slice(-consecutiveCount);
  if (recent.length < consecutiveCount) return 'normal';
  if (recent.every(v => v > thresholds.critical)) return 'critical';
  if (recent.every(v => v > thresholds.warning)) return 'warning';
  return 'normal';
}
```

**Result**：需要連續 3 個點（6 秒）才觸發告警，過濾瞬間 spike，與 Prometheus 的 `for: 15s` 設計原理相同。

---

### Q4. 圖表大量資料如何優化？

| 資料量 | 策略 |
|--------|------|
| < 300 點（SSE MVP） | 直接 SVG 渲染 |
| 300 ~ 10k 點 | LTTB 降採樣（時間序列保視覺保真度） |
| > 10k 點 | Canvas 渲染 + Web Worker 降採樣 |

**LTTB（Largest Triangle Three Buckets）**：每個 bucket 保留三角形面積最大的點，保留峰/谷/轉折，捨棄中間平坦段的冗餘點。

```typescript
// 完整實作：docs/chart-large-data-optimization.md
export function lttbDownsample(data: [number, number][], threshold: number) { ... }
```

---

### Q5. 如果要加 GPU 監控怎麼做？

MVP 刻意排除（`psutil` 不支援 GPU），但架構已預留：

- 後端：改用 `py3nvml` / `pynvml` 讀取 NVIDIA GPU 指標
- `SystemMetrics` type 加 `gpu?: GpuMetrics`（optional，向後相容）
- 前端：GPU 卡片設計為 conditional render（有才顯示，沒有不報錯）
- 水平擴充：`hostname` 欄位已存在，可擴展成多節點叢集監控

---

## 預測題目快查

| 題目 | 答法關鍵字 |
|------|-----------|
| 介紹最有挑戰性的專案 | domain-aware 告警、SSE、三層 API |
| 即時監控怎麼設計 | SSE + sliding window + history event |
| 可重用元件怎麼設計 | Consumer-first + Transform Layer（純函式） |
| React 效能優化 | useMemo、skipAnimation、LTTB 降採樣 |
| 公司了解多少 | AIDMS No-Code 五步驟、LLM RAG、三種使用者角色 |
| 為何 dark mode | 工程師工具鏈（Grafana/NGC/VSCode）慣用，降低眼睛疲勞 |
| TypeScript strict mode | 禁 any、Zod runtime 驗證、type guard |

---

## AIDMS Domain 語義（必背）

- **GPU 100% = 好事**（AI 訓練正常執行）
- **GPU 長時間 0% = critical**（訓練任務崩潰）
- 這與通用監控**完全相反**，是展示產品理解的切入點

No-Code 五步驟：`上傳資料 → 自動標注 → 選擇任務/模型 → 自動訓練 → 一鍵部署`

---

## 公司快速資料

| 項目 | 內容 |
|------|------|
| 技術棧吻合度 | React + TypeScript + MUI（面試硬性要求） |
| 工時 | 週 ~40 小時，幾乎不加班 |
| 薪資範圍 | 前端 70~100 萬 / 年 |
| 面試難度 | 低，重視作品集 |
| 錄取率 | 42%（不需刷 LeetCode） |

詳細資料：`docs/leadtek-interview-prep.md`、`docs/leadtek-company-research.md`
