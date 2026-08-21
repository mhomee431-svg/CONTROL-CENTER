import 'package:flutter/material.dart';
import '../../domain/models/shop_details_models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/network_image_view.dart';

class ShopHeader extends StatelessWidget {
  final ShopProfile shop;
  const ShopHeader({super.key, required this.shop});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NetworkImageView(imageUrl: shop.imageUrl, height: 200, width: double.infinity, borderRadius: 0),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(shop.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.secondary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        const Icon(Icons.star, size: 16, color: AppColors.secondary),
                        const SizedBox(width: 4),
                        Text('${shop.rating}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: shop.isOpenNow ? AppColors.secondary : AppColors.error,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(shop.isOpenNow ? 'OPEN' : 'CLOSED', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text('${shop.distanceInKm} km away • ${shop.reviewCount} reviews', style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on, size: 16, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Expanded(child: Text(shop.address, style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.3))),
                ],
              )
            ],
          ),
        )
      ],
    );
  }
}