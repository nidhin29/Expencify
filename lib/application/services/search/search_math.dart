import 'dart:math';
import 'package:diacritic/diacritic.dart';

/// BERT uncased basic tokenizer followed by greedy WordPiece (MiniLM vocabulary).
class WordPieceTokenizer {
  final Map<String, int> vocabulary;
  WordPieceTokenizer(String vocab)
    : vocabulary = {
        for (final entry in vocab.trimRight().split('\n').asMap().entries)
          entry.value.trimRight(): entry.key,
      };
  List<int> encode(String text, {int maxLength = 256}) {
    if (maxLength < 2 || maxLength > 256) {
      throw ArgumentError('Invalid token limit');
    }
    if (text.length > 4096) text = text.substring(0, 4096);
    final ids = <int>[vocabulary['[CLS]']!];
    final clean = removeDiacritics(
      text.toLowerCase(),
    ).replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F\uFFFD]'), '');
    final tokens = RegExp(
      r'[\u4E00-\u9FFF]|[^\s\p{L}\p{N}]|[\p{L}\p{N}]+',
      unicode: true,
    ).allMatches(clean);
    for (final match in tokens) {
      final word = match.group(0)!;
      if (word.length > 100) {
        ids.add(vocabulary['[UNK]']!);
      } else {
        var start = 0;
        final pieces = <int>[];
        var unknown = false;
        while (start < word.length) {
          var end = word.length;
          int? found;
          while (start < end) {
            found =
                vocabulary['${start == 0 ? '' : '##'}${word.substring(start, end)}'];
            if (found != null) break;
            end--;
          }
          if (found == null) {
            unknown = true;
            break;
          }
          pieces.add(found);
          start = end;
        }
        ids.addAll(unknown ? [vocabulary['[UNK]']!] : pieces);
      }
      if (ids.length >= maxLength - 1) break;
    }
    return [...ids.take(maxLength - 1), vocabulary['[SEP]']!];
  }
}

List<double> meanPool(List<dynamic> flattened, int tokens, int dimensions) {
  if (tokens <= 0 ||
      dimensions <= 0 ||
      flattened.length != tokens * dimensions) {
    throw const FormatException('Unexpected embedding output shape');
  }
  final result = List<double>.filled(dimensions, 0);
  for (var t = 0; t < tokens; t++) {
    for (var d = 0; d < dimensions; d++) {
      result[d] += (flattened[t * dimensions + d] as num).toDouble() / tokens;
    }
  }
  final norm = sqrt(result.fold<double>(0, (s, v) => s + v * v));
  if (!norm.isFinite || norm == 0) {
    throw const FormatException('Invalid embedding');
  }
  return result.map((v) => v / norm).toList();
}

double cosine(List<double> a, List<double> b) {
  if (a.isEmpty || a.length != b.length) return -1;
  var dot = 0.0, aa = 0.0, bb = 0.0;
  for (var i = 0; i < a.length; i++) {
    if (!a[i].isFinite || !b[i].isFinite) return -1;
    dot += a[i] * b[i];
    aa += a[i] * a[i];
    bb += b[i] * b[i];
  }
  if ((aa - 1).abs() > .02 || (bb - 1).abs() > .02) return -1;
  return dot.clamp(-1.0, 1.0);
}

/// Rank fusion preserves exact lexical matches without comparing unlike scores.
List<int> reciprocalRankFusion(List<int> lexical, List<int> semantic) {
  final scores = <int, double>{};
  for (final ranking in [lexical, semantic]) {
    for (var i = 0; i < ranking.length; i++) {
      scores.update(
        ranking[i],
        (s) => s + 1 / (60 + i + 1),
        ifAbsent: () => 1 / (60 + i + 1),
      );
    }
  }
  return scores.keys.toList()..sort((a, b) => scores[b]!.compareTo(scores[a]!));
}

List<String> searchTokens(String text) =>
    RegExp(r'[\p{L}\p{N}]+', unicode: true)
        .allMatches(removeDiacritics(text.toLowerCase()))
        .map((m) => m.group(0)!)
        .toList();

/// BM25 for a bounded local result set. No optional SQLite extensions required.
List<int> lexicalRanking(Map<int, String> documents, String query) {
  final queryTokens = searchTokens(query).toSet();
  final words = documents.map((id, text) => MapEntry(id, searchTokens(text)));
  if (words.isEmpty) return [];
  final average = max(
    1.0,
    words.values.fold<int>(0, (s, v) => s + v.length) / words.length,
  );
  final frequencies = {
    for (final token in queryTokens)
      token: words.values.where((w) => w.contains(token)).length,
  };
  final scores = <int, double>{};
  for (final doc in words.entries) {
    var score = 0.0;
    for (final token in queryTokens) {
      final tf = doc.value.where((w) => w == token).length;
      if (tf == 0) continue;
      final df = frequencies[token]!;
      final idf = log(1 + (words.length - df + .5) / (df + .5));
      score +=
          idf *
          tf *
          2.2 /
          (tf + 1.2 * (.25 + .75 * doc.value.length / average));
    }
    if (score > 0) scores[doc.key] = score;
  }
  return scores.keys.toList()..sort((a, b) => scores[b]!.compareTo(scores[a]!));
}
