# 麗臺科技前端工程師面試準備

> 面試標的：麗臺科技 AIDMS 前端工程師
> 整理日期：2026-03-12

---

## 核心定位

> 「我不只做了面試作業，我研究了你們的產品，把 AIDMS 的 domain 邏輯帶進設計決策裡。」

---

## 一、公司基本資料

| 項目 | 內容 |
|------|------|
| 股票代碼 | 2465（台灣證交所，2001年上市） |
| 成立年份 | 1986年 |
| 總部 | 新北市中和區建一路 166 號 18 樓 |
| 合作夥伴 | NVIDIA 亞太地區長期核心合作夥伴 |
| 認證 | ISO 9001 / 14001 / 27001 |

### 主要產品線

| 產品線 | 說明 |
|--------|------|
| 顯示卡 | WinFast GeForce RTX 50/40/30 消費級系列 |
| 專業繪圖卡 | NVIDIA RTX PRO Blackwell、Quadro 後繼 |
| **AI 管理平台** | AIDMS（No-Code AI 視覺開發）、GDMS（GPU Docker 資源管理） |
| 虛擬桌面 | PCoIP Zero Client、Thin Client |
| 生醫（新） | 心血管監測、肺功能檢測、健康貼片（2023 年起） |

### 近年轉型方向

從硬體代理商轉型為**軟硬體垂直整合**，AIDMS + GDMS 為核心戰略，同步布局生醫技術。

### 公司評估

| 面向 | 評價 |
|------|------|
| 穩定性 | 高（上市 25 年，1986 老牌） |
| 技術前沿性 | 中（NVIDIA AI 接觸，但非純軟體公司） |
| 工時 | 優（週 40 小時，幾乎不加班） |
| 薪資競爭力 | 中偏低（前端職缺 70～100 萬，平均 ~45k） |
| 成長空間 | 中（AI 轉型期，有機會但軟體文化成熟度待觀察） |

---

## 二、AIDMS 產品深度

### 產品定位

**AIDMS（AI Development Management System）**：No-Code MLOps Web 平台
- 核心主張：「三日訓練驗證，七日快速落地」
- 目標：讓無程式碼背景的領域專家完成 AI 全生命週期管理

### 三種使用者角色

| 角色 | 核心問題 | 看什麼 |
|------|---------|--------|
| 品管工程師 | 「我的 AOI 訓練跑完了沒？機器還活著嗎？」 | StatusBar 綠燈 + Compute Gauge |
| AI 工程師 | 「GPU/CPU 用滿了嗎？要不要調 batch size？」 | MetricCards + TrendCharts 全看 |
| IT / 部署人員 | 「磁碟快滿了嗎？網路有沒有問題？」 | Storage DetailPanel + Network Chart |

### Domain 語義（重要）

- **GPU 100% = 好事**（AI 訓練正常執行）
- **GPU 長時間 0% = critical**（訓練任務崩潰或 GPU 未被正確分配）
- 這與通用監控邏輯**完全相反**，是面試中展示產品理解的切入點

### No-Code 五步驟流程

```
上傳資料 → 自動標注 → 選擇任務/模型 → 自動訓練 → 一鍵部署
```

### 支援 AI 任務

異常偵測、影像分類、物件偵測（YOLOv4～v11）、語意分割（U-Net）、OCR、**LLM RAG**（最新）

### 競品比較

| | AIDMS | NVIDIA TAO | Roboflow | Landing AI |
|---|---|---|---|---|
| No-Code 程度 | **全流程** | 需程式碼 | 部分 | 部分 |
| LLM 整合 | **有** | 無 | 無 | 無 |
| 在地支援 | **台灣本土** | 美商 | 美商 | 美商 |

### 實際案例（可在面試中提及）

| 案例 | 成果 |
|------|------|
| 水產養殖魚苗計數（LumiGood） | 3人×3天 → **2小時**，準確率 >97% |
| 台師大深度學習課程 | Mask R-CNN 架設 4～5小時 → **5分鐘** |
| 製造業 AOI 瑕疵檢測 | 跨設備統一模型，降低機差 |

### 業務現況

- 國內已出貨約十幾套，已進入日本市場
- 目標：2025 年軟體業務倍增，貢獻總營收 20%

---

## 三、薪資與面試流程

### 工程師薪資

| 職位 | 薪資 | 來源 |
|------|------|------|
| 前端工程師（AI 產品，現役） | 年薪 **70～100 萬** | CakeResume |
| 軟體工程師（資深，5 年以上） | 月薪 **9.5 萬** | GoodJob 2025/07 |
| 軟體工程師（資淺） | 年薪 **50～65 萬** | GoodJob |

工時：幾乎不加班，平均週工時 ~40 小時

### 面試流程

1. **人資電話篩選**：薪資期望、工作地點確認
2. **技術主管面試**：作品集審查 + 技術問答（重點在此）
3. **部門主管面談**：文化契合度

| 項目 | 數據 |
|------|------|
| 面試評分 | 3.8 / 5（面試趣，92 筆心得） |
| 面試難度 | 低 |
| 錄取率 | 42% |

不需刷 LeetCode，重視實務作品集勝於演算法。

---

## 四、我的優勢

### 專案直接對應產品需求

| aidms-dashboard 設計 | 對應麗臺需求 |
|---------------------|------------|
| SSE 即時監控（2 秒推送） | GDMS GPU 資源管理面板 |
| `@aidms/chart-components` 自製套件 | 元件庫設計能力 |
| Dark mode + MUI | AIDMS 目標用戶習慣（Grafana/IDE 風格） |
| Domain-aware 告警三態 | AI 訓練監控的語義正確性 |
| 三層漸進式 API 設計 | Staff Engineer 級別的 API 思維 |

技術棧：React + TypeScript + MUI，與產品方向高度吻合。

---

## 五、面試 Q&A 準備

### 介紹專案

**不要說**：「我做了一個 Dashboard 練習專案。」

**要說**：
> 「我在面試前研究了 AIDMS 和 GDMS 的產品形態，發現核心挑戰在於 domain-aware 的告警邏輯——通用監控和 AI 訓練監控的指標語義完全不同。GPU 100% 在通用監控是告警，在 AIDMS 是正常。所以我針對這個場景設計了一套監控 Dashboard，並把圖表元件抽成獨立套件，設計了三層漸進式 API。」

### 預測題目

| 題目 | 答法要點 |
|------|---------|
| 介紹最有挑戰性的專案 | aidms-dashboard：domain-aware 告警、SSE 架構選型、元件庫三層 API |
| 如何設計即時監控 UI？ | SSE 單向推送 + 前端 sliding window（150 點 deque），說明為何不用 WebSocket |
| 如何設計可重用圖表元件？ | Consumer-first + 三層漸進式 API（Level 1 零配置 → Level 2 進階 → Level 3 escape hatch） |
| React 效能優化做過什麼？ | chart re-render 頻率控制、window 點數限制 |
| 你對我們公司了解多少？ | AIDMS 定位、No-Code 五步驟、LLM RAG 新功能、三種使用者角色 |
| 為何想在硬體公司的軟體部門發展？ | 垂直整合的軟硬體場景、NVIDIA 生態接觸、AI 工具產品的實際落地 |

### 需補強的弱點：GPU 監控

MVP 刻意排除 GPU 監控（`psutil` 不支援），面試官可能追問：

> 「如果要加 GPU 監控怎麼做？」

**答案**：
- 後端改用 `py3nvml` 或 `pynvml` 讀取 NVIDIA GPU 指標
- 架構上 `SystemMetrics` 已有 `hostname` 欄位，可水平擴充成多節點叢集監控
- 前端 GPU 區塊設計為 optional（graceful fallback：有 GPU 就顯示，沒有也不報錯）

---

## 參考連結

- [面試趣 麗臺科技](https://interview.tw/c/MDvk) — 92 筆面試心得
- [GoodJob 麗臺科技](https://www.goodjob.life/companies/%E9%BA%97%E8%87%BA%E7%A7%91%E6%8A%80%E8%82%A1%E4%BB%BD%E6%9C%89%E9%99%90%E5%85%AC%E5%8F%B8)
- [比薪水 麗臺科技](https://salary.tw/c/MDvk)
- [AIDMS 官方中文頁](https://www.leadtek.com/cht/aidms/)
- [AIDMS LLM RAG 模組](https://www.leadtek.com/eng/aidms/llm_rag)
- [iThome 台北自動化展報導](https://www.ithome.com.tw/pr/164515)
