# OrcaSlicer 切片服务

3D 打印报价用：把模型切片成 G-code，返回耗材重量、打印时间、层数和打印参数，并可下载 G-code 用于生产。

镜像 = Ubuntu 24.04 + [OrcaSlicer](https://github.com/OrcaSlicer/OrcaSlicer) Linux 版命令行（AppImage 解包，当前 2.5.1）+ 同版本源码中的预设 JSON + HTTP 包装 `server.py`（只用 Python 标准库）。

- OrcaSlicer 2.5 起安装包中的预设打包为 `.opc`（自定义压缩格式），构建时从同版本源码包（codeload.github.com）只解压 `resources/profiles` 下的 JSON 到 `/opt/orca-profiles`，供本服务展开继承、列出预设。
- 2.5 支持拓竹 P2S、X2D、H2D、H2C、H2S 等新机型（2.3.1 没有）。后端（yudao-blocks 的 print3d-slice 积木）通过 HTTP 调用本服务。

## 构建与启动

```bash
# 构建（首次约几分钟，镜像约 1.5GB）；Docker Hub 访问不了时在 .env 中设置 ORCA_SLICER_BASE_IMAGE、ORCA_SLICER_APT_MIRROR
docker compose -f compose/services/orca-slicer.yaml --env-file .env --profile orca-slicer build

# 启动（或用 compose\yudao.bat 菜单 44 / 54）
docker compose -f compose/services/orca-slicer.yaml --env-file .env --profile orca-slicer up -d

curl http://127.0.0.1:8590/health
```

升级 OrcaSlicer：改 `.env` 的 `ORCA_SLICER_VERSION`（需与 GitHub Release 的版本号一致），重新 build。

## 预设

切片需要三类预设：**机型**（machine）、**工艺**（process，层高、墙数、填充、支撑等）、**耗材**（filament）。

- **系统预设**：OrcaSlicer 自带的厂商预设（拓竹、Voron、Prusa、创想三维等，约 7000 个），按名称使用，如 `Bambu Lab A1 0.4 nozzle`、`0.20mm Standard @BBL A1`、`Bambu PLA Basic @BBL A1`。
- **自定义预设**：在 OrcaSlicer 中调好后，从用户预设目录复制 JSON（Windows：`%AppData%\OrcaSlicer\user\default\{machine,process,filament}\*.json`），放到 `config/orca-slicer/presets/{machine,process,filament}/`，按 JSON 中的 `name` 使用；修改后自动生效，不用重启。自定义预设必须继承某个系统预设（OrcaSlicer 中新建的预设都会继承）。

OrcaSlicer 命令行**不会展开预设的继承关系**（直接使用时平台尺寸、耗材密度等会变成默认值，重量为 0），本服务先按 `inherits` 逐级合并成完整配置，再交给命令行。

注意：用户预设中可能包含打印机地址（`print_host`）、API Key 等，提交到仓库前先删除这些字段。

## 接口

设置了 `ORCA_SLICER_TOKEN` 时，除 `/health` 外都要带请求头 `Authorization: Bearer <token>`。出错时返回 HTTP 4xx / 5xx 和 `{"error": "原因", "log": [命令行日志最后几行]}`。

| 接口 | 说明 |
|---|---|
| `GET /health` | 状态、OrcaSlicer 版本、系统预设数量 |
| `GET /presets?type=machine&keyword=A1` | 预设列表；`type` 为 `machine` / `process` / `filament`；工艺、耗材可加 `machine=<机型名称>` 只列出适用于该机型的 |
| `GET /presets/detail?type=process&name=...` | 预设展开继承后的完整配置 |
| `POST /presets/resolve` | 同上，JSON 请求体 `{"type": "machine", "preset": 名称或预设 JSON 对象}`，用于校验自定义预设、读取平台尺寸 |
| `POST /slice` | 切片，见下 |
| `GET /slice/{id}/gcode?plate=1` | 下载 G-code；切片结果保留 1 小时（`JOB_TTL`），调用方应及时转存到文件服务 |

### POST /slice

`multipart/form-data`：`file` 为模型文件（STL / OBJ / 3MF / STEP / AMF），`params` 为 JSON；也可以用 `application/json` 只传 `params`，模型由 `modelUrl` 下载。

```json
{
  "machine": "Bambu Lab A1 0.4 nozzle",
  "process": "0.20mm Standard @BBL A1",
  "filaments": ["Bambu PLA Basic @BBL A1"],
  "overrides": {
    "process": { "sparse_infill_density": "20%", "enable_support": "1", "layer_height": "0.16" },
    "filament": {},
    "machine": {}
  },
  "modelUrl": "https://...",
  "fileName": "a.stl",
  "fullConfig": false
}
```

- `machine`、`process`、`filaments` 可以是预设名称，也可以直接传预设 JSON 对象。
- 3MF 只使用其中的模型：Bambu Studio / OrcaSlicer 的项目文件中带的切片设置会被忽略（返回提示「已忽略 3MF 中的切片设置」），按传入的预设切片；新版软件保存的 3MF 也能切（`--allow-newer-file`）。
- 打印板：没有在覆盖参数中指定 `curr_bed_type` 时，按耗材支持的打印板自动选择（耗材预设中该打印板温度为 0 表示不支持），优先纹理 PEI 板、高温板、工程板、低温板。
- `process` 也可以写成 `auto:<层高>`（如 `auto:0.20`）：按机型自动选择适用的系统工艺预设中层高最接近的一个（同层高优先 Standard / Optimal / Fine），并把层高设为该值。多台不同机型共用一个切片方案时用这种写法，每台机器都用自己的速度、加速度等工艺参数。
- `overrides` 覆盖预设中的参数，键名和值的写法与 OrcaSlicer 预设 JSON 相同（如填充率 `"20%"`、开关 `"1"`）。
- 多色打印时 `filaments` 传多个，返回每种耗材的用量。
- 模型会自动摆放（arrange）；超出打印平台时报「模型超出打印平台」。

返回（30mm 立方体，拓竹 A1、0.20mm 标准、拓竹 PLA Basic）：

```json
{
  "id": "03b2f4e96cc245fbaeada56cb5dc3f53",
  "version": "2.3.1",
  "elapsedMs": 195,
  "stats": {
    "filamentWeight": 9.89,      // 耗材重量 g（含支撑、裙边、擦料塔）
    "filamentLength": 3264.52,   // 耗材长度 mm
    "filamentVolume": 7.85,      // 耗材体积 cm³
    "filamentCost": 0.25,        // 耗材费用（按耗材预设的 filament_cost 单价计算）
    "printTime": 1831,           // 预计打印时间（秒，含热床预热、校准等）
    "modelPrintTime": 1488,      // 模型本身的打印时间（秒，部分机型才有）
    "firstLayerTime": 343,       // 首层时间（秒）
    "layers": 150,
    "maxZ": 30.0,                // 模型高度 mm
    "plateCount": 1
  },
  "plates": [{ "plate": 1, "file": "plate_1.gcode", "size": 906036, "filaments": [{ "index": 1, "weight": 9.89, "length": 3264.52, "volume": 7.85, "cost": 0.25 }] }],
  "settings": {
    "printer_model": "Bambu Lab A1", "nozzle_diameter": "0.4", "printable_area": "0x0,256x0,256x256,0x256", "printable_height": "256",
    "layer_height": "0.2", "wall_loops": "2", "top_shell_layers": "5", "bottom_shell_layers": "3",
    "sparse_infill_density": "15%", "sparse_infill_pattern": "crosshatch", "enable_support": "0", "support_type": "normal(auto)",
    "filament_type": "PLA", "filament_density": "1.26", "filament_cost": "24.99", "nozzle_temperature": "220"
  },
  "warnings": []
}
```

`settings` 只返回主要参数，`fullConfig: true` 时另外返回完整切片配置 `config`；完整配置也写在 G-code 末尾的 `CONFIG_BLOCK` 中。

## 环境变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `SLICER_WORKERS` | 2 | 同时切片的数量，超出的请求排队；按 CPU 核数调整 |
| `SLICE_TIMEOUT` | 600 | 单次切片超时（秒） |
| `JOB_TTL` | 3600 | 切片结果（G-code）保留时间（秒） |
| `MAX_UPLOAD_MB` | 200 | 模型文件大小上限 |
| `SLICER_TOKEN` | 空 | 调用令牌；compose 中取 `.env` 的 `ORCA_SLICER_TOKEN` |
| `ORCA_XVFB` | auto | 是否用 `xvfb-run` 运行命令行（auto：没有 `DISPLAY` 时使用） |
