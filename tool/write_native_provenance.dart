import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('Usage: write_native_provenance.dart <output> key=value...');
    exitCode = 64;
    return;
  }

  final data = <String, String>{};
  for (final argument in args.skip(1)) {
    final separator = argument.indexOf('=');
    if (separator <= 0) {
      stderr.writeln('Expected key=value, got: $argument');
      exitCode = 64;
      return;
    }
    data[argument.substring(0, separator)] = argument.substring(separator + 1);
  }
  File(
    args.first,
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
}
