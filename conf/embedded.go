package conf

import _ "embed"

// DependenciesJSON 儲存嵌入的 dependencies.json 原始位元組資料
//go:embed dependencies.json
var DependenciesJSON []byte
