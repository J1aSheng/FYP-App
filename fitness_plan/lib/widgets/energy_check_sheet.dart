import 'package:flutter/material.dart';
import '../models/gamification_model.dart';

const _kGreen = Color(0xFF2E7D32);
const _kInk = Color(0xFF191C19);
const _kMuted = Color(0xFF747972);

/// Daily energy/readiness check-in.
///
/// IMPORTANT:
/// - "Normal" is only the visible UI label.
/// - It still returns [EnergyLevel.medium], so the existing enum/model does
///   not need to be changed.
Future<EnergyLevel?> showEnergyCheckIn(
  BuildContext context,
) {
  return showModalBottomSheet<EnergyLevel>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => const _EnergyCheckSheet(),
  );
}

class _EnergyCheckSheet extends StatelessWidget {
  const _EnergyCheckSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          24,
          14,
          24,
          32,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(30),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE7EAE6),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "How's your energy today?",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _kInk,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Low = lighter • Normal = balanced • High = harder',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _kMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 26),
            const Row(
              children: [
                Expanded(
                  child: _EnergyOption(
                    label: 'Low',
                    subtitle: 'Lighter',
                    icon: Icons.battery_1_bar_rounded,
                    level: EnergyLevel.low,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _EnergyOption(
                    label: 'Normal',
                    subtitle: 'Balanced',
                    icon: Icons.battery_4_bar_rounded,
                    level: EnergyLevel.medium,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _EnergyOption(
                    label: 'High',
                    subtitle: 'Harder',
                    icon: Icons.battery_full_rounded,
                    level: EnergyLevel.high,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _EnergyOption extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final EnergyLevel level;

  const _EnergyOption({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => Navigator.pop(context, level),
      child: Container(
        height: 154,
        padding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 18,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F4EF),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: const Color(0xFFE3EEE3),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: _kGreen,
              size: 30,
            ),
            const SizedBox(height: 14),
            Text(
              label,
              style: const TextStyle(
                color: _kInk,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                color: _kMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
