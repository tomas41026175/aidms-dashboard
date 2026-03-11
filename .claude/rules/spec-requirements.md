# Spec 文件撰寫規範

本專案所有 spec 文件必須滿足以下 5 個要求。
這是對 `spec-work` 預設模板的擴充，不是取代。

---

## 技術標籤（Tags）

每份 spec header 必須包含 `Tags` 欄位，列出此 Task 直接涉及的技術 / 套件 / 概念：

```markdown
**Tags**: `React` `TypeScript` `@mui/x-charts` `SSE` `FastAPI` `Vitest`
```

規則：
- 只列**此 Task 實際用到**的技術，不列整個專案的 stack
- 格式：反引號包住每個 tag，空格分隔
- 目的：快速掃描 spec 時判斷涉及範圍，面試中定位技術對話切入點

---

## 必要區塊

### 1. 亮點與 WHY（Highlights）

每份 spec 必須在 Decision Lock 前加入此區塊：

```markdown
## Highlights

**這個 Task 的亮點**：
- {亮點 1}：{一句話說明為什麼這是亮點}
- {亮點 2}：...

**關鍵設計決策 WHY**：
- WHY {決策}：{理由，連結到 domain 或技術限制}
- WHY {決策}：...
```

目的：面試討論時能快速提取核心論點。

---

### 2. Domain + 實作掌握度（Mastery）

```markdown
## Domain & Code 掌握

**Domain 知識點**（此 Task 涉及）：
- {知識點}：{說明}

**實作關鍵細節**：
- {細節}：{說明，含具體程式碼位置}
```

目的：開發者（你）執行前確認理解完整，不是只看設計文件。

---

### 3. MVP 範圍標記

Task Plan 中每個 task 必須標記：

- `[MVP]` — 本次實作，面試交付
- `[EXTENSIBLE]` — MVP 實作，但架構已預留擴充點，說明擴充方式
- `[MVP-CUT]` — 本次不實作，但說明未來最小改動

```markdown
**Task N: {名稱}** [MVP] / [EXTENSIBLE] / [MVP-CUT]

若為 [EXTENSIBLE]：
  > 擴充點：{說明未來如何擴充，最小改動是什麼}

若為 [MVP-CUT]：
  > 未來實作：{說明何時做、最小改動是什麼}
  > 目前保留：{說明架構上已留了什麼位置}
```

---

### 4. 完整執行流程（Execution Flow）

Task Plan 的每個 task 必須細化到「可直接執行」的顆粒度：

```markdown
**Task N: {名稱}** [標記]
- Files:
  - 新增：`{路徑}` — {一句話說明這個檔案做什麼}
  - 修改：`{路徑}` — {說明改哪裡}
- Steps:
  1. {具體步驟，含函式名稱 / 型別名稱}
  2. {具體步驟}
- Verify: `{可執行的命令}`
- Done: {明確的完成標準，不模糊}
- Blocked by: Task {N}（若有依賴）
```

---

### 5. 技術變更記錄（Technical Changes）

每次因技術問題修改實作方式，在 spec.md 底部追加：

```markdown
## Technical Change Log

### [YYYY-MM-DD] {變更標題}

**原計畫**：{原本要怎麼做}
**問題**：{遇到什麼技術問題}
**變更後**：{改成怎麼做}
**影響範圍**：{哪些 task / 檔案受影響}
```

此區塊在 spec 建立時為空，執行期間視需要填入。

---

## 標準 spec.md 結構（本專案）

```markdown
# Spec: {Task 標題}

**Task**: {描述}
**Started**: {ISO timestamp}
**Phase**: planning
**Mode**: simple
**Tags**: `{技術1}` `{技術2}` `{技術3}`

---

## Highlights
...

## Domain & Code 掌握
...

## Decision Lock
...

## Acceptance Criteria
- [ ] {AC} — verify: {命令}

---

## Task Plan

**Task 1: {名稱}** [MVP]
- Files: ...
- Steps: ...
- Verify: ...
- Done: ...

**Task 2: {名稱}** [EXTENSIBLE]
> 擴充點：...
- Files: ...

**Task 3: {名稱}** [MVP-CUT]
> 未來實作：...
> 目前保留：...

---

## Deviation Rules
- 自動修復：bug、型別錯誤、lint、缺少 import
- 停止回報：改變 API contract、影響 5+ 個計畫外的檔案

---

## Technical Change Log
（執行期間填入）
```
