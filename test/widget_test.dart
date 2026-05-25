// test/widget_test.dart
//
// Smoke test del módulo Handshake.
// Verifica que la HandshakePage renderiza correctamente en estado Idle.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/app.dart';

void main() {
  testWidgets(
    'HandshakePage — muestra el formulario de vinculación en estado Idle',
    (WidgetTester tester) async {
      await tester.pumpWidget(const ProviderScope(child: DevUbiApp()));

      // Dar tiempo al GoRouter para resolver la ruta inicial
      await tester.pumpAndSettle();

      // Verificar elementos clave de la UI en estado Idle
      expect(find.text('DevUbi / Warey'), findsOneWidget);
      expect(find.text('Vincular dispositivo'), findsOneWidget);
    },
  );
}
