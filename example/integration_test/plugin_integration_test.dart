import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_youtube_player_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('starts on the episode list', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('新闻视频'), findsOneWidget);
  });
}
