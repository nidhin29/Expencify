import 'dart:io';
import 'model_file_hash.dart';
import 'package:dio/dio.dart';
import 'local_ai_model.dart';

/// Import a user-selected official artifact without replacing a good file with
/// an incomplete or unrelated model. Copy by stream, never into the Dart heap.
Future<void> importVerifiedModel({
  required File source,
  required File destination,
  required LocalAIModelMetadata metadata,
}) async {
  if (await source.length() != metadata.expectedSize) {
    throw const FormatException('This is not the supported model file.');
  }
  final partial = File('${destination.path}.import.tmp');
  try {
    final sink = partial.openWrite();
    try {
      await sink.addStream(source.openRead());
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (await partial.length() != metadata.expectedSize ||
        await ModelFileHash.sha256File(partial.path) != metadata.sha256Hash) {
      throw const FormatException('Model checksum verification failed.');
    }
    await partial.rename(destination.path);
  } finally {
    if (await partial.exists()) await partial.delete();
  }
}

Future<void> downloadVerifiedModel({
  required LocalAIModelMetadata metadata,
  required File partial,
  required File destination,
  required void Function(double) onProgress,
  CancelToken? cancelToken,
  Dio? client,
}) async {
  return downloadVerifiedFile(
    url: metadata.url,
    expectedSize: metadata.expectedSize,
    sha256Hash: metadata.sha256Hash,
    partial: partial,
    destination: destination,
    onProgress: onProgress,
    cancelToken: cancelToken,
    client: client,
  );
}

Future<void> downloadVerifiedFile({
  required String url,
  required int expectedSize,
  required String sha256Hash,
  required File partial,
  required File destination,
  required void Function(double) onProgress,
  CancelToken? cancelToken,
  Dio? client,
}) async {
  var existing = await partial.exists() ? await partial.length() : 0;
  if (existing >= expectedSize) {
    if (existing == expectedSize &&
        await ModelFileHash.sha256File(partial.path) == sha256Hash) {
      await partial.rename(destination.path);
      onProgress(1);
      return;
    }
    await partial.writeAsBytes([]);
    existing = 0;
  }
  final dio = client ?? Dio();
  RandomAccessFile? output;
  try {
    final response = await dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        headers: existing > 0 ? {'range': 'bytes=$existing-'} : null,
        validateStatus: (status) => status == 200 || status == 206,
      ),
      cancelToken: cancelToken,
    );
    final range = response.headers.value('content-range');
    final match = range == null
        ? null
        : RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(range);
    final resumed = response.statusCode == 206;
    if (resumed &&
        (match == null ||
            int.parse(match.group(1)!) != existing ||
            int.parse(match.group(3)!) != expectedSize ||
            int.parse(match.group(2)!) != expectedSize - 1)) {
      throw const FormatException('Invalid model resume response.');
    }
    if (!resumed) existing = 0;
    final length = int.tryParse(response.headers.value('content-length') ?? '');
    if (length != null && length != expectedSize - existing) {
      throw const FormatException('Unexpected model download size.');
    }
    output = await partial.open(
      mode: resumed ? FileMode.append : FileMode.write,
    );
    var downloaded = existing;
    await for (final chunk in response.data!.stream) {
      if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
      downloaded += chunk.length;
      if (downloaded > expectedSize) {
        throw const FormatException('Model download is too large.');
      }
      await output.writeFrom(chunk);
      onProgress(downloaded / expectedSize);
    }
    await output.close();
    output = null;
    if (downloaded != expectedSize) {
      throw const FormatException(
        'Incomplete model download; retry to resume.',
      );
    }
    if (await ModelFileHash.sha256File(partial.path) != sha256Hash) {
      await partial.writeAsBytes([]);
      throw const FormatException('Model checksum verification failed.');
    }
    await partial.rename(destination.path);
  } finally {
    await output?.close();
    if (client == null) dio.close();
  }
}
