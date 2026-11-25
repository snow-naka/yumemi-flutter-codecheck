import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

abstract interface class UnexpectedErrorReporter {
  void report(Object error, StackTrace stackTrace);
}

final unexpectedErrorReporterProvider = Provider<UnexpectedErrorReporter>(
  (ref) => const DeveloperLogUnexpectedErrorReporter(),
);

// Debug専用の診断出力。例外本文やスタックトレースは出力しない。
final class DeveloperLogUnexpectedErrorReporter
    implements UnexpectedErrorReporter {
  const DeveloperLogUnexpectedErrorReporter();

  @override
  void report(Object error, StackTrace stackTrace) {
    if (!kDebugMode) return;

    developer.log(
      'Unexpected search error (details omitted)',
      name: 'yumemi.search',
    );
  }
}
