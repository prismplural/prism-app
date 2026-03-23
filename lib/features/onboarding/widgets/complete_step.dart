import 'package:flutter/material.dart';

class CompleteStep extends StatelessWidget {
  const CompleteStep({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.check_circle,
            size: 64,
            color: Colors.green,
          ),
          const SizedBox(height: 16),
          const Text(
            "You're All Set!",
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your system is ready to use',
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 32),

          // Next steps
          const _NextStepRow(
            icon: Icons.swap_horiz,
            color: Colors.cyan,
            title: 'Track fronting sessions',
            description: 'Log who is currently fronting and view history',
          ),
          const SizedBox(height: 16),
          const _NextStepRow(
            icon: Icons.chat_bubble_outline,
            color: Colors.orange,
            title: 'Start chatting',
            description: 'Send messages between system members',
          ),
          const SizedBox(height: 16),
          const _NextStepRow(
            icon: Icons.poll_outlined,
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
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              Text(
                description,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
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
