import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skykeep/screens/channels.dart';

import 'fakes.dart';

void main() {
  testWidgets('create channel: button always tappable, name required, rest optional', (t) async {
    await pumpApp(t, FakeApi(), const ChannelForm());
    expect(find.text('Create channel'), findsWidgets);
    expect(find.text('Description (optional)'), findsOneWidget);
    expect(find.text('Category (optional)'), findsOneWidget);
    expect(find.text('Tags (optional, comma separated)'), findsOneWidget);

    await t.tap(find.text('Create channel').last);
    await t.pump();
    expect(find.text('Enter a channel name (at least 2 characters)'), findsOneWidget);

    await t.enterText(find.widgetWithText(TextField, 'Channel name'), 'Cooking');
    await t.pump();
    expect(find.text('Enter a channel name (at least 2 characters)'), findsNothing);
  });
}
