import 'dart:convert';

/// Port of src/utils/streamParser.ts (which itself mirrors
/// api/stream_events.py). The chat transports carry the model's answer as
/// plain text, interleaved with out-of-band "process" events (tool calls,
/// reasoning tokens) framed as:
///
///   `\x01FDW\x01` + kind + `\x02` + json-payload + `\x03`
///
/// feed() must be called with every raw chunk in order -- a frame's start
/// sentinel, kind, or payload can each land in a different WebSocket
/// message, so partial frames are buffered across calls exactly like the
/// TS version does.
class ProcessEvent {
  final String kind;
  final Map<String, dynamic> payload;
  const ProcessEvent(this.kind, this.payload);
}

class StreamFeedResult {
  final String text;
  final List<ProcessEvent> events;
  const StreamFeedResult(this.text, this.events);
}

class StreamParser {
  static const _procIntro = '\x01FDW\x01';
  static const _procField = '\x02';
  static const _procEnd = '\x03';

  String _buffer = '';

  StreamFeedResult feed(String chunk) {
    _buffer += chunk;
    final textBuf = StringBuffer();
    final events = <ProcessEvent>[];

    while (true) {
      final introIdx = _buffer.indexOf(_procIntro);
      if (introIdx == -1) {
        final holdBack = _longestPartialSuffixOf(_procIntro, _buffer);
        textBuf.write(_buffer.substring(0, _buffer.length - holdBack));
        _buffer = _buffer.substring(_buffer.length - holdBack);
        break;
      }

      textBuf.write(_buffer.substring(0, introIdx));
      final rest = _buffer.substring(introIdx + _procIntro.length);

      final fieldIdx = rest.indexOf(_procField);
      if (fieldIdx == -1) {
        _buffer = _procIntro + rest;
        break;
      }
      final kind = rest.substring(0, fieldIdx);
      final afterField = rest.substring(fieldIdx + _procField.length);

      final endIdx = afterField.indexOf(_procEnd);
      if (endIdx == -1) {
        _buffer = _procIntro + kind + _procField + afterField;
        break;
      }

      final jsonPayload = afterField.substring(0, endIdx);
      try {
        events.add(ProcessEvent(kind, jsonDecode(jsonPayload) as Map<String, dynamic>));
      } catch (_) {
        // Malformed payload -- skip, matching the TS side's console.error-and-continue.
      }
      _buffer = afterField.substring(endIdx + _procEnd.length);
    }

    return StreamFeedResult(textBuf.toString(), events);
  }

  static int _longestPartialSuffixOf(String needle, String s) {
    final maxLen = s.length < needle.length - 1 ? s.length : needle.length - 1;
    for (var len = maxLen; len > 0; len--) {
      if (needle.startsWith(s.substring(s.length - len))) return len;
    }
    return 0;
  }
}
