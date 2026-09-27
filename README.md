# USB DAC 音量修复 / USB DAC Volume Fix

> 修复 ColorOS / Android 设备上 **USB DAC 有线耳机音量不响应音量键** 的问题，并提供分段线性的感知音量曲线。

Fixes the issue where **USB DAC wired-earphone volume does not respond to the volume keys** on certain ColorOS / Android devices, and provides a perceptually-linear volume curve via gamma correction.

---

## 问题背景 / The Problem

在 ColorOS ROM 上，系统音频 HAL（AHAL）不会将 `STREAM_MUSIC` 的音量变化路由到 USB DAC。结果是：插上 USB Type-C 耳机后，按音量键**扬声器音量在变，耳机音量纹丝不动**，耳机始终处于一个固定（通常很大）的硬件音量。

On some ColorOS ROMs, the system audio HAL does not route `STREAM_MUSIC` volume changes to the USB DAC. The result: after plugging in a USB Type-C earphone, pressing the volume keys changes the **speaker** volume but the **earphone** volume stays fixed (usually uncomfortably loud).

## 工作原理 / How It Works

本模块由两个组件构成：

```
service.sh (开机启动)
   │
   └─ 启动 watchdog (setsid, 后台)
          │
          ├─ 每 1s 轮询 /proc/asound/card1..8
          ├─ 检测到 USB DAC 插入 → 启动 daemon
          ├─ 检测到 USB DAC 拔出 → 立即 kill daemon (kill + kill -9 + pkill)
          │
          └─ daemon (仅在 USB 连接时存活)
                 ├─ 每 200ms 读取系统音量: cmd audio get-stream-volume 3
                 ├─ 经 gamma=0.3 预计算表映射到 USB DAC 硬件音量
                 ├─ 设置 USB DAC: tinymix -D <card> 3 <L>  /  5 <R>
                 └─ USB 断开 → 自动 exit 0
```

- **watchdog** 常驻，负责按需启停 daemon，保证「只有检测到有线耳机才运行服务，拔出后立即终止」。
- **daemon** 仅在 USB 连接时存活，轮询系统音量键状态，把音量映射后直接写入 USB DAC 的 ALSA mixer 控制（`tinymix -D 1`）。

## 为什么用 tinymix / Why tinymix

Android 的 `AudioManager` / `AudioPolicyManager` 的 `set-device-volume`、`set-stream-volume` 命令**不会到达 USB DAC 硬件**——它们只改变软件流音量。唯一能把音量真正写入 USB DAC 的路径是直接操作 ALSA mixer：

```sh
tinymix -D <usb_card> <control_id> <value>
```

> 注意：`AudioManager.getStreamVolume()`（只读）仍然有效，daemon 用它来感知用户按音量键的意图，但**绝不调用任何 set 命令、不修改系统设置**。

## gamma 感知音量曲线 / Perceptual Volume Curve

人耳对响度的感知是对数的。若 USB DAC 硬件音量与系统音量线性对应，低音量段会显得「太轻」。本模块使用 **gamma 校正**（幂律映射）补偿：

```
hardware_volume = max × (stream_volume / stream_max) ^ gamma
```

- `gamma = 0.3`：50% 系统音量 → 81% 硬件音量，低段被提升，整体听感更均匀。
- 由于 Android `/system/bin/sh`（mksh）**没有 awk / 浮点运算**，gamma 表被**预计算**为 161 项（索引 0→160）硬编码在 daemon 中，运行时只做查表，零浮点开销。

如需调整曲线陡度，修改 `usbvol_fix_v2.conf` 中的 `gamma` 值并重新生成查找表（见 daemon 源码中的 GAMMA_TABLE）。

## 兼容性 / Compatibility

| 项目 | 值 |
|------|-----|
| 测试设备 | Lenovo 小新 Pro GT 13（OP615CL1 / OPD2409） |
| 系统 | ColorOS 16 / Android 15（SDK 35） |
| Root | KernelSU（兼容 Magisk） |
| 音频架构 | Qualcomm AHAL（sun-qrd-sku2-snd-card） |
| USB DAC | 作为 ALSA card 1 出现 |

> **其他设备**：USB DAC 的 ALSA 控制编号、最大值可能不同。请先用 `tinymix -D <card> -a`（或 `tinypcminfo`）查看你的 USB DAC 控制列表，然后修改 `usbvol_fix_v2.conf`：
> - `usb_l_ctrl` / `usb_r_ctrl`：左右声道控制编号
> - `usb_l_max` / `usb_r_max`：左右声道最大值
> - `stream` / `stream_max`：音量流类型与最大值

## 安装 / Installation

1. 确保已 root（KernelSU 或 Magisk）
2. 下载 `usb_volume_fix_v2.zip`
3. **KernelSU**：管理器 → 模块 → 从存储安装 → 选择 zip
   **Magisk**：模块 → 从存储安装 → 选择 zip
   或命令行：
   ```sh
   adb push usb_volume_fix_v2.zip /data/local/tmp/
   adb shell su -c 'ksud module install /data/local/tmp/usb_volume_fix_v2.zip'   # KernelSU
   adb shell su -c 'magisk --install-package /data/local/tmp/usb_volume_fix_v2.zip'  # Magisk
   ```
4. 重启
5. 插入 USB 耳机，播放音乐，按音量键验证

## 配置 / Configuration

配置文件 `usbvol_fix_v2.conf`（安装后位于 `/data/adb/service.d/usbvol_fix_v2/`）：

```ini
poll_ms=200          # 轮询间隔（毫秒）
stream=3             # 音量流（3 = STREAM_MUSIC）
stream_max=160       # 音量最大值
usb_l_ctrl=3         # USB DAC 左声道 ALSA 控制编号
usb_l_max=11520      # 左声道最大值
usb_r_ctrl=5         # USB DAC 右声道 ALSA 控制编号
usb_r_max=8191       # 右声道最大值
gamma=0.3            # 感知曲线参数（仅用于参考，实际查表已固定）
```

修改后重启服务：`adb shell su -c 'pkill -f usbvol_fix_v2_watchdog; sh /data/adb/modules/usb_volume_fix_v2/service.sh'`

## 安全声明 / Safety

本模块**严格遵守最小干预原则**：

- ✅ **只操作 USB DAC**（`tinymix -D <usb_card>`），不触碰扬声器（card 0）
- ✅ **不读写任何 `persist.audio.*` / `persist.oplus.audio.*` 属性**
- ✅ **不重启音频 HAL / audioserver**（`ctl.restart`）
- ✅ **不修改 SPL 限制（spllimit）等系统保护机制**
- ✅ **USB 拔出后 daemon 立即退出**，无后台残留
- ✅ 仅在检测到 USB 耳机时才启动服务

## 构建 / Build

从源码打包刷入 zip：

```sh
python3 package.py    # 生成 usb_volume_fix_v2.zip
```

打包脚本使用正斜杠路径、跳过隐藏文件与仓库元数据（README/LICENSE/.gitignore 等）。

## 卸载 / Uninstall

在 KernelSU / Magisk 管理器中卸载模块并重启，或：

```sh
ksud module uninstall usb_volume_fix_v2 && reboot   # KernelSU
```

卸载脚本会先杀 watchdog 再杀 daemon（防止 watchdog 重启 daemon），并清理配置与日志。

## 项目结构 / Repository Structure

```
usb-volume-fix/
├── README.md
├── LICENSE
├── .gitignore
├── package.py                       # 打包脚本
├── module.prop                      # 模块元数据
├── customize.sh                     # 安装时钩子（设置权限）
├── post-fs-data.sh                  # 早期启动钩子（创建配置目录）
├── service.sh                       # 启动 watchdog
├── uninstall.sh                     # 卸载清理
├── usbvol_fix_v2.conf               # 默认配置
└── system/bin/
    ├── usbvol_fix_v2_watchdog.sh     # USB 热插拔看门狗
    └── usbvol_fix_v2_daemon.sh       # 音量映射守护进程
```

## 许可证 / License

[MIT](./LICENSE)
