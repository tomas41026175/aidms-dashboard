# 面試應對策略

> 面試標的：麗臺科技 AIDMS 前端工程師
> 整理日期：2026-03-12

---

## 核心定位

> 「我不只做了面試作業，我研究了你們的產品，把 AIDMS 的 domain 邏輯帶進設計決策裡。」

---

## 我的優勢

### 1. 對產品有深度理解

- 知道 AIDMS 的 domain 語義：GPU 100% = 好事（AI 訓練正常），GPU 0% 才是 critical
- 了解三種使用者角色（品管工程師、AI 工程師、IT 部署人員）及其核心問題
- 研究過 AIDMS 競品（NVIDIA TAO、Roboflow、Landing AI）與差異化定位

### 2. 專案直接對應產品需求

| aidms-dashboard 設計 | 對應麗臺需求 |
|---------------------|------------|
| SSE 即時監控（2 秒推送） | GDMS GPU 資源管理面板 |
| `@aidms/chart-components` 自製套件 | 元件庫設計能力 |
| Dark mode + MUI | AIDMS 目標用戶習慣（Grafana/IDE 風格） |
| Domain-aware 告警三態 | AI 訓練監控的語義正確性 |
| 三層漸進式 API 設計 | Staff Engineer 級別的 API 思維 |

### 3. 技術棧吻合

React + TypeScript + MUI，正是此類 AI 管理平台的主流選擇。

---

## 預測題目與答法

| 題目 | 答法要點 |
|------|---------|
| 介紹最有挑戰性的專案 | aidms-dashboard：domain-aware 告警設計、SSE 架構選型（vs WebSocket 取捨）、元件庫三層 API |
| 如何設計即時監控 UI？ | SSE 單向推送 + 前端 sliding window（150 點 deque），說明為何不用 WebSocket |
| 如何設計可重用的圖表元件？ | Consumer-first + 三層漸進式 API（Level 1 零配置 → Level 2 進階 → Level 3 escape hatch） |
| React 效能優化做過什麼？ | chart re-render 頻率控制、window 點數限制 |
| 你對我們公司了解多少？ | AIDMS 定位、No-Code MLOps 五步驟、LLM RAG 新功能、三種使用者角色 |

---

## 介紹專案的說法

**不要說**：「我做了一個 Dashboard 練習專案。」

**要說**：

> 「我在面試前研究了 AIDMS 和 GDMS 的產品形態，發現核心挑戰在於 domain-aware 的告警邏輯——通用監控和 AI 訓練監控的指標語義完全不同。GPU 100% 在通用監控是告警，在 AIDMS 是正常。所以我針對這個場景設計了一套監控 Dashboard，並把圖表元件抽成獨立套件，設計了三層漸進式 API...」

---

## 需要補強的弱點

### GPU 監控

MVP 刻意排除 GPU 監控（`psutil` 不支援），面試官可能追問：

> 「如果要加 GPU 監控怎麼做？」

**準備答案**：
- 後端改用 `py3nvml` 或 `pynvml` 讀取 NVIDIA GPU 指標
- 架構上 `SystemMetrics` 已有 `hostname` 欄位，可水平擴充成多節點叢集監控
- 前端 GPU 區塊設計為 optional（graceful fallback：有 GPU 就顯示，沒有也不報錯）

---

## 面試流程預測

1. **人資電話篩選**：薪資期望、工作地點確認
2. **技術主管面試**：作品集審查 + 技術問答（重點在此）
3. **部門主管面談**：文化契合度

面試難度低（面試趣評分），錄取率 42%，重視實務作品集勝於演算法。
