# Flutter example

Join a VoltKit room, publish your camera and microphone, see everyone's video, mute, flip the camera, chat, and leave.
It uses [`voltkit_rtc`](https://pub.dev/packages/voltkit_rtc) from pub.dev.

## Run

```bash
flutter pub get
flutter run
```

Start a token server first (examples in Node, PHP, Go and Python are in the [VoltKit docs](https://voltkit.in)). In the app, enter its URL and app key, a room name and your name. Join
the same room from a second phone to see video both ways.

## The code

| File | What it shows |
| --- | --- |
| [`lib/token_api.dart`](lib/token_api.dart) | Asking your server for a room token. The token is never printed or stored. |
| [`lib/join_page.dart`](lib/join_page.dart) | The join form. The app key is kept in secure storage (Keystore / Keychain). |
| [`lib/room_page.dart`](lib/room_page.dart) | **The VoltKit part.** |

`room_page.dart` follows the steps every VoltKit app takes:

1. `StreamClient(wsUrl:, token:)` with what your server returned.
2. Listen to `onTrack`, `onTrackEnded`, `onMessage` and `onClosed` **before** connecting: people already in the room
   arrive during `connect()`.
3. `connect()` to join.
4. Ask for camera and microphone permission, then `publish()` if the role can publish (`join.role.canPublish`).
5. Show each remote video with an `RTCVideoRenderer` (`renderer.srcObject = track.stream`). Audio plays by itself.
6. Use `setMicEnabled`, `setCamEnabled`, `switchCamera` and `sendMessage` while in the room.
7. `close()` when leaving: it releases the camera, microphone and connection.
