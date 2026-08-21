import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/utils/logger.dart';
import '../domain/product_detail_repository.dart';
import '../domain/product_detail_models.dart';

class ApiProductDetailRepository implements ProductDetailRepository {
  ApiProductDetailRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<ProductDetail> getProductDetail(int productId) async {
    try {
      final json = await _apiClient.get('/products/$productId');
      return ProductDetail.fromJson(json);
    } on ApiException catch (e) {
      throw ProductDetailException(e.message);
    } catch (e) {
      throw ProductDetailException('Failed to load product details');
    }
  }

  @override
  Future<List<ProductReview>> getProductReviews(int productId, {int page = 1, int pageSize = 20}) async {
    try {
      final json = await _apiClient.get(
        '/products/$productId/reviews',
        queryParameters: {'page': page, 'page_size': pageSize},
      );
      return (json['reviews'] as List)
          .map((review) => ProductReview.fromJson(review as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Failed to load reviews: $e');
    }
  }
}