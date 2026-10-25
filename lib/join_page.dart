import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'room_page.dart';
import 'token_api.dart';

/// Step 1: ask your token server for a room token, then open the room.
class JoinPage extends StatefulWidget {
  const JoinPage({super.key});
  @override
  State<JoinPage> createState() => _JoinPageState();
}

class _JoinPageState extends State<JoinPage> {
  final _server = TextEditingController(text: 'https://milunzo.philecoders.com');
  final _appKey = TextEditingController();
  final _room = TextEditingController(text: 'demo-room');
  final _name = TextEditingController();
  String _role = 'host';
  bool _busy = false;
  String? _error;

  // The app key is a secret: kept in the Android Keystore / iOS Keychain, not in plain preferences.
  static const _secure = FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _secure.read(key: 'appKey');
    if (!mounted) return;
    setState(() {
      _server.text = prefs.getString('server') ?? _server.text;
      _room.text = prefs.getString('room') ?? _room.text;
      _name.text = prefs.getString('name') ?? _name.text;
      _role = prefs.getString('role') ?? _role;
      _appKey.text = key ?? '';
    });
  }

  Future<void> _join() async {
    final problem = serverUrlProblem(_server.text) ??
        (_appKey.text.isEmpty ? 'Enter the app key (LAB_KEY on the server).' : null) ??
        (_name.text.trim().isEmpty ? 'Enter your name.' : null);
    if (problem != null) return setState(() => _error = problem);
    setState(() {
      _busy = true;
      _error = null;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server', _server.text.trim());
    await prefs.setString('room', _room.text.trim());
    await prefs.setString('name', _name.text.trim());
    await prefs.setString('role', _role);
    await _secure.write(key: 'appKey', value: _appKey.text);

    try {
      final ticket = await fetchRoomTicket(
        serverUrl: _server.text,
        appKey: _appKey.text,
        room: _room.text.trim(),
        identity: _name.text.trim(),
        role: _role,
      );
      if (!mounted) return;
      // The ticket (and its token) is handed over in memory only.
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => RoomPage(ticket: ticket)));
    } on TokenApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('VoltKit example')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(controller: _server, decoration: const InputDecoration(labelText: 'Token server URL'), keyboardType: TextInputType.url),
        const SizedBox(height: 12),
        TextField(controller: _appKey, decoration: const InputDecoration(labelText: 'App key'), obscureText: true),
        const SizedBox(height: 12),
        TextField(controller: _room, decoration: const InputDecoration(labelText: 'Room')),
        const SizedBox(height: 12),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Your name')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _role,
          decoration: const InputDecoration(labelText: 'Role'),
          items: [for (final r in ['host', 'cohost', 'moderator', 'viewer']) DropdownMenuItem(value: r, child: Text(r))],
          onChanged: (r) => setState(() => _role = r ?? _role),
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: _busy ? null : _join, child: Text(_busy ? 'Joining…' : 'Join room')),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ],
    ),
  );
}
