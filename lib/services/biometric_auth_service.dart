import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Resultado de un intento de autenticación biométrica.
enum BiometricAuthStatus {
  success,
  cancelled,
  failed,
  lockedOut,
  notAvailable,
  error,
}

class BiometricAuthResult {
  final BiometricAuthStatus status;
  final String? errorMessage;

  const BiometricAuthResult({
    required this.status,
    this.errorMessage,
  });

  bool get isSuccess => status == BiometricAuthStatus.success;

  @override
  String toString() =>
      'BiometricAuthResult(status: $status, errorMessage: $errorMessage)';
}

/// Servicio encargado de la autenticación biométrica (huella dactilar, Face ID)
/// optimizado para dispositivos móviles con manejo resiliente de errores y ciclo de vida.
class BiometricAuthService {
  final LocalAuthentication _auth;

  BiometricAuthService({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  /// Comprueba si el dispositivo tiene hardware biométrico y está configurado.
  Future<bool> isBiometricsAvailable() async {
    try {
      final isSupported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return isSupported && canCheck;
    } catch (e) {
      debugPrint('BiometricAuthService.isBiometricsAvailable error: $e');
      return false;
    }
  }

  /// Retorna los tipos biométricos disponibles en el dispositivo (huella, rostro, etc.).
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (e) {
      debugPrint('BiometricAuthService.getAvailableBiometrics error: $e');
      return [];
    }
  }

  /// Ejecuta el diálogo de autenticación biométrica nativo.
  Future<BiometricAuthResult> authenticate({
    String localizedReason = 'Autentícate para acceder a tu servidor Navidrome',
    bool biometricOnly = false,
    bool persistAcrossBackgrounding = true,
  }) async {
    try {
      final isAvailable = await isBiometricsAvailable();
      if (!isAvailable) {
        return const BiometricAuthResult(
          status: BiometricAuthStatus.notAvailable,
          errorMessage:
              'La biometría no está disponible o configurada en este dispositivo.',
        );
      }

      final authenticated = await _auth.authenticate(
        localizedReason: localizedReason,
        biometricOnly: biometricOnly,
        persistAcrossBackgrounding: persistAcrossBackgrounding,
      );

      if (authenticated) {
        return const BiometricAuthResult(status: BiometricAuthStatus.success);
      } else {
        return const BiometricAuthResult(
          status: BiometricAuthStatus.cancelled,
          errorMessage: 'Autenticación cancelada.',
        );
      }
    } on LocalAuthException catch (e) {
      debugPrint(
          'BiometricAuthService.authenticate LocalAuthException: ${e.code} - ${e.description}');
      switch (e.code) {
        case LocalAuthExceptionCode.temporaryLockout:
        case LocalAuthExceptionCode.biometricLockout:
          return const BiometricAuthResult(
            status: BiometricAuthStatus.lockedOut,
            errorMessage:
                'Biometría bloqueada temporalmente por intentos fallidos. Usa tu contraseña.',
          );
        case LocalAuthExceptionCode.noCredentialsSet:
        case LocalAuthExceptionCode.noBiometricsEnrolled:
        case LocalAuthExceptionCode.noBiometricHardware:
        case LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable:
          return BiometricAuthResult(
            status: BiometricAuthStatus.notAvailable,
            errorMessage: e.description,
          );
        case LocalAuthExceptionCode.userCanceled:
        case LocalAuthExceptionCode.systemCanceled:
        case LocalAuthExceptionCode.timeout:
          return const BiometricAuthResult(
            status: BiometricAuthStatus.cancelled,
            errorMessage: 'Autenticación cancelada.',
          );
        default:
          return BiometricAuthResult(
            status: BiometricAuthStatus.error,
            errorMessage: e.description,
          );
      }
    } on PlatformException catch (e) {
      debugPrint(
          'BiometricAuthService.authenticate PlatformException: ${e.code} - ${e.message}');
      return BiometricAuthResult(
        status: BiometricAuthStatus.error,
        errorMessage: e.message ?? 'Error en autenticación biométrica.',
      );
    } catch (e) {
      debugPrint('BiometricAuthService.authenticate unexpected error: $e');
      return BiometricAuthResult(
        status: BiometricAuthStatus.error,
        errorMessage: 'Error inesperado: $e',
      );
    }
  }
}
