import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yumemi_app/data/fake_github_repository_gateway.dart';
import 'package:yumemi_app/main.dart';
import 'package:yumemi_app/providers.dart';

void main() {
  testWidgets('external app scope supplies the Fake gateway', (tester) async {
    final fake = FakeGitHubRepositoryGateway(delay: Duration.zero);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [githubRepositoryGatewayProvider.overrideWithValue(fake)],
        child: const MyApp(),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold)),
    );
    expect(find.byType(ProviderScope), findsOneWidget);
    expect(container.read(githubRepositoryGatewayProvider), same(fake));
  });
}
