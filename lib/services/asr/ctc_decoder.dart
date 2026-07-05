/// CTC greedy decoder and token-to-text mapping.
///
/// Implements the CTC greedy decoding algorithm (spec §4.3):
///   1. argmax per frame over the 1025-class log-probabilities
///   2. Collapse consecutive identical tokens
///   3. Drop blank tokens (id = 1024)
///   4. Map remaining token IDs to text via tokens.txt
///   5. Replace SentencePiece space marker ▁ (U+2581) with actual space
///
/// The tokens.txt file format is: "token_text id" per line.
/// Example lines:
///   `<unk>` 0
///   ة 1
///   ▁و 9
///   ▁ 10
///
/// The SentencePiece ▁ (U+2581) is the space prefix marker — when a
/// token starts with ▁, it means there's a word boundary (space)
/// before that token. We replace ▁ with a literal space in the
/// final output.
///
/// No external SentencePiece library is needed — we parse tokens.txt
/// directly for a simple ID→text mapping. This avoids adding a native
/// dependency and works identically on all platforms.
library;

import 'dart:typed_data';

/// CTC blank token ID (1024 SentencePiece BPE tokens + 1 blank).
const int ctcBlankId = 1024;

/// SentencePiece space marker (U+2581, LOWER ONE EIGHTH BLOCK).
const String _spaceMarker = '\u2581';

/// Unknown token text from tokens.txt (id 0).
const String _unkToken = '<unk>';

/// Token vocabulary loaded from tokens.txt.
///
/// Maps token ID → token text string.
/// Token IDs range from 0 to 1023 (1024 BPE tokens).
/// The CTC blank (1024) is NOT in tokens.txt — it's handled separately.
class TokenVocab {
  final List<String> _idToToken;

  TokenVocab._(this._idToToken);

  /// Parse tokens.txt content and build the vocabulary.
  ///
  /// Each line: "token_text id"
  /// The token text may contain spaces (it's the part before the last
  /// space-separated integer on the line).
  factory TokenVocab.fromTokensTxt(String content) {
    final lines = content.split('\n');
    // Find max ID to size the list
    int maxId = 0;
    final entries = <int, String>{};

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Find the last space — everything before is token text, after is ID
      final lastSpace = trimmed.lastIndexOf(' ');
      if (lastSpace < 0) continue;

      final tokenText = trimmed.substring(0, lastSpace);
      final idStr = trimmed.substring(lastSpace + 1);
      final id = int.tryParse(idStr);
      if (id == null) continue;

      entries[id] = tokenText;
      if (id > maxId) maxId = id;
    }

    // Build list indexed by ID
    final idToToken = List<String>.filled(maxId + 1, _unkToken);
    for (final entry in entries.entries) {
      idToToken[entry.key] = entry.value;
    }

    return TokenVocab._(idToToken);
  }

  /// Get the token text for a given ID.
  String idToToken(int id) {
    if (id < 0 || id >= _idToToken.length) return _unkToken;
    return _idToToken[id];
  }

  /// Number of tokens in the vocabulary (excluding blank).
  int get vocabSize => _idToToken.length;
}

/// CTC greedy decoder.
///
/// Performs frame-by-frame argmax, collapses consecutive duplicates,
/// and drops blank tokens. Returns a list of decoded token IDs.
///
/// [logprobs] — flat Float32List of shape [T × V] in row-major order,
///              where V = 1025 (1024 BPE tokens + 1 blank).
/// [tOut] — number of time frames (T).
/// [vocabSize] — number of classes (V = 1025).
/// [blankId] — CTC blank token ID (1024).
///
/// Returns: `List<int>` of decoded token IDs (non-blank, non-repeated).
List<int> ctcGreedyDecode(
  Float32List logprobs,
  int tOut,
  int vocabSize, {
  int blankId = ctcBlankId,
}) {
  final decoded = <int>[];
  int prev = blankId;

  for (int t = 0; t < tOut; t++) {
    final frameOffset = t * vocabSize;

    // argmax over vocab dimension
    int bestId = 0;
    double bestVal = logprobs[frameOffset];
    for (int v = 1; v < vocabSize; v++) {
      final val = logprobs[frameOffset + v];
      if (val > bestVal) {
        bestVal = val;
        bestId = v;
      }
    }

    // Collapse repeats + drop blanks
    if (bestId != prev && bestId != blankId) {
      decoded.add(bestId);
    }
    prev = bestId;
  }

  return decoded;
}

/// Convert decoded token IDs to final text string.
///
/// 1. Map each ID to its token text via the vocabulary.
/// 2. Join all token pieces.
/// 3. Replace SentencePiece ▁ (U+2581) with literal space.
/// 4. Collapse multiple consecutive spaces into one.
/// 5. Trim leading/trailing whitespace.
String decodeTokensToText(List<int> tokenIds, TokenVocab vocab) {
  final buffer = StringBuffer();

  for (final id in tokenIds) {
    final token = vocab.idToToken(id);
    buffer.write(token);
  }

  // Replace SentencePiece space marker with literal space
  var text = buffer.toString().replaceAll(_spaceMarker, ' ');

  // Collapse multiple spaces
  while (text.contains('  ')) {
    text = text.replaceAll('  ', ' ');
  }

  // Trim
  return text.trim();
}
