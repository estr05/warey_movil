// lib/core/security/session_notice_provider.dart
//
// Avisos efimeros de seguridad para que la UI pueda explicar por que el
// usuario volvio al pairing sin que los interceptores conozcan BuildContext.

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SessionNoticeType { revoked }

class SessionNotice {
  final SessionNoticeType type;
  final String message;
  final DateTime occurredAt;

  const SessionNotice({
    required this.type,
    required this.message,
    required this.occurredAt,
  });
}

class SessionNoticeNotifier extends StateNotifier<SessionNotice?> {
  SessionNoticeNotifier() : super(null);

  void showRevoked([String? message]) {
    state = SessionNotice(
      type: SessionNoticeType.revoked,
      message:
          message ??
          'Tu sesion de telemetria fue revocada. Vincula este telefono de nuevo.',
      occurredAt: DateTime.now(),
    );
  }

  void clear() {
    state = null;
  }
}

final sessionNoticeProvider =
    StateNotifierProvider<SessionNoticeNotifier, SessionNotice?>((ref) {
      return SessionNoticeNotifier();
    });
