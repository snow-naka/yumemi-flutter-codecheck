import 'dart:developer' as developer;

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
    developer.log(
      'Unexpected search error',
      name: 'yumemi.search.spike',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
