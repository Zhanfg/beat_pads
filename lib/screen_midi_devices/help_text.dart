import 'dart:io' show Platform;

import 'package:beat_pads/shared_components/_shared.dart';
import 'package:flutter/material.dart';

List<Widget> helpText = [
  if (Platform.isAndroid)
    const StringInfoBox(
      header: 'USB',
      body: [
        '用 USB 数据线连接到运行 FL Studio 的主机',
        '下拉系统通知栏，将 USB 用途切换为“ MIDI ”',
        '如果没有 MIDI 选项，请在 Android 开发者选项中检查“默认 USB 配置”。',
        '切换到 MIDI 模式后，刷新设备列表。',
        '点击 USB MIDI 设备即可连接。',
        '',
        '提示：可以在开发者选项中把默认 USB 配置设为 MIDI。',
      ],
    ),
  if (Platform.isIOS)
    const StringInfoBox(
      header: 'USB',
      body: [
        '用 USB 数据线连接到运行 FL Studio 的主机',
        "Open 'Audio MIDI Setup' on Mac and click 'Enable' under iPad/iPhone in the 'Audio Devices' Window",
        'Refresh this Device List',
        "Tap 'IDAM MIDI Host' to Connect",
        '',
        "Note: USB without third-party adapters works only with MacOS devices, due to Apple's MIDI implementation!",
      ],
    ),
  StringInfoBox(
    header: '蓝牙 MIDI',
    body: [
      '先在目标设备或软件中开启 BLE MIDI 广播。',
      '例如 macOS 可在“音频 MIDI 设置”中开启蓝牙 MIDI；iPad/iPhone 通常需要在对应音乐应用内开启。',
      '点击刷新即可重新扫描附近的 BLE MIDI 设备。'
    ],
  ),
  StringInfoBox(
    header: '虚拟 MIDI',
    body: [
      if (Platform.isIOS)
        "Some third-Party apps, like 'AudioKit Synth One', make a Virtual Midi Device available on your Phone or Tablet, which you can connect to in Midi Poly Grid through CoreMidi",
      if (Platform.isAndroid)
        '部分 Android 音频应用会创建虚拟 MIDI 端口，可直接在这里连接。',
      '安装并启动支持虚拟 MIDI 的应用后，它会出现在设备列表中。',
      '连接后，本应用可以向该应用发送 MIDI，例如控制手机上的合成器。',
      '',
      '提示：如果接收端支持后台运行，请开启对应选项。',
    ],
  ),
  if (Platform.isIOS)
    const StringInfoBox(
      header: 'Wi‑Fi MIDI',
      body: [
        '让手机与主机连接到同一个 Wi‑Fi。',
        '在设备列表中连接“Network Session 1”。',
        '在 Mac 打开“音频 MIDI 设置”，进入 MIDI Studio。',
        '在 MIDI Network Setup 中创建 Session，并连接手机。',
        '',
        '提示：无线 MIDI 会增加延迟；Windows 通常需要 rtpMIDI 等第三方软件。',
      ],
    ),
];
