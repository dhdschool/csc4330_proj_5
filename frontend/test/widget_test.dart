import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/main.dart';

void main() {
  testWidgets('starts on the login page', (WidgetTester tester) async {
    await tester.pumpWidget(const GradescopeUploaderApp());

    expect(find.text('Gradescope Uploader'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
  });

  testWidgets('login checks the form before calling the backend',
      (WidgetTester tester) async {
    await tester.pumpWidget(const GradescopeUploaderApp());

    await tester.tap(find.text('Log in'));
    await tester.pump();

    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
  });
}
