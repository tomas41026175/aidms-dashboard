# CR Log — DashboardApp

**日期**: 2026-03-12
**範圍**: DashboardApp 全部 27 個檔案
**結果**: 🔴 Blocker x3 / 🟠 Major x8 / 🟡 Minor x8 / 🟢 Nit x3

## Blocker

| # | 檔案 | 問題 |
|---|------|------|
| 1 | server.js:13 | CORS `*` — 任何網域可取得系統資訊 |
| 2 | server.js:153 | catch-all 路由掩蓋 API 404，應加 `/api` 404 handler |
| 3 | server.js:152-154 | SSE endpoint 無 rate limit，clients Set 無上限 → DoS / 記憶體洩漏 |

## Major

| # | 檔案 | 問題 |
|---|------|------|
| 4 | server.js:94-104 | 重複呼叫 si.currentLoad() + loadavg import 方式問題 |
| 5 | server.js:75 | d.use 可能為 null，.toFixed() 會 throw |
| 6 | MetricCards.tsx:41 | 磁碟 Gauge 顯示 disk[0]，告警用 worstDisk，語意不一致 |
| 7 | useSystemMetrics.ts:22 | SSE payload 無 runtime 驗證 |
| 8 | TrendPanel.tsx:28 | 網路圖 yRange 固定 [0,100]，超過 100 KB/s 被截斷 |
| 9 | server.js:175-178 | 心跳 write() 無 try/catch，斷線時 unhandled exception |
| 10 | App.tsx:13 | createAppTheme 未 useMemo，每次 render 重建 theme |
| 11 | useSystemMetrics.ts:22,31 | as string + as Type 雙重 unsafe cast |
