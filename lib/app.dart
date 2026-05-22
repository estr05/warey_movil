// lib/app.dart
//
// Widget raíz de la aplicación DevUbi.
// Responsabilidad única: configurar MaterialApp.router con el tema
// y el router declarativo. No contiene lógica de negocio.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';

class DevUbiApp extends ConsumerWidget {
  const DevUbiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      // ── Metadatos ──────────────────────────────────────────────────────────
      title: 'DevUbi Client',
      debugShowCheckedModeBanner: false,

      // ── Tema ───────────────────────────────────────────────────────────────
      // Modo oscuro por defecto, esquema basado en teal (telemetría / industria)
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
      ),

      // ── Router ─────────────────────────────────────────────────────────────
      routerConfig: appRouter,
    );
  }
}
