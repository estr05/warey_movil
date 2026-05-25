// lib/features/tracking/data/repositories/safe_place_repository.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../domain/models/geofence_zone.dart';

class SafePlaceRepository {
  final Dio _dio;

  SafePlaceRepository(this._dio);

  Future<List<GeofenceZone>> fetchSafePlaces() async {
    final response = await _dio.get<Map<String, dynamic>>(
      'device/safe-places',
    );

    final data = response.data;
    if (data == null || data['success'] != true) return [];

    final List<dynamic> places = data['data'] as List<dynamic>;
    return places
        .map((json) => GeofenceZone.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<GeofenceZone> createSafePlace({
    required String name,
    required double latitude,
    required double longitude,
    required int radius,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'device/safe-places',
      data: {
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'radius': radius,
      },
    );

    final data = response.data!['data'] as Map<String, dynamic>;
    return GeofenceZone.fromJson(data);
  }

  Future<void> deleteSafePlace(String id) async {
    await _dio.delete('safe-places/$id');
  }
}

final safePlaceRepositoryProvider = Provider<SafePlaceRepository>((ref) {
  return SafePlaceRepository(ref.watch(dioProvider));
});
