import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mojac/core/app_info.dart';

void main() {
  test('kAppVersion matches the pubspec version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(version, isNotNull, reason: 'pubspec.yaml has no version: line');
    expect(
      kAppVersion,
      version!.group(1),
      reason: 'lib/core/app_info.dart and pubspec.yaml must agree',
    );
  });
}
