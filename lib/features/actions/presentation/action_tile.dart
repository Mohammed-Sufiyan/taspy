import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../domain/card_action.dart';

/// One action in a list: icon badge, title and detail line.
class ActionTile extends StatelessWidget {
  const ActionTile({
    super.key,
    required this.action,
    this.trailing,
    this.onTap,
    this.detail,
    this.detailColor,
  });

  final CardAction action;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Replaces the action's own subtitle (e.g. a status or error).
  final String? detail;
  final Color? detailColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sub = detail ?? action.subtitle;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: TapsyColors.lime.withValues(alpha: 0.12),
                border: Border.all(
                  color: TapsyColors.lime.withValues(alpha: 0.35),
                ),
              ),
              child: Icon(action.type.icon, size: 19, color: TapsyColors.lime),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          action.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      if (action.whenLabel case final schedule?) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: TapsyColors.lime.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            schedule,
                            maxLines: 1,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: TapsyColors.lime,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (sub != null && sub.isNotEmpty)
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: detailColor,
                      ),
                    ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
