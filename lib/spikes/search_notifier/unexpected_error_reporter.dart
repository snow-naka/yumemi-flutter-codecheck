import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class UnexpectedErrorReporter {
  void report(Object error, StackTrace stackTrace);
}

final unexpectedErrorReporterProvider = Provider<UnexpectedErrorReporter>(
  (ref) => const DeveloperLogUnexpectedErrorReporter(),
);

// 比較試作用の診断出力
final class DeveloperLogUnexpectedErrorReporter
    implements UnexpectedErrorReporter {
  const DeveloperLogUnexpectedErrorReporter();

  @override
  void report(Object error, StackTrace stackTrace) {
    if (!kDebugMode) return;

    developer.log(
      'Unexpected search error (details omitted)',
      name: 'yumemi.search.spike',
    );
  }
}
