import 'package:flutter/material.dart';
import '../../domain/models/product_details_models.dart';
import '../../../../core/theme/app_theme.dart';

/// Displays the **PRODUCT MASTER** (global static information).
///
/// This section shows only product-level data that is NOT shop-specific:
/// name, brand, category, variant, MRP, product info, attributes,
/// description, and identifiers.
class ProductMasterSection extends StatelessWidget {
  final ProductMasterDetails product;

  const ProductMasterSection({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Brand ──────────────────────────────────────────────────────
          Text(
            product.brand.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),

          // ── Name ───────────────────────────────────────────────────────
          Text(
            product.name,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.sm),

          // ── Category / Subcategory ─────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.category_outlined, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  [
                    if (product.category.isNotEmpty) product.category,
                    if (product.subcategory != null && product.subcategory!.isNotEmpty)
                      ' • ${product.subcategory}',
                  ].join(),
                  style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // ── MRP / Price Range ──────────────────────────────────────────
          if (product.mrp != null || product.priceRange != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (product.mrp != null)
                  Text(
                    'MRP ₹${product.mrp!.toInt()}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  )
                else if (product.priceRange != null)
                  Text(
                    product.priceRange!,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                if (product.baseUnit != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    'per ${product.baseUnit}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // ── Variants ───────────────────────────────────────────────────
          if (product.variants.isNotEmpty) ...[
            const _SectionTitle('Variants'),
            const SizedBox(height: AppSpacing.sm),
            ...product.variants.map((v) => _VariantChip(variant: v)),
            const SizedBox(height: AppSpacing.md),
          ],

          // ── Product Information ────────────────────────────────────────
          if (product.shortDescription != null ||
              product.baseQuantity != null) ...[
            const _SectionTitle('Product Information'),
            const SizedBox(height: AppSpacing.sm),
            if (product.shortDescription != null)
              Text(
                product.shortDescription!,
                style: const TextStyle(color: AppColors.textMuted, height: 1.4),
              ),
            if (product.baseQuantity != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Quantity: ${product.baseQuantity} ${product.baseUnit ?? ''}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
          ],

          // ── Attributes ─────────────────────────────────────────────────
          if (product.attributes.isNotEmpty) ...[
            const _SectionTitle('Attributes'),
            const SizedBox(height: AppSpacing.sm),
            ...product.attributes.map((attr) => _AttributeRow(attribute: attr)),
            const SizedBox(height: AppSpacing.md),
          ],

          // ── Description ────────────────────────────────────────────────
          if (product.description != null && product.description!.isNotEmpty) ...[
            const _SectionTitle('Description'),
            const SizedBox(height: AppSpacing.sm),
            Text(
              product.description!,
              style: const TextStyle(color: AppColors.textMuted, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // ── Identifiers ────────────────────────────────────────────────
          if (product.identifiers.isNotEmpty) ...[
            const _SectionTitle('Identifiers'),
            const SizedBox(height: AppSpacing.sm),
            ...product.identifiers.map((id) => _IdentifierRow(identifier: id)),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    );
  }
}

class _VariantChip extends StatelessWidget {
  final ProductVariant variant;
  const _VariantChip({required this.variant});

  @override
  Widget build(BuildContext context) {
    final attrText = variant.attributes.entries
        .map((e) => '${e.key}: ${e.value}')
        .join(' • ');

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              variant.name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          if (attrText.isNotEmpty)
            Text(
              attrText,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }
}

class _AttributeRow extends StatelessWidget {
  final ProductAttribute attribute;
  const _AttributeRow({required this.attribute});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              attribute.name,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              attribute.values.join(', '),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _IdentifierRow extends StatelessWidget {
  final ProductIdentifier identifier;
  const _IdentifierRow({required this.identifier});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              identifier.type,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              identifier.value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (identifier.isPrimary)
            const Text(
              'Primary',
              style: TextStyle(fontSize: 11, color: AppColors.secondary, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}