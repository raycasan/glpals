import 'package:flutter/material.dart';

/// One tab in [GlpalsNavBar].
class NavItem {
  const NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final IconData activeIcon;
  final String label;

  /// The tab's own accent, used for the pill and the active icon.
  final Color color;
}

/// Bottom bar where every tab carries its own colour. The selected tab grows a
/// tinted pill behind its icon and swaps to the filled version of the glyph.
class GlpalsNavBar extends StatelessWidget {
  const GlpalsNavBar({
    super.key,
    required this.index,
    required this.onTap,
    required this.items,
  });

  final int index;
  final ValueChanged<int> onTap;
  final List<NavItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .06),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _Tab(
                    item: items[i],
                    selected: i == index,
                    muted: scheme.onSurfaceVariant,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.item,
    required this.selected,
    required this.muted,
    required this.onTap,
  });
  final NavItem item;
  final bool selected;
  final Color muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Every tab keeps its own colour, dimmed when it is not the current one,
    // so the bar reads as a row of colours rather than grey placeholders.
    final iconColor = selected ? item.color : item.color.withValues(alpha: .62);
    final labelColor = selected ? item.color : muted;
    return InkResponse(
      onTap: onTap,
      radius: 42,
      containedInkWell: false,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutBack,
            width: selected ? 46 : 38,
            height: 30,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: selected ? .20 : .08),
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: Alignment.center,
            child: AnimatedScale(
              scale: selected ? 1.08 : 1,
              duration: const Duration(milliseconds: 240),
              child: Icon(selected ? item.activeIcon : item.icon,
                  size: selected ? 22 : 21, color: iconColor),
            ),
          ),
          const SizedBox(height: 3),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: labelColor,
            ),
            child:
                Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
