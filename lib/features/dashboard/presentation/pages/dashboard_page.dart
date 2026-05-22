// lib/features/dashboard/presentation/pages/dashboard_page.dart
//
// Feature: Dashboard — Capa Presentation (UI)
// Pantalla de administración del nodo de telemetría activo.
// Muestra el estado del servicio en tiempo real y permite desconectar el nodo.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/services/background_service.dart';
import '../../../../core/services/secure_storage_service.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/services/local_database_service.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  
  // Real-time data state
  final Battery _battery = Battery();
  int _batteryLevel = 100;
  bool _isCharging = false;
  int _offlineQueueCount = 0;
  String _gpsAccuracy = 'Calculando...';
  
  StreamSubscription<BatteryState>? _batteryStateSubscription;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _initRealTimeData();
  }

  Future<void> _initRealTimeData() async {
    // 1. Listen to charging state changes in real-time
    _batteryStateSubscription = _battery.onBatteryStateChanged.listen((BatteryState state) {
      if (mounted) {
        setState(() {
          _isCharging = state == BatteryState.charging;
        });
      }
    });
    
    // 2. Fetch initial battery level
    _batteryLevel = await _battery.batteryLevel;
    if (mounted) setState(() {});

    // 3. Start a timer to poll local DB and GPS accuracy every 3 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      _pollData();
    });
    
    // Initial fetch
    _pollData();
  }
  
  Future<void> _pollData() async {
    // Get battery level
    final level = await _battery.batteryLevel;
    
    // Get offline queue count from local DB
    final count = await ref.read(localDatabaseProvider).getPendingFramesCount();
    
    // Get last known GPS accuracy (cheap, doesn't wake GPS hardware heavily)
    String accuracyStr = 'Desconocida';
    try {
      final position = await Geolocator.getLastKnownPosition();
      if (position != null) {
        accuracyStr = '± ${position.accuracy.toStringAsFixed(1)} metros';
      }
    } catch (e) {
      // Ignorar errores de GPS en UI
    }

    if (mounted) {
      setState(() {
        _batteryLevel = level;
        _offlineQueueCount = count;
        _gpsAccuracy = accuracyStr;
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _batteryStateSubscription?.cancel();
    _pollingTimer?.cancel();
    super.dispose();
  }

  /// Detiene el servicio y limpia las credenciales, redirigiendo a Handshake.
  Future<void> _disconnectNode() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Desvincular Nodo'),
          ],
        ),
        content: const Text(
          '¿Estás seguro de que deseas desvincular este nodo? Se detendrá la transmisión de telemetría y se eliminarán las credenciales del dispositivo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Desvincular'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // 1. Detener gracefully el servicio en background
      BackgroundServiceManager.stopService();

      // 2. Eliminar el token de Secure Storage
      await ref.read(secureStorageProvider).deleteToken();

      // 3. Actualizar authStateProvider para que la guardia del router redirija a handshake
      ref.read(authStateProvider.notifier).updateToken(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Deep Slate elegante
      appBar: AppBar(
        title: const Text(
          'NODO DE TELEMETRÍA',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── CARD PRINCIPAL DE ESTADO ───────────────────────────────────
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.teal.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.teal.withValues(alpha: 0.1),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ESTADO DEL DISPOSITIVO',
                              style: TextStyle(
                                color: Colors.teal,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                // Indicador LED de latido dinámico (Neon Green)
                                AnimatedBuilder(
                                  animation: _pulseController,
                                  builder: (context, child) {
                                    return Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.greenAccent.withValues(
                                          alpha: 0.3 + (_pulseController.value * 0.7),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.greenAccent,
                                            blurRadius: 8 * _pulseController.value,
                                            spreadRadius: 2 * _pulseController.value,
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'ACTIVE',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.teal.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.wifi, size: 14, color: Colors.tealAccent),
                              SizedBox(width: 6),
                              Text(
                                'ONLINE',
                                style: TextStyle(
                                  color: Colors.tealAccent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: Color(0xFF334155), height: 32),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _StatusIndicator(
                          title: 'Modo Telemetría',
                          value: 'Dynamic (5s/30s)',
                          icon: Icons.speed_rounded,
                        ),
                        _StatusIndicator(
                          title: 'Intervalo Activo',
                          value: '30 Segundos',
                          icon: Icons.timer_outlined,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // ── CARD DETALLES DE TRANSMISIÓN ──────────────────────────────
              Text(
                'MONITOR DE TELEMETRÍA',
                style: textTheme.labelLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF334155),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    _TelemetryDataRow(
                      label: 'Precisión GPS',
                      value: _gpsAccuracy,
                      icon: Icons.gps_fixed,
                      color: Colors.tealAccent,
                    ),
                    Divider(color: const Color(0xFF334155).withValues(alpha: 0.5), height: 24),
                    _TelemetryDataRow(
                      label: 'Batería del Nodo',
                      value: '$_batteryLevel% (${_isCharging ? 'Cargando' : 'Descargando'})',
                      icon: _isCharging ? Icons.battery_charging_full : Icons.battery_full,
                      color: _isCharging ? Colors.amberAccent : (_batteryLevel > 20 ? Colors.greenAccent : Colors.redAccent),
                    ),
                    Divider(color: const Color(0xFF334155).withValues(alpha: 0.5), height: 24),
                    _TelemetryDataRow(
                      label: 'Cola Offline',
                      value: '$_offlineQueueCount frames pendientes',
                      icon: Icons.cloud_done_outlined,
                      color: _offlineQueueCount > 0 ? Colors.orangeAccent : Colors.lightBlueAccent,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── CARD INFORMACIÓN DEL SISTEMA ───────────────────────────────
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF334155).withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.tealAccent, size: 24),
                    SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Este dispositivo está transmitiendo coordenadas geográficas encriptadas de forma dinámica y automática según las políticas de DevUbi.',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 48),

              // ── BOTÓN DESVINCULAR NODO ─────────────────────────────────────
              ElevatedButton.icon(
                onPressed: _disconnectNode,
                icon: const Icon(Icons.link_off_rounded, size: 20),
                label: const Text('DISCONNECT NODE'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.redAccent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Colors.redAccent, width: 1.5),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _StatusIndicator({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: Colors.teal),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TelemetryDataRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _TelemetryDataRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
