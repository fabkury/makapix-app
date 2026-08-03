// The "Open in Makapix" receiving end: the OS hands the app a document — a .mkps/.mkpx
// tapped in Files, AirDropped, or shared via "Copy to Makapix" — the native side buffers
// it, and this service drains the buffer over one MethodChannel and routes each file onto
// the existing cross-pillar bridges (club/state/edit_bridge.dart). The shell's provider
// listeners then switch pillars exactly as for in-app requests.
//
// Protocol (the native half: ios/Runner/IncomingFilesPlugin.swift; Android can join later
// with an ACTION_VIEW intent-filter feeding the same channel): the native side queues
// {name, bytes} payloads and nudges Dart with "filesPending"; Dart always pulls via
// "drainPendingFiles" — on the nudge and once on attach — so delivery never depends on
// timing (a cold-start file is queued before Flutter runs and caught by the attach drain).
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../club/state/edit_bridge.dart';

/// Classification of one incoming file by its extension. The native side already filters
/// to the document types the app registers for; this classifies defensively anyway.
enum IncomingFileKind { scene, drawing }

/// The [IncomingFileKind] for [name], or null when the extension is not one of ours.
IncomingFileKind? incomingFileKind(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return null;
  return switch (name.substring(dot + 1).toLowerCase()) {
    'mkps' => IncomingFileKind.scene,
    'mkpx' => IncomingFileKind.drawing,
    _ => null,
  };
}

/// [name] without its final extension — the incoming scene's title ("Bouncing ball.mkps"
/// → "Bouncing ball"); 'Untitled' when nothing usable remains.
String incomingFileTitle(String name) {
  final dot = name.lastIndexOf('.');
  final base = dot >= 0 ? name.substring(0, dot) : name;
  return base.isEmpty ? 'Untitled' : base;
}

/// Route one incoming file onto the matching cross-pillar bridge. Returns true when the
/// file was recognized and dispatched (the shell's listeners do the pillar switch).
bool dispatchIncomingFile(ProviderContainer container, String name, Uint8List bytes) {
  switch (incomingFileKind(name)) {
    case IncomingFileKind.scene:
      container.read(pendingAnimatorProvider.notifier).state =
          OpenSceneBytes(bytes, incomingFileTitle(name));
      return true;
    case IncomingFileKind.drawing:
      // The editor landing strips the extension itself (it shows the full filename in the
      // keep/discard prompt), so pass the name through untouched.
      container.read(pendingLocalLibraryProvider.notifier).state =
          OpenDrawingBytes(bytes, name);
      return true;
    case null:
      return false;
  }
}

/// The channel wiring. The shell attaches on mount and detaches on dispose. Platforms
/// without a native leg (Android, desktop, tests) have no handler behind the channel —
/// the drain swallows the resulting MissingPluginException.
class IncomingFiles {
  static const MethodChannel channel = MethodChannel('club.makapix.app/incoming_files');

  static Future<void> attach(void Function(String name, Uint8List bytes) onFile) async {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'filesPending') await _drain(onFile);
    });
    await _drain(onFile); // pick up anything queued before Flutter was up (cold start)
  }

  static void detach() => channel.setMethodCallHandler(null);

  static Future<void> _drain(void Function(String, Uint8List) onFile) async {
    List<Object?>? files;
    try {
      files = await channel.invokeMethod<List<Object?>>('drainPendingFiles');
    } on MissingPluginException {
      return; // no native leg on this platform
    }
    for (final f in files ?? const <Object?>[]) {
      if (f is! Map) continue;
      final name = f['name'], bytes = f['bytes'];
      if (name is String && bytes is Uint8List && bytes.isNotEmpty) onFile(name, bytes);
    }
  }
}
