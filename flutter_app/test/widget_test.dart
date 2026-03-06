import 'package:flutter_test/flutter_test.dart';
import 'package:arab_news_reels/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ArabNewsApp());
    expect(find.byType(ArabNewsApp), findsOneWidget);
  });
}
