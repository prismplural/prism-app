import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

class CompleteStep extends StatelessWidget {
  const CompleteStep({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            AppIcons.checkCircle,
            size: 64,
            color: Colors.green,
          ),
          const SizedBox(height: 16),
          const Text(
            "You're All Set!",
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.warmWhite,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your system is ready to use',
            style: TextStyle(
              fontSize: 15,
              color: AppColors.warmWhite.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 32),

          // Next steps
          _NextStepRow(
            icon: AppIcons.swapHoriz,
            color: Colors.cyan,
            title: 'Track fronting sessions',
            description: 'Log who is currently fronting and view history',
          ),
          const SizedBox(height: 16),
          _NextStepRow(
            icon: AppIcons.chatBubbleOutline,
            color: Colors.orange,
            title: 'Start chatting',
            description: 'Send messages between system members',
          ),
          const SizedBox(height: 16),
          _NextStepRow(
            icon: AppIcons.pollOutlined,
            color: Colors.indigo,
            title: 'Create polls',
            description: 'Make decisions together as a system',
          ),
        ],
      ),
    );
  }
}

class _NextStepRow extends StatelessWidget {
  const _NextStepRow({
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
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.warmWhite,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              Text(
                description,
                style: TextStyle(
                  color: AppColors.warmWhite.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
