import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfcpin/app/theme.dart';
import 'package:nfcpin/features/cards/data/card_repository.dart';
import 'package:nfcpin/features/cards/domain/registered_card.dart';
import 'package:nfcpin/features/nfc/domain/nfc_models.dart';
import 'package:nfcpin/features/security/app_lock_gate.dart';
import 'package:nfcpin/features/security/security_controller.dart';
import 'package:nfcpin/shared/security/auth_service.dart';

import 'fake_auth.dart';
import 'fake_nfc_platform.dart';

/// Reversible stand-in for the Keystore cipher.
class _FakeCipher implements StorageCipher {
  @override
  Future<String> encrypt(String plain) async =>
      base64Encode(utf8.encode(plain).reversed.toList());

  @override
  Future<String> decrypt(String data) async =>
      utf8.decode(base64Decode(data).reversed.toList());
}

void main() {
  group('SecurityController', () {
    late FakeNfcPlatform platform;
    late FakeAuthService auth;
    late DateTime now;

    SecurityController make() =>
        SecurityController(platform, auth, clock: () => now);

    setUp(() {
      platform = FakeNfcPlatform();
      auth = FakeAuthService();
      now = DateTime(2026, 10, 9, 12);
    });

    test('starts locked when app lock is on, and blocks screenshots', () async {
      platform.appLock = true;
      final s = make();
      await s.load();
      expect(s.locked, isTrue);
      expect(platform.secure, isTrue);
      expect(await s.unlock(), AuthResult.success);
      expect(s.locked, isFalse);
    });

    test('failed unlock stays locked', () async {
      platform.appLock = true;
      auth.result = AuthResult.failed;
      final s = make();
      await s.load();
      await s.unlock();
      expect(s.locked, isTrue);
    });

    test('relocks only after a minute in the background', () async {
      platform.appLock = true;
      final s = make();
      await s.load();
      await s.unlock();

      s.onHidden();
      now = now.add(const Duration(seconds: 30));
      s.onShown();
      expect(s.locked, isFalse);

      s.onHidden();
      now = now.add(const Duration(seconds: 61));
      s.onShown();
      expect(s.locked, isTrue);
    });

    test('turning app lock on or off requires verification', () async {
      final s = make();
      await s.load();
      auth.result = AuthResult.failed;
      await s.setAppLock(true);
      expect(s.appLock, isFalse);
      expect(platform.appLock, isFalse);

      auth.result = AuthResult.success;
      await s.setAppLock(true);
      expect(platform.appLock, isTrue);
      expect(platform.secure, isTrue);
    });

    test('never locks out a phone whose screen lock was removed', () async {
      platform.appLock = true;
      auth.available = false;
      final s = make();
      await s.load();
      expect(s.locked, isFalse);
      expect(s.appLock, isFalse);
    });
  });

  testWidgets('lock gate hides the app until unlocked', (tester) async {
    final platform = FakeNfcPlatform()..appLock = true;
    final auth = FakeAuthService(result: AuthResult.failed);
    final s = SecurityController(platform, auth);
    await s.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: AppLockGate(security: s, child: const Text('secret home')),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Tapsy is locked'), findsOneWidget);
    expect(find.text('secret home'), findsNothing);

    auth.result = AuthResult.success;
    await tester.tap(find.text('UNLOCK'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('secret home'), findsOneWidget);
  });

  group('encrypted storage', () {
    late Directory dir;

    setUp(() async => dir = await Directory.systemTemp.createTemp('tapsy_enc'));
    tearDown(() => dir.delete(recursive: true));

    RegisteredCard card() => RegisteredCard.create(
      name: 'SBI Card',
      fingerprint: 'aaaa-bbbb-cccc',
      category: CardCategory.smartCard,
      message: 'my private note',
      secret: true,
    );

    test('files on disk contain no plaintext and read back', () async {
      final repo = FileCardRepository(
        directory: () async => dir,
        cipher: _FakeCipher(),
      );
      await repo.saveAll([card()]);
      await repo.saveTaps([TapEvent(cardId: 'x', at: DateTime(2026))]);
      final raw = File('${dir.path}/cards.json').readAsStringSync();
      expect(raw, isNot(contains('private note')));
      expect(raw, isNot(contains('SBI')));
      expect(raw, contains('aes-256-gcm'));
      final loaded = (await repo.loadAll()).single;
      expect(loaded.message, 'my private note');
      expect(loaded.secret, isTrue);
      expect((await repo.loadTaps()).single.cardId, 'x');
    });

    test('older plain files are read and immediately encrypted', () async {
      final plain = FileCardRepository(directory: () async => dir);
      await plain.saveAll([card()]);
      await plain.saveTaps([TapEvent(cardId: 'x', at: DateTime(2026))]);
      final repo = FileCardRepository(
        directory: () async => dir,
        cipher: _FakeCipher(),
      );
      final cards = await repo.loadAll();
      expect(cards.single.name, 'SBI Card');
      expect((await repo.loadTaps()).single.cardId, 'x');
      expect(
        File('${dir.path}/taps.json').readAsStringSync(),
        isNot(contains('cardId')),
      );
      expect(
        File('${dir.path}/cards.json').readAsStringSync(),
        isNot(contains('SBI')),
      );
    });

    test('encrypted file without a key fails clearly', () async {
      await FileCardRepository(
        directory: () async => dir,
        cipher: _FakeCipher(),
      ).saveAll([card()]);
      expect(
        FileCardRepository(directory: () async => dir).loadAll(),
        throwsA(isA<CardStoreException>()),
      );
    });
  });
}
