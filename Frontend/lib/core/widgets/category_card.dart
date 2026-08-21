import 'package:flutter/material.dart';
import '../../features/home/domain/models/home_data.dart';
import '../theme/app_theme.dart';
import 'network_image_view.dart';

class CategoryCard extends StatelessWidget {
  final Category category;
  final VoidCallback onTap;

  const CategoryCard({super.key, required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade200, width: 2),
            ),
            child: ClipOval(
              child: NetworkImageView(
                imageUrl: category.iconUrl,
                width: 56,
                height: 56,
                borderRadius: 0,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            category.name,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}