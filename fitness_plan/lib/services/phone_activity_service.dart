import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PhoneActivityData {
  final int steps;
  final double activeCalories;
  final double distanceKm;
  final int exerciseMinutes;
  final bool healthConnectUsed;
  final bool sensorUsed;

  const PhoneActivityData({
    required this.steps,
    required this.activeCalories,
    required this.distanceKm,
    required this.exerciseMinutes,
    required this.healthConnectUsed,
    required this.sensorUsed,
  });

  const PhoneActivityData.empty()
      : steps = 0,
        activeCalories = 0,
        distanceKm = 0,
        exerciseMinutes = 0,
        healthConnectUsed = false,
        sensorUsed = false;
}

class PhoneActivityService {
  final Health _health = Health();

  static const List<HealthDataType> _healthTypes = [
    HealthDataType.STEPS,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.DISTANCE_DELTA,
    HealthDataType.WORKOUT,
  ];

  /// Ask only for the generic Android motion permission first.
  /// Health Connect is attempted separately and is optional.
  Future<bool> requestMotionPermission() async {
    if (!Platform.isAndroid) return true;

    final status =
        await Permission.activityRecognition.request();

    return status.isGranted;
  }

  /// Health Connect is preferred when it contains data, but the app does
  /// not fail when Health Connect is unavailable or the user denies it.
  Future<bool> requestHealthConnectPermission() async {
    try {
      await _health.configure();

      final permissions = _healthTypes
          .map((_) => HealthDataAccess.READ)
          .toList();

      return await _health.requestAuthorization(
        _healthTypes,
        permissions: permissions,
      );
    } catch (e) {
      debugPrint('Health Connect permission unavailable: $e');
      return false;
    }
  }

  Future<PhoneActivityData> getTodayActivity({
    required double weightKg,
  }) async {
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    );

    final healthData = await _readHealthConnect(
      start: start,
      end: now,
    );

    final sensorSteps = await _readTodaySensorSteps();

    // Prefer Health Connect steps when Health Connect actually has steps.
    // Otherwise use the device's physical step-counter sensor.
    final finalSteps = healthData.steps > 0
        ? healthData.steps
        : sensorSteps;

    // Prefer Health Connect distance/calories when present. Otherwise
    // estimate from steps so the card still works across Android brands.
    final estimatedDistanceKm =
        _estimateDistanceKm(finalSteps);

    final finalDistance = healthData.distanceKm > 0
        ? healthData.distanceKm
        : estimatedDistanceKm;

    final estimatedCalories = _estimateWalkingCalories(
      steps: finalSteps,
      weightKg: weightKg,
      distanceKm: finalDistance,
    );

    final finalCalories = healthData.activeCalories > 0
        ? healthData.activeCalories
        : estimatedCalories;

    final estimatedExerciseMinutes =
        _estimateExerciseMinutes(finalSteps);

    final finalExerciseMinutes =
        healthData.exerciseMinutes > 0
            ? healthData.exerciseMinutes
            : estimatedExerciseMinutes;

    return PhoneActivityData(
      steps: finalSteps,
      activeCalories: finalCalories,
      distanceKm: finalDistance,
      exerciseMinutes: finalExerciseMinutes,
      healthConnectUsed:
          healthData.steps > 0 ||
          healthData.activeCalories > 0 ||
          healthData.distanceKm > 0 ||
          healthData.exerciseMinutes > 0,
      sensorUsed:
          healthData.steps <= 0 && sensorSteps > 0,
    );
  }

  /// Stream today's step count from the physical Android step counter.
  /// This is the fallback that lets the app update while the user walks,
  /// even when Samsung/Realme/Xiaomi/etc. do not share their private
  /// pedometer database into Health Connect.
  Stream<int> watchTodaySensorSteps() async* {
    final allowed = await requestMotionPermission();
    if (!allowed) {
      throw Exception(
        'Activity recognition permission was not granted.',
      );
    }

    await for (final event in Pedometer.stepCountStream) {
      final todaySteps =
          await _convertRawSensorCountToToday(event.steps);
      yield todaySteps;
    }
  }

  Future<PhoneActivityData> _readHealthConnect({
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      await _health.configure();

      final steps =
          await _health.getTotalStepsInInterval(
            start,
            end,
            includeManualEntry: false,
          ) ??
          0;

      var points =
          await _health.getHealthDataFromTypes(
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
        if (point.type ==
            HealthDataType.ACTIVE_ENERGY_BURNED) {
          final value = point.value;

          if (value is NumericHealthValue) {
            activeCalories +=
                value.numericValue.toDouble();
          }
        } else if (point.type ==
            HealthDataType.DISTANCE_DELTA) {
          final value = point.value;

          if (value is NumericHealthValue) {
            distanceMeters +=
                value.numericValue.toDouble();
          }
        } else if (point.type ==
            HealthDataType.WORKOUT) {
          final minutes =
              point.dateTo
                  .difference(point.dateFrom)
                  .inMinutes;

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
        healthConnectUsed: true,
        sensorUsed: false,
      );
    } catch (e) {
      debugPrint(
        'Health Connect read unavailable: $e',
      );

      return const PhoneActivityData.empty();
    }
  }

  Future<int> _readTodaySensorSteps() async {
    try {
      final allowed =
          await requestMotionPermission();

      if (!allowed) return 0;

      final event =
          await Pedometer.stepCountStream.first.timeout(
        const Duration(seconds: 6),
      );

      return _convertRawSensorCountToToday(
        event.steps,
      );
    } catch (e) {
      debugPrint(
        'Device step sensor unavailable: $e',
      );
      return 0;
    }
  }

  Future<int> _convertRawSensorCountToToday(
    int rawSteps,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    final now = DateTime.now();
    final todayKey =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    const storedDateKey =
        'phone_step_sensor_date';
    const storedBaselineKey =
        'phone_step_sensor_baseline';
    const storedLastRawKey =
        'phone_step_sensor_last_raw';
    const storedTodayKey =
        'phone_step_sensor_today_steps';

    final storedDate =
        prefs.getString(storedDateKey);
    final previousRaw =
        prefs.getInt(storedLastRawKey);
    final savedToday =
        prefs.getInt(storedTodayKey) ?? 0;

    // First ever observation.
    if (previousRaw == null) {
      await prefs.setString(
        storedDateKey,
        todayKey,
      );
      await prefs.setInt(
        storedBaselineKey,
        rawSteps,
      );
      await prefs.setInt(
        storedLastRawKey,
        rawSteps,
      );
      await prefs.setInt(
        storedTodayKey,
        0,
      );
      return 0;
    }

    // If the device rebooted, Android's raw step-counter resets.
    if (rawSteps < previousRaw) {
      await prefs.setString(
        storedDateKey,
        todayKey,
      );
      await prefs.setInt(
        storedBaselineKey,
        rawSteps,
      );
      await prefs.setInt(
        storedLastRawKey,
        rawSteps,
      );

      // Preserve steps already collected today before reboot.
      await prefs.setInt(
        storedTodayKey,
        savedToday,
      );

      return savedToday;
    }

    // A new calendar day. The first sensor reading becomes today's
    // baseline. From this point onward all new steps are counted today.
    if (storedDate != todayKey) {
      await prefs.setString(
        storedDateKey,
        todayKey,
      );
      await prefs.setInt(
        storedBaselineKey,
        rawSteps,
      );
      await prefs.setInt(
        storedLastRawKey,
        rawSteps,
      );
      await prefs.setInt(
        storedTodayKey,
        0,
      );
      return 0;
    }

    final baseline =
        prefs.getInt(storedBaselineKey) ??
            rawSteps;

    final todaySteps =
        (rawSteps - baseline).clamp(
      0,
      1000000,
    );

    await prefs.setInt(
      storedLastRawKey,
      rawSteps,
    );
    await prefs.setInt(
      storedTodayKey,
      todaySteps,
    );

    return todaySteps;
  }

  double _estimateDistanceKm(int steps) {
    // General adult walking estimate:
    // ~0.75 m per step.
    return steps * 0.00075;
  }

  double _estimateWalkingCalories({
    required int steps,
    required double weightKg,
    required double distanceKm,
  }) {
    if (steps <= 0 || distanceKm <= 0) {
      return 0;
    }

    final safeWeight =
        weightKg <= 0 ? 65.0 : weightKg;

    // A simple walking estimate suitable as a fallback only.
    // Around 0.5 kcal per kg per km.
    return safeWeight *
        distanceKm *
        0.5;
  }

  int _estimateExerciseMinutes(int steps) {
    if (steps <= 0) return 0;

    // Approximate moderate walking cadence:
    // 100 steps/minute.
    return (steps / 100).floor();
  }
}
