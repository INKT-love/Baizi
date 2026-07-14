import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../utils/app_directories.dart';

class RequestLogger {
  RequestLogger._();

  static const String redactedValue = '<redacted>';
  static const Set<String> _sensitiveKeys = <String>{
    'authorization',
    'proxyauthorization',
    'xapikey',
    'apikey',
    'accesskey',
    'accesskeyid',
    'secretaccesskey',
    'token',
    'accesstoken',
    'refreshtoken',
    'authtoken',
    'bearertoken',
    'idtoken',
    'sessiontoken',
    'apitoken',
    'clientsecret',
    'password',
    'passwd',
    'secret',
    'apisecret',
    'secretkey',
    'privatekey',
    'credential',
    'credentials',
    'clientkey',
    'setcookie',
    'cookie',
  };
  static const String _sensitiveTextKeyPattern =
      r'(?:(?:x[._\-\s]?)?(?:api[._\-\s]?key|access[._\-\s]?key(?:[._\-\s]?id)?|access[._\-\s]?token|refresh[._\-\s]?token|auth[._\-\s]?token|bearer[._\-\s]?token|id[._\-\s]?token|session[._\-\s]?token|api[._\-\s]?token|client[._\-\s]?secret|client[._\-\s]?key)|authorization|proxy[._\-\s]?authorization|token|password|passwd|secret[._\-\s]?access[._\-\s]?key|secret[._\-\s]?key|secret|api[._\-\s]?secret|private[._\-\s]?key|credentials?|set[._\-\s]?cookie|cookie)';
  static final RegExp _bearerCredentialPattern = RegExp(
    r'Bearer\s+[A-Za-z0-9._~+/=-]+',
    caseSensitive: false,
  );
  static final RegExp _doubleQuotedSensitiveValuePattern = RegExp(
    '''((?:"|')?$_sensitiveTextKeyPattern(?:"|')?\\s*[:=]\\s*")([^"\\r\\n]*)(")''',
    caseSensitive: false,
  );
  static final RegExp _singleQuotedSensitiveValuePattern = RegExp(
    '''((?:"|')?$_sensitiveTextKeyPattern(?:"|')?\\s*[:=]\\s*')([^'\\r\\n]*)(')''',
    caseSensitive: false,
  );
  static final RegExp _unquotedSensitiveValuePattern = RegExp(
    '''(($_sensitiveTextKeyPattern)\\s*[:=]\\s*)([^"'\\s,;&?}\\]\\r\\n][^,;&?}\\]\\r\\n]*)''',
    caseSensitive: false,
  );

  static bool _enabled = false;
  static bool get enabled => _enabled;
  static bool _writeErrorReported = false;

  static bool saveOutput = true;

  static int _nextRequestId = 0;
  static int nextRequestId() => ++_nextRequestId;

  static Future<void> setEnabled(bool v) async {
    if (_enabled == v) return;
    _enabled = v;
    if (!v) {
      try {
        await _sink?.flush();
      } catch (_) {}
      try {
        await _sink?.close();
      } catch (_) {}
      _sink = null;
      _sinkDate = null;
    } else {
      _writeErrorReported = false;
    }
  }

  static IOSink? _sink;
  static DateTime? _sinkDate;
  static Future<void> _writeQueue = Future<void>.value();

  static String _two(int v) => v.toString().padLeft(2, '0');
  static DateTime _dayOf(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
  static String _formatDate(DateTime dt) =>
      '${dt.year}-${_two(dt.month)}-${_two(dt.day)}';
  static String _formatTs(DateTime dt) {
    return '${_formatDate(dt)} ${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}.${dt.millisecond.toString().padLeft(3, '0')}';
  }

  static Future<IOSink> _ensureSink() async {
    final now = DateTime.now();
    final today = _dayOf(now);
    if (_sink != null && _sinkDate == today) return _sink!;

    try {
      await _sink?.flush();
    } catch (_) {}
    try {
      await _sink?.close();
    } catch (_) {}
    _sink = null;
    _sinkDate = today;

    final dir = await AppDirectories.getAppDataDirectory();
    final logsDir = Directory('${dir.path}/logs');
    if (!await logsDir.exists()) {
      await logsDir.create(recursive: true);
    }

    final active = File('${logsDir.path}/logs.txt');
    if (await active.exists()) {
      try {
        final stat = await active.stat();
        final fileDay = _dayOf(stat.modified.toLocal());
        if (fileDay != today) {
          final suffix = _formatDate(fileDay);
          var rotated = File('${logsDir.path}/logs_$suffix.txt');
          if (await rotated.exists()) {
            int i = 1;
            while (await File(
              '${logsDir.path}/logs_${suffix}_$i.txt',
            ).exists()) {
              i++;
            }
            rotated = File('${logsDir.path}/logs_${suffix}_$i.txt');
          }
          await active.rename(rotated.path);
        }
      } catch (_) {}
    }

    _sink = active.openWrite(mode: FileMode.append);
    return _sink!;
  }

  static void logLine(String line) {
    if (!_enabled) return;
    final now = DateTime.now();
    final text = '[${_formatTs(now)}] ${redactText(line)}\n';
    _writeQueue = _writeQueue.then((_) async {
      if (!_enabled) return;
      try {
        final sink = await _ensureSink();
        sink.write(text);
        await sink.flush();
      } catch (_) {
        try {
          await _sink?.flush();
        } catch (_) {}
        try {
          await _sink?.close();
        } catch (_) {}
        _sink = null;
        _sinkDate = null;
        if (!_writeErrorReported) {
          _writeErrorReported = true;
          try {
            stderr.writeln(
              '[RequestLogger] write failed; further write errors will be suppressed.',
            );
          } catch (_) {}
        }
      }
    });
  }

  static String encodeObject(Object? obj) {
    try {
      return const JsonEncoder.withIndent('  ').convert(_redactValue(obj));
    } catch (_) {
      return redactText(obj?.toString() ?? '');
    }
  }

  static String redactBody(String input) {
    try {
      return encodeObject(jsonDecode(input));
    } catch (_) {
      return redactText(input);
    }
  }

  static String redactText(String input) {
    var redacted = input.replaceAllMapped(
      _bearerCredentialPattern,
      (_) => 'Bearer $redactedValue',
    );
    redacted = redacted.replaceAllMapped(
      _doubleQuotedSensitiveValuePattern,
      (match) => '${match[1]}$redactedValue${match[3]}',
    );
    redacted = redacted.replaceAllMapped(
      _singleQuotedSensitiveValuePattern,
      (match) => '${match[1]}$redactedValue${match[3]}',
    );
    return redacted.replaceAllMapped(
      _unquotedSensitiveValuePattern,
      (match) => '${match[1]}$redactedValue',
    );
  }

  static Object? _redactValue(Object? value, {String? key}) {
    if (key != null && _isSensitiveKey(key)) return redactedValue;
    if (value is Map) {
      return value.map(
        (mapKey, mapValue) => MapEntry(
          mapKey.toString(),
          _redactValue(mapValue, key: mapKey.toString()),
        ),
      );
    }
    if (value is Iterable) {
      return value.map((item) => _redactValue(item)).toList();
    }
    if (value is String) return redactText(value);
    return value;
  }

  static bool _isSensitiveKey(String key) {
    final normalized = key.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    if (_sensitiveKeys.contains(normalized)) return true;
    return normalized.endsWith('apikey') ||
        normalized.endsWith('password') ||
        normalized.endsWith('token') ||
        normalized.endsWith('clientsecret') ||
        normalized.endsWith('apisecret') ||
        normalized.endsWith('secretkey') ||
        normalized.endsWith('privatekey') ||
        normalized.endsWith('credential') ||
        normalized.endsWith('credentials') ||
        normalized.endsWith('clientkey') ||
        normalized.endsWith('accesskey') ||
        normalized.endsWith('accesskeyid') ||
        normalized.endsWith('secret');
  }

  static String safeDecodeUtf8(List<int> bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  static String escape(String input) {
    return input
        .replaceAll('\\', r'\\')
        .replaceAll('\r', r'\r')
        .replaceAll('\n', r'\n')
        .replaceAll('\t', r'\t');
  }

  static Future<void> cleanupLogs({
    required int autoDeleteDays,
    required int maxSizeMB,
  }) async {
    try {
      final dir = await AppDirectories.getAppDataDirectory();
      final logsDir = Directory('${dir.path}/logs');
      if (!await logsDir.exists()) return;

      final files = await logsDir
          .list()
          .where((e) => e is File && e.path.toLowerCase().endsWith('.txt'))
          .cast<File>()
          .toList();
      if (files.isEmpty) return;

      // Auto-delete old files
      if (autoDeleteDays > 0) {
        final cutoff = DateTime.now().subtract(Duration(days: autoDeleteDays));
        for (final f in List<File>.from(files)) {
          try {
            final stat = await f.stat();
            if (stat.modified.isBefore(cutoff)) {
              await f.delete();
              files.remove(f);
            }
          } catch (_) {}
        }
      }

      // Enforce max size
      if (maxSizeMB > 0 && files.isNotEmpty) {
        final maxBytes = maxSizeMB * 1024 * 1024;
        final statMap = <File, FileStat>{};
        int totalSize = 0;
        for (final f in files) {
          try {
            final s = await f.stat();
            statMap[f] = s;
            totalSize += s.size;
          } catch (_) {}
        }
        if (totalSize > maxBytes) {
          // Sort oldest first
          final sorted = statMap.entries.toList()
            ..sort((a, b) => a.value.modified.compareTo(b.value.modified));
          for (final entry in sorted) {
            if (totalSize <= maxBytes) break;
            try {
              totalSize -= entry.value.size;
              await entry.key.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }
}

class RedactingResponseLogBuffer {
  RedactingResponseLogBuffer({
    required this.eventStream,
    this.maxPendingCharacters = 64 * 1024,
  });

  final bool eventStream;
  final int maxPendingCharacters;

  String _pending = '';
  bool _suppressed = false;

  List<String> add(String text) {
    if (_suppressed || text.isEmpty) return const <String>[];
    _pending += text;
    final output = eventStream ? _drainEvents() : <String>[];
    if (_pending.length > maxPendingCharacters) {
      _pending = '';
      _suppressed = true;
      output.add('<response body omitted: log buffer limit exceeded>');
    }
    return output;
  }

  List<String> close() {
    if (_suppressed || _pending.isEmpty) return const <String>[];
    final pending = _pending;
    _pending = '';
    return <String>[RequestLogger.redactBody(pending)];
  }

  List<String> _drainEvents() {
    final output = <String>[];
    while (true) {
      final lfIndex = _pending.indexOf('\n\n');
      final crlfIndex = _pending.indexOf('\r\n\r\n');
      if (lfIndex == -1 && crlfIndex == -1) break;

      final useCrlf = crlfIndex != -1 && (lfIndex == -1 || crlfIndex < lfIndex);
      final eventEnd = useCrlf ? crlfIndex + 4 : lfIndex + 2;
      final event = _pending.substring(0, eventEnd);
      _pending = _pending.substring(eventEnd);
      output.add(RequestLogger.redactBody(event));
    }
    return output;
  }
}
