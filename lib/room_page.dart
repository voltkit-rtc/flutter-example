import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:voltkit_rtc/voltkit_rtc.dart';
import 'token_api.dart';

/// Step 2: connect to the room, publish your camera and microphone, show everyone's video, chat, leave.
class RoomPage extends StatefulWidget {
  const RoomPage({super.key, required this.ticket});
  final RoomTicket ticket;
  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  late final StreamClient _client;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _local = RTCVideoRenderer();
  final _remote = <String, (RemoteTrack, RTCVideoRenderer)>{}; // producerId -> video
  final _messages = <ChatMessage>[];
  final _chatInput = TextEditingController();
  String _status = 'Connecting…';
  bool _micOn = true, _camOn = true, _publishing = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await _local.initialize();
    // 1. Create the client with the URL and token from your server.
    _client = StreamClient(wsUrl: widget.ticket.wsUrl, token: widget.ticket.token);

    // 2. Listen BEFORE connecting: people already publishing arrive during connect().
    _subscriptions.addAll([
      _client.onTrack.listen(_onTrack),
      _client.onTrackEnded.listen((e) => _removeVideo(e.producerId)),
      _client.onMessage.listen((m) => setState(() => _messages.add(m))),
      _client.onClosed.listen((reason) {
        if (mounted) setState(() => _status = 'Room closed (${reason.name})');
      }),
    ]);

    try {
      // 3. Join the room.
      final join = await _client.connect();
      if (!mounted) return;
      setState(() => _status = 'In ${widget.ticket.room} as ${join.identity}');

      // 4. Publish camera + microphone if this role may speak.
      if (join.role.canPublish) await _publish();
    } on RpcError catch (e) {
      if (mounted) setState(() => _status = 'Could not join: ${e.message}');
    }
  }

  Future<void> _publish() async {
    final granted = await [Permission.camera, Permission.microphone].request();
    if (granted.values.any((s) => !s.isGranted)) {
      return setState(() => _status = 'Camera/microphone permission refused');
    }
    await _client.publish();
    _local.srcObject = _client.localStream;
    if (mounted) setState(() => _publishing = true);
  }

  // A remote video (or sound) arrived: video gets its own renderer; audio plays by itself.
  Future<void> _onTrack(RemoteTrack track) async {
    if (track.kind != 'video') return;
    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    renderer.srcObject = track.stream;
    if (!mounted) return renderer.dispose();
    setState(() => _remote[track.producerId] = (track, renderer));
  }

  void _removeVideo(String producerId) {
    final removed = _remote.remove(producerId);
    if (removed == null) return;
    removed.$2.srcObject = null;
    removed.$2.dispose();
    if (mounted) setState(() {});
  }

  Future<void> _toggleMic() async {
    await _client.setMicEnabled(!_micOn);
    setState(() => _micOn = !_micOn);
  }

  Future<void> _toggleCam() async {
    await _client.setCamEnabled(!_camOn);
    setState(() => _camOn = !_camOn);
  }

  Future<void> _sendChat() async {
    final text = _chatInput.text.trim();
    if (text.isEmpty) return;
    _chatInput.clear();
    try {
      await _client.sendMessage(text); // arrives back on onMessage, like everyone else's
    } on RpcError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  void dispose() {
    // 5. Leave: close() releases the camera, microphone and connection.
    for (final s in _subscriptions) {
      s.cancel();
    }
    _client.close();
    for (final (_, renderer) in _remote.values) {
      renderer.dispose();
    }
    _local.dispose();
    _chatInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tiles = [
      if (_publishing) _tile(RTCVideoView(_local, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover), 'You'),
      for (final (track, renderer) in _remote.values)
        _tile(RTCVideoView(renderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover), track.identity),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(widget.ticket.room)),
      body: Column(
        children: [
          Padding(padding: const EdgeInsets.all(8), child: Text(_status)),
          Expanded(
            flex: 3,
            child: tiles.isEmpty
                ? const Center(child: Text('Waiting for video…'))
                : GridView.count(crossAxisCount: tiles.length == 1 ? 1 : 2, padding: const EdgeInsets.all(8), mainAxisSpacing: 8, crossAxisSpacing: 8, children: tiles),
          ),
          if (_publishing)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(onPressed: _toggleMic, icon: Icon(_micOn ? Icons.mic : Icons.mic_off), tooltip: 'Microphone'),
                IconButton.filledTonal(onPressed: _toggleCam, icon: Icon(_camOn ? Icons.videocam : Icons.videocam_off), tooltip: 'Camera'),
                IconButton.filledTonal(onPressed: _client.switchCamera, icon: const Icon(Icons.cameraswitch), tooltip: 'Flip camera'),
              ],
            ),
          Expanded(
            flex: 2,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [for (final m in _messages) Text('${m.from}: ${m.text ?? ''}')],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(child: TextField(controller: _chatInput, decoration: const InputDecoration(hintText: 'Message'), onSubmitted: (_) => _sendChat())),
                  IconButton(onPressed: _sendChat, icon: const Icon(Icons.send)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(Widget video, String name) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Colors.black, child: video),
        Positioned(left: 8, bottom: 8, child: Text(name, style: const TextStyle(color: Colors.white))),
      ],
    ),
  );
}
