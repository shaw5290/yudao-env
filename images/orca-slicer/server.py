#!/usr/bin/env python3
"""
OrcaSlicer 切片服务：OrcaSlicer 命令行的 HTTP 包装，只用 Python 标准库。

接口（JSON，出错时返回 {"error": "...", "log": [...]}）：
  GET  /health                          状态与 OrcaSlicer 版本
  GET  /presets?type=&keyword=&machine= 可用预设列表（系统预设 + /presets 下的自定义预设；machine 用于筛选适用的工艺 / 耗材）
  GET  /presets/detail?type=&name=      预设展开继承后的完整配置
  POST /presets/resolve                 同上，preset 可以是名称或预设 JSON 对象：{"type": "machine", "preset": ...}
  POST /slice                           切片；multipart/form-data：file（模型文件）+ params（JSON）
  GET  /slice/{id}/gcode?plate=1        下载切片生成的 G-code（保留 JOB_TTL 秒）

params：
  {
    "machine": "Voron Trident 300 0.4 nozzle",        # 预设名称，或预设 JSON 对象（如 OrcaSlicer 导出的用户预设）
    "process": "0.20mm Standard @Voron",               # 或 auto:0.20：用该机型自己的、层高最接近的系统工艺预设
    "filaments": ["Generic PLA @System"],              # 多色时多个
    "overrides": {                                     # 覆盖参数（选填），值的写法与预设 JSON 相同
      "process": {"sparse_infill_density": "20%", "enable_support": "1"},
      "filament": {}, "machine": {}
    },
    "modelUrl": "https://...",                         # 不上传 file 时从地址下载模型（选填）
    "fileName": "a.stl",                               # modelUrl 时用于识别格式（选填）
    "fullConfig": false                                # 是否返回完整切片配置
  }

OrcaSlicer 命令行不会展开预设的 inherits，这里先按系统预设逐级合并成完整配置，再交给命令行。

环境变量：ORCA_HOME、ORCA_PROFILES_DIR（系统预设 JSON 目录）、PRESETS_DIR（/presets）、PORT（8080）、SLICER_WORKERS（2）、SLICE_TIMEOUT（600 秒）、
JOB_TTL（3600 秒）、MAX_UPLOAD_MB（200）、SLICER_TOKEN（选填，设置后请求头需带 Authorization: Bearer <token>）、
ORCA_XVFB（auto / 1 / 0：是否用 xvfb-run 运行命令行）
"""
import io
import json
import os
import re
import shutil
import subprocess
import tempfile
import threading
import time
import urllib.parse
import urllib.request
import uuid
import zipfile
from email import policy
from email.parser import BytesParser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ORCA_HOME = os.environ.get('ORCA_HOME', '/opt/orca-slicer')
ORCA_BIN = os.path.join(ORCA_HOME, 'AppRun')
# 系统预设 JSON 目录：OrcaSlicer 2.5 起安装包中为 .opc，镜像构建时从源码包解压 JSON 到 ORCA_PROFILES_DIR
PROFILES_DIR = os.environ.get('ORCA_PROFILES_DIR') or os.path.join(ORCA_HOME, 'resources', 'profiles')
PRESETS_DIR = os.environ.get('PRESETS_DIR', '/presets')
PORT = int(os.environ.get('PORT', '8080'))
WORKERS = int(os.environ.get('SLICER_WORKERS', '2'))
SLICE_TIMEOUT = int(os.environ.get('SLICE_TIMEOUT', '600'))
JOB_TTL = int(os.environ.get('JOB_TTL', '3600'))
MAX_UPLOAD = int(os.environ.get('MAX_UPLOAD_MB', '200')) * 1024 * 1024
TOKEN = os.environ.get('SLICER_TOKEN', '')
XVFB = os.environ.get('ORCA_XVFB', 'auto')
JOBS_DIR = os.path.join(tempfile.gettempdir(), 'orca-jobs')

TYPES = ('machine', 'process', 'filament')
MODEL_EXTS = ('.stl', '.obj', '.3mf', '.step', '.stp', '.amf')
# 返回给调用方的主要打印参数
SETTING_KEYS = (
    'printer_model', 'printer_settings_id', 'print_settings_id', 'filament_settings_id', 'nozzle_diameter',
    'printable_area', 'printable_height', 'curr_bed_type',
    'layer_height', 'initial_layer_print_height', 'wall_loops', 'top_shell_layers', 'bottom_shell_layers',
    'sparse_infill_density', 'sparse_infill_pattern', 'enable_support', 'support_type', 'brim_type',
    'seam_position', 'ironing_type', 'print_sequence',
    'filament_type', 'filament_colour', 'filament_density', 'filament_diameter', 'filament_cost',
    'nozzle_temperature', 'nozzle_temperature_initial_layer', 'hot_plate_temp', 'cool_plate_temp', 'textured_plate_temp',
)

slice_semaphore = threading.Semaphore(WORKERS)


def version_tuple(version):
    return tuple(int(x) for x in re.findall(r'\d+', version or '')[:3]) or (0,)


# OrcaSlicer 2.5 起命令行自己展开预设的 inherits
CLI_RESOLVES_INHERITS = version_tuple(os.environ.get('ORCA_VERSION')) >= (2, 5)


class SliceError(Exception):
    def __init__(self, message, status=400, log=None):
        super().__init__(message)
        self.status = status
        self.log = log or []


# ==================== 预设 ====================

class PresetLibrary:
    """系统预设（OrcaSlicer resources/profiles）+ 自定义预设（PRESETS_DIR/<type>/*.json），按 (类型, 名称) 索引"""

    def __init__(self):
        self.system = {}
        self.vendors = {}
        self.custom = {}
        self.lock = threading.Lock()
        self.custom_mtime = None
        self.resolved = {}  # 按名称展开继承的结果缓存，自定义预设变化时清空

    def load_system(self):
        for vendor in sorted(os.listdir(PROFILES_DIR)):
            vendor_dir = os.path.join(PROFILES_DIR, vendor)
            if not os.path.isdir(vendor_dir):
                continue
            for preset_type in TYPES:
                for path in iter_json(os.path.join(vendor_dir, preset_type)):
                    data = read_json(path)
                    if data and data.get('name'):
                        key = (preset_type, data['name'])
                        if key not in self.system:
                            self.system[key] = data
                            self.vendors[key] = vendor

    def reload_custom(self):
        """自定义预设目录有变化时重新读取（按目录下文件的最新修改时间判断）"""
        mtime = latest_mtime(PRESETS_DIR)
        with self.lock:
            if mtime == self.custom_mtime:
                return
            custom = {}
            for preset_type in TYPES:
                for path in iter_json(os.path.join(PRESETS_DIR, preset_type)):
                    data = read_json(path)
                    if not data:
                        continue
                    name = data.get('name') or os.path.splitext(os.path.basename(path))[0]
                    data['name'] = name
                    custom[(preset_type, name)] = data
            self.custom = custom
            self.custom_mtime = mtime
            self.resolved = {}

    def get(self, preset_type, name):
        return self.custom.get((preset_type, name)) or self.system.get((preset_type, name))

    def is_system_instance(self, preset_type, name):
        data = self.system.get((preset_type, name))
        return data is not None and str(data.get('instantiation', 'true')).lower() == 'true' \
            and (preset_type, name) not in self.custom

    def resolve(self, preset_type, spec):
        """展开继承，返回 (完整配置, 最近的系统预设名称)；返回副本，调用方可以修改"""
        self.reload_custom()
        if isinstance(spec, str):
            key = (preset_type, spec)
            if key not in self.resolved:
                self.resolved[key] = self.resolve_spec(preset_type, spec)
            merged, system_name = self.resolved[key]
            return dict(merged), system_name
        return self.resolve_spec(preset_type, spec)

    def resolve_spec(self, preset_type, spec):
        if isinstance(spec, str):
            data = self.get(preset_type, spec)
            if data is None:
                raise SliceError(f'{preset_type} 预设不存在：{spec}')
        elif isinstance(spec, dict):
            data = spec
        else:
            raise SliceError(f'缺少 {preset_type} 预设')
        chain, current, seen = [], data, set()
        system_name = None
        while current is not None:
            name = current.get('name')
            if name in seen:
                raise SliceError(f'{preset_type} 预设循环继承：{name}')
            seen.add(name)
            chain.append(current)
            if system_name is None and name and self.is_system_instance(preset_type, name):
                system_name = name
            parent = current.get('inherits')
            if not parent:
                break
            current = self.get(preset_type, parent)
            if current is None:
                raise SliceError(f'{preset_type} 预设【{name}】继承的【{parent}】不存在')
        merged = {}
        for item in reversed(chain):
            merged.update(item)
        merged['name'] = data.get('name') or f'custom-{preset_type}'
        return merged, system_name

    def list(self, preset_type, keyword='', machine=''):
        """预设列表；machine 不为空时只返回适用于该机型的工艺 / 耗材（compatible_printers 为空的视为通用）"""
        self.reload_custom()
        machine_system = None
        if machine and preset_type != 'machine':
            machine_system = self.resolve('machine', machine)[1] or machine
        result = []
        candidates = [(k, v, 'custom') for k, v in self.custom.items()] \
            + [(k, v, 'system') for k, v in self.system.items() if self.is_system_instance(*k)]
        for (t, name), data, source in candidates:
            if t != preset_type or keyword.lower() not in name.lower():
                continue
            if machine_system and not self.is_compatible(t, name, machine_system):
                continue
            result.append(self.summary(t, name, data, source))
        return result

    def is_compatible(self, preset_type, name, machine_system):
        try:
            key = (preset_type, name)
            if key not in self.resolved:
                self.resolved[key] = self.resolve_spec(preset_type, name)
            printers = self.resolved[key][0].get('compatible_printers') or []
        except SliceError:
            return False
        if printers:
            return machine_system in printers
        # 没有列出适用机型时：自定义预设、同一厂商或通用耗材库（OrcaFilamentLibrary）的预设视为适用
        vendor = self.vendors.get((preset_type, name))
        return (preset_type, name) in self.custom or vendor in (self.vendors.get(('machine', machine_system)), 'OrcaFilamentLibrary')

    def summary(self, preset_type, name, data, source):
        item = {'name': name, 'type': preset_type, 'source': source, 'inherits': data.get('inherits') or None}
        if source == 'system':
            item['vendor'] = self.vendors.get((preset_type, name))
        for key in ('printer_model', 'nozzle_diameter', 'layer_height', 'filament_type'):
            if data.get(key) is not None:
                item[key] = data[key]
        return item


def iter_json(directory):
    if not os.path.isdir(directory):
        return
    for root, _, files in os.walk(directory):
        for file in sorted(files):
            if file.endswith('.json'):
                yield os.path.join(root, file)


def read_json(path):
    try:
        with open(path, encoding='utf-8') as f:
            data = json.load(f)
        return data if isinstance(data, dict) else None
    except (OSError, ValueError):
        return None


def latest_mtime(directory):
    if not os.path.isdir(directory):
        return None
    latest = os.path.getmtime(directory)
    for root, dirs, files in os.walk(directory):
        for name in dirs + files:
            try:
                latest = max(latest, os.path.getmtime(os.path.join(root, name)))
            except OSError:
                pass
    return latest


library = PresetLibrary()


# ==================== 切片 ====================

def build_presets(params, warnings):
    """生成交给命令行的三类预设：展开继承、应用覆盖参数、设置兼容机型"""
    overrides = params.get('overrides') or {}
    machine, machine_system = library.resolve('machine', params.get('machine'))
    process_spec = params.get('process')
    auto_layer = parse_auto_process(process_spec)
    if auto_layer is not None:
        # auto:<层高>：用该机型自己的、层高最接近的系统工艺预设
        process_spec = pick_process(machine_system, auto_layer, warnings)
    process, process_system = library.resolve('process', process_spec)
    if auto_layer is not None and 'layer_height' not in (overrides.get('process') or {}):
        process['layer_height'] = format_number(auto_layer)
    filament_specs = params.get('filaments') or ([params['filament']] if params.get('filament') else [])
    if not filament_specs:
        raise SliceError('缺少 filament 预设')
    if not machine_system:
        raise SliceError('机型预设需要继承某个 OrcaSlicer 系统机型预设（inherits）')
    filaments = []
    for spec in filament_specs:
        filament, filament_system = library.resolve('filament', spec)
        filament.update(overrides.get('filament') or {})
        filaments.append((filament, filament_system))
    machine.update(overrides.get('machine') or {})
    process.update(overrides.get('process') or {})

    # 打印板：未指定时按耗材支持的打印板选择（耗材预设中该打印板温度为 0 表示不支持，否则报「耗材与打印板类型不兼容」）
    if 'curr_bed_type' not in (overrides.get('process') or {}):
        bed_type = pick_bed_type(process.get('curr_bed_type') or machine.get('curr_bed_type'), [f for f, _ in filaments])
        if bed_type:
            process['curr_bed_type'] = bed_type

    # 相对挤出需要每层重置挤出量，系统基础机型预设可能没有写，命令行校验会失败
    if str(first(machine.get('use_relative_e_distances', '1'))) == '1':
        gcodes = str(machine.get('layer_change_gcode', '')) + str(machine.get('before_layer_change_gcode', ''))
        if not re.search(r'G92\s+E0', gcodes):
            machine['layer_change_gcode'] = (str(machine.get('layer_change_gcode', '')) + '\nG92 E0').strip()
            warnings.append('机型预设使用相对挤出但换层 G-code 中没有 G92 E0，已自动补上')

    # 预设已展开为完整配置。2.5 起命令行会自己按 inherits 去程序数据目录加载系统预设（容器内没有），所以不再传 inherits，
    # 兼容机型写机型预设本身的名称；2.5 之前的版本按 inherits 判断兼容，需要传系统预设名称
    if CLI_RESOLVES_INHERITS:
        compatible = machine.get('name') or machine_system
        machine.update({'type': 'machine', 'from': 'User', 'inherits': ''})
        process_inherits, filament_inherits = '', {}
    else:
        compatible = machine_system
        machine.update({'type': 'machine', 'from': 'User', 'inherits': machine_system})
        process_inherits = process_system or ''
        filament_inherits = None
    process.update({'type': 'process', 'from': 'User', 'inherits': process_inherits,
                    'compatible_printers': [compatible], 'compatible_printers_condition': ''})
    result_filaments = []
    for filament, filament_system in filaments:
        filament.update({'type': 'filament', 'from': 'User',
                         'inherits': '' if filament_inherits is not None else (filament_system or ''),
                         'compatible_printers': [compatible], 'compatible_printers_condition': '',
                         'compatible_prints': [], 'compatible_prints_condition': ''})
        result_filaments.append(filament)
    return machine, process, result_filaments


AUTO_PROCESS_PREFIX = 'auto:'
# OrcaSlicer 的默认层高（预设的继承链中没有写 layer_height 时使用）
DEFAULT_LAYER_HEIGHT = 0.2
# 自动选择工艺预设时，同层高下名称的优先顺序
PROCESS_NAME_PREFERENCE = ('Standard', 'Optimal', 'Fine', 'Balanced Quality', 'High Quality', 'Quality')


def parse_auto_process(spec):
    """process 为「auto:<层高 mm>」时返回层高，如 auto:0.20 → 0.2；否则返回 None"""
    if not isinstance(spec, str) or not spec.startswith(AUTO_PROCESS_PREFIX):
        return None
    layer = to_float(spec[len(AUTO_PROCESS_PREFIX):])
    if layer is None or layer <= 0:
        raise SliceError(f'自动工艺预设的层高无效：{spec}（写法如 auto:0.20）')
    return layer


def pick_process(machine_system, layer, warnings):
    """适用于该机型的系统工艺预设中，层高最接近的一个；同层高时按 PROCESS_NAME_PREFERENCE 优先"""
    candidates = []
    for item in library.list('process', '', machine_system):
        if item['source'] != 'system':
            continue
        height = to_float(first(library.resolve('process', item['name'])[0].get('layer_height')))
        if height is None:
            height = DEFAULT_LAYER_HEIGHT  # 预设中没写层高时为 OrcaSlicer 的默认值
        rank = next((i for i, word in enumerate(PROCESS_NAME_PREFERENCE) if word in item['name']),
                    len(PROCESS_NAME_PREFERENCE))
        candidates.append((abs(height - layer), rank, item['name'], height))
    if not candidates:
        raise SliceError(f'机型【{machine_system}】没有可用的系统工艺预设，请在切片方案中指定工艺预设')
    candidates.sort()
    _, _, name, height = candidates[0]
    if abs(height - layer) > 1e-6:
        warnings.append(f'机型【{machine_system}】没有 {format_number(layer)}mm 层高的工艺预设，'
                        f'使用【{name}】并把层高改为 {format_number(layer)}mm')
    return name


def format_number(value):
    return ('%.3f' % value).rstrip('0').rstrip('.')


# 3MF 中只保留模型几何：Bambu Studio / OrcaSlicer 的项目文件还带有切片设置（Metadata/project_settings.config 等），
# 其中可能有当前版本不认的参数值导致切片失败；切片参数以切片方案为准
KEEP_3MF_PREFIXES = ('3D/', '_rels/', '[Content_Types].xml')


def strip_3mf_settings(content, warnings):
    try:
        source = zipfile.ZipFile(io.BytesIO(content))
    except zipfile.BadZipFile:
        raise SliceError('3MF 文件无法读取，请检查文件是否损坏')
    names = source.namelist()
    kept = [name for name in names if name.startswith(KEEP_3MF_PREFIXES)]
    if len(kept) == len(names):
        return content
    if not any(name.startswith('3D/') and name.endswith('.model') for name in kept):
        raise SliceError('3MF 文件中没有模型（3D/*.model）')
    output = io.BytesIO()
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as target:
        for name in kept:
            target.writestr(source.getinfo(name), source.read(name))
    if any(name.startswith('Metadata/') and name.endswith('.config') for name in names):
        warnings.append('已忽略 3MF 中的切片设置，按切片方案切片')
    return output.getvalue()


# 打印板类型 → 耗材预设中的温度参数；按顺序优先选择
BED_TYPES = (
    ('Textured PEI Plate', 'textured_plate_temp'),
    ('High Temp Plate', 'hot_plate_temp'),
    ('Engineering Plate', 'eng_plate_temp'),
    ('Cool Plate', 'cool_plate_temp'),
    ('Smooth PEI Plate', 'hot_plate_temp'),
)


def plate_supported(filament, temp_key):
    value = to_float(first(filament.get(temp_key)))
    return value is None or value > 0


def pick_bed_type(current, filaments):
    """当前打印板所有耗材都支持时不变；否则选第一个所有耗材都支持的打印板；都不支持时返回 None（保持原样，由命令行报错）"""
    current = first(current)
    keys = dict(BED_TYPES)
    if current in keys and all(plate_supported(f, keys[current]) for f in filaments):
        return None
    for bed_type, temp_key in BED_TYPES:
        if all(plate_supported(f, temp_key) for f in filaments):
            return bed_type
    return None


def first(value):
    return value[0] if isinstance(value, list) and value else value


def run_slice(model_name, model_bytes, params):
    ext = os.path.splitext(model_name.lower())[1]
    if ext not in MODEL_EXTS:
        raise SliceError(f'不支持的模型格式：{ext or model_name}，支持 {" / ".join(MODEL_EXTS)}')
    warnings = []
    machine, process, filaments = build_presets(params, warnings)

    job_id = uuid.uuid4().hex
    job_dir = os.path.join(JOBS_DIR, job_id)
    out_dir = os.path.join(job_dir, 'out')
    os.makedirs(out_dir)
    model_path = os.path.join(job_dir, 'model' + ext)
    if ext == '.3mf':
        model_bytes = strip_3mf_settings(model_bytes, warnings)
    with open(model_path, 'wb') as f:
        f.write(model_bytes)
    files = {'machine.json': machine, 'process.json': process}
    for i, filament in enumerate(filaments):
        files[f'filament_{i + 1}.json'] = filament
    for name, data in files.items():
        with open(os.path.join(job_dir, name), 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False)

    # --allow-newer-file：允许新版 Bambu Studio / OrcaSlicer 保存的 3MF 项目文件
    cmd = [ORCA_BIN, '--debug', '2', '--slice', '0', '--arrange', '1', '--allow-newer-file',
           '--load-settings', f'{job_dir}/machine.json;{job_dir}/process.json',
           '--load-filaments', ';'.join(f'{job_dir}/filament_{i + 1}.json' for i in range(len(filaments))),
           '--outputdir', out_dir, model_path]
    if XVFB == '1' or (XVFB == 'auto' and not os.environ.get('DISPLAY') and shutil.which('xvfb-run')):
        cmd = ['xvfb-run', '-a'] + cmd
    started = time.time()
    with slice_semaphore:
        try:
            proc = subprocess.run(cmd, cwd=job_dir, capture_output=True, timeout=SLICE_TIMEOUT)
        except subprocess.TimeoutExpired:
            raise SliceError(f'切片超时（{SLICE_TIMEOUT} 秒）', 504)
    log = (proc.stdout + proc.stderr).decode('utf-8', 'replace').splitlines()
    with open(os.path.join(job_dir, 'slice.log'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(log))
    errors = [translate_error(m.group(1).strip()) for m in (re.search(r'\[error\]\s*(.*)', line) for line in log)
              if m and 'exclude triangles' not in m.group(1)]
    if not errors:
        # 部分错误没有 [error] 标记，如「model.stl: Loading of a model file failed.」
        errors = [translate_error(line.strip()) for line in log
                  if 'failed' in line.lower() and not re.search(r'\[(trace|debug|info)\]', line)]
    # 命令行把失败原因写在 result.json 的 error_string 中（部分错误日志里没有）
    result_error = read_json(os.path.join(out_dir, 'result.json')) or {}
    if result_error.get('error_string'):
        errors.append(translate_error(str(result_error['error_string'])))
    gcodes = sorted((f for f in os.listdir(out_dir) if f.endswith('.gcode')), key=plate_number)
    if proc.returncode != 0 or not gcodes:
        raise SliceError(errors[-1] if errors else f'切片失败（退出码 {proc.returncode}）', 422, tail(log))

    plates = [parse_gcode(os.path.join(out_dir, f)) for f in gcodes]
    for plate, file in zip(plates, gcodes):
        plate['plate'] = plate_number(file)
    result = {
        'id': job_id,
        'version': os.environ.get('ORCA_VERSION'),
        'elapsedMs': int((time.time() - started) * 1000),
        'stats': summarize(plates),
        'plates': [{k: v for k, v in p.items() if k not in ('config',)} for p in plates],
        'settings': {k: unquote(plates[0]['config'][k]) for k in SETTING_KEYS if k in plates[0]['config']},
        'warnings': warnings,
    }
    if params.get('fullConfig'):
        result['config'] = plates[0]['config']
    return result


ERROR_HINTS = (
    ('Nothing to be sliced', '模型超出打印平台（或模型为空），请缩小模型或换用更大的机型'),
    ('not compatible with printer', '工艺 / 耗材预设与机型不兼容'),
    ('Failed loading', '模型文件无法读取，请检查文件是否损坏'),
    ('Unsupported 3MF version', '3MF 文件的版本不受支持，请用正式版的 Bambu Studio / OrcaSlicer 重新导出'),
    ('Loading of a model file failed', '模型文件无法读取，请检查文件是否损坏（如三角面、法向量错误），可在建模软件中修复后重新导出'),
)


def translate_error(message):
    message = re.sub(r'\S*/orca-jobs/[0-9a-f]+/', '', message)  # 去掉容器内的临时路径
    for keyword, hint in ERROR_HINTS:
        if keyword in message:
            return f'{hint}（{message}）'
    return message


def plate_number(file):
    match = re.search(r'(\d+)', file)
    return int(match.group(1)) if match else 0


def tail(log, n=30):
    lines = [line for line in log if '[trace]' not in line and '[debug]' not in line]
    return lines[-n:]


STAT_PATTERNS = {
    'filamentLength': r'filament used \[mm\]',
    'filamentVolume': r'filament used \[cm3\]',
    'filamentWeights': r'filament used \[g\]',
    'filamentCosts': r'filament cost',
    'filamentWeight': r'total filament used \[g\]',
    'filamentCost': r'total filament cost',
    'layers': r'total layers count',
    'printTime': r'estimated printing time \(normal mode\)',
    'firstLayerTime': r'estimated first layer printing time \(normal mode\)',
}


def parse_gcode(path):
    """读取 G-code 中的统计注释（文件尾）与切片配置（CONFIG_BLOCK）"""
    stats, config, header = {}, {}, {}
    in_config = False
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            if not line.startswith(';'):
                continue
            text = line[1:].strip()
            if text == 'CONFIG_BLOCK_START':
                in_config = True
                continue
            if text == 'CONFIG_BLOCK_END':
                in_config = False
                continue
            if in_config:
                key, sep, value = text.partition(' = ')
                if sep:
                    config[key.strip()] = value.strip()
                continue
            if ' = ' in text:
                key, _, value = text.partition(' = ')
                for name, pattern in STAT_PATTERNS.items():
                    if re.fullmatch(pattern, key.strip()):
                        stats[name] = value.strip()
            elif ': ' in text:
                # 拓竹机型的文件头：; model printing time: 24m 48s; total estimated time: 30m 31s
                for item in text.split(';'):
                    key, _, value = item.strip().partition(': ')
                    if key in ('total layer number', 'max_z_height', 'model printing time', 'total estimated time'):
                        header[key] = value.strip()
    numbers = lambda v: [to_float(x) for x in v.split(',')] if v else []
    lengths, volumes = numbers(stats.get('filamentLength')), numbers(stats.get('filamentVolume'))
    weights, costs = numbers(stats.get('filamentWeights')), numbers(stats.get('filamentCosts'))
    filaments = []
    for i in range(max(len(lengths), len(volumes), len(weights))):
        filaments.append({'index': i + 1, 'length': at(lengths, i), 'volume': at(volumes, i),
                          'weight': at(weights, i), 'cost': at(costs, i)})
    return {
        'file': os.path.basename(path),
        'size': os.path.getsize(path),
        'filamentWeight': to_float(stats.get('filamentWeight')) if stats.get('filamentWeight') else sum_of(weights),
        'filamentLength': sum_of(lengths),
        'filamentVolume': sum_of(volumes),
        'filamentCost': to_float(stats.get('filamentCost')) if stats.get('filamentCost') else sum_of(costs),
        'printTime': parse_duration(stats.get('printTime') or header.get('total estimated time')),
        'modelPrintTime': parse_duration(header.get('model printing time')),
        'firstLayerTime': parse_duration(stats.get('firstLayerTime')),
        'layers': int(to_float(stats.get('layers') or header.get('total layer number')) or 0),
        'maxZ': to_float(header.get('max_z_height')),
        'filaments': filaments,
        'config': config,
    }


def summarize(plates):
    total = lambda key: round(sum(p[key] or 0 for p in plates), 4)
    return {
        'filamentWeight': total('filamentWeight'),
        'filamentLength': total('filamentLength'),
        'filamentVolume': total('filamentVolume'),
        'filamentCost': total('filamentCost'),
        'printTime': int(total('printTime')),
        'modelPrintTime': int(total('modelPrintTime')) or None,
        'firstLayerTime': int(plates[0]['firstLayerTime'] or 0),
        'layers': max(p['layers'] for p in plates),
        'maxZ': max(p['maxZ'] or 0 for p in plates),
        'plateCount': len(plates),
    }


def unquote(value):
    """单个带引号的值去掉引号：\"Generic PLA\" → Generic PLA；多个值（\"a\";\"b\"）保持原样"""
    if len(value) >= 2 and value[0] == value[-1] == '"' and '";"' not in value:
        return value[1:-1]
    return value


def to_float(value):
    try:
        return float(str(value).strip())
    except (TypeError, ValueError):
        return None


def at(values, i):
    return values[i] if i < len(values) else None


def sum_of(values):
    return round(sum(v for v in values if v is not None), 4)


def parse_duration(text):
    """1d 2h 3m 4s → 秒"""
    if not text:
        return None
    units = {'d': 86400, 'h': 3600, 'm': 60, 's': 1}
    return sum(int(n) * units[u] for n, u in re.findall(r'(\d+)\s*([dhms])', text))


def cleanup_loop():
    while True:
        time.sleep(300)
        if not os.path.isdir(JOBS_DIR):
            continue
        for name in os.listdir(JOBS_DIR):
            path = os.path.join(JOBS_DIR, name)
            try:
                if time.time() - os.path.getmtime(path) > JOB_TTL:
                    shutil.rmtree(path, ignore_errors=True)
            except OSError:
                pass


# ==================== HTTP ====================

class Handler(BaseHTTPRequestHandler):
    server_version = 'orca-slicer-service'

    def do_GET(self):
        self.handle_request(self.route_get)

    def do_POST(self):
        self.handle_request(self.route_post)

    def handle_request(self, route):
        try:
            url = urllib.parse.urlparse(self.path)
            if url.path != '/health' and TOKEN and self.headers.get('Authorization') != f'Bearer {TOKEN}':
                raise SliceError('未授权', 401)
            route(url.path, {k: v[0] for k, v in urllib.parse.parse_qs(url.query).items()})
        except SliceError as e:
            self.send_json({'error': str(e), 'log': e.log}, e.status)
        except Exception as e:  # noqa: BLE001
            self.send_json({'error': f'{type(e).__name__}: {e}'}, 500)

    def route_get(self, path, query):
        if path == '/health':
            return self.send_json({'status': 'UP', 'version': os.environ.get('ORCA_VERSION'),
                                   'systemPresets': len(library.system)})
        if path == '/presets':
            preset_type = query.get('type', 'machine')
            if preset_type not in TYPES:
                raise SliceError('type 只能是 machine / process / filament')
            return self.send_json(library.list(preset_type, query.get('keyword', ''), query.get('machine', '')))
        if path == '/presets/detail':
            data, system_name = library.resolve(query.get('type', 'machine'), query.get('name', ''))
            return self.send_json({'systemPreset': system_name, 'config': data})
        match = re.fullmatch(r'/slice/([0-9a-f]{32})/gcode', path)
        if match:
            out_dir = os.path.join(JOBS_DIR, match.group(1), 'out')
            file = os.path.join(out_dir, f'plate_{int(query.get("plate", "1"))}.gcode')
            if not os.path.isfile(file):
                raise SliceError('G-code 不存在或已过期', 404)
            return self.send_file(file)
        raise SliceError('Not Found', 404)

    def route_post(self, path, query):
        if path not in ('/slice', '/presets/resolve'):
            raise SliceError('Not Found', 404)
        length = int(self.headers.get('Content-Length') or 0)
        if length > MAX_UPLOAD:
            raise SliceError(f'上传内容超过 {MAX_UPLOAD // 1024 // 1024}MB', 413)
        body = self.rfile.read(length)
        if path == '/presets/resolve':
            # 展开预设（名称或 JSON 对象），用于保存配置时校验、读取平台尺寸等
            params = json.loads(body.decode('utf-8') or '{}')
            if params.get('type') not in TYPES:
                raise SliceError('type 只能是 machine / process / filament')
            auto_layer = parse_auto_process(params.get('preset')) if params['type'] == 'process' else None
            if auto_layer is not None:
                # 自动工艺预设在切片时按机型选择，这里只校验写法
                return self.send_json({'systemPreset': None, 'config': {'layer_height': format_number(auto_layer)}})
            data, system_name = library.resolve(params['type'], params.get('preset'))
            return self.send_json({'systemPreset': system_name, 'config': data})
        content_type = self.headers.get('Content-Type', '')
        model_name, model_bytes, params = None, None, {}
        if content_type.startswith('multipart/form-data'):
            message = BytesParser(policy=policy.default).parsebytes(
                b'Content-Type: ' + content_type.encode() + b'\r\n\r\n' + body)
            for part in message.iter_parts():
                name = part.get_param('name', header='content-disposition')
                if name == 'file':
                    model_name, model_bytes = part.get_filename() or 'model.stl', part.get_payload(decode=True)
                elif name == 'params':
                    params = json.loads(part.get_payload(decode=True).decode('utf-8'))
        elif content_type.startswith('application/json'):
            params = json.loads(body.decode('utf-8'))
        else:
            raise SliceError('请使用 multipart/form-data（file + params）或 application/json（modelUrl）')
        if model_bytes is None:
            if not params.get('modelUrl'):
                raise SliceError('缺少模型文件 file 或 modelUrl')
            model_name = params.get('fileName') or urllib.parse.urlparse(params['modelUrl']).path.rsplit('/', 1)[-1]
            with urllib.request.urlopen(params['modelUrl'], timeout=120) as response:
                model_bytes = response.read(MAX_UPLOAD + 1)
            if len(model_bytes) > MAX_UPLOAD:
                raise SliceError(f'模型文件超过 {MAX_UPLOAD // 1024 // 1024}MB', 413)
        self.send_json(run_slice(model_name, model_bytes, params))

    def send_json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_file(self, path):
        self.send_response(200)
        self.send_header('Content-Type', 'text/x-gcode')
        self.send_header('Content-Length', str(os.path.getsize(path)))
        self.send_header('Content-Disposition', f'attachment; filename="{os.path.basename(path)}"')
        self.end_headers()
        with open(path, 'rb') as f:
            shutil.copyfileobj(f, self.wfile)

    def log_message(self, fmt, *args):
        print(f'[{self.log_date_time_string()}] {self.address_string()} {fmt % args}', flush=True)


def main():
    os.makedirs(JOBS_DIR, exist_ok=True)
    library.load_system()
    library.reload_custom()
    print(f'OrcaSlicer {os.environ.get("ORCA_VERSION")}：系统预设 {len(library.system)} 个，自定义预设 {len(library.custom)} 个，'
          f'监听 {PORT}', flush=True)
    threading.Thread(target=cleanup_loop, daemon=True).start()
    ThreadingHTTPServer(('0.0.0.0', PORT), Handler).serve_forever()


if __name__ == '__main__':
    main()
