# AuraBridge Pi 2.2 Project Whitepaper

> Faithful Markdown rendering of `AuraBridge Pi 2.2 Project Whitepaper.docx`.
> The original is Chinese-dominant with inline English technical terms; that
> bilingual style is preserved here. For authoritative phase scope and safety
> rules in English, see [PROJECT_OVERVIEW_2_2.md](PROJECT_OVERVIEW_2_2.md).

*基于 Raspberry Pi 4、PipeWire、WirePlumber、FiiO KA11 与实时音频安全层的多协议家庭音频桥接系统*

## 1. 项目概述 (Project Overview)

AuraBridge Pi 2.2 是一个基于 Raspberry Pi 4 的多协议家庭无线音频接收系统。项目目标是把
Harman Kardon Aura Studio 3（琉璃3）通过一个外置 Raspberry Pi 音频桥升级为支持 AirPlay 2、
Spotify Connect、Bluetooth A2DP，以及可选 DLNA / UPnP 的现代网络音频终端。

本项目不拆解琉璃3，不修改音箱内部电路，不刷音箱固件。Raspberry Pi 4 负责无线协议接收、音频服务管理、
音频路由、音量安全和系统监控。FiiO KA11 Type-C 作为指定 USB DAC / headphone amplifier，负责把
Raspberry Pi 输出的数字 USB 音频转换成模拟 3.5mm 音频信号，再通过 AUX 输入连接琉璃3。

2.2 版相比 2.1 版的核心修正：

- `volume-guard-loop.sh` 不再被视为实时安全机制，只能作为 recovery、audit、diagnostics 工具。
- 实时音量安全必须在 PipeWire / WirePlumber 音频图内部实现，或者在无法验证之前禁用高风险协议。
- DLNA 被标记为 blocked feature，必须等 PipeWire-level limiter、virtual safe sink 或等效硬限制
  验证成功后才能启用。
- FiiO KA11 物理 sink 不应直接暴露为长期默认 sink，推荐通过 AuraBridge Safe Sink 受控输出。
- WirePlumber policy 必须基于实际安装版本编写，不能盲目复制最新版配置示例。
- Shairport Sync MVP 默认使用 PulseAudio backend，通过 `pipewire-pulse` 接入 PipeWire，而不是
  native PipeWire backend。
- Controller MVP 保持 Bash scripts + systemd services/timers，不引入 FastAPI 或 Node.js。

## 2. 总体系统链路 (End-to-end Signal Chain)

```
iPhone / Mac / iPad / Android / Xiaomi / Samsung / PC
        ↓
AirPlay 2 / Spotify Connect / Bluetooth A2DP / optional DLNA
        ↓
Raspberry Pi 4
        ↓
PipeWire + WirePlumber
        ↓
AuraBridge Safe Sink (virtual controlled sink)
        ↓
PipeWire filter-chain limiter or fixed-gain stage
        ↓
FiiO KA11 Type-C USB DAC
        ↓
3.5mm AUX cable
        ↓
Harman Kardon Aura Studio 3
```

核心设计原则：normal clients should not directly target the FiiO KA11 physical sink; they should
target an AuraBridge Safe Sink whenever possible; the Safe Sink should enforce gain limiting or
real-time protection before audio reaches KA11.

## 3. 设计背景 (Background)

琉璃3 声音和外观都不错，但缺少现代网络音频能力：没有原生 AirPlay 2；不能稳定作为 Apple Home 认证
音箱；没有 Spotify Connect；没有 DLNA / UPnP renderer；蓝牙是点对点体验。本项目采用外置音频桥方案，
不破解或模拟小米妙播、三星 SmartThings、Google Cast 等私有生态，而是使用稳定通用协议组合：Apple
devices → AirPlay 2；Spotify users → Spotify Connect；Android / Xiaomi / Samsung → Bluetooth
A2DP；local network media apps → optional DLNA / UPnP (blocked until safety is verified)。

## 4. 项目目标 (Goals)

**4.1 Core MVP 目标:** Pi 4 headless 启动；KA11 被识别为 USB Audio DAC；PipeWire 识别 KA11 为
sink；建立受控默认输出路径；AirPlay 2 从 iPhone/Mac 播放；Spotify Connect 播放；核心服务由 systemd
管理；提供 status/logs 脚本；服务重启自动恢复；不发生爆音或 ALSA device busy 冲突。

**4.2 MVP Plus 目标:** Bluetooth A2DP 接收；手动开启配对窗口；避免永久 discoverable；测试蓝牙是否
抢占 AirPlay/Spotify；必要时加入 WirePlumber policy 或中控脚本修正。

**4.3 Optional 目标:** DLNA / UPnP renderer；AuraBridge Safe Sink；PipeWire filter-chain limiter；
I2C OLED 状态显示；物理按钮；source priority controller；极轻量本地 status page。

## 5. 非目标 (Non-Goals)

不实现小米妙播 receiver；不实现三星 SmartThings / Tap Sound / Music Share receiver；不实现完整
Chromecast receiver；不拆解或改造琉璃3；不使用 Pi 板载 3.5mm 作为最终输出；不使用无源 Type-C 转
3.5mm 模拟直通线；不把 Apple Home app 稳定作为核心验收标准；不在多协议版本中使用纯 ALSA direct
output 作为主架构；不在 MVP 引入大型 Web framework；不使用 Bash polling 作为实时音频安全机制；不在
未验证 limiter / safe sink 前启用 DLNA。

## 6. 指定硬件架构 (Hardware)

**6.1 必需硬件:** Raspberry Pi 4 Model B；microSD 32GB+；5V 3A USB-C 电源；USB-A male to
Type-C female adapter；FiiO KA11 Type-C USB DAC / headphone amplifier；3.5mm AUX cable；
Harman Kardon Aura Studio 3。

**6.2 可选硬件:** Ethernet cable；case；heatsink/fan；powered USB hub；I2C OLED display；
physical button。

**6.3 FiiO KA11 定位:** Primary USB DAC；headphone amplifier output stage；3.5mm analog AUX
source for Aura Studio 3。注意：KA11 是 DAC / headphone amplifier，**不是固定电平 line-out**。
输出能力较强，直接接入有源音箱 AUX 时必须谨慎控制音量。因此 2.2 版增加安全规则：首次测试琉璃3 音量
必须调低；PipeWire 默认音量先设 20%–30%；如 KA11 暴露硬件 mixer 需检查并设安全值；禁止在未知状态下
播放高音量测试信号；DLNA 在未验证实时 audio safety layer 前不允许启用；KA11 physical sink 不应直接
作为正常客户端长期默认 sink。

## 7. 硬件连接 (Wiring)

```
Raspberry Pi 4 USB-A port
        ↓
USB-A male to Type-C female adapter
        ↓
FiiO KA11 Type-C
        ↓
3.5mm AUX cable
        ↓
Aura Studio 3 AUX-IN
```

注意：不要使用 Pi 4 板载 3.5mm 输出；KA11 需被系统识别为 USB audio device；若 `lsusb` 无反应，检查
转接头方向、供电、线材或 USB 枚举；若出现 USB reset、断音、爆音，尝试换 USB 口、换电源或用 powered
USB hub。

## 8. 系统软件架构 (Software Architecture)

**8.1 总体架构:** Protocol Receiver Layer (Shairport Sync / librespot / BlueZ+PipeWire BT /
optional gmrender or Rygel blocked until safe) → Audio API Layer (`pipewire-pulse` for
PulseAudio-compatible clients; PipeWire native graph where appropriate) → Policy Layer
(WirePlumber, version-specific configuration only) → Safety Layer (AuraBridge Safe Sink preferred;
PipeWire filter-chain limiter or fixed-gain stage if verified; KA11 physical sink not exposed as
default if possible) → Output Layer (FiiO KA11 USB DAC sink) → Analog Playback Layer (3.5mm AUX to
Aura Studio 3)。

**8.2 为什么不用纯 ALSA:** 纯 ALSA direct output 适合单一 AirPlay receiver，但不适合多协议主架构：
服务可能独占 USB DAC；多服务同时运行易发生 Device or resource busy；蓝牙自动连接可能改变默认路由；
DLNA 音量控制不可靠；后续 dashboard / volume guard / source policy 更难做。

## 9. AirPlay 2 设计

**9.1 组件:** NQPTP、Shairport Sync、PulseAudio backend、`pipewire-pulse`、PipeWire、WirePlumber、
FiiO KA11。

**9.2 backend 决策:** MVP 不使用 native PipeWire backend。推荐 `Shairport Sync PulseAudio backend
→ pipewire-pulse → PipeWire → AuraBridge Safe Sink (if implemented) → FiiO KA11 sink`。理由：
PulseAudio backend 更成熟；`pipewire-pulse` 能把 PulseAudio API client 接入 PipeWire media graph；
可避免 native PipeWire backend 在不同发行版/版本上的不确定性。

**9.3 构建策略:** 先运行 `./configure --help | grep -i pulse` 与 `./configure --help | grep -i
airplay`，然后选择实际可用的 PulseAudio backend flag。优先目标：

```
./configure --sysconfdir=/etc \
  --with-pa --with-soxr --with-avahi \
  --with-ssl=openssl --with-systemd-startup --with-airplay-2
```

如 `--with-pa` 不存在，以 `./configure --help` 输出为准。

**9.4 AirPlay 验收:** nqptp.service active；shairport-sync.service active；pipewire-pulse active；
iPhone/Mac sees "Aura Studio 3 AirPlay"；audio routes to KA11 through PipeWire；no ALSA device busy；
safe volume init works；no dangerous initial output level。

## 10. Spotify Connect 设计

使用 librespot。推荐 `librespot → PulseAudio-compatible output → pipewire-pulse → PipeWire →
AuraBridge Safe Sink (if implemented) → FiiO KA11`。设备名 **Aura Studio 3 Spotify**。验收：app 可见
设备；playback works；AirPlay 与 Spotify 共存；no ALSA device locking conflict；output level safe。

## 11. Bluetooth A2DP 设计 (Phase 4 — 本次不实现)

组件：BlueZ、PipeWire Bluetooth、WirePlumber BlueZ monitor、Safe Sink (if implemented)、KA11 sink。
蓝牙不能永久 discoverable，必须提供 `scripts/bt-pairing-window.sh`（`discoverable on` → `sleep 120`
→ `discoverable off`）。Phase 4 必须做 routing spike，记录 PipeWire/WirePlumber 版本，识别 0.4.x 或
0.5.x+，使用版本匹配文档，配对 Android，观察连接前后 `wpctl status` 与 `pactl list sink-inputs`，测试
是否抢占 AirPlay/Spotify，必要时实现版本特定 policy 或中控修正。若短期无法优雅处理抢占，MVP 可默认禁用
蓝牙，手动启用，AirPlay 与 Spotify 保持主路径。

## 12. DLNA / UPnP 设计 (Phase 6 — 本次不实现，blocked)

DLNA 是 blocked optional feature，不进核心 MVP。风险：客户端连接时强制设置音量 100%；控制端与
renderer 音量不同步；多客户端争抢 renderer；输出绕过部分软件音量逻辑；瞬间爆音无法用 Bash polling 及时
阻止。2.2 策略：DLNA is blocked until real-time audio safety is verified；disabled by default；不能
依赖 `volume-guard-loop.sh`；polling-based correction 不可作为安全机制。解锁条件（全部满足）：Safe Sink
或等效保护路径存在；KA11 physical sink 不直接暴露为 default sink；PipeWire-level limiter / fixed-gain /
hard cap 验证通过；100% client volume 不产生危险模拟输出；测试时琉璃3 物理音量低；存在 quick disable
脚本；记录精确 renderer 与 client 行为。候选工具：gmrender-resurrect、Rygel。

## 13. 音量安全设计 (Volume Safety)

**13.1** KA11 是小尾巴 DAC / headphone amplifier，输出能力强，直接接琉璃3 AUX 若音量过高可能非常大声。

**13.2 2.1 版问题:** 原设想 `volume-guard-loop.sh` 每 5–10 秒检查，超过 45% 就 clamp。该方案有竞态
条件，只能事后补救，不能阻止瞬间爆音。

**13.3 2.2 修正:** `volume-guard-loop.sh` 降级为 recovery / audit / diagnostics /
post-failure correction tool。它**不是** real-time safety mechanism / limiter / hard cap /
speaker protection layer。

**13.4 三层音量保护:**

- Layer 1 — hardware mixer check：`aplay -l`、`amixer -c <card_id> scontrols`、
  `alsamixer -c <card_id>`，若 KA11 暴露硬件音量控制则设到安全值。
- Layer 2 — real-time PipeWire audio safety (preferred)：AuraBridge Safe Sink、PipeWire
  filter-chain limiter、fixed-gain stage、KA11 不直接作为 normal default sink。若无法验证：DLNA
  remains disabled，risky clients remain disabled。
- Layer 3 — Bash recovery：`safe-volume.sh`、`volume-guard-loop.sh`、systemd timer、logging。
  Recovery only。

**13.5 初始测试建议:** initial PipeWire volume 20%–30%；max normal testing volume 45%；Aura Studio 3
physical volume low；phone volume low；DLNA disabled；untrusted clients disabled。

**13.6 必需脚本:** `safe-volume.sh`、`volume-guard-loop.sh`、`check-ka11.sh`、
`aurabridge-volume-guard.service`、`aurabridge-volume-guard.timer`。注意：the volume guard timer is
not a safety guarantee; it exists for recovery and diagnostics only.

## 14. PipeWire Safe Sink 设计 (Phase 5 — 本次不实现)

目标：正常客户端不应直接把音频送到 KA11 physical sink，推荐建立虚拟受控输出 `AuraBridge Safe Sink →
limiter or fixed-gain → FiiO KA11 physical sink`。优势：所有客户端看到受控 sink；KA11 physical sink
可隐藏或不设默认；进入 KA11 前做固定 gain 或 limiter；DLNA 等不可信客户端输出更易约束；source priority
controller 更易实现。实现要求：不假设某 limiter 插件一定存在，先探测 `pipewire --version`、
`wireplumber --version`、`pw-cli ls Node`、`wpctl status`、`ls /usr/lib/*/ladspa`、
`ls /usr/lib/*/lv2`；可用则尝试 PipeWire filter-chain，不可用则记录原因并保持 DLNA disabled。

## 15. Controller 设计

2.2 不使用 FastAPI 或 Node.js 作为 MVP controller。MVP 采用 Bash scripts、systemd services、systemd
timers、SSH、journalctl logs。原因：更轻量、更适合 headless embedded Linux、更易 debug、更少依赖。后续
如需 Web UI，可用 Python 原生 `http.server` 或极轻量 CGI 风格实现，不建议 MVP 使用大型框架。

## 16. 推荐 repository 结构

见 [PROJECT_OVERVIEW_2_2.md](PROJECT_OVERVIEW_2_2.md) 第 17 节（结构一致）。

## 17. Phase Plan (摘要)

- **Phase 0 — 准备阶段:** prepare hardware, OS image, documentation, scripts.
- **Phase 1 — Base OS + PipeWire + KA11 验收:** confirm KA11 as primary USB DAC sink; confirm
  PipeWire/WirePlumber versions; confirm hardware mixer behavior; apply safe initial volume.
- **Phase 2 — AirPlay 2:** works through Shairport Sync PulseAudio backend and `pipewire-pulse`.
- **Phase 3 — Spotify Connect:** works through librespot.
- **Phase 4 — Bluetooth A2DP:** works without destroying AirPlay/Spotify (本次不实现).
- **Phase 5 — Safe Sink / Real-time Audio Safety:** implement/verify real-time safety before risky
  clients (本次不实现).
- **Phase 6 — Optional DLNA:** manual enable only after safety testing (本次不实现).
- **Phase 7 — Optional UI / OLED:** convenience features after core audio is stable (本次不实现).

## 18–19. 验收标准与风险矩阵

验收标准 (Core MVP / MVP Plus / Safe Sink / Optional DLNA) 与风险矩阵详见
[PROJECT_OVERVIEW_2_2.md](PROJECT_OVERVIEW_2_2.md) 第 20–25 节。核心补充：probability 列在 risk
matrix 中标注 ALSA device locking (High/High)、Bash volume guard race condition (High/High) 为最高
优先级缓解项。

## 20. 最终定义 (Final Definition)

> AuraBridge Pi 2.2 turns a traditional AUX speaker into a practical multi-protocol network audio
> endpoint using Raspberry Pi 4, PipeWire, WirePlumber, Shairport Sync, librespot, Bluetooth A2DP,
> optional DLNA, a real-time audio safety layer, and a FiiO KA11 USB DAC.

核心工程原则：Audio safety must be real-time and inside the audio graph; Bash polling is not a
safety mechanism; DLNA remains blocked until a real-time limiter or equivalent hard cap is
verified; WirePlumber policy must be version-specific; FiiO KA11 is powerful enough that output
level must be treated carefully.
