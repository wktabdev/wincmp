# UI 效能優化記錄

## 優化背景

用戶反映在切換 Projects、Settings 等 Tab 時有明顯延遲（約 0.5 秒），本文件記錄針對此問題的效能優化改動。

**問題診斷結論**：主要是專案代碼問題（同步 I/O 在主線程執行），而非 Fyne 框架本身的渲染效能。

---

## 優化項目

### 1. Projects List 效能優化

**問題**：`widget.NewList` 的 `UpdateItem` 回調中，每次渲染都執行 `os.Stat()` 檢查 Caddy 設定檔是否存在。當專案數量多時，造成大量同步系統調用。

**解決方案**：在 `ProjectConfig` 結構體中添加 `ConfigExists` 快取欄位，於啟動時和專案變更時一次性計算，而非每次渲染都 stat。

| 檔案 | 修改內容 |
|------|----------|
| `internal/config/config.go` | 新增 `ConfigExists bool` 欄位（json 忽略）+ `RefreshConfigExists(baseDir)` 預計算函式 |
| `main.go:587` | 設定檔載入後呼叫 `appCfg.RefreshConfigExists(baseDir)` |
| `main.go:2140-2145` | List `UpdateItem` 直接讀取 `proj.ConfigExists`，移除 `os.Stat()` 呼叫 |
| `main.go:2197` | 更新專案後重新整理快取 |
| `main.go:2209` | 刪除專案後重新整理快取 |
| `main.go:2266` | 新增專案後重新整理快取 |

**效果**：假設 10 個專案，渲染時從 10 次 `os.Stat()` 減少為 0 次（啟動時執行一次）。

---

### 2. DB Explorer 異步查詢 + Loading 狀態

**問題**：`queryDatabases()` 和 `queryTables()` 在主線程同步執行 SQL 查詢，網絡 I/O 造成 UI 阻塞。

**解決方案**：將資料庫查詢移至 goroutine 執行，完成後透過 `fyne.Do()` 回傳主線程更新 UI。同時顯示 `ProgressBarInfinite` 給用戶視覺反饋。

| 檔案 | 修改內容 |
|------|----------|
| `main.go:2516` | 新增 `loadingIndicator *widget.ProgressBarInfinite` 和 `dbTabLock sync.Mutex` |
| `main.go:2519-2563` | `refreshUI` 重構為異步模式：先顯示 loading → goroutine 查詢 → `fyne.Do()` 更新結果 |
| `main.go:2532-2539` | 查詢前透過 `fyne.Do()` 顯示 loading 指示器 |
| `main.go:2543-2561` | 查詢完成後通過 `fyne.Do()` 更新 UI，並設置 `isMainTabLoading = false` |
| `main.go:2596-2615` | `schemaList.OnSelected` 查詢 tables 也改為 goroutine 異步執行 |
| `main.go:2621-2625` | Refresh 按鈕使用 `dbTabLock` 防止並發呼叫 |

**效果**：Tab 切換時顯示 loading 動畫，UI 保持響應。

---

### 3. Tab 切換互斥鎖（防止快速切換）

**問題**：用戶快速點擊不同 Tab 時，前一個載入尚未完成又被中斷，導致 race condition 或重複查詢。

**解決方案**：使用 `sync.Mutex` + `atomic.Bool` 實作全局鎖，確保前一個 Tab 載入完成後才能切換到下一個。

| 檔案 | 修改內容 |
|------|----------|
| `main.go:75-76` | 新增全域變數 `mainTabLock sync.Mutex` 和 `isMainTabLoading atomic.Bool` |
| `main.go:698-703` | `mainTabs.OnSelected` 回調檢查 `isMainTabLoading.Load()`，若為 true 則忽略此次切換 |
| `main.go:2663-2671` | `safeRefresh` 進入時 `isMainTabLoading.Store(true)`，完成後設為 `false` |

**效果**：快速連續點擊 Tab 時，必須等當前 Tab 載入完成才會響應下一個點擊。

---

### 4. 移除不必要的人為延遲

**問題**：DB Explorer Tab 初始化時有 `time.Sleep(300ms)` 人為延遲。

**解決方案**：移除該 sleep，因為 `refreshUI` 本身就是異步執行。

| 檔案 | 修改內容 |
|------|----------|
| `main.go:2632-2636`（舊） | 原本的 `go func() { time.Sleep(300 * time.Millisecond); refreshUI() }()` |
| `main.go:2669-2672`（新） | 改為 `go func() { safeRefresh() }()`，無需 sleep |

---

### 5. Node.js Tab 異步優化

**問題**：`createNodeTab()` 在初始化時同步執行 `scanner.ScanBinDir()`，阻塞 UI。

**解決方案**：將掃描改為 goroutine 異步執行，`refreshFunc` 同樣異步化。

| 檔案 | 修改內容 |
|------|----------|
| `ui_node.go:95-102` | 初始化時的 `ScanBinDir` 改為 `go func()` 異步執行 |
| `ui_node.go:375-386` | `refreshFunc` 加入 `isMainTabLoading` 檢查和異步執行 |

---

## 關鍵技術細節

### Fyne 跨線程 UI 更新
```go
// 正確模式
go func() {
    result := heavyWork()           // 在 goroutine 執行
    fyne.Do(func() {               // 回到主線程
        updateUI(result)
    })
}()

// 錯誤模式（會 panic 或未定義行為）
go func() {
    someWidget.SetText("new")       // 不要直接更新 UI
}()
```

### sync.Mutex 防並發
```go
var lock sync.Mutex

safeFunc := func() {
    lock.Lock()
    defer lock.Unlock()
    // 臨界區操作
}
```

### atomic.Bool 狀態標誌
```go
var isLoading atomic.Bool

func onTabSelected() {
    if isLoading.Load() {
        return  // 忽略快速切換
    }
    isLoading.Store(true)
    defer isLoading.Store(false)
    // 執行操作
}
```

---

## 修改檔案清單

| 檔案 | 改動類型 |
|------|----------|
| `internal/config/config.go` | 修改 |
| `main.go` | 修改 |
| `ui_node.go` | 修改 |

---

## 驗證方式

1. 啟動應用程式，切換各 Tab 觀察是否有 Loading 指示器
2. 快速連續點擊不同 Tab，確認行為符合預期（必須等上一個載入完成）
3. 在 Projects Tab 新增/刪除專案，確認 ConfigExists 快取正確更新
4. 測量 Tab 切換延遲時間，確認從 ~500ms 降至流暢級別
