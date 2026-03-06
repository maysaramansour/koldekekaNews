import 'package:flutter/material.dart';
import '../models/article.dart';

class SourceFilter extends StatelessWidget {
  final List<NewsSource> sources;
  final String selected;
  final ValueChanged<String> onSelected;

  const SourceFilter({
    super.key,
    required this.sources,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final allSources = [
      const NewsSource(name: 'all', color: '#2c3e50'),
      ...sources,
    ];

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: allSources.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final src = allSources[i];
          final isSelected = src.name == selected;
          final label = src.name == 'all' ? 'All Sources' : src.name;
          final color = isSelected ? src.sourceColor : Colors.transparent;

          return GestureDetector(
            onTap: () => onSelected(src.name),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withOpacity(0.85)
                    : Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? color
                      : Colors.white.withOpacity(0.25),
                  width: 1,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 12,
                  fontWeight: isSelected
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
