import 'package:material_ui/material_ui.dart';
import '../../services/pdf_thumbnail_service.dart';
import '../../widgets/app_toast.dart';

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

class SettingsCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const SettingsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: padding != null ? Padding(padding: padding!, child: child) : child,
    );
  }
}

class SettingsIconBadge extends StatelessWidget {
  final IconData icon;

  const SettingsIconBadge({
    super.key,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: theme.colorScheme.primary, size: 22),
    );
  }
}

class SettingsCardHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final double titleFontSize;

  const SettingsCardHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.titleFontSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SettingsIconBadge(icon: icon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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
            AppToast.show(
              hostContext,
              'Thumbnail cache cleared successfully',
              icon: Icons.check_circle_outline_rounded,
            );
          },
          child: const Text('Clear'),
        ),
      ],
    ),
  );
}
