# Spec: @aidms/chart-components npm 套件

**Task**: 實作可重用圖表元件庫，包含 LineChart / BarChart / GaugeChart，三層漸進式 API 設計
**Started**: 2026-03-12T00:00:00+08:00
**Phase**: planning
**Mode**: simple
**Tags**: `TypeScript` `@mui/x-charts` `@mui/material` `Vitest` `tsup` `React` `TDD`

---

## Highlights

**這個 Task 的亮點**：
- **三層漸進式 API**：Level 1 零配置覆蓋 80% 場景，Level 3 escape hatch 不犧牲 MUI 原生能力
- **Transform Layer 是純函式**：`toLineChartProps()` / `toBarChartProps()` / `toGaugeProps()` 無 DOM、無 React，70% 邏輯 100% 可測
- **業務邏輯邊界**：套件不含告警閾值與顏色語義，消費者自行傳入 `color fn`，關注點分離徹底
- **Pit of Success**：開發期 `console.error` + 視覺 fallback 雙重提醒；生產期只顯示 fallback，不洩漏內部資訊

**關鍵設計決策 WHY**：
- **WHY 純函式 Transform Layer**：70% 邏輯不需 DOM，Vitest 直接測試，不需 jsdom overhead，測試速度快 10x
- **WHY 不 throw，改用 fallback**：圖表是儀表板的局部元件，錯誤不應白屏整頁；監控場景中資料異常多為暫時性
- **WHY peerDependencies 鎖 ^7**：面試題範圍，簡單明確；支援多 major 版本增加複雜度但無實際收益
- **WHY `showMark: false` 超過 30 點自動關閉**：150 點時 SVG mark 元素數量爆炸，效能急遽下降；閾值 30 是視覺上仍能辨識單點的邊界
- **WHY tsup 而非 Vite library mode**：tsup 同時輸出 ESM + CJS + `.d.ts`，設定更簡單；Vite library mode 對 CJS 支援較複雜
- **WHY BarChart/GaugeChart 也套用 `skipAnimation`**：SSE 即時更新場景下三個元件應一致，避免畫面局部閃爍不一致

---

## Domain & Code 掌握

**Domain 知識點**：
- `@mui/x-charts` v7 `series[].data` 與 `xAxis[].data` 長度必須一致，否則圖表無聲渲染錯誤（不報 error）
- `null` 是合法缺值（折線斷點），`NaN` / `Infinity` 是非法值，兩者處理邏輯完全不同
- `gaugeClasses.valueArc` 是 MUI CSS class 常數，需從 `@mui/x-charts/Gauge` import
- `ResizeObserver` 在 jsdom 不存在，MUI x-charts 底層依賴它，測試前必須 mock
- `SVGElement.getTotalLength` 在 jsdom 不實作，LineChart 動畫路徑計算需 mock 回傳 0
- `curve: 'monotoneX'` 是時間序列最自然的插值方式，對應 D3 monotone interpolation

**實作關鍵細節**：
- `validateSeriesData()` — 先空 datasets，再長度比對，最後 NaN/Infinity；`null` 跳過不算錯誤
- `toLineChartProps()` — `showMark: labels.length <= 30` 效能保護；scaleType 自動偵測（Date → 'time'，number → 'linear'，其他 → 'point'）；`animate → skipAnimation` 反向映射
- `toBarChartProps()` / `toGaugeProps()` — 同樣處理 `animate → skipAnimation`
- `LineChart.tsx` 渲染決策樹：`datasets 全空 → Skeleton` → `validateSeriesData 失敗 → ChartError` → `useMemo transform → MUI 元件`
- `GaugeChart.tsx` 使用 `role="meter"` + `aria-valuenow/min/max`（非 `role="img"`）
- `index.ts` 必須用具名 export，禁止 `export *`（阻礙 tree-shaking）
- `tsup.config.ts` 的 `external` 必須列出所有 peer deps 的子路徑

---

## Decision Lock

| 決策 | 選擇 | 理由 |
|------|------|------|
| 打包工具 | tsup | ESM + CJS + .d.ts 一次輸出，設定最簡 |
| 測試框架 | Vitest | 與 Vite 同生態，zero-config TypeScript |
| 驗證策略 | 手動 type guard | 零依賴；zod +13KB 不值得 |
| Error 回報 | console.error（開發）+ fallback（生產） | 不 throw，不白屏 |
| peerDeps 版本 | `^7`（react ^18\|\|^19, @mui/material ^7, @mui/x-charts ^7） | 面試題，簡單明確 |
| MUI v7 emotion | 仍需 @emotion/react + @emotion/styled 為 peerDeps | MUI v7 仍以 emotion 為預設 CSS engine |
| LTTB 降採樣 | MVP-CUT（SSE 150 點不需要） | 架構不預留欄位，未來加 prop 為最小改動 |
| Canvas 渲染 | MVP-CUT | SVG 足夠 150 點，10k+ 才需要 |
| enableCanvasFallback prop | **不加入** types.ts（YAGNI） | MVP 不實作就不暴露 prop，未來才加 |

---

## Acceptance Criteria

- [ ] `npm run test` 全部通過，coverage ≥ 80% — verify: `npm run test -- --coverage`
- [ ] `npm run build` 成功，輸出 dist/index.js + dist/index.mjs + dist/index.d.ts — verify: `ls ChartComponents/dist/`
- [ ] Level 1 API 可用：`<LineChart labels={[1,2,3]} datasets={[{label:'A', data:[10,20,30]}]} />` 無報錯
- [ ] 空 datasets → ChartSkeleton（Skeleton 元素存在） — verify: `npm test -- LineChart`
- [ ] 長度不一致 → ChartError（含錯誤原因文字） — verify: `npm test -- LineChart`
- [ ] GaugeChart `value={null}` → 顯示 `--` 而非崩潰 — verify: `npm test -- GaugeChart`
- [ ] BarChart stacked + horizontal layout 正常渲染，無報錯 — verify: `npm test -- BarChart`
- [ ] TypeScript strict mode 無 error — verify: `npx tsc --noEmit`

---

## Task Plan

**Task 1: 專案初始化** [MVP]
- Files:
  - 新增：`ChartComponents/package.json` — npm 套件設定（name, exports, peerDeps, scripts）
  - 新增：`ChartComponents/tsconfig.json` — strict mode TypeScript 設定
  - 新增：`ChartComponents/tsup.config.ts` — ESM + CJS + .d.ts 打包設定
  - 新增：`ChartComponents/vitest.config.ts` — jsdom 環境 + coverage 設定
  - 新增：`ChartComponents/src/test/setup.ts` — ResizeObserver / getTotalLength / matchMedia mock
- Steps:
  1. 建立 `package.json`：name=`@aidms/chart-components`，exports field，peerDeps（react ^18||^19, @mui/material ^7, @mui/x-charts ^7, @emotion/react ^11, @emotion/styled ^11），sideEffects: false
  2. 建立 `tsconfig.json`：strict, target ES2020, moduleResolution bundler
  3. 建立 `tsup.config.ts`：entry src/index.ts，format ['esm','cjs']，dts true，external 含所有 peer deps 及其子路徑（@mui/x-charts/LineChart 等）
  4. 建立 `vitest.config.ts`：environment jsdom，setupFiles setup.ts，coverage thresholds（lines/functions/statements 80%, branches 75%）
  5. 建立 `src/test/setup.ts`：三個必要 mock（ResizeObserver / getTotalLength / matchMedia）
- Verify: `cd ChartComponents && npm install && npx tsc --noEmit`
- Done: `node_modules/` 安裝完成，TypeScript 無報錯

**Task 2: 型別定義** [MVP]
- Files:
  - 新增：`ChartComponents/src/types.ts` — 所有 Public API 型別
- Steps:
  1. 定義 `Dataset`（label, data, color）
  2. 定義 `ChartBaseProps`（height, title, animate）
  3. 定義 `LineChartProps extends ChartBaseProps`（labels, datasets, curve, fill, yRange, connectNulls, slotProps）— **不加** maxPoints / downsampleStrategy / enableCanvasFallback（YAGNI）
  4. 定義 `BarChartProps extends ChartBaseProps`（labels, datasets, layout, stacked, yRange, slotProps）
  5. 定義 `GaugeChartProps extends ChartBaseProps`（value, min, max, label, formatValue, arc, color, slotProps）
- Verify: `npx tsc --noEmit`
- Done: 所有型別無 error，`null` 在 `data` 陣列與 `value` 欄位都能被正確接受
- Blocked by: Task 1

**Task 3: Validation Layer TDD** [MVP]
- Files:
  - 新增：`ChartComponents/src/validation/__tests__/validate-series.test.ts`
  - 新增：`ChartComponents/src/validation/validate-series.ts`
  - 新增：`ChartComponents/src/validation/__tests__/validate-gauge.test.ts`
  - 新增：`ChartComponents/src/validation/validate-gauge.ts`
- Steps:
  1. 寫 `validate-series.test.ts`（先 RED）：空 datasets / 長度一致 / 長度不一致＋具體訊息 / NaN / Infinity / null 合法 / 空 data 合法 / 多 datasets 均一致 / 開發模式 console.error（共 **9 cases**，依 test-spec.md）
  2. 執行測試確認 RED
  3. 實作 `validateSeriesData(labels, datasets): ValidationResult`
  4. 執行測試確認 GREEN
  5. 寫 `validate-gauge.test.ts`（先 RED）：null 合法 / 超出 max / 超出 min / 正常值（共 4 cases）
  6. 實作 `validateGaugeData(value, min, max): ValidationResult`
  7. 執行測試確認 GREEN
- Verify: `npm test -- validation`
- Done: 9 + 4 = **13 個**測試全部通過
- Blocked by: Task 2

**Task 4: Line + Bar Transform Layer TDD** [MVP]
- Files:
  - 新增：`ChartComponents/src/transforms/__tests__/to-line-props.test.ts`
  - 新增：`ChartComponents/src/transforms/to-line-props.ts`
  - 新增：`ChartComponents/src/transforms/__tests__/to-bar-props.test.ts`
  - 新增：`ChartComponents/src/transforms/to-bar-props.ts`
- Steps:
  1. 寫 `to-line-props.test.ts`（先 RED）：Date → time / string → point / smooth → monotoneX / linear curve / step curve / 30+ 點 → showMark false / animate false → skipAnimation true / animate true（預設）→ skipAnimation false / slotProps 合併 / yRange 套用 / fill → area true / connectNulls 傳遞（共 **12 cases**，依 test-spec.md）
  2. 實作 `toLineChartProps()`：CURVE_MAP、scaleType 自動偵測、showMark 閾值、`animate → skipAnimation`
  3. 寫 `to-bar-props.test.ts`（先 RED）：stacked → stack key 相同 / horizontal → 軸交換 / layout vertical / animate → skipAnimation（共 4 cases）
  4. 實作 `toBarChartProps()`：含 `animate → skipAnimation` 映射
- Verify: `npm test -- "to-(line|bar)-props"`
- Done: 12 + 4 = **16 個**測試全部通過
- Blocked by: Task 2

**Task 5: Gauge Transform Layer TDD** [MVP]
- Files:
  - 新增：`ChartComponents/src/transforms/__tests__/to-gauge-props.test.ts`
  - 新增：`ChartComponents/src/transforms/to-gauge-props.ts`
- Steps:
  1. 寫 `to-gauge-props.test.ts`（先 RED）：half → startAngle -110/endAngle 110 / full → 0/360 / value clamp max / value clamp min / null value / color fn 套用 / color string 靜態 / formatValue 自訂 / animate → skipAnimation（共 **9 cases**，依 test-spec.md）
  2. 實作 `toGaugeProps()`：ARC_MAP、clamp 邏輯、color fn 解析、`animate → skipAnimation`
- Verify: `npm test -- to-gauge`
- Done: 9 個測試全部通過
- Blocked by: Task 2

**Task 6: Fallback 元件** [MVP]
- Files:
  - 新增：`ChartComponents/src/fallbacks/ChartSkeleton.tsx`
  - 新增：`ChartComponents/src/fallbacks/ChartError.tsx`
- Steps:
  1. 實作 `ChartSkeleton`：MUI `<Skeleton variant="rectangular" width="100%" height={height} />`
  2. 實作 `ChartError`：虛線框 + `Typography` 顯示 reason
- Verify: `npx tsc --noEmit`
- Done: 兩個元件 TypeScript 無 error（render 測試在 Task 7 間接覆蓋：ChartSkeleton 路徑 + ChartError 路徑）
- Blocked by: Task 1

**Task 7: LineChart Rendering TDD** [MVP]
- Files:
  - 新增：`ChartComponents/src/__tests__/LineChart.test.tsx`
  - 新增：`ChartComponents/src/LineChart.tsx`
- Steps:
  1. 寫 `LineChart.test.tsx`（先 RED）：正常數據渲染 SVG / 空 data → ChartSkeleton / 長度不一致 → ChartError + 原因文字 / 開發模式 → console.error 被呼叫 / null 值正常渲染（共 **5 cases**，依 test-spec.md）
  2. 實作 `LineChart.tsx`：渲染決策樹 + `role="img"` + `aria-label`；`useMemo` 包住 transform 呼叫
  3. 執行測試確認 GREEN
- Verify: `npm test -- LineChart`
- Done: 5 個測試全部通過
- Blocked by: Task 3, Task 4, Task 6

**Task 8: BarChart + GaugeChart Rendering TDD** [MVP]
- Files:
  - 新增：`ChartComponents/src/__tests__/BarChart.test.tsx`
  - 新增：`ChartComponents/src/BarChart.tsx`
  - 新增：`ChartComponents/src/__tests__/GaugeChart.test.tsx`
  - 新增：`ChartComponents/src/GaugeChart.tsx`
- Steps:
  1. 寫 `BarChart.test.tsx`（先 RED）：正常數據渲染 SVG / 空 data → ChartSkeleton / stacked 渲染無報錯 / 長度不一致 → ChartError（共 **4 cases**）
  2. 實作 `BarChart.tsx`：渲染決策樹 + `role="img"` + `aria-label`
  3. 寫 `GaugeChart.test.tsx`（先 RED）：正常值渲染 SVG / null value 顯示 "--" / role="meter" 存在 / aria-valuenow 正確 / value 超出 max 不 throw（共 **5 cases**，依 test-spec.md）
  4. 實作 `GaugeChart.tsx`：`role="meter"` + `aria-valuenow/min/max`；null → `--`
  5. 執行所有測試確認 GREEN
- Verify: `npm test -- "(BarChart|GaugeChart)"`
- Done: 4 + 5 = **9 個**測試全部通過
- Blocked by: Task 3, Task 5, Task 6

**Task 9: Package Entry + Build 驗證** [MVP]
- Files:
  - 新增：`ChartComponents/src/index.ts`
- Steps:
  1. 實作 `index.ts`：具名 export `LineChart`、`BarChart`、`GaugeChart`、型別（`LineChartProps` 等）；禁止 `export *`
  2. 執行 `npm run build`（tsup）
  3. 確認 `dist/` 輸出：index.js（CJS）+ index.mjs（ESM）+ index.d.ts
- Verify: `npm run build && ls dist/`
- Done: dist/ 有三種輸出，`index.d.ts` 包含三個元件型別
- Blocked by: Task 7, Task 8

**Task 10: LTTB 降採樣** [MVP-CUT]
> 未來實作：SSE 歷史回顧功能上線後（> 300 點）才實作。最小改動：新增 `src/transforms/downsample.ts`，在 `LineChartProps` 加入 `maxPoints?: number` 和 `downsampleStrategy?: 'lttb' | 'minmax'`，`toLineChartProps()` 呼叫 `downsampleDatasets()`。
> 目前保留：`docs/chart-large-data-optimization.md` 已有完整實作設計，不加入 types.ts（YAGNI）

**Task 11: Canvas 渲染路徑** [MVP-CUT]
> 未來實作：10k+ 點時才需要。最小改動：新增 `src/canvas/CanvasLineChart.tsx`，在 `LineChart.tsx` 加 `if (totalPoints > 10_000) return <CanvasLineChart />`，同時在 `LineChartProps` 加入 `enableCanvasFallback?: boolean`
> 目前保留：`docs/chart-large-data-optimization.md` 有完整 Canvas 實作設計

---

## Deviation Rules
- 自動修復：bug、型別錯誤、lint、缺少 import
- 停止回報：改變 Public API（types.ts 中的 Props 介面）、影響 5+ 個計畫外的檔案

---

## Technical Change Log
（執行期間填入）
