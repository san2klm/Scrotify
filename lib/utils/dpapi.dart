import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Cifrado de datos con DPAPI de Windows (`CryptProtectData`): solo el mismo
/// usuario de Windows en el mismo equipo puede descifrarlos.
///
/// Solo existe en Windows; en otras plataformas [isSupported] es `false` y
/// llamar a [protect]/[unprotect] lanza [UnsupportedError].
class Dpapi {
  Dpapi._();

  static bool get isSupported => Platform.isWindows;

  static Uint8List protect(Uint8List plain) => _call(plain, protect: true);

  static Uint8List unprotect(Uint8List blob) => _call(blob, protect: false);

  static Uint8List _call(Uint8List input, {required bool protect}) {
    if (!isSupported) throw UnsupportedError('DPAPI solo existe en Windows');
    final crypt32 = DynamicLibrary.open('crypt32.dll');
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final cryptProtect = crypt32.lookupFunction<
        Int32 Function(Pointer<_DataBlob>, Pointer<Utf16>, Pointer<_DataBlob>,
            Pointer<Void>, Pointer<Void>, Uint32, Pointer<_DataBlob>),
        int Function(Pointer<_DataBlob>, Pointer<Utf16>, Pointer<_DataBlob>,
            Pointer<Void>, Pointer<Void>, int, Pointer<_DataBlob>)>(
      protect ? 'CryptProtectData' : 'CryptUnprotectData',
    );
    final localFree = kernel32.lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)>('LocalFree');

    final inBlob = calloc<_DataBlob>();
    final outBlob = calloc<_DataBlob>();
    final buffer = calloc<Uint8>(input.isEmpty ? 1 : input.length);
    try {
      buffer.asTypedList(input.length).setAll(0, input);
      inBlob.ref
        ..cbData = input.length
        ..pbData = buffer;
      final ok = cryptProtect(
        inBlob,
        nullptr,
        nullptr,
        nullptr,
        nullptr,
        0x1, // CRYPTPROTECT_UI_FORBIDDEN
        outBlob,
      );
      if (ok == 0) {
        throw const FileSystemException('DPAPI: no se pudo procesar el dato');
      }
      final result = Uint8List.fromList(
          outBlob.ref.pbData.asTypedList(outBlob.ref.cbData));
      localFree(outBlob.ref.pbData.cast<Void>());
      return result;
    } finally {
      calloc.free(buffer);
      calloc.free(inBlob);
      calloc.free(outBlob);
    }
  }
}

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;

  external Pointer<Uint8> pbData;
}
