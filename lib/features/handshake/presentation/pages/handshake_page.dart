// lib/features/handshake/presentation/pages/handshake_page.dart
//
// Pantalla de vinculacion de dispositivo. Flutter solo interpreta respuestas
// del backend, muestra estados, pide confirmaciones y conduce la UX.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/security/session_notice_provider.dart';
import '../../../../core/services/permission_service.dart';
import '../../domain/repositories/handshake_repository.dart';
import '../providers/handshake_provider.dart';

class HandshakePage extends ConsumerStatefulWidget {
  const HandshakePage({super.key});

  @override
  ConsumerState<HandshakePage> createState() => _HandshakePageState();
}

class _HandshakePageState extends ConsumerState<HandshakePage> {
  static const _background = Color(0xFF07111F);
  static const _surface = Color(0xFF101C2E);
  static const _surfaceSoft = Color(0xFF17253A);
  static const _border = Color(0xFF28405F);
  static const _muted = Color(0xFF96A8BE);
  static const _cyan = Color(0xFF00A8CC);
  static const _green = Color(0xFF27AE60);
  static const _amber = Color(0xFFE67E22);
  static const _red = Color(0xFFE75B64);

  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _codeFocusNode = FocusNode();
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _codeController.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final currentState = ref.read(handshakeProvider);
    if (currentState is HandshakeLoading || currentState is Success) return;
    if (_cooldownSeconds(currentState.cooldownUntil) > 0) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Mostrar feedback visual INMEDIATO antes de pedir permisos
    ref.read(handshakeProvider.notifier).setLoadingState('Solicitando permisos de ubicaci\u00f3n...');

    final permResult = await PermissionService.requestAll();
    if (!mounted) return;

    if (!permResult.granted) {
      if (permResult.isPermanentlyDenied) {
        _showPermissionDeniedDialog(permResult.deniedPermission ?? 'ubicacion');
      } else {
        _showSnack(
          'Permiso de ${permResult.deniedPermission} requerido para operar el nodo.',
          color: _red,
          icon: Icons.location_off_rounded,
        );
      }
      return;
    }

    await ref
        .read(handshakeProvider.notifier)
        .validatePairingCode(_codeController.text.trim());
  }

  void _showPermissionDeniedDialog(String permName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_off_rounded, color: _amber),
            SizedBox(width: 8),
            Text('Permiso requerido'),
          ],
        ),
        content: Text(
          'El permiso de $permName fue denegado permanentemente. '
          'Activalo manualmente en Ajustes del sistema.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              PermissionService.openSettings();
            },
            icon: const Icon(Icons.settings_rounded),
            label: const Text('Ir a Ajustes'),
          ),
        ],
      ),
    );
  }

  void _showSnack(
    String message, {
    required Color color,
    required IconData icon,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _useNewCode() {
    _codeController.clear();
    ref.read(handshakeProvider.notifier).reset();
    _codeFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(handshakeProvider);
    final notice = ref.watch(sessionNoticeProvider);
    final status = notice?.type == SessionNoticeType.revoked
        ? PairingLifecycleStatus.revoked
        : state.visualStatus;
    final spec = _statusSpec(status);
    final cooldownSeconds = _cooldownSeconds(state.cooldownUntil);

    ref.listen<HandshakeState>(handshakeProvider, (previous, next) {
      if (next is Success) {
        _showSnack(
          'Dispositivo vinculado. Revisa el resumen antes de continuar.',
          color: _green,
          icon: Icons.verified_rounded,
        );
      }
      if (next is HandshakeRevokedState) {
        _showSnack(next.message, color: _red, icon: Icons.lock_reset_rounded);
      }
    });

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(spec: spec),
                      const SizedBox(height: 18),
                      if (notice != null) ...[
                        _SessionNoticeBanner(
                          notice: notice,
                          onDismiss: () =>
                              ref.read(sessionNoticeProvider.notifier).clear(),
                        ),
                        const SizedBox(height: 14),
                      ],
                      _StatusPanel(spec: spec),
                      const SizedBox(height: 16),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: _bodyForState(
                          state,
                          cooldownSeconds: cooldownSeconds,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _StatusLegend(current: status),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _bodyForState(HandshakeState state, {required int cooldownSeconds}) {
    if (state is Success) {
      return _PairedSummaryPanel(
        key: const ValueKey('paired-summary'),
        device: state.device,
        onContinue: () =>
            ref.read(handshakeProvider.notifier).continueToDashboard(),
      );
    }

    if (state is HandshakeConfirmationRequired) {
      return _ConflictPanel(
        key: const ValueKey('pairing-conflict'),
        conflict: state.conflict,
        onCancel: () =>
            ref.read(handshakeProvider.notifier).cancelReplacement(),
        onReplace: () =>
            ref.read(handshakeProvider.notifier).confirmReplacement(),
      );
    }

    if (state is HandshakeCodeExpiredState) {
      return _ExpiredPanel(
        key: const ValueKey('pairing-expired'),
        message: state.message,
        cooldownSeconds: cooldownSeconds,
        onNewCode: _useNewCode,
      );
    }

    if (state is HandshakeRevokedState) {
      return _RevokedPanel(
        key: const ValueKey('pairing-revoked'),
        message: state.message,
        onNewPairing: _useNewCode,
      );
    }

    return Column(
      key: const ValueKey('pairing-form'),
      children: [
        _PairingFormPanel(
          formKey: _formKey,
          codeController: _codeController,
          focusNode: _codeFocusNode,
          enabled: state is! HandshakeLoading && cooldownSeconds == 0,
          loading: state is HandshakeLoading,
          loadingMessage: state is HandshakeLoading
              ? state.message
              : 'Validando codigo...',
          cooldownSeconds: cooldownSeconds,
          onSubmit: _submit,
          validator: _validateCode,
        ),
        if (state is HandshakeError) ...[
          const SizedBox(height: 12),
          _InlineMessage(message: state.message, status: state.visualStatus),
        ],
        if (state is HandshakeCooldown) ...[
          const SizedBox(height: 12),
          _InlineMessage(
            message: state.message,
            status: PairingLifecycleStatus.pending,
          ),
        ],
      ],
    );
  }

  String? _validateCode(String? value) {
    if (value == null || value.isEmpty) {
      return 'El codigo no puede estar vacio.';
    }
    final regex = RegExp(r'^WRY-[A-Z0-9]{4}-[A-Z0-9]{4}$');
    if (!regex.hasMatch(value)) {
      return 'Formato esperado: WRY-XXXX-XXXX.';
    }
    return null;
  }

  int _cooldownSeconds(DateTime? retryAt) {
    if (retryAt == null) return 0;
    final remaining = retryAt.difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining + 1 : 0;
  }

  static _StatusSpec _statusSpec(PairingLifecycleStatus status) {
    return switch (status) {
      PairingLifecycleStatus.pending => const _StatusSpec(
        label: 'PENDING',
        title: 'Esperando pairing',
        message: 'Listo para validar el codigo con el backend.',
        color: _amber,
        icon: Icons.hourglass_top_rounded,
      ),
      PairingLifecycleStatus.paired => const _StatusSpec(
        label: 'PAIRED',
        title: 'Dispositivo vinculado',
        message: 'Token recibido y almacenado de forma segura.',
        color: _cyan,
        icon: Icons.link_rounded,
      ),
      PairingLifecycleStatus.active => const _StatusSpec(
        label: 'ACTIVE',
        title: 'Telemetry activa',
        message: 'El servicio de tracking esta listo para operar.',
        color: _green,
        icon: Icons.sensors_rounded,
      ),
      PairingLifecycleStatus.revoked => const _StatusSpec(
        label: 'REVOKED',
        title: 'Sesion revocada',
        message: 'El backend invalido el token de telemetria.',
        color: _red,
        icon: Icons.lock_reset_rounded,
      ),
      PairingLifecycleStatus.offline => const _StatusSpec(
        label: 'OFFLINE',
        title: 'Sin conexion',
        message: 'No hay comunicacion estable con el backend.',
        color: Color(0xFF94A3B8),
        icon: Icons.cloud_off_rounded,
      ),
    };
  }

  static String _formatTimestamp(DateTime? value) {
    if (value == null) return 'No informado';
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  static String _relativeTime(DateTime? value) {
    if (value == null) return 'No informado';
    final diff = DateTime.now().difference(value.toLocal());
    if (diff.inSeconds < 60) return 'hace unos segundos';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    return 'hace ${diff.inDays} dias';
  }
}

class _Header extends StatelessWidget {
  final _StatusSpec spec;

  const _Header({required this.spec});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _HandshakePageState._surfaceSoft,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _HandshakePageState._border),
          ),
          child: Icon(Icons.fingerprint_rounded, color: spec.color, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DevUbi / Warey',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                'Vinculacion segura de dispositivo',
                style: TextStyle(
                  color: _HandshakePageState._muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        _StatusBadge(spec: spec, compact: true),
      ],
    );
  }
}

class _StatusPanel extends StatelessWidget {
  final _StatusSpec spec;

  const _StatusPanel({required this.spec});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _HandshakePageState._surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: spec.color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(spec.icon, color: spec.color, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spec.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  spec.message,
                  style: const TextStyle(
                    color: _HandshakePageState._muted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PairingFormPanel extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController codeController;
  final FocusNode focusNode;
  final bool enabled;
  final bool loading;
  final String loadingMessage;
  final int cooldownSeconds;
  final VoidCallback onSubmit;
  final String? Function(String?) validator;

  const _PairingFormPanel({
    required this.formKey,
    required this.codeController,
    required this.focusNode,
    required this.enabled,
    required this.loading,
    required this.loadingMessage,
    required this.cooldownSeconds,
    required this.onSubmit,
    required this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final buttonLabel = cooldownSeconds > 0
        ? 'Reintentar en ${cooldownSeconds}s'
        : loading
        ? loadingMessage
        : 'Vincular dispositivo';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _HandshakePageState._surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _HandshakePageState._border),
      ),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: codeController,
              focusNode: focusNode,
              enabled: enabled,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [_PairingCodeFormatter()],
              maxLength: 13,
              keyboardType: TextInputType.visiblePassword,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
              decoration: InputDecoration(
                labelText: 'Codigo de vinculacion',
                hintText: 'WRY-XXXX-XXXX',
                prefixIcon: const Icon(Icons.vpn_key_rounded),
                counterText: '',
                filled: true,
                fillColor: const Color(0xFF0B1627),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: _HandshakePageState._border,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: _HandshakePageState._border,
                  ),
                ),
              ),
              validator: validator,
              onFieldSubmitted: (_) {
                if (enabled) onSubmit();
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: enabled ? onSubmit : null,
                icon: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.3,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.link_rounded),
                label: Text(buttonLabel),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _HandshakePageState._cyan,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _HandshakePageState._cyan.withValues(
                    alpha: 0.25,
                  ),
                  disabledForegroundColor: Colors.white70,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConflictPanel extends StatelessWidget {
  final PairingConflict conflict;
  final VoidCallback onCancel;
  final VoidCallback onReplace;

  const _ConflictPanel({
    super.key,
    required this.conflict,
    required this.onCancel,
    required this.onReplace,
  });

  @override
  Widget build(BuildContext context) {
    return _ActionPanel(
      icon: Icons.warning_amber_rounded,
      color: _HandshakePageState._amber,
      title: 'Este dispositivo ya esta vinculado',
      message: conflict.message,
      children: [
        _DetailRow(
          icon: Icons.phone_android_rounded,
          label: 'Telefono',
          value: conflict.alias,
        ),
        _DetailRow(
          icon: Icons.schedule_rounded,
          label: 'Ultima conexion',
          value: _HandshakePageState._relativeTime(conflict.lastSeenAt),
        ),
        _DetailRow(
          icon: Icons.fingerprint_rounded,
          label: 'Fingerprint',
          value: conflict.fingerprint,
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Cancelar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: _HandshakePageState._border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onReplace,
                icon: const Icon(Icons.swap_horiz_rounded),
                label: const Text('Reemplazar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _HandshakePageState._amber,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ExpiredPanel extends StatelessWidget {
  final String message;
  final int cooldownSeconds;
  final VoidCallback onNewCode;

  const _ExpiredPanel({
    super.key,
    required this.message,
    required this.cooldownSeconds,
    required this.onNewCode,
  });

  @override
  Widget build(BuildContext context) {
    return _ActionPanel(
      icon: Icons.timer_off_rounded,
      color: _HandshakePageState._amber,
      title: 'Codigo vencido',
      message: message,
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: cooldownSeconds == 0 ? onNewCode : null,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(
              cooldownSeconds == 0
                  ? 'Ingresar codigo nuevo'
                  : 'Disponible en ${cooldownSeconds}s',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _HandshakePageState._amber,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RevokedPanel extends StatelessWidget {
  final String message;
  final VoidCallback onNewPairing;

  const _RevokedPanel({
    super.key,
    required this.message,
    required this.onNewPairing,
  });

  @override
  Widget build(BuildContext context) {
    return _ActionPanel(
      icon: Icons.lock_reset_rounded,
      color: _HandshakePageState._red,
      title: 'Sesion revocada',
      message: message,
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onNewPairing,
            icon: const Icon(Icons.qr_code_2_rounded),
            label: const Text('Nuevo pairing'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _HandshakePageState._red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PairedSummaryPanel extends StatelessWidget {
  final PairedDeviceInfo device;
  final VoidCallback onContinue;

  const _PairedSummaryPanel({
    super.key,
    required this.device,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final spec = _HandshakePageState._statusSpec(device.status);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _HandshakePageState._surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: spec.color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.verified_rounded, color: spec.color, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Dispositivo vinculado',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
              _StatusBadge(spec: spec, compact: true),
            ],
          ),
          const SizedBox(height: 16),
          _DetailRow(
            icon: Icons.badge_rounded,
            label: 'Alias',
            value: device.alias,
          ),
          _DetailRow(
            icon: Icons.phone_android_rounded,
            label: 'Modelo',
            value: '${device.manufacturer} ${device.model}',
          ),
          _DetailRow(
            icon: Icons.sensors_rounded,
            label: 'Estado',
            value: spec.label,
          ),
          _DetailRow(
            icon: Icons.schedule_rounded,
            label: 'Vinculado',
            value: _HandshakePageState._formatTimestamp(device.pairedAt),
          ),
          _DetailRow(
            icon: Icons.update_rounded,
            label: 'Ultima conexion',
            value: _HandshakePageState._formatTimestamp(device.lastSeenAt),
          ),
          _DetailRow(
            icon: Icons.fingerprint_rounded,
            label: 'Fingerprint',
            value: device.fingerprint,
            selectable: true,
          ),
          _DetailRow(
            icon: Icons.android_rounded,
            label: 'Android',
            value: device.androidVersion,
          ),
          _DetailRow(
            icon: Icons.apps_rounded,
            label: 'App',
            value: device.appVersion,
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: onContinue,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Ir al panel'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _HandshakePageState._green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionPanel extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final List<Widget> children;

  const _ActionPanel({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _HandshakePageState._surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      message,
                      style: const TextStyle(
                        color: _HandshakePageState._muted,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool selectable;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.selectable = false,
  });

  @override
  Widget build(BuildContext context) {
    final valueStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _HandshakePageState._cyan, size: 18),
          const SizedBox(width: 10),
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: const TextStyle(
                color: _HandshakePageState._muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: selectable
                ? SelectableText(value, style: valueStyle)
                : Text(value, style: valueStyle, softWrap: true),
          ),
        ],
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  final String message;
  final PairingLifecycleStatus status;

  const _InlineMessage({required this.message, required this.status});

  @override
  Widget build(BuildContext context) {
    final spec = _HandshakePageState._statusSpec(status);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: spec.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: spec.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(spec.icon, color: spec.color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionNoticeBanner extends StatelessWidget {
  final SessionNotice notice;
  final VoidCallback onDismiss;

  const _SessionNoticeBanner({required this.notice, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _HandshakePageState._red.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _HandshakePageState._red.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_reset_rounded, color: _HandshakePageState._red),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              notice.message,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Cerrar aviso',
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _StatusLegend extends StatelessWidget {
  final PairingLifecycleStatus current;

  const _StatusLegend({required this.current});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: PairingLifecycleStatus.values.map((status) {
        final spec = _HandshakePageState._statusSpec(status);
        return _StatusBadge(spec: spec, selected: current == status);
      }).toList(),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final _StatusSpec spec;
  final bool selected;
  final bool compact;

  const _StatusBadge({
    required this.spec,
    this.selected = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: spec.title,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 7 : 8,
        ),
        decoration: BoxDecoration(
          color: selected
              ? spec.color.withValues(alpha: 0.22)
              : _HandshakePageState._surfaceSoft,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? spec.color
                : _HandshakePageState._border.withValues(alpha: 0.65),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(spec.icon, size: compact ? 14 : 16, color: spec.color),
            const SizedBox(width: 6),
            Text(
              spec.label,
              style: TextStyle(
                color: selected ? Colors.white : _HandshakePageState._muted,
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusSpec {
  final String label;
  final String title;
  final String message;
  final Color color;
  final IconData icon;

  const _StatusSpec({
    required this.label,
    required this.title,
    required this.message,
    required this.color,
    required this.icon,
  });
}

class _PairingCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final rawText = newValue.text.toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]'),
      '',
    );

    final limited = rawText.length > 11 ? rawText.substring(0, 11) : rawText;

    String formatted = limited;
    if (limited.length > 7) {
      formatted =
          '${limited.substring(0, 3)}-${limited.substring(3, 7)}-${limited.substring(7)}';
    } else if (limited.length > 3) {
      formatted = '${limited.substring(0, 3)}-${limited.substring(3)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
