import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skykeep/screens/channels.dart';
import 'package:skykeep/theme.dart';

import 'fakes.dart';

void main() {
  testWidgets('create channel: button always tappable, name required, rest optional', (t) async {
    await pumpApp(t, FakeApi(), const ChannelForm());
    expect(find.text('Create channel'), findsWidgets);
    expect(find.text('Description (optional)'), findsOneWidget);
    expect(find.text('Category (optional)'), findsOneWidget);
    expect(find.text('Tags (optional, comma separated)'), findsOneWidget);

    await t.ensureVisible(find.widgetWithText(GradientButton, 'Create channel'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(GradientButton, 'Create channel'));
    await t.pump();
    expect(find.text('Enter a channel name (at least 2 characters)', skipOffstage: false), findsOneWidget);

    await t.enterText(find.widgetWithText(TextField, 'Channel name'), 'Cooking');
    await t.pump();
    expect(find.text('Enter a channel name (at least 2 characters)'), findsNothing);
  });
}
