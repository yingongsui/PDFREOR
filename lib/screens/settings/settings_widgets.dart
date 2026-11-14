import 'package:flutter/material.dart';
import '../../services/pdf_thumbnail_service.dart';

class SettingsSectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const SettingsSectionHeader({
    super.key,
    required this.title,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

class SettingsFeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const SettingsFeatureRow({
    super.key,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.blue.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

void showClearThumbnailCacheDialog(BuildContext hostContext) {
  showDialog(
    context: hostContext,
    builder: (dialogContext) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.cleaning_services_rounded, color: Colors.orange),
          SizedBox(width: 8),
          Text('Clear Thumbnail Cache'),
        ],
      ),
      content: const Text(
        'This will clear cached PDF thumbnails. Thumbnails will be regenerated automatically as you browse files.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.pop(dialogContext);
            await PdfThumbnailService.instance.clearAllCache();
            if (!hostContext.mounted) return;
            ScaffoldMessenger.of(hostContext).showSnackBar(
              const SnackBar(
                content: Text('Thumbnail cache cleared successfully'),
                duration: Duration(seconds: 2),
              ),
            );
          },
          child: const Text('Clear'),
        ),
      ],
    ),
  );
}
