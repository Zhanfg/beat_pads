# FL Studio Companion · Touch Instruments

This branch adds a dedicated low-latency performance surface on top of Midi Poly Grid's existing MIDI stack.

## What is included

- 25-note multi-touch chromatic keyboard with octave shifting
- 4x4 FPC/drum pad bank with 16-note bank shifting
- Pitch bend, modulation wheel and sustain controls
- MIDI panic / all-notes-off
- Connected MIDI-device status
- Five learnable transport controls for FL Studio
- Existing USB/Bluetooth MIDI device drawer remains available
- Material 3 performance deck with adaptive dark color system
- Five persistent scenes backed by the existing preset system
- Scale Lock with Chromatic, Major, Minor, Dorian and Minor Pentatonic modes
- Hardware-pressure Velocity mapping with safe fixed-Velocity fallback
- Two-axis XY control with user-editable X/Y CC assignments
- Four user-editable MIDI CC macro controls for FL Studio Link to controller

## FL Studio setup

1. Connect the Android device by USB MIDI or another MIDI transport supported by the app.
2. In FL Studio, open **Options > MIDI settings**.
3. Enable the input exposed by the phone/MIDI bridge.
4. Use the keyboard and drum pads as normal note input.
5. For transport controls, map these momentary CC messages once in FL Studio:

| Control | CC |
| --- | ---: |
| Record | 110 |
| Play | 111 |
| Stop | 112 |
| Loop | 113 |
| Metronome | 114 |
| Go to Beginning | 115 |

The controller sends value 127 on press and 0 shortly after release/trigger.

## Design notes

The FL Studio workspace intentionally reuses the existing `flutter_midi_command` send path rather than adding a parallel transport layer. That keeps note, pitch, CC and sustain traffic on the same tested path as the existing pad/MPE modes and avoids additional buffering.

The existing Midi Poly Grid workflow remains unchanged. The FL Studio screen is an additive workspace reachable from the piano icon in the main menu.

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

- glissando pointer hand-off across piano keys
- optional chord/voicing layer
- Mackie/transport protocol experiment behind an opt-in setting
- MIDI receive feedback for motor-style macro state
- latency telemetry and Android USB-specific tuning
