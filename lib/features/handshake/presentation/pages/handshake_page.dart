// lib/features/handshake/presentation/pages/handshake_page.dart
//
// Feature: Handshake — Capa Presentation (UI)
// Pantalla de vinculación de dispositivo. El usuario ingresa el código de 8
// caracteres generado en el panel Admin para asociar su dispositivo.
//
// Arquitectura de la UI:
//   - ConsumerStatefulWidget para gestionar Form, TextController y lifecycle.
//   - ref.listen() para side-effects (SnackBar) sin lógica en el build().
//   - _requestPermissions() se ejecuta antes del primer submit para garantizar
//     que los permisos de GPS estén disponibles antes de iniciar el servicio.
//   - Todos los widgets sin estado usan `const` para optimizar el árbol.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/handshake_provider.dart';
import '../../../../core/services/permission_service.dart';

class HandshakePage extends ConsumerStatefulWidget {
  const HandshakePage({super.key});

  @override
  ConsumerState<HandshakePage> createState() => _HandshakePageState();
}

class _HandshakePageState extends ConsumerState<HandshakePage> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  // ── Acciones ─────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Solicitar permisos ANTES de iniciar el handshake.
    // El servicio de background necesita ubicación concedida antes de arrancar.
    final permResult = await PermissionService.requestAll();
    if (!mounted) return;

    if (!permResult.granted) {
      // Si el permiso fue denegado permanentemente, guiar al usuario a Settings
      if (permResult.isPermanentlyDenied) {
        _showPermissionDeniedDialog(permResult.deniedPermission ?? 'ubicación');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Permiso de ${permResult.deniedPermission} requerido para operar el nodo.',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return; // No continuar sin permisos
    }

    // Permisos concedidos → proceder con el handshake
    ref
        .read(handshakeProvider.notifier)
        .validatePairingCode(_codeController.text.trim());
  }

  void _showPermissionDeniedDialog(String permName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_off_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Permiso requerido'),
          ],
        ),
        content: Text(
          'El permiso de $permName fue denegado permanentemente. '
          'Para operar el nodo, actívalo manualmente en Ajustes del sistema.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              PermissionService.openSettings();
            },
            child: const Text('Ir a Ajustes'),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(handshakeProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Side-effects: SnackBars fuera del árbol de widgets
    ref.listen<HandshakeState>(handshakeProvider, (previous, next) {
      if (next is Success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Dispositivo Activo. Transmitiendo telemetría...',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.teal.shade700,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      if (next is HandshakeError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    next.message,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: colorScheme.error,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Reintentar',
              textColor: Colors.white,
              onPressed: () => ref.read(handshakeProvider.notifier).reset(),
            ),
          ),
        );
      }
    });

    final bool isLoading = state is HandshakeLoading;
    final bool isLinked = state is Success;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Encabezado ──────────────────────────────────────────────
                  Icon(
                    isLinked ? Icons.verified_rounded : Icons.fingerprint,
                    size: 72,
                    color: isLinked ? Colors.teal : colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'DevUbi / Warey',
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isLinked
                        ? 'Dispositivo activo y transmitiendo.'
                        : 'Ingresa el código de vinculación generado\nen el panel de administración.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),

                  // ── Campo de código ─────────────────────────────────────────
                  TextFormField(
                    controller: _codeController,
                    enabled: !isLoading && !isLinked,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      _PairingCodeFormatter(),
                    ],
                    maxLength: 13,
                    keyboardType: TextInputType.visiblePassword,
                    decoration: InputDecoration(
                      labelText: 'Código de Emparejamiento',
                      hintText: 'WRY-XXXX-XXXX',
                      prefixIcon: const Icon(Icons.vpn_key_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      counterText: '',
                    ),
                    validator: _validateCode,
                    onFieldSubmitted: (_) => isLoading || isLinked ? null : _submit(),
                  ),
                  const SizedBox(height: 28),

                  // ── Botón de acción ─────────────────────────────────────────
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: isLoading || isLinked ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.teal.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      child: isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(isLinked ? 'Vinculado ✓' : 'Vincular Dispositivo'),
                    ),
                  ),

                  // ── Estado de error inline ────────
                  if (state is HandshakeError) ...[
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.info_outline,
                            size: 16, color: colorScheme.error),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            state.message,
                            style: TextStyle(
                              color: colorScheme.error,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Validadores ───────────────────────────────────────────────────────────────

  String? _validateCode(String? value) {
    if (value == null || value.isEmpty) {
      return 'El código no puede estar vacío.';
    }
    final regex = RegExp(r'^WRY-[A-Z0-9]{4}-[A-Z0-9]{4}$');
    if (!regex.hasMatch(value)) {
      return 'Formato incorrecto. Debe ser WRY-XXXX-XXXX.';
    }
    return null;
  }
}

// ── Input Formatter ───────────────────────────────────────────────────────────

class _PairingCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final rawText = newValue.text
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');

    final limited = rawText.length > 11 ? rawText.substring(0, 11) : rawText;

    String formatted = limited;
    if (limited.length > 7) {
      formatted = '${limited.substring(0, 3)}-${limited.substring(3, 7)}-${limited.substring(7)}';
    } else if (limited.length > 3) {
      formatted = '${limited.substring(0, 3)}-${limited.substring(3)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}