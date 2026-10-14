import 'dart:convert';
import 'package:crypto/crypto.dart';

typedef Obj = Map<String, dynamic>;
Obj obj(dynamic x) {
  if (x is! Map<String, dynamic>) throw const FormatException('Expected an object.');
  return x;
}
List<Obj> objects(dynamic x) => (x as List).map(obj).toList();
int integer(dynamic x, [int min = 0, int max = 10000000]) {
  if (x is! int || x < min || x > max) throw const FormatException('Invalid integer amount.');
  return x;
}
String string(dynamic x, [int max = 500]) {
  if (x is! String || x.length > max) throw const FormatException('Invalid text.');
  return x;
}
String canonical(dynamic x) {
  if (x == null || x is bool || x is int) return '$x';
  if (x is String) {
    final b = StringBuffer('"');
    for (final c in x.codeUnits) {
      switch (c) {
        case 34: b.write(r'\"');
        case 92: b.write(r'\\');
        case 10: b.write(r'\n');
        case 13: b.write(r'\r');
        case 9: b.write(r'\t');
        default: b.write(c < 32 ? '\\u${c.toRadixString(16).padLeft(4, '0')}' : String.fromCharCode(c));
      }
    }
    return '${b.toString()}"';
  }
  if (x is List) return '[${x.map(canonical).join(',')}]';
  final m = obj(x), keys = m.keys.toList()..sort();
  return '{${keys.map((k) => '${canonical(k)}:${canonical(m[k])}').join(',')}}';
}
String digest(dynamic x) => sha256.convert(utf8.encode(canonical(x))).toString();
String bytesHash(List<int> x) => sha256.convert(x).toString();
Obj clone(Obj x) => obj(jsonDecode(jsonEncode(x)));
int cents(String text) {
  final m = RegExp(r'^([0-9]+)(?:\.([0-9]{1,2}))?$').firstMatch(text.trim());
  if (m == null) throw const FormatException('Enter an AUD amount with at most two decimal places.');
  return integer(int.parse(m[1]!) * 100 + int.parse((m[2] ?? '').padRight(2, '0')));
}
String money(int n) => '${n < 0 ? '−' : ''}\$${n.abs() ~/ 100}.${(n.abs() % 100).toString().padLeft(2, '0')}';
String amount(int n) => '${n ~/ 100}.${(n % 100).toString().padLeft(2, '0')}';
int? time(dynamic x) => x == null ? null : x is int ? integer(x, 946684800000, 4102444800000) : DateTime.parse(x as String).millisecondsSinceEpoch;
String displayDate(int? n) => n == null ? 'Date unknown' : '${DateTime.fromMillisecondsSinceEpoch(n, isUtc: true).add(const Duration(hours: 8)).toIso8601String().substring(0, 16).replaceFirst('T', ' ')} Perth';

/// Reject duplicate object keys and noninteger JSON before accepting any backup.
dynamic strictJson(String text) {
  if (utf8.encode(text).length > 64 * 1024 * 1024) throw const FormatException('Backup exceeds 64 MB.');
  return _Parser(text).parse();
}
class _Parser {
  final String s; int i = 0;
  _Parser(this.s);
  Never bad() => throw FormatException('Invalid JSON near character $i.');
  void space() { while (i < s.length && ' \n\r\t'.contains(s[i])) { i++; } }
  bool eat(String c) { space(); if (i < s.length && s[i] == c) { i++; return true; } return false; }
  dynamic parse() { final x = value(0); space(); if (i != s.length) bad(); return x; }
  String text() {
    final start = i++;
    while (i < s.length) { final c = s[i++]; if (c == '"') return jsonDecode(s.substring(start, i)) as String; if (c == r'\') i++; }
    return bad();
  }
  dynamic value(int depth) {
    if (depth > 32) bad(); space(); if (i >= s.length) bad();
    if (s[i] == '"') return text();
    if (eat('{')) {
      final m = <String, dynamic>{}; if (eat('}')) return m;
      do { space(); if (i >= s.length || s[i] != '"') bad(); final key = text(); if (m.containsKey(key) || !eat(':')) bad(); m[key] = value(depth + 1); } while (eat(','));
      if (!eat('}')) bad(); return m;
    }
    if (eat('[')) { final a = <dynamic>[]; if (eat(']')) return a; do { if (a.length > 100100) bad(); a.add(value(depth + 1)); } while (eat(',')); if (!eat(']')) bad(); return a; }
    for (final word in ['true', 'false', 'null']) { if (s.startsWith(word, i)) { i += word.length; return word == 'null' ? null : word == 'true'; } }
    final m = RegExp(r'^-?(?:0|[1-9][0-9]*)').firstMatch(s.substring(i)); if (m == null) bad(); i += m![0]!.length; return int.parse(m[0]!);
  }
}

String csvCell(dynamic value) {
  var text=value?.toString() ?? '';
  if(value is String && RegExp(r'^\s*[=+@-]').hasMatch(text))text="'$text";
  return '"${text.replaceAll('"','""')}"';
}

/// Bound each SQLite row without splitting a UTF-16 surrogate pair in platform messages.
Iterable<String> stateChunks(String text) sync* {
  var start=0;
  while(start<text.length) {
    var end=start+131072<text.length?start+131072:text.length;
    if(end<text.length && text.codeUnitAt(end-1)>=0xd800 && text.codeUnitAt(end-1)<=0xdbff && text.codeUnitAt(end)>=0xdc00 && text.codeUnitAt(end)<=0xdfff)end--;
    yield text.substring(start,end);start=end;
  }
}
