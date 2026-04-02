# WinCMP 項目結構與技術棧

> **版本**: v1.0  
> **最後更新**: 2026-03-30  
> **維護者**: WinCMP 開發團隊

---

## 目錄

1. [項目概述](#1-項目概述)
2. [技術棧](#2-技術棧)
3. [項目結構](#3-項目結構)
4. [核心模組說明](#4-核心模組說明)
5. [依賴關係圖](#5-依賴關係圖)

---

## 1. 項目概述

**WinCMP** (**Win**dows + **C**addy + **M**ariaDB + **P**HP) 是一個專為 Windows 11 設計的**可攜式 (Portable)**、**免管理員權限**的本機開發環境控制面板。

### 1.1 設計原則

| 原則 | 說明 |
|------|------|
| **可攜性** | 免安裝、不修改系統環境變數、不寫入登錄檔 |
| **零管理員權限** | 所有服務以普通使用者身份啟動，僅 Hosts 檔更新需要提升權限 |
| **隔離性** | 子進程的 `PATH` 環境變數透過動態注入，確保不同版本的 PHP 及其 DLL 互不干擾 |
| **簡單至上** | 追求最少改動量，避免過度工程 |

---

## 2. 技術棧

### 2.1 編譯環境

| 組件 | 版本 | 用途 |
|------|------|------|
| **Go** | 1.25.7+ | 主程式語言 |
| **Fyne** | v2.7.3 | 跨平台 GUI 框架 (基於 Cgo + OpenGL) |
| **WinLibs (MinGW-w64)** | Latest | C 編譯器 (Fyne 所需的 Cgo 依賴) |

### 2.2 核心第三方套件

| 套件 | 版本 | 用途 |
|------|------|------|
| `fyne.io/fyne/v2` | v2.7.3 | GUI 框架 (含 System Tray 支援) |
| `fyne.io/systray` | v1.12.0 | Windows 系統匣整合 |
| `github.com/ncruces/zenity` | v0.10.14 | 原生檔案選擇器對話框 |
| `github.com/dweymouth/fyne-tooltip` | v0.4.0 | 為 Fyne Widget 添加 Tooltip 支援 |
| `gopkg.in/natefinch/lumberjack.v2` | v2.2.1 | 日誌滾動與保留期限管理 |
| `github.com/go-sql-driver/mysql` | v1.9.3 | MariaDB 資料庫驅動 |
| `golang.org/x/sys` | v0.42.0 | 系統層級操作 (進程管理、環境變數) |

### 2.3 管理的外部服務

| 服務 | 類型 | 通訊協議 |
|------|------|----------|
| **Caddy** | HTTP/3、HTTP/2、HTTP/1.1 反向代理 | 管理 API: `localhost:2019` |
| **MariaDB** | 關聯式資料庫 | TCP: `localhost:3306` |
| **PHP-CGI** | FastCGI 處理引擎 | FastCGI over TCP: `127.0.0.1:3xxxx` |

---

## 3. 項目結構

```
wincmp/
├── wincmp.exe               # Go 編譯產物：主程式 (含 GUI + 進程管理)
├── main.go                  # 應用程式進入點：GUI 建構、事件綁定、配置生成
│
├── internal/                 # 核心業務邏輯 (不對外暴露)
│   ├── config/               # JSON 設定檔的讀寫與資料結構定義
│   │   └── config.go         #   WincmpConfig, GlobalConfig, ProjectConfig
│   ├── scanner/              # bin/ 目錄掃描器：偵測已安裝服務版本與 Port 計算
│   │   └── scanner.go        #   ScanBinDir(), PHPVersionInfo, ServiceInfo
│   ├── process/              # 子進程生命週期管理器
│   │   ├── manager.go        #   Manager 核心：register/unregister/StopAll
│   │   ├── caddy.go          #   StartCaddy / StopCaddy / ReloadCaddy
│   │   ├── mariadb.go        #   StartMariaDB / StopMariaDB
│   │   ├── php.go            #   StartPHPCGI / StopPHPCGI (多進程)
│   │   ├── job.go            #   進程 Job 定義
│   │   └── node.go          #   節點結構
│   ├── detect/               # 專案類型偵測器
│   │   ├── laravel.go        #   DetectLaravel(): 信心分數制判定
│   │   └── node.go          #   偵測節點結構
│   ├── hosts/                # Windows Hosts 檔管理
│   │   └── hosts.go         #   CheckHosts / UpdateHosts / BackupHosts
│   ├── port/                 # Port 計算工具
│   │   └── port.go          #   PHP Port 分配邏輯
│   └── singleinstance/        # 單實例鎖 (防止重複啟動)
│       └── singleinstance.go
│
├── conf/                     # 配置文件中心
│   ├── wincmp.json          # ★ 核心設定檔 (全域 + 專案列表)
│   ├── Caddyfile            # Caddy 進入點 (import snippets & sites)
│   ├── my.ini               # MariaDB 啟動配置
│   ├── snippets/            # Caddy 共用配置片段
│   │   ├── common.caddy     #   共用 headers、日誌、IP 白名單
│   │   └── php-upstream.caddy # ★ 自動生成的 PHP 負載均衡定義
│   ├── sites/               # ★ 自動生成的專案站點配置
│   │   └── *.caddy
│   └── ssl/                 # SSL 憑證 (*.crt, *.key)
│
├── bin/                     # 服務二進制檔 (使用者自備或下載器取得)
│   ├── caddy/               # caddy-x.y.z/caddy.exe
│   ├── mariadb/             # mariadb-x.y.z/bin/mariadbd.exe
│   └── php/                 # php-x.y.z/php-cgi.exe
│
├── data/                    # 持久化資料
│   ├── mariadb/             # MariaDB Data 目錄
│   └── backup/hosts/        # Hosts 備份檔
│
├── logs/                    # 日誌輸出 (依日期分檔)
│   ├── wincmp-YYYY-MM-DD.log  # 應用程式日誌
│   ├── error-YYYY-MM-DD.log   # 獨立錯誤日誌
│   ├── caddy.log              # Caddy 自身日誌
│   └── access.log             # HTTP 存取日誌
│
├── www/                     # 預設網頁專案根目錄
├── bat/                     # 備份用啟動腳本 (調試參考)
│
├── ui_node.go              # UI 節點定義
├── bundled_icon.go          # 應用圖示資源
│
└── go.mod / go.sum         # Go 模組依賴管理
```

### 3.1 目錄職責對照表

| 目錄/檔案 | 職責 |
|-----------|------|
| `main.go` | 應用程式進入點，負責 GUI 建構、事件處理、Caddyfile 生成 |
| `internal/config` | 管理 `wincmp.json` 的序列化/反序列化 |
| `internal/scanner` | 掃描 `bin/` 目錄，自動偵測所有已安裝的服務版本 |
| `internal/process` | 管理所有子進程 (Caddy/MariaDB/PHP-CGI) 的完整生命週期 |
| `internal/detect` | 透過信心分數制判定專案是否為 Laravel |
| `internal/hosts` | Windows Hosts 檔的讀寫、備份管理 |
| `internal/port` | PHP Port 計算邏輯 (3<主版本><次版本><序號>) |
| `internal/singleinstance` | 單實例鎖，防止程式重複啟動 |
| `conf/` | 所有運行時配置檔案 |
| `bin/` | Caddy、MariaDB、PHP 等二進制執行檔 |
| `data/` | MariaDB 資料庫檔案、Hosts 備份 |
| `logs/` | 應用程式日誌、服務日誌 |

---

## 4. 核心模組說明

### 4.1 `internal/scanner` — 版本掃描器

**職責**：啟動時掃描 `bin/` 目錄，自動偵測所有已安裝的服務版本。

**關鍵資料結構**：

```go
// ServiceInfo — Caddy / MariaDB 共用
type ServiceInfo struct {
    Name    string // "caddy" | "mariadb"
    Version string // "2.11.1" | "11.4.10"
    ExePath string // 完整執行檔路徑
}

// PHPVersionInfo — PHP 專用 (含 Port 配置)
type PHPVersionInfo struct {
    Version   string // "8.2.30"
    ExePath   string // php-cgi.exe 的完整路徑
    MajorMin  string // "8.2" (用於 Port 計算與設定 key)
    PortBase  int    // Port 基數 (如 38200)
    PortCount int    // 進程數量 (預設 3)
}
```

### 4.2 `internal/process` — 進程管理器

**職責**：管理所有子進程的完整生命週期 (啟動 → 監控 → 停止)。

**核心設計**：

```go
type Manager struct {
    mu       sync.Mutex
    services map[string]*ServiceState // key: "caddy" | "mariadb-11.4" | "php-8.2.30"
    baseDir  string
    logFn    LogFunc
    errLogFn ErrorLogFunc
}

type ServiceState struct {
    Name      string
    Running   bool
    ExePath   string
    Commands  []*exec.Cmd  // PHP 可能有多個子進程
    PIDs      []int
    StartTime time.Time
    Ctx       context.Context
    Cancel    context.CancelFunc
}
```

### 4.3 `internal/config` — 配置管理

**職責**：管理 `conf/wincmp.json` 的序列化/反序列化，並提供路徑推導輔助函式。

**路徑推導邏輯**：

- `GetProjectRoot()`: 若有自訂 RootPath 則使用，否則拼接 `DefaultWWW + ProjectName`。若 Type 為 `laravel`，自動附加 `/public`。
- `GetSSLCertPath()` / `GetSSLKeyPath()`: 若有自訂路徑則使用，否則以 `DefaultSSL + 第一個 Domain + .crt/.key` 推導。

### 4.4 `internal/detect` — 專案類型偵測

**職責**：透過**信心分數制**判定專案是否為 Laravel。

**計分規則** (總分 ≥ 50 判定為 Laravel)：

| 檢查項目 | 分數 |
|----------|------|
| `composer.json` 含 `laravel/framework` | +35 |
| `artisan` 檔案存在 | +30 |
| `bootstrap/app.php` | +25 |
| `public/index.php` | +20 |
| `routes/web.php` | +10 |
| `config/app.php` | +10 |
| `app/Http` | +8 |
| `resources/views` | +6 |
| `database/migrations` | +6 |
| `storage` | +5 |

### 4.5 `internal/port` — Port 計算

**PHP Port 命名規則**：採用 **`3<主版本><次版本><序號00~99>`** 的規則分配 Port。

| PHP 版本 | 進程數 | Port 範圍 | 計算公式 |
|----------|--------|-----------|----------|
| 7.3 | 3 (預設) | 37300, 37301, 37302 | `37000 + 7*100 + 3*10 + [00..02]` |
| 8.2 | 8 (設定) | 38200~38207 | `38000 + 8*100 + 2*10 + [00..07]` |

---

## 5. 依賴關係圖

```
┌──────────────────────────────────────────────────────┐
│                     main.go                          │
│  (GUI 建構 · 事件處理 · Caddyfile 生成 · Hosts 觸發) │
└──────────┬──────────┬──────────┬──────────┬──────────┘
           │          │          │          │
     ┌─────▼─────┐   │   ┌──────▼──────┐   │
     │  config   │   │   │   scanner   │   │
     │ (設定讀寫)│   │   │ (版本偵測)  │   │
     └───────────┘   │   └──────────────┘   │
              ┌──────▼──────┐       ┌──────▼──────┐
              │   process   │       │   detect    │
              │ (進程管理)  │       │ (專案偵測)  │
              └──────┬──────┘       └─────────────┘
                     │
        ┌────────────┼────────────┐
        │            │            │
   ┌────▼────┐ ┌─────▼────┐ ┌────▼────┐
   │  caddy  │ │  mariadb │ │   php   │
   └─────────┘ └──────────┘ └────────┘
                     │
              ┌──────▼──────┐
              │    hosts    │
              │ (Hosts 管理)│
              └─────────────┘
```

---

## 6. GUI 結構 (Fyne v2.7)

```
┌─────────────────────────────────────────────┐
│ WinCMP Control Panel                        │
├──────────┬──────────────────────────────────┤
│ 側邊選單  │                                  │
│ ──────── │   上方功能區 (65%)                │
│ Dashboard│   ┌───────────────────────────┐  │
│ Projects │   │ Dashboard / Projects /    │  │
│ DB Explor│   │ DB Explorer / Node.js     │  │
│ Node.js  │   │ Settings                  │  │
│ Settings │   └───────────────────────────┘  │
│─────────────────────────────────────────────┤
│ Terminal Logs  下方 Log 區 (35%)             │
│  ┌────────────────────────────────────────┐ │
│  │ [System][Caddy][MariaDB][PHP][Node]    │ │
│  │                                        │ │
│  └────────────────────────────────────────  │
└─────────────────────────────────────────────┘
```

---

> **附註**：本文件將隨專案迭代持續更新。如有架構變更，請先更新此文件再進行實作。
