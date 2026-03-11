# 系統監控儀表板 Domain Knowledge

## 1. 核心監控指標

### CPU

**指標優先順序：**

1. **整體使用率** `cpu_percent(interval=None)` — 最直觀
2. **各核心使用率** `cpu_percent(percpu=True)` — 可發現單核瓶頸
3. **Load Average（1m/5m/15m）** — Linux/macOS 專有，健康值：load / cores < 1.0
4. **CPU 頻率** `cpu_freq()` — 判斷是否降頻（thermal throttling）
5. **Temperature** — macOS 無法直接取得，Linux 用 `sensors_temperatures()`

**儀表板建議：** 優先顯示整體 usage%，次要顯示 per-core 熱力圖，load average 作補充。

---

### Memory

`virtual_memory()` 各欄位意義：

| 欄位 | 意義 | 重要性 |
|---|---|---|
| `total` | 實體記憶體總量 | 基準值 |
| `available` | **可立即使用**（free + reclaimable cache） | **最重要** |
| `used` | total - available - buffers - cached | 中 |
| `free` | 完全未使用（不含 cache） | 容易誤解，不建議主顯 |
| `cached` | 檔案系統快取（可回收） | Linux 專有 |
| `buffers` | I/O 緩衝區（可回收） | Linux 專有 |

**正確使用率計算：**
```python
usage_pct = (mem.total - mem.available) / mem.total * 100
# 不要用 used / total，Linux 的 used 包含 cache 會誤報
```

**Swap 必須監控：** `swap_memory().percent` > 20% 是明顯效能警訊。

---

### Disk

**分區篩選（重要）：**
```python
EXCLUDE_FSTYPES = {
    'tmpfs', 'devtmpfs', 'devfs', 'iso9660',
    'squashfs', 'overlay', 'aufs',
    'proc', 'sysfs', 'cgroup', 'cgroup2',
    'pstore', 'bpf', 'tracefs',
}

def get_valid_partitions():
    seen_devices = set()
    results = []
    for partition in psutil.disk_partitions(all=False):
        if partition.fstype in EXCLUDE_FSTYPES:
            continue
        if partition.device in seen_devices:
            continue
        seen_devices.add(partition.device)
        try:
            usage = psutil.disk_usage(partition.mountpoint)
            results.append({
                'device': partition.device,
                'mountpoint': partition.mountpoint,
                'fstype': partition.fstype,
                'total_gb': usage.total / (1024 ** 3),
                'used_gb': usage.used / (1024 ** 3),
                'free_gb': usage.free / (1024 ** 3),
                'percent': usage.percent,
            })
        except PermissionError:
            continue
    return results
```

**IOPS 計算（需兩次採樣）：**
```python
iops_read = (d2.read_count - d1.read_count) / interval
throughput_read_mb = (d2.read_bytes - d1.read_bytes) / interval / 1024 / 1024
```

---

### Network

`net_io_counters()` 是**累計值**，必須兩次採樣計算速率：

```python
class NetworkRateCalculator:
    def __init__(self):
        self._prev = psutil.net_io_counters(pernic=True)
        self._prev_time = time.monotonic()

    def get_rates(self):
        curr = psutil.net_io_counters(pernic=True)
        curr_time = time.monotonic()
        interval = curr_time - self._prev_time

        rates = {}
        for nic, c in curr.items():
            if nic == 'lo':
                continue
            p = self._prev.get(nic)
            if p is None:
                continue
            rates[nic] = {
                'rx_bps': max(0, (c.bytes_recv - p.bytes_recv) / interval),
                'tx_bps': max(0, (c.bytes_sent - p.bytes_sent) / interval),
                'rx_errs': (c.errin - p.errin) / interval,
                'tx_errs': (c.errout - p.errout) / interval,
                'rx_drops': (c.dropin - p.dropin) / interval,
                'tx_drops': (c.dropout - p.dropout) / interval,
            }

        self._prev = curr
        self._prev_time = curr_time
        return rates
```

**注意反轉問題：** 差值為負（計數器溢出）時使用 `max(0, delta)` 跳過。

---

## 2. 監控數據最佳實踐

### 採集頻率

| 情境 | 建議頻率 |
|---|---|
| 即時儀表板 | **2 秒** |
| 警告檢測 | 5 秒（避免尖峰誤觸發） |
| 歷史趨勢存儲 | 30 秒 |

**本專案採用：後端每 2 秒採集，SSE 每 2 秒推送。**

### 歷史數據保留

```
即時視圖：最近 5 分鐘 = 150 個點（2 秒 × 150）
前端 sliding window：MAX_POINTS = 150
```

```javascript
const addDataPoint = (history, newPoint) =>
    [...history.slice(-MAX_POINTS + 1), newPoint];
```

---

## 3. 告警閾值（業界標準）

### CPU
| 狀態 | 閾值 | 顏色 |
|---|---|---|
| 正常 | < 70% | `#22c55e` green-500 |
| Warning | 70–85% | `#f59e0b` amber-500 |
| Critical | > 85% | `#ef4444` red-500 |

**觸發條件：連續 3 個採樣點超過閾值**（避免瞬間尖峰誤報）

### Memory
| 狀態 | 閾值 |
|---|---|
| 正常 | < 75% |
| Warning | 75–90% |
| Critical | > 90% |

Swap 獨立閾值：Warning > 10%，Critical > 50%

### Disk
| 狀態 | 閾值 |
|---|---|
| 正常 | < 80% |
| Warning | 80–90% |
| Critical | > 90% |

> 磁碟不同於 CPU，95% 時許多系統會直接拒絕寫入。

### Network Errors/Drops
- 任何非零的 error rate → Warning
- drops > 0.1% of packets → Warning

### 數據精度
- CPU %：1 位小數
- Memory %：整數
- Disk %：整數
- Network 速率：自動換算單位（B/KB/MB/GB），2 位小數

---

## 4. Dashboard UX 最佳實踐

### 資訊層級

```
Level 1（Hero）：CPU%、Memory%、Disk%、Network 速率
  → 4 個大型 Gauge / 數字卡片

Level 2（趨勢）：CPU / Memory 5 分鐘歷史折線圖

Level 3（明細）：per-core 使用率、各磁碟分區、各網路介面

Level 4（進程）：Top 10 CPU / Memory 進程列表（可選）
```

### 顏色系統
```css
--color-normal:      #22c55e;
--color-warning:     #f59e0b;
--color-critical:    #ef4444;
--color-bg-warning:  rgba(245, 158, 11, 0.1);
--color-bg-critical: rgba(239, 68, 68, 0.1);
```

**視覺強化：**
- Critical 狀態加脈衝動畫
- 卡片背景色跟隨狀態
- 圖表上畫告警閾值參考線
- 使用狀態圖示 ✓ / ⚠ / ✕（色盲友善）

### 時間軸設計
- **預設顯示：5 分鐘**
- X 軸標籤格式：`HH:mm:ss`，每分鐘一個標籤
- Y 軸：**固定 0–100%**（不自動縮放，視覺誤導）

### 響應式斷點策略
```
< 640px    單欄：只顯示 Level 1 + 告警狀態
640–1024px 雙欄：Level 1 + Level 2
> 1024px   完整儀表板
```

**手機版隱藏：** per-core 詳細、進程列表、網路詳細

---

## 5. psutil 在 FastAPI 的使用細節

### cpu_percent 首次回傳 0 的處理

```python
class MetricsCollector:
    def __init__(self):
        # 啟動時先呼叫一次，丟棄結果（建立基準線）
        psutil.cpu_percent(interval=None)
        psutil.cpu_percent(percpu=True, interval=None)
```

### FastAPI 非同步環境中的阻塞呼叫

`cpu_percent(interval=1)` 會阻塞，必須在執行緒池執行：

```python
from concurrent.futures import ThreadPoolExecutor
executor = ThreadPoolExecutor(max_workers=2)

async def get_cpu_async():
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(
        executor,
        lambda: psutil.cpu_percent(interval=1, percpu=True)
    )
```

### 廣播架構（多 Client 資源共享）

```python
class MetricsBroadcaster:
    """單一採集器，廣播給所有連線的 clients"""

    def __init__(self):
        self._clients: set[asyncio.Queue] = set()
        self._history: deque = deque(maxlen=150)
        self._task: asyncio.Task | None = None

    async def start(self):
        if self._task is None:
            self._task = asyncio.create_task(self._collect_loop())

    async def _collect_loop(self):
        while True:
            metrics = await collect_metrics()
            self._history.append(metrics)
            dead = set()
            for q in self._clients:
                try:
                    q.put_nowait(metrics)
                except asyncio.QueueFull:
                    dead.add(q)
            self._clients -= dead
            await asyncio.sleep(2)

    def subscribe(self) -> asyncio.Queue:
        q = asyncio.Queue(maxsize=10)
        self._clients.add(q)
        return q

    def unsubscribe(self, q: asyncio.Queue):
        self._clients.discard(q)

    def get_history(self) -> list:
        return list(self._history)
```

---

## 6. FastAPI SSE 技術細節

### sse-starlette 完整實作

```python
from sse_starlette.sse import EventSourceResponse

async def sse_generator(request: Request):
    queue = broadcaster.subscribe()

    # 先送歷史數據，client 立刻有圖可看
    history = broadcaster.get_history()
    if history:
        yield {"event": "history", "data": json.dumps(history)}

    try:
        while True:
            if await request.is_disconnected():
                break
            try:
                metrics = await asyncio.wait_for(queue.get(), timeout=5.0)
                yield {"event": "metrics", "data": json.dumps(metrics)}
            except asyncio.TimeoutError:
                yield {"comment": "heartbeat"}  # 15 秒心跳
    finally:
        broadcaster.unsubscribe(queue)  # 必須清理

@app.get("/api/metrics/stream")
async def stream(request: Request):
    return EventSourceResponse(
        sse_generator(request),
        headers={"X-Accel-Buffering": "no"},  # 關閉 Nginx 緩衝
    )
```

### CORS 設定（SSE 特殊注意）

```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],  # 不能用 "*"（withCredentials 時）
    allow_credentials=True,
    allow_methods=["GET"],
    allow_headers=["*"],
    expose_headers=["Content-Type", "Cache-Control"],
)
```

### 心跳必要性
- Nginx 預設 60 秒無流量會斷開連線
- 建議每 **15 秒**發送一次 SSE comment（`yield {"comment": "heartbeat"}`）

---

## 7. 架構建議總結

```
採集層：
  - MetricsBroadcaster 單例，每 2 秒採集
  - 歷史保留 150 點（5 分鐘）
  - 阻塞呼叫放執行緒池

傳輸層：
  - SSE，2 秒推送
  - 15 秒心跳
  - 連線時先推送歷史

前端層：
  - Sliding window 150 點
  - EventSource 自動重連（內建）
  - 告警連續 3 點超閾值才觸發
```
