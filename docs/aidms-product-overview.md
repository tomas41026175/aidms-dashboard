# AIDMS 產品深度研究

> AI Development Management System — 麗臺科技自研 No-Code MLOps 平台
> 整理日期：2026-03-12

---

## 產品定位

| 項目 | 內容 |
|------|------|
| 核心主張 | 「三日訓練驗證，七日快速落地」 |
| 目標 | 讓無程式碼背景的領域專家完成 AI 全生命週期管理 |
| 平台類型 | No-Code MLOps Web 平台 |

### 目標客群

- **業務/領域專家**：製造、品管、農業、醫療，無需工程師全程介入
- **AI 工程師**：加速開發、多模型統一管理
- **教育機構**：大學研究實驗室、產學合作
- **企業管理者**：快速啟動 AI 轉型

---

## 功能架構

### 支援 AI 任務類型

| 任務 | 應用場景 |
|------|---------|
| 異常偵測（Anomaly Detection） | AOI 瑕疵、品質異常辨識 |
| 影像分類（Classification） | 產品分類、缺陷分級 |
| 物件偵測（Object Detection） | 生產線計數、安全監控 |
| 語意分割（Semantic Segmentation） | 像素級場景理解 |
| 實例分割（Instance Segmentation） | 個體區分 |
| OCR | 工業文字、標籤讀取 |
| LLM RAG | 企業知識庫 AI 助理（最新功能） |

### 支援模型

**視覺分類**
VGG、ResNet、Inception V3、DenseNet、MobileNet V3、EfficientNet V2、ViT、Swin Transformer

**物件偵測**
DAMO-YOLO、YOLOv4/7/9/10/11、Faster RCNN

**分割**
U-Net、DeepLab V3+、BiSeNet V2、Mask R-CNN、CenterMask

**OCR**：TrOCR

**異常偵測**：FastFlow

**LLM**：Llama 3、DeepSeek R1

### No-Code 五步驟流程

```
1. 上傳資料     → 本地影像資料集
2. 自動標注     → 系統自動產生，支援人工修正
3. 選擇任務/模型 → GUI 介面選擇，無需程式碼
4. 自動訓練     → 多用戶同時訓練不衝突
5. 一鍵部署     → 雲端 API 或地端工具包
```

### 六大平台功能模組

1. 影像資料集管理
2. 系統資源管理（GPU/CPU/RAM 動態分配）
3. 模型開發（框架選擇、超參數設定）
4. 模型訓練與驗證
5. 模型部署（API 服務化）
6. 分析報告（訓練曲線、模型比較）

---

## 技術架構

### 後端

| 項目 | 技術 |
|------|------|
| 深度學習框架 | PyTorch、TensorFlow |
| 模型格式輸出 | ONNX（跨平台部署） |
| 版本控制 | 模型生命週期管理 |
| 開放程度 | 開放模型程式碼，可二次開發 |

### 部署方式

| 模式 | 介面 | 支援語言 | OS |
|------|------|---------|-----|
| 雲端 | REST API、Socket API | Python、C#、C++、Java | 不限 |
| 地端（On-Premise） | 模型工具包 | Python、C#、C++ | Windows、Linux |
| 邊緣裝置 | ONNX 格式輸出 | 多語言 | 嵌入式 |

**可部署目標**：AI 相機、GPU 工業電腦、智慧型手機、機器人、自動化設備

### 硬體支援（NVIDIA 生態系）

| 等級 | 配置 | 最大模型規模 |
|------|------|------------|
| 專業級 | RTX 5000 Ada × 1 | 32B 參數 |
| 企業級 | RTX 6000 Ada × 2 | 110B 參數 |
| 旗艦級 | RTX 6000 Ada × 6 | 400B 參數 |
| 最新旗艦 | RTX PRO 6000 Blackwell 雙卡（192GB VRAM） | 大型 VLM/LLM |

---

## 競品比較

| | AIDMS | NVIDIA TAO | Roboflow | Landing AI |
|---|---|---|---|---|
| 目標用戶 | 業務人員 + 工程師 | AI 工程師 | 開發者 | 製造業品管 |
| No-Code 程度 | **全流程** | 需程式碼 | 部分 | 部分 |
| LLM 整合 | **有** | 無 | 無 | 無 |
| 部署靈活性 | 雲 + 地 + 邊緣 | NVIDIA 生態 | 雲端為主 | 雲 + 地 |
| 在地支援 | **台灣本土、中文** | 美商 | 美商 | 美商 |
| 授權模式 | 軟體銷售 + 訂閱 | 免費 SDK | SaaS | 企業授權 |

**AIDMS 差異化**：
- 唯一同時整合視覺 AI + LLM RAG 的台灣本土平台
- 硬體（GPU 工作站）+ 軟體垂直整合銷售
- 開放模型程式碼，可客製化二次開發

---

## 實際案例

| 案例 | 客戶 | 成果 |
|------|------|------|
| 水產養殖魚苗計數 | LumiGood | 3人×3天 → **2小時**，準確率 >97% |
| AOI 瑕疵檢測 | 製造業 | 跨設備統一模型，降低機差 |
| 深度學習課程 | 臺灣師範大學 | Mask R-CNN 架設 4～5小時 → **5分鐘** |
| 智慧巴士管理 | 佳得合作 | 行前安全檢查、駕駛行為分析 |
| LLM RAG 企業助理 | GPU 規劃助理 | 整合即時庫存規格查詢 |
| 五面外觀檢測 | 製造業 | 機械手臂 + AIDMS 視覺整合 |

---

## 業務現況

| 項目 | 數據 |
|------|------|
| 已出貨 | 國內約十幾套（2024 法說會） |
| 市場 | 台灣 + 日本（已進入） |
| 目標 | 2025 年軟體業務倍增，貢獻總營收 20% |
| 試用 | 提供免費試用申請 |

---

## 展覽記錄

| 年份 | 展覽 | 重點 |
|------|------|------|
| 2024 | COMPUTEX 2024 | 魚苗辨識、Omniverse 整合 |
| 2024 | 台北國際自動化工業大展 | AIDMS 高效整合、數位孿生 |
| 2025 | COMPUTEX 2025（InnoVEX） | 五面外觀檢測、地端 AI Agent |
| 2025 | 台灣機器人與智慧自動化展 | AIDMS 最新功能 |

---

## 與前端開發的關聯

AIDMS / GDMS 皆為 **Web Dashboard** 產品，前端工程師負責：

- 模型訓練進度即時監控 UI（WebSocket / Polling）
- GPU 資源使用率圖表（資料視覺化）
- 多用戶協作介面
- 模型比較報告介面
- No-Code 拖拽操作流程設計

**技術需求推測**：React 或 Vue + 資料視覺化（ECharts/D3）+ WebSocket + REST API 整合

---

## 參考連結

- [AIDMS 官方中文頁](https://www.leadtek.com/cht/aidms/)
- [AIDMS 官方英文頁](https://www.leadtek.com/eng/aidms/)
- [AIDMS LLM RAG 模組](https://www.leadtek.com/eng/aidms/llm_rag)
- [AIDMS 教育版](https://www.leadtek.com/cht/aidms_education)
- [iThome 台北自動化展報導](https://www.ithome.com.tw/pr/164515)
