import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:voltkit_rtc_lab/token_api.dart';

void main() {
  test('the ticket never prints its token', () {
    final t = RoomTicket.fromJson({'wsUrl': 'wss://x/ws', 'token': 'secret-room-token', 'room': 'r', 'identity': 'a', 'role': 'host'});
    expect(t.token, 'secret-room-token');
    expect('$t', isNot(contains('secret-room-token')));
    expect(() => RoomTicket.fromJson({'wsUrl': 'wss://x/ws'}), throwsA(isA<TokenApiException>()));
  });

  test('the token server must be https (plain http only for this computer or the emulator host)', () {
    expect(serverUrlProblem('https://example.com'), isNull);
    expect(serverUrlProblem('http://10.0.2.2:7000'), isNull);
    expect(serverUrlProblem('http://localhost:7000'), isNull);
    expect(serverUrlProblem('http://example.com'), isNotNull);
    expect(serverUrlProblem('not a url'), isNotNull);
  });

  test('fetchRoomTicket posts room/identity/role with X-App-Key and reads the reply or the error', () async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    final seen = <Map<String, Object?>>[];
    server.listen((req) async {
      final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
      seen.add({'path': req.uri.path, 'key': req.headers.value('x-app-key'), ...body});
      req.response.headers.contentType = ContentType.json;
      if (req.headers.value('x-app-key') != 'good-key') {
        req.response.statusCode = 401;
        req.response.write(jsonEncode({'error': {'code': 'unauthorized', 'message': 'Wrong app key.'}}));
      } else {
        req.response.write(jsonEncode({'wsUrl': 'wss://rtc/ws', 'token': 't', 'room': body['room'], 'identity': body['identity'], 'role': body['role']}));
      }
      await req.response.close();
    });
    addTearDown(server.close);
    final url = 'http://127.0.0.1:${server.port}/';
    final ticket = await fetchRoomTicket(serverUrl: url, appKey: 'good-key', room: 'demo-room', identity: 'asha', role: 'viewer');
    expect(ticket.wsUrl, 'wss://rtc/ws');
    expect(seen.single, {'path': '/token', 'key': 'good-key', 'room': 'demo-room', 'identity': 'asha', 'role': 'viewer'});
    await expectLater(
      fetchRoomTicket(serverUrl: url, appKey: 'bad', room: 'demo-room', identity: 'asha', role: 'host'),
      throwsA(isA<TokenApiException>().having((e) => e.message, 'message', 'Wrong app key.')),
    );
  });
}
