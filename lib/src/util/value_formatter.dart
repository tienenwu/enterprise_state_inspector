import 'dart:convert';

String describeValue(Object? value, {int maxChars = 120}) {
  if (value == null) {
    return 'null';
  }
  try {
    String text;
    if (value is Map || value is Iterable) {
      text = const JsonEncoder().convert(value);
    } else if (value is DateTime) {
      text = value.toIso8601String();
    } else if (value is Enum) {
      text = value.name;
    } else {
      text = value.toString();
    }
    if (text.length > maxChars) {
      text = '${text.substring(0, maxChars)}…';
    }
    return text;
  } catch (error) {
    return '<format error: $error>';
  }
}

String prettyPrintValue(Object? value) {
  if (value == null) {
    return 'null';
  }
  try {
    if (value is Map || value is Iterable) {
      return const JsonEncoder.withIndent('  ').convert(value);
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is Enum) {
      return value.name;
    }
    return value.toString();
  } catch (error) {
    return '<format error: $error>';
  }
}

String describeError(Object error, StackTrace stackTrace, {int maxChars = 200}) {
  final message = '$error\n$stackTrace';
  if (message.length <= maxChars) {
    return message;
  }
  return '${message.substring(0, maxChars)}…';
}
