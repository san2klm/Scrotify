import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/models/crotolink_models.dart';
import 'package:crotowave/services/remote_crotolink_service.dart';

void main() {
  inviteTests();
  group('CrotoLinkServerEndpoint.parse', () {
    test('accepts wss and normalizes path', () {
      final e = CrotoLinkServerEndpoint.parse(' wss://crotolink.example.org ');
      expect(e.url, 'wss://crotolink.example.org/');
      expect(e.host, 'crotolink.example.org');
      expect(e.port, 443);
      expect(e.httpBase.toString(), 'https://crotolink.example.org/');
      expect(e.warning, isNull);
    });

    test('bare host defaults to wss and keeps custom port', () {
      final e = CrotoLinkServerEndpoint.parse('crotolink.example.org:8443');
      expect(e.url, 'wss://crotolink.example.org:8443/');
      expect(e.port, 8443);
    });

    test('https/http are converted', () {
      expect(CrotoLinkServerEndpoint.parse('https://a.example.org').url,
          'wss://a.example.org/');
      expect(CrotoLinkServerEndpoint.parse('http://192.168.1.10:8080').url,
          'ws://192.168.1.10:8080/');
    });

    test('ws:// only on private hosts, with a warning', () {
      final ok = CrotoLinkServerEndpoint.parse('ws://192.168.1.10:8080');
      expect(ok.isValid, isTrue);
      expect(ok.warning, isNotNull);
      expect(ok.httpBase.scheme, 'http');
      expect(
          CrotoLinkServerEndpoint.parse('ws://localhost:8080').isValid, isTrue);
      expect(
          CrotoLinkServerEndpoint.parse('ws://crotolink.example.org').isValid,
          isFalse);
      expect(CrotoLinkServerEndpoint.parse('ws://8.8.8.8').isValid, isFalse);
      expect(CrotoLinkServerEndpoint.parse('ws://172.32.0.1').isValid, isFalse);
    });

    test('rejects empty, garbage and foreign schemes', () {
      expect(CrotoLinkServerEndpoint.parse('').isValid, isFalse);
      expect(CrotoLinkServerEndpoint.parse('   ').error, isNotNull);
      expect(CrotoLinkServerEndpoint.parse('ftp://x.org').isValid, isFalse);
      expect(CrotoLinkServerEndpoint.parse('wss://').isValid, isFalse);
    });

    test('no hay servidor por defecto; el ejemplo de Ajustes es válido', () {
      expect(kDefaultRemoteCrotoLinkEndpoint, isEmpty);
      expect(
          CrotoLinkServerEndpoint.parse(kDefaultRemoteCrotoLinkEndpoint)
              .isValid,
          isFalse);
      expect(
          CrotoLinkServerEndpoint.parse(kExampleRemoteCrotoLinkEndpoint)
              .isValid,
          isTrue);
    });

    test('sin servidor, crear o unirse a una sala explica qué falta', () async {
      final remote = RemoteCrotoLinkService();
      expect(
          await remote.createRoom(
              pin: 'ABC234', hostName: 'Ana', initialState: const {}),
          isFalse);
      expect(remote.lastError, kNoCrotoLinkServerMessage);
      expect(await remote.checkRoom('ABC234'), isNull);
    });
  });
}

void inviteTests() {
  group('CrotoLinkInviteLink', () {
    test('custom scheme with server', () {
      final l = CrotoLinkInviteLink.parse(
          'crotowave://join?code=abc-234&server=crotolink.example.org')!;
      expect(l.code, 'ABC234');
      expect(l.endpoint, 'wss://crotolink.example.org/');
    });
    test('legacy crotowave:// scheme still works', () {
      final l = CrotoLinkInviteLink.parse(
          'crotowave://join?code=abc-234&server=crotolink.example.org')!;
      expect(l.code, 'ABC234');
    });
    test('https landing link', () {
      final l =
          CrotoLinkInviteLink.parse('https://crotolink.example.org/j/ABC234')!;
      expect(l.code, 'ABC234');
      expect(l.server, 'crotolink.example.org');
      expect(
          CrotoLinkInviteLink.parse('http://192.168.1.5:8080/j/ABC234')!
              .endpoint,
          'ws://192.168.1.5:8080/');
    });
    test('rejects junk, bad codes and public ws:// servers', () {
      expect(CrotoLinkInviteLink.parse('hola'), isNull);
      expect(CrotoLinkInviteLink.parse('crotowave://join?code=ABC'), isNull);
      expect(CrotoLinkInviteLink.parse('crotowave://join?code=ABC10O'),
          isNull); // 0/1/I/O
      expect(CrotoLinkInviteLink.parse('https://x.org/otra/ABC234'), isNull);
      expect(CrotoLinkInviteLink.parse('crotowave://crotolink?code=ABC234'),
          isNull);
      expect(
          CrotoLinkInviteLink.parse(
                  'crotowave://join?code=ABC234&server=ws://evil.org')!
              .endpoint,
          isNull);
    });
    test('link without server uses the configured relay', () {
      expect(
          CrotoLinkInviteLink.parse('crotowave://join?code=ABC234')!.endpoint,
          isNull);
    });
  });
}
