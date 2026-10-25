import 'dart:convert';
import 'dart:io';

/// What the token server returns: where to connect and a short-lived room token.
/// The token is only ever kept in memory; [toString] never prints it.
class RoomTicket {
  RoomTicket({required this.wsUrl, required this.token, required this.room, required this.identity, required this.role});

  factory RoomTicket.fromJson(Map<String, dynamic> json) {
    final wsUrl = json['wsUrl'], token = json['token'];
    if (wsUrl is! String || token is! String || wsUrl.isEmpty || token.isEmpty) {
      throw const TokenApiException('The server reply has no wsUrl/token.');
    }
    return RoomTicket(
      wsUrl: wsUrl,
      token: token,
      room: json['room'] as String? ?? '',
      identity: json['identity'] as String? ?? '',
      role: json['role'] as String? ?? '',
    );
  }

  final String wsUrl, token, room, identity, role;

  @override
  String toString() => 'RoomTicket($room as $identity, $role, token: <redacted>)';
}

class TokenApiException implements Exception {
  const TokenApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Your backend's address must be HTTPS (plain http only for a server on this machine or the emulator host).
String? serverUrlProblem(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasAuthority) return 'Enter the token server URL, e.g. https://example.com';
  final local = const {'localhost', '127.0.0.1', '10.0.2.2'}.contains(uri.host);
  if (uri.scheme == 'https' || (uri.scheme == 'http' && local)) return null;
  return 'The token server must use https://';
}

/// Asks YOUR token server (see the VoltKit docs for Node, PHP, Go and Python examples) for a room token. The VoltKit API secret is never in the app.
Future<RoomTicket> fetchRoomTicket({
  required String serverUrl,
  required String appKey,
  required String room,
  required String identity,
  required String role,
  HttpClient? client,
}) async {
  final http = client ?? HttpClient();
  try {
    final base = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final request = await http.postUrl(Uri.parse('$base/token')).timeout(const Duration(seconds: 10));
    request.headers
      ..contentType = ContentType.json
      ..set('X-App-Key', appKey);
    request.write(jsonEncode({'room': room, 'identity': identity, 'role': role}));
    final response = await request.close().timeout(const Duration(seconds: 15));
    final body = await utf8.decoder.bind(response).join();
    final json = body.isEmpty ? <String, dynamic>{} : jsonDecode(body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      final error = json['error'] as Map<String, dynamic>?;
      throw TokenApiException(error?['message'] as String? ?? 'The server answered HTTP ${response.statusCode}.');
    }
    return RoomTicket.fromJson(json);
  } on SocketException catch (e) {
    throw TokenApiException('Cannot reach the server: ${e.message}');
  } on FormatException {
    throw const TokenApiException('The server reply is not JSON.');
  } finally {
    if (client == null) http.close(force: true);
  }
}
