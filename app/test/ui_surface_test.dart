import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/theme/granmap_theme.dart';
import 'package:granmap/widgets/granmap_ui.dart';

void main() {
  testWidgets('GranMapSurface preserva tinta e interação de ListTile', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: GranMapTheme.dark,
        home: Scaffold(
          body: GranMapSurface(
            child: ListTile(
              title: const Text('Minha grade'),
              onTap: () => tapped = true,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Minha grade'));
    await tester.pump();

    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });
}
