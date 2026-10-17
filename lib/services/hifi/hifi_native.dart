// Puente Dart ↔ nativo para las funciones Hi-Fi que Flutter no expone.
// Implementaciones nativas:
//   android/app/src/main/kotlin/.../HifiAudioPlugin.kt
//   ios/Runner/HifiAudioPlugin.swift

import 'dart:io' show Platform;

import 'package:flutter/services.dart';

class HifiOutputInfo {
  final String deviceName;
  final String deviceType; // usb, bluetooth, speaker, wired, airplay...
  final int? sampleRate;
  final bool bitPerfectActive;
  final bool bitPerfectSupported;

  const HifiOutputInfo({
    required this.deviceName,
    required this.deviceType,
    this.sampleRate,
    this.bitPerfectActive = false,
    this.bitPerfectSupported = false,
  });

  factory HifiOutputInfo.fromMap(Map<dynamic, dynamic> m) => HifiOutputInfo(
        deviceName: m['deviceName'] as String? ?? 'Desconocido',
        deviceType: m['deviceType'] as String? ?? 'unknown',
        sampleRate: m['sampleRate'] as int?,
        bitPerfectActive: m['bitPerfectActive'] as bool? ?? false,
        bitPerfectSupported: m['bitPerfectSupported'] as bool? ?? false,
      );
}

class HifiNative {
  static const _ch = MethodChannel('crotowave/hifi');

  static bool get _mobile => Platform.isAndroid || Platform.isIOS;

  /// Android 14+: fija el mezclador USB en modo bit-perfect para la
  /// frecuencia/formato de la pista. Devuelve false si no es posible
  /// (sin DAC USB, Android < 14, o el DAC no anuncia ese formato).
  static Future<bool> enableAndroidBitPerfect({
    required int sampleRate,
    required int bitDepth,
  }) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _ch.invokeMethod<bool>('enableBitPerfect', {
            'sampleRate': sampleRate,
            'bitDepth': bitDepth,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> disableAndroidBitPerfect() async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('disableBitPerfect');
    } on PlatformException {
      /* sin efecto */
    } on MissingPluginException {
      /* sin plugin nativo */
    }
  }

  /// iOS: pide a AVAudioSession que trabaje a la frecuencia de la pista.
  static Future<int?> setIosPreferredSampleRate(int sampleRate) async {
    if (!Platform.isIOS) return null;
    try {
      return await _ch.invokeMethod<int>(
          'setPreferredSampleRate', {'sampleRate': sampleRate});
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<HifiOutputInfo?> currentOutput() async {
    if (!_mobile) return null;
    try {
      final m = await _ch.invokeMethod<Map<dynamic, dynamic>>('currentOutput');
      return m == null ? null : HifiOutputInfo.fromMap(m);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
