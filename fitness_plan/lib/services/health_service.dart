import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';

class PhoneActivityData {
  final int steps;
  final double activeCalories;
  final double distanceKm;
  final int exerciseMinutes;

  const PhoneActivityData({
    required this.steps,
    required this.activeCalories,
    required this.distanceKm,
    required this.exerciseMinutes,
  });

  const PhoneActivityData.empty()
      : steps = 0,
        activeCalories = 0,
        distanceKm = 0,
        exerciseMinutes = 0;
}

class HealthService {
  final Health _health = Health();

  static const List<HealthDataType> _types = [
    HealthDataType.STEPS,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.DISTANCE_DELTA,
    HealthDataType.WORKOUT,
  ];

  Future<void> configure() async {
    await _health.configure();
  }

  Future<bool> requestPermissions() async {
    try {
      await configure();

      if (Platform.isAndroid) {
        await Permission.activityRecognition.request();
      }

      final permissions =
          _types.map((_) => HealthDataAccess.READ).toList();

      return await _health.requestAuthorization(
        _types,
        permissions: permissions,
      );
    } catch (e) {
      debugPrint('Health Connect permission error: $e');
      return false;
    }
  }

  Future<PhoneActivityData> getTodayActivity() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);

    return getActivityForInterval(
      start: start,
      end: now,
    );
  }

  Future<PhoneActivityData> getActivityForInterval({
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      await configure();

      final steps = await _health.getTotalStepsInInterval(
            start,
            end,
            includeManualEntry: false,
          ) ??
          0;

      var points = await _health.getHealthDataFromTypes(
        types: const [
          HealthDataType.ACTIVE_ENERGY_BURNED,
          HealthDataType.DISTANCE_DELTA,
          HealthDataType.WORKOUT,
        ],
        startTime: start,
        endTime: end,
      );

      points = _health.removeDuplicates(points);

      double activeCalories = 0;
      double distanceMeters = 0;
      int exerciseMinutes = 0;

      for (final point in points) {
        if (point.type == HealthDataType.ACTIVE_ENERGY_BURNED) {
          final value = point.value;
          if (value is NumericHealthValue) {
            activeCalories += value.numericValue.toDouble();
          }
        } else if (point.type == HealthDataType.DISTANCE_DELTA) {
          final value = point.value;
          if (value is NumericHealthValue) {
            distanceMeters += value.numericValue.toDouble();
          }
        } else if (point.type == HealthDataType.WORKOUT) {
          final minutes =
              point.dateTo.difference(point.dateFrom).inMinutes;
          if (minutes > 0) {
            exerciseMinutes += minutes;
          }
        }
      }

      return PhoneActivityData(
        steps: steps,
        activeCalories: activeCalories,
        distanceKm: distanceMeters / 1000.0,
        exerciseMinutes: exerciseMinutes,
      );
    } catch (e) {
      debugPrint('Health Connect read error: $e');
      return const PhoneActivityData.empty();
    }
  }
}
