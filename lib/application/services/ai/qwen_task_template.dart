import 'dart:convert';
import 'ai_conversation.dart';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// A deterministic correction for one checksum-pinned public model artifact.
/// Weights/tokenizer stay byte-for-byte unchanged. Unknown artifacts are refused.
class QwenTaskTemplate {
  static const originalHash =
      'e608953f169aeb1bd7b9155fec2559825e08453fc209b84eda3a781ed0452fd2';
  static const correctedHash =
      '0f83bfbaddb60b76d3c79e78815046a1f7ced46c0598b127277aed7f2f525bac';
  static const conversationHash =
      '492a48dc494c5741579af360ad6e43ba95a0498de9340d24e6dd2ff5181cd363';
  static const size = 546660344;
  static final _verified = <String, ({String signature, String hash})>{};
  static String _signature(FileStat stat) =>
      '${stat.modified.microsecondsSinceEpoch}:${stat.size}';

  /// Shares the service's completed checksum verification within this process.
  /// Same private-file stat signature policy as AIService's verification cache.
  static void rememberVerified(
    String path,
    FileStat stat,
    String sourceHash,
    String actualHash,
  ) {
    if (stat.size == size &&
        sourceHash == originalHash &&
        accepts(sourceHash, actualHash)) {
      _verified[path] = (signature: _signature(stat), hash: actualHash);
    }
  }

  static bool accepts(String sourceHash, String actualHash) =>
      actualHash == sourceHash ||
      sourceHash == originalHash &&
          {correctedHash, conversationHash}.contains(actualHash);

  static Uint8List correctedMetadata() {
    const prefix =
        '<|im_start|>system\nYou are Qwen, created by Alibaba Cloud. You are a helpful assistant.<|im_end|>\n<|im_start|>user\n';
    const suffix = '<|im_end|>\n<|im_start|>assistant\n';
    final p = utf8.encode(prefix), s = utf8.encode(suffix);
    final nested = [0x12, p.length, ...p, 0x1a, s.length, ...s];
    return Uint8List.fromList([
      0x2a, 10, ...utf8.encode('<|im_end|>'),
      0x32, 13, ...utf8.encode('<|endoftext|>'),
      0x42, (nested.length & 127) | 128, nested.length >> 7, ...nested,
      // Unknown protobuf field 127 pads to the original 187 bytes. This keeps
      // ZIP offsets and model weights unchanged; protobuf readers ignore it.
      0xfa, 0x07, 2, 0, 0,
    ]);
  }

  static Uint8List conversationMetadata() {
    final prefix = utf8.encode(AiConversation.nativePrefix);
    final suffix = utf8.encode(AiConversation.nativeSuffix);
    final nested = [
      0x12,
      prefix.length,
      ...prefix,
      0x1a,
      suffix.length,
      ...suffix,
    ];
    return Uint8List.fromList([
      0x2a,
      10,
      ...utf8.encode('<|im_end|>'),
      0x32,
      13,
      ...utf8.encode('<|endoftext|>'),
      0x42,
      nested.length,
      ...nested,
      0xfa,
      0x07,
      99,
      ...List<int>.filled(99, 0),
    ]);
  }

  static Future<String> prepare(String source, String fallbackDirectory) async {
    final stat = await File(source).stat();
    final cached = _verified[source];
    final trusted = cached?.signature == _signature(stat) ? cached?.hash : null;
    if (trusted == conversationHash) return source;
    final prepared = await Isolate.run(
      () => _prepareFile(source, fallbackDirectory, trusted),
    );
    _verified[prepared] = (
      signature: _signature(await File(prepared).stat()),
      hash: conversationHash,
    );
    return prepared;
  }

  static Future<String> _hash(File file) async =>
      (await file.openRead().transform(sha256).first).toString();

  /// Public for the reproducible file-migration test; no platform APIs needed.
  static Future<String> prepareFile(String source, String fallbackDirectory) =>
      _prepareFile(source, fallbackDirectory, null);

  static Future<String> _prepareFile(
    String source,
    String fallbackDirectory,
    String? verifiedHash,
  ) async {
    final input = File(source);
    if (await input.length() != size) {
      throw const FormatException('Unexpected Qwen model size');
    }
    final hash = verifiedHash ?? await _hash(input);
    if (hash == conversationHash) return source;
    if (!{originalHash, correctedHash}.contains(hash)) {
      throw const FormatException('Unverified Qwen model');
    }
    var destination = input;
    var temporary = File('$source.template-tmp');
    try {
      final probe = await temporary.open(mode: FileMode.write);
      await probe.close();
    } on FileSystemException {
      // Play asset packs are read-only. Keep their original file intact and
      // place the verified runtime copy in application support storage.
      await Directory(fallbackDirectory).create(recursive: true);
      destination = File('$fallbackDirectory/qwen-template-v2.task');
      if (await destination.exists() &&
          await _hash(destination) == conversationHash) {
        return destination.path;
      }
      temporary = File('${destination.path}.tmp');
    }
    try {
      // Stream rather than loading 547 MB into Dart's heap.
      final sink = temporary.openWrite();
      try {
        await sink.addStream(input.openRead());
        await sink.flush();
      } finally {
        await sink.close();
      }
      final output = await temporary.open(mode: FileMode.append);
      try {
        final metadata = conversationMetadata();
        if (metadata.length != 187) {
          throw StateError('Unexpected template length');
        }
        final crc = ByteData(4)..setUint32(0, 158979818, Endian.little);
        for (final offset in [546659928, 546660284]) {
          await output.setPosition(offset);
          await output.writeFrom(crc.buffer.asUint8List());
        }
        await output.setPosition(546659952);
        await output.writeFrom(metadata);
        await output.flush();
      } finally {
        await output.close();
      }
      if (await _hash(temporary) != conversationHash) {
        throw StateError('Corrected model verification failed');
      }
      // Same-directory atomic replacement: failure never deletes the source.
      await temporary.rename(destination.path);
      return destination.path;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
