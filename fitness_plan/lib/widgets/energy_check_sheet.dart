import 'package:flutter/material.dart';
import '../models/gamification_model.dart';

const _kGreen = Color(0xFF2E7D32);
const _kInk = Color(0xFF191C19);
const _kMuted = Color(0xFF747972);

/// Shows a quick energy/mood check-in as a bottom sheet. Returns the chosen
/// [EnergyLevel], or null if the user dismissed it without choosing.
Future<EnergyLevel?> showEnergyCheckIn(BuildContext context) {
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
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F0F0),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "How's your energy today?",
            style: TextStyle(color: _kInk, fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            "We'll tailor today's suggestion to match.",
            style: TextStyle(color: _kMuted, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              _EnergyOption(label: "Low", icon: Icons.battery_1_bar_rounded, level: EnergyLevel.low),
              _EnergyOption(label: "Okay", icon: Icons.battery_4_bar_rounded, level: EnergyLevel.medium),
              _EnergyOption(label: "High", icon: Icons.battery_full_rounded, level: EnergyLevel.high),
            ],
          ),
        ],
      ),
    );
  }
}

class _EnergyOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final EnergyLevel level;
  const _EnergyOption({required this.label, required this.icon, required this.level});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context, level),
      child: Container(
        width: 96,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F4EF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE8F5E9)),
        ),
        child: Column(
          children: [
            Icon(icon, color: _kGreen, size: 26),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: _kInk, fontWeight: FontWeight.w800, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}