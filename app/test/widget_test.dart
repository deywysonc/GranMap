import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/main.dart';

void main() {
  testWidgets('GranMap monta a aplicação', (WidgetTester tester) async {
    await tester.pumpWidget(const GranMapApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
