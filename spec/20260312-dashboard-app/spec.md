# Spec: 系統監控儀表板（DashboardApp）

**Task**: Task 1 — React/TypeScript 前端 + Node.js Express 後端全端監控儀表板
**Started**: 2026-03-12T00:00:00Z
**Phase**: execution
**Mode**: complex
**Tags**: `React` `TypeScript` `Node.js` `Express` `SSE` `@mui/material` `@mui/x-charts` `@aidms/chart-components` `Vitest` `Vite`

---

## Decision Lock

- 後端：`server.js`（Node.js + Express + systeminformation）— PDF 明確要求
- 前端：Vite + React 18 + TypeScript strict
- 套件：`@aidms/chart-components` 使用 `file:../ChartComponents`
- SSE port：後端 3001，前端 5173（vite proxy）
- 告警：連續 3 點才觸發（非單點）
- 測試：Vitest + @testing-library/react，至少 3 個場景

## Acceptance Criteria

- [ ] `node server.js` 啟動後端，port 3001 回應 SSE
- [ ] `npm start` 啟動前端，頁面載入 < 2 秒
- [ ] CPU / 記憶體 / 磁碟 Gauge 即時顯示（2 秒更新）
- [ ] 告警色變化（normal / warning / critical）
- [ ] 響應式：手機 2×2、平板 + trends、桌面 + details
- [ ] 至少 3 個測試場景通過

---

## Task Plan

**Task 1: Project Setup** [MVP]
- Files: package.json, vite.config.ts, tsconfig.json, index.html
- Steps: 手動建立 Vite React TS 設定，安裝所有依賴
- Verify: `npm install` 成功，`npm run build` 無錯誤
- Done: node_modules 存在，tsc 通過

**Task 2: Types + Utils** [MVP]
- Files: src/types/metrics.ts, src/utils/alert-thresholds.ts, src/utils/alert-colors.ts, src/utils/format.ts
- Verify: `npx tsc --noEmit`
- Done: 型別無錯誤

**Task 3: Backend server.js** [MVP]
- Files: server.js
- Steps: Express + systeminformation + SSE ring buffer + history event + 2s interval + 15s heartbeat
- Verify: `node server.js` → curl http://localhost:3001/api/metrics/stream
- Done: SSE 回應包含 history 及 metrics event

**Task 4: Theme + Entry** [MVP]
- Files: src/theme.ts, src/main.tsx, src/App.tsx
- Verify: `npm run build`
- Done: 無型別錯誤

**Task 5: useSystemMetrics Hook** [MVP]
- Files: src/hooks/useSystemMetrics.ts
- Verify: `npx tsc --noEmit`
- Done: hook 型別正確

**Task 6: Base Components** [MVP]
- Files: src/components/ErrorBoundary.tsx, src/components/DashboardAppBar.tsx, src/components/ConnectionBadge.tsx, src/components/ThemeToggle.tsx
- Verify: `npx tsc --noEmit`

**Task 7: Metric Cards** [MVP]
- Files: src/components/MetricCards.tsx, src/components/MetricGauge.tsx, src/components/NetworkCard.tsx
- Verify: `npx tsc --noEmit`

**Task 8: Chart Panels** [MVP]
- Files: src/components/TrendCharts.tsx, src/components/TrendPanel.tsx, src/components/DetailPanels.tsx, src/components/CpuCorePanel.tsx, src/components/DiskPanel.tsx
- Verify: `npx tsc --noEmit`

**Task 9: Dashboard** [MVP]
- Files: src/components/Dashboard.tsx
- Verify: `npm run build`
- Done: 建置成功

**Task 10: Tests** [MVP]
- Files: src/__tests__/setup.ts, src/__tests__/alert-thresholds.test.ts, src/__tests__/format.test.ts, src/__tests__/scenarios/*.test.tsx
- Verify: `npm test`
- Done: 3 個場景全部通過

**Task 11: Build + README** [MVP]
- Files: README.md
- Verify: `npm run build && node server.js`（靜態檔案從 dist/ 服務）
- Done: 整合完成

---

## Deviation Rules
- 自動修復：型別錯誤、lint、缺少 import
- 停止回報：改變 API contract、影響 5+ 個計畫外的檔案

## Technical Change Log
（執行期間填入）
