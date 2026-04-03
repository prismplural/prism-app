import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

class WelcomeStep extends StatelessWidget {
  const WelcomeStep({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _FeatureRow(
            icon: AppIcons.shieldOutlined,
            color: Colors.blue,
            title: 'Privacy First',
            description:
                'Your data stays on your device with optional encrypted cloud sync.',
          ),
          SizedBox(height: 20),
          _FeatureRow(
            icon: AppIcons.cloudOutlined,
            color: Colors.cyan,
            title: 'Cloud Sync',
            description:
                'Optionally sync across devices with end-to-end encryption.',
          ),
          SizedBox(height: 20),
          _FeatureRow(
            icon: AppIcons.paletteOutlined,
            color: Colors.purple,
            title: 'Customizable',
            description:
                'Tailor terminology, colors, and features to your system.',
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.warmWhite,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  color: AppColors.warmWhite.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
