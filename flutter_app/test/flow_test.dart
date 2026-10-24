import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shotrelay/api.dart';
import 'package:shotrelay/controller.dart';
import 'package:shotrelay/main.dart';

class FakeGateway implements Gateway {
  bool logged;
  bool paired;
  String name = 'A';
  FakeGateway({this.logged = false, this.paired = false});
  @override
  Future<Json> request(String route, [Json? data]) async {
    if (route == 'login') {
      logged = true;
      name = data!['name'] as String;
      return {};
    }
    if (!logged) throw const ApiException(401, '最初に名前を入力してください');
    if (route == 'rooms') {
      paired = true;
      return {};
    }
    if (route == 'state')
      return {
        'user': {'id': 'a', 'name': name},
        'room': paired
            ? {
                'code': '123456',
                'members': [
                  {'id': 'a', 'name': name},
                  {'id': 'b', 'name': 'B'},
                ],
              }
            : null,
        'rounds': [],
      };
    return {};
  }

  @override
  Future<Uint8List> photo(String roundId, String photoId) async => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j99kAAAAASUVORK5CYII=',
  );
  @override
  void close() {}
}

void main() {
  testWidgets('名前入力を更新で消さず、名前登録後にペア画面へ進む', (tester) async {
    final gateway = FakeGateway();
    final c = RelayController(gateway);
    await tester.pumpWidget(ShotRelayApp(controller: c, poll: false));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('name-input')), 'りお');
    await c.refresh();
    await tester.pumpAndSettle();
    expect(find.text('りお'), findsOneWidget);
    await tester.tap(find.text('はじめる'));
    await tester.pumpAndSettle();
    expect(find.text('ふたりをつなぐ'), findsOneWidget);
    expect(gateway.name, 'りお');
    expect(find.text('招待コードを作る'), findsOneWidget);
  });

  testWidgets('ホームから撮影画面へ進み、戻ってアルバムを開ける', (tester) async {
    final c = RelayController(FakeGateway(logged: true, paired: true));
    await tester.pumpWidget(ShotRelayApp(controller: c, poll: false));
    await tester.pumpAndSettle();
    expect(find.text('A ＆ B'), findsOneWidget);
    await tester.tap(find.text('撮影をはじめる'));
    await tester.pumpAndSettle();
    expect(find.text('Bを撮る'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    final album = find.text('ふたりのアルバム');
    await tester.ensureVisible(album);
    await tester.tap(album);
    await tester.pumpAndSettle();
    expect(find.text('まだ写真はありません'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
