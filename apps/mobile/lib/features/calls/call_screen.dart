import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/localization/strings.dart';

class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({
    super.key,
    required this.conversationId,
    this.video = false,
  });
  final String conversationId;
  final bool video;
  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  final localView = RTCVideoRenderer(), remoteView = RTCVideoRenderer();
  RTCPeerConnection? peer;
  MediaStream? stream;
  String? callId, error;
  bool muted = false;
  final pendingIce = <RTCIceCandidate>[];
  @override
  void initState() {
    super.initState();
    start();
  }

  Future<void> start() async {
    try {
      await ref.read(preferencesProvider.notifier).ready;
      if (!mounted) return;
      await localView.initialize();
      await remoteView.initialize();
      stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': widget.video,
      });
      muted = ref.read(preferencesProvider).startMuted;
      for (final track in stream!.getAudioTracks()) {
        track.enabled = !muted;
      }
      localView.srcObject = stream;
      peer = await createPeerConnection({
        'iceServers': [
          {
            'urls': const String.fromEnvironment(
              'STUN_URL',
              defaultValue: 'stun:stun.l.google.com:19302',
            ),
          },
          if (const String.fromEnvironment('TURN_URL').isNotEmpty)
            {
              'urls': const String.fromEnvironment('TURN_URL'),
              'username': const String.fromEnvironment('TURN_USERNAME'),
              'credential': const String.fromEnvironment('TURN_PASSWORD'),
            },
        ],
      });
      for (final track in stream!.getTracks()) {
        await peer!.addTrack(track, stream!);
      }
      peer!.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          remoteView.srcObject = event.streams.first;
          if (mounted) setState(() {});
        }
      };
      peer!.onIceCandidate = (candidate) {
        if (callId == null) {
          pendingIce.add(candidate);
        } else {
          signal('call:ice-candidate', jsonEncode(candidate.toMap()));
        }
      };
      final socket = ref.read(clientProvider).socket;
      if (socket == null || !socket.connected) {
        throw StateError('Realtime unavailable');
      }
      socket.on('call:answer', answer);
      socket.on('call:ice-candidate', ice);
      socket.on('call:end', ended);
      final offer = await peer!.createOffer();
      await peer!.setLocalDescription(offer);
      socket.emitWithAck(
        'call:offer',
        {
          'conversationId': widget.conversationId,
          'kind': widget.video ? 'VIDEO' : 'AUDIO',
          'data': jsonEncode(offer.toMap()),
        },
        ack: (result) {
          if (result['ok'] == true) {
            callId = result['data']['callId'];
            for (final candidate in pendingIce) {
              signal('call:ice-candidate', jsonEncode(candidate.toMap()));
            }
            pendingIce.clear();
          } else if (mounted) {
            setState(() => error = result['error']);
          }
        },
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => error = tr(context, 'networkError'));
    }
  }

  void signal(String event, String data) => ref
      .read(clientProvider)
      .socket
      ?.emitWithAck(event, {'callId': callId, 'data': data});
  void answer(dynamic data) async {
    if (data['callId'] != callId) return;
    final s = jsonDecode(data['data']);
    await peer?.setRemoteDescription(
      RTCSessionDescription(s['sdp'], s['type']),
    );
  }

  void ice(dynamic data) async {
    if (data['callId'] != callId) return;
    final c = jsonDecode(data['data']);
    await peer?.addCandidate(
      RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']),
    );
  }

  void ended(dynamic data) {
    if (data['callId'] == callId && mounted) context.pop();
  }

  @override
  void dispose() {
    final socket = ref.read(clientProvider).socket;
    socket?.off('call:answer', answer);
    socket?.off('call:ice-candidate', ice);
    socket?.off('call:end', ended);
    for (final track in stream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    stream?.dispose();
    peer?.close();
    localView.dispose();
    remoteView.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => QChatPage(
    title: tr(c, widget.video ? 'videoCall' : 'call'),
    child: Column(
      children: [
        Expanded(
          child: widget.video
              ? Stack(
                  children: [
                    RTCVideoView(remoteView),
                    Positioned(
                      right: 16,
                      top: 16,
                      width: 120,
                      height: 180,
                      child: RTCVideoView(localView, mirror: true),
                    ),
                  ],
                )
              : Center(child: Text(error ?? tr(c, 'calling'))),
        ),
        if (error != null) Text(error!),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              QChatButton(
                tr(c, 'mute'),
                secondary: true,
                onTap: () {
                  muted = !muted;
                  for (final t
                      in stream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
                    t.enabled = !muted;
                  }
                  setState(() {});
                },
              ),
              QChatButton(
                tr(c, 'endCall'),
                onTap: () {
                  if (callId != null) signal('call:end', '');
                  context.pop();
                },
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
