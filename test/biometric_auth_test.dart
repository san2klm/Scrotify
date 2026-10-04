import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:navidrome_client/services/biometric_auth_service.dart';

class FakeLocalAuthentication implements LocalAuthentication {
  bool isSupported = true;
  bool canCheck = true;
  bool authenticateResult = true;
  LocalAuthException? exceptionToThrow;
  PlatformException? platformExceptionToThrow;
  List<BiometricType> biometrics = [BiometricType.fingerprint];

  @override
  Future<bool> isDeviceSupported() async => isSupported;

  @override
  Future<bool> get canCheckBiometrics async => canCheck;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => biometrics;

  @override
  Future<bool> stopAuthentication() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #authenticate) {
      if (exceptionToThrow != null) {
        throw exceptionToThrow!;
      }
      if (platformExceptionToThrow != null) {
        throw platformExceptionToThrow!;
      }
      return Future<bool>.value(authenticateResult);
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  group('BiometricAuthService Tests', () {
    late FakeLocalAuthentication fakeAuth;
    late BiometricAuthService service;

    setUp(() {
      fakeAuth = FakeLocalAuthentication();
      service = BiometricAuthService(auth: fakeAuth);
    });

    test('isBiometricsAvailable returns true when supported and capable', () async {
      fakeAuth.isSupported = true;
      fakeAuth.canCheck = true;
      final available = await service.isBiometricsAvailable();
      expect(available, isTrue);
    });

    test('isBiometricsAvailable returns false when device is not supported', () async {
      fakeAuth.isSupported = false;
      fakeAuth.canCheck = true;
      final available = await service.isBiometricsAvailable();
      expect(available, isFalse);
    });

    test('getAvailableBiometrics returns list of enrolled biometrics', () async {
      fakeAuth.biometrics = [BiometricType.fingerprint, BiometricType.face];
      final types = await service.getAvailableBiometrics();
      expect(types, contains(BiometricType.fingerprint));
      expect(types, contains(BiometricType.face));
    });

    test('authenticate returns success when auth succeeds', () async {
      fakeAuth.authenticateResult = true;
      final res = await service.authenticate();
      expect(res.status, BiometricAuthStatus.success);
      expect(res.isSuccess, isTrue);
    });

    test('authenticate returns cancelled when auth returns false', () async {
      fakeAuth.authenticateResult = false;
      final res = await service.authenticate();
      expect(res.status, BiometricAuthStatus.cancelled);
      expect(res.isSuccess, isFalse);
    });

    test('authenticate returns notAvailable when biometrics unavailable on device', () async {
      fakeAuth.isSupported = false;
      final res = await service.authenticate();
      expect(res.status, BiometricAuthStatus.notAvailable);
      expect(res.isSuccess, isFalse);
    });

    test('authenticate handles temporaryLockout LocalAuthException', () async {
      fakeAuth.exceptionToThrow = const LocalAuthException(
        code: LocalAuthExceptionCode.temporaryLockout,
        description: 'Locked out due to too many attempts',
      );
      final res = await service.authenticate();
      expect(res.status, BiometricAuthStatus.lockedOut);
      expect(res.errorMessage, contains('bloqueada temporalmente'));
    });

    test('authenticate handles biometricLockout LocalAuthException', () async {
      fakeAuth.exceptionToThrow = const LocalAuthException(
        code: LocalAuthExceptionCode.biometricLockout,
        description: 'Biometric locked out',
      );
      final res = await service.authenticate();
      expect(res.status, BiometricAuthStatus.lockedOut);
    });

    test('authenticate handles userCanceled LocalAuthException', () async {
      fakeAuth.exceptionToThrow = const LocalAuthException(
        code: LocalAuthExceptionCode.userCanceled,
        description: 'User canceled dialog',
      );
      final res = await service.authenticate();
      expect(res.status, BiometricAuthStatus.cancelled);
    });

    test('authenticate handles noBiometricsEnrolled LocalAuthException', () async {
      fakeAuth.exceptionToThrow = const LocalAuthException(
        code: LocalAuthExceptionCode.noBiometricsEnrolled,
        description: 'No enrolled biometrics',
      );
      final res = await service.authenticate();
      expect(res.status, BiometricAuthStatus.notAvailable);
    });

    test('authenticate handles generic PlatformException', () async {
      fakeAuth.platformExceptionToThrow = PlatformException(
        code: 'hardware_failure',
        message: 'Sensor failure',
      );
      final res = await service.authenticate();
      expect(res.status, BiometricAuthStatus.error);
      expect(res.errorMessage, contains('Sensor failure'));
    });
  });
}
