# FL Studio Companion · AXYP Touch Instruments

当前分支已经从原 Midi Poly Grid 的旧 Grid/MPE UI 重构为独立的移动乐器工作台。主运行链只保留实际在产品里使用的本地音频、MIDI 设备、触控输入、持久设置与 AXYP 协议模块。

## 1.7.0 工作站结构与横屏演奏模型

- 横屏键盘新增 **滑奏 / 滚动 / 弯音** 三种触控语义。滚动模式可直接在琴键表面横向移动声域，弯音模式保留按键并按水平位移发送 Pitch Bend。
- 横屏新增全音域定位条，可快速定位当前可演奏窗口；竖屏继续优先保证手指可落下的键宽。
- 应用从单一乐器页拆为 **乐器 / 轨道 / 混音 / 浏览器** 四个真实工作区。
- 新增 AXYP 驱动的 StudioSession：本地录制 NoteOn/NoteOff 的相对时间、音高、力度与时值，停止录制后形成可回放 clip。
- 轨道页可以录制、停止、回放、清空真实本地片段，并可视化已录音符。
- 混音页承载当前实际工作的本地监听、音量、音色、宏和控制参数；浏览器成为独立乐器选择工作区。
- 横屏工作区导航改为左侧窄 Rail，避免底栏侵占演奏高度；竖屏继续使用底部导航。
- 时间标尺只在轨道工作区出现，不再永久占用触控乐器的演奏空间。
- 移除未安装的 legacy custom_lint analyzer plugin 配置。
- StudioSession 已加入真实录制单元测试。

这一版开始把产品从“FL Studio MIDI Companion Demo”迁移为独立移动工作站架构。后续 Piano Roll、多轨 Session、Sampler/SF2、音频录制、Track FX/Mixer Bus、项目持久化都直接落在现有 Workspace + Session + AXYP 分层上，而不是继续扩张单页。

## 1.6.0 多点触控与核心现代化

- 键盘改为单一 raw-pointer 触控画布，按 `pointerId` 独立追踪每根手指。
- 支持真正的同时按键/和弦；一根手指滑奏不会影响其他仍按住的音。
- 同一个音被多个手指持有时使用引用计数，最后一根手指离开才发送 Note Off。
- 吉他、贝斯、鼓垫、智能和弦也统一携带真实 pointerId。
- 新增 **AXYP/1（Axymorrsen eXtensible Performance Protocol）**：UI 不再直接散发 MIDI，而是先发布统一性能事件，再由 Router 分发到 MIDI、本地音频及未来扩展端。
- AXYP/1 使用固定 magic/version、sequence、微秒时间戳、pointerId、channel、payload length 和类型化 payload；已支持 encode/decode。
- 应用启动路径彻底删除 SplashScreen/Rive/doggo，初始化完偏好后直接进入主页面。
- 删除旧 Beat Pads、旧菜单、旧 MPE/Modulation/PlayMode/MidiSender 等不再进入运行图的代码。
- `services.dart` 收缩为当前运行时 API；MIDI 状态只保留实际使用的通道和力度。
- 旧占位 ASCII 测试替换为多点触控和 AXYP 协议单元测试。
- AXYP 详细规范见 `docs/AXYP_PROTOCOL.md`。

## 当前运行架构

`Touch Surface → MultiTouchNoteRouter → AXYP PerformanceRouter → Local Audio + MIDI`

生成型乐器（琶音器、智能鼓机、步进音序器）也进入同一个 PerformanceRouter，但使用 pointerId = -1。MIDI 现在只是 AXYP 的一个输出适配器，不再是内部事件模型本身。

## FL Studio 连接

Android 设备可以继续通过 USB MIDI / BLE MIDI 等方式连接 FL Studio。本地发声与外部 MIDI 完全独立：不连接电脑时可作为独立乐器使用，连接后可同时本机监听并发送 MIDI。

Transport 默认映射仍为：

| 控制 | CC |
| --- | ---: |
| 录制 | 110 |
| 播放 | 111 |
| 停止 | 112 |
| 循环 | 113 |
| 节拍器 | 114 |
| 回到开头 | 115 |

## 1.5.0 独立发声与横屏交互重构

- 新增低延迟本地 Audio Engine。触控乐器不连接 FL Studio 或 MIDI 设备时也能直接从手机扬声器/耳机发声。
- 本地监听与 MIDI 是并行路径：连接 FL Studio 后可同时本机监听并发送 MIDI。
- 本地监听默认开启，可持久保存开关、音量和温暖/明亮/脉冲/纯音 4 种基础音色。
- 键盘/吉他/贝斯/和弦/琶音器使用复音振荡器；鼓组/智能鼓机/节拍音序器使用短包络电子打击音。
- Sustain、Pitch Bend 与 Panic 同步作用于本地声音。
- 横屏窗口改为 full-bleed：背景铺满摄像头/挖孔区域，实际可交互内容使用 display-cutout inset 留出安全余量。
- Android NormalTheme 与 Flutter immersive 模式统一为透明、cutout-aware 的全屏窗口。
- 乐器浏览器和轨道控制改为 DraggableScrollableSheet + ListView，可上拉展开、下拉收起并滚动到最后一项。
- 音阶与根音下拉菜单增加最大高度，避免底部选项不可点击。

## 1.4.1 中文界面修复

- 应用启动后默认直接进入 FL Studio Companion，不再先显示上游英文设置主页。
- 启动页、MIDI 设备抽屉、连接帮助、布局/MIDI/高级/系统设置、MPE 调制选项以及旧演奏控件全部中文化。
- FL Studio 工作区剩余的鼓组标签（Kick/Snare/Hi-Hat 等）改为中文。
- 保留 FL Studio、MIDI、MPE、CC、BPM、Program Change 等必要专业术语，不做误导性翻译。

## 1.4.0 中文化与扩展乐器

1.4.0 将 FL Studio Companion 工作区的主要可见界面中文化，并把触控乐器扩展到 9 类：

- 键盘：真实黑白键叠层、延音、音阶锁定、压力力度。
- 吉他：标准 E2-A2-D3-G3-B3-E4 定弦的 12 品 MIDI 指板。
- 贝斯：标准 E1-A1-D2-G2 定弦的 12 品 MIDI 指板。
- 鼓组：自适应鼓垫布局。
- 智能和弦：按根音与音阶生成和弦条。
- 琶音器：1/8、1/16、1/32，上行/下行/上下行/随机，1–4 八度。
- 智能鼓机：二维网格中向右增加复杂度、向上增加力度，并实时生成 MIDI Groove。
- 节拍音序器：4 行 × 16 步实时 MIDI 音序器，支持随机生成与清空。
- 现场循环：4 轨 × 5 场景 MIDI 触发矩阵，可映射到 FL Studio Performance Mode/Clip/Scene。

全局 BPM 40–240 会持久保存，并供琶音器、智能鼓机与节拍音序器共同使用。音阶库新增和声小调、旋律小调、混合利底亚、弗里吉亚、大调五声音阶和布鲁斯等模式。

## 1.3.0 Touch Instrument architecture

The primary interaction model now follows a Touch Instrument workflow: choose an instrument from the browser, perform in a full-screen play area, use the top control bar for transport, and open Track Controls only when deeper parameters are needed.

Available Touch Instruments:
- Keyboard: real overlaid black/white piano geometry, octave shifting, Sustain, Scale Lock and touch dynamics.
- Drums: adaptive 4×4 / 8×2 pad layout depending on orientation.
- Smart Chords: scale-aware chord strips generated from the selected root and scale.

The top control bar exposes instrument browsing, MIDI-device access, go-to-beginning, stop, play, record, metronome on wide layouts, Track Controls and Panic. CC115 is reserved for Go to Beginning.

## 1.2.0 interaction model

Smart-control settings are stored locally. Scale, root note, Scale Lock, Touch Dynamics and CC assignments survive restarts. Scene buttons P1–P5 reuse Midi Poly Grid's existing persistent preset system.

Touch Dynamics uses real pressure data only when the platform reports a usable pressure range. Devices that expose a constant placeholder pressure keep the configured fixed Velocity, avoiding accidental full-velocity notes.

The XY pad defaults to CC74/CC71 and the four macro controls default to CC20–CC23. All six assignments are editable from the controller UI.

## Next implementation targets

- optional chord/voicing layer
- Mackie/transport protocol experiment behind an opt-in setting
- MIDI receive feedback for motor-style macro state
- latency telemetry and Android USB-specific tuning
