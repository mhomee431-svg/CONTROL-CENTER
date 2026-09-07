import '../domain/home_repository.dart';
import '../domain/models/home_data.dart';

class MockHomeRepository implements HomeRepository {
  @override
  @override
  Future<HomeData> fetchHomeFeed({double? latitude, double? longitude}) async {
    // Simulate network latency
    await Future.delayed(const Duration(seconds: 2));

    return const HomeData(
      categories: [
        Category(id: '1', name: 'Electronics', iconUrl: 'https://via.placeholder.com/150'),
        Category(id: '2', name: 'Groceries', iconUrl: 'https://via.placeholder.com/150'),
        Category(id: '3', name: 'Medicines', iconUrl: 'https://via.placeholder.com/150'),
        Category(id: '4', name: 'Hardware', iconUrl: 'https://via.placeholder.com/150'),
      ],
      popularProducts: [
        Product(
          id: 'p1',
          name: 'Samsung Galaxy S24',
          brand: 'Samsung',
          imageUrl: 'https://via.placeholder.com/300',
          priceRange: '₹75,000 - ₹80,000',
        ),
        Product(
          id: 'p2',
          name: 'Aashirvaad Atta 5kg',
          brand: 'Aashirvaad',
          imageUrl: 'https://via.placeholder.com/300',
          priceRange: '₹220 - ₹240',
        ),
        Product(
          id: 'p3',
          name: 'Dettol Handwash 750ml',
          brand: 'Dettol',
          imageUrl: 'https://via.placeholder.com/300',
          priceRange: '₹99 - ₹120',
        ),
        Product(
          id: 'p4',
          name: 'Bajaj Ceiling Fan',
          brand: 'Bajaj',
          imageUrl: 'https://via.placeholder.com/300',
          priceRange: '₹1,800 - ₹2,200',
        ),
      ],
      nearbyShops: [
        Shop(
          id: 's1',
          name: 'Gupta Electronics',
          imageUrl: 'https://via.placeholder.com/300',
          distance: 1.2,
          rating: 4.5,
          isVerified: true,
        ),
        Shop(
          id: 's2',
          name: 'Sharma General Store',
          imageUrl: 'https://via.placeholder.com/300',
          distance: 0.8,
          rating: 4.2,
          isVerified: false,
        ),
        Shop(
          id: 's3',
          name: 'Patna Medical Hall',
          imageUrl: 'https://via.placeholder.com/300',
          distance: 2.1,
          rating: 4.8,
          isVerified: true,
        ),
      ],
      recentSearches: ['Paracetamol 500mg', 'Amul Butter', 'Ceiling Fan'],
      recentlyViewed: [
        Product(
          id: 'rv1',
          name: 'Colgate MaxFresh',
          brand: 'Colgate',
          imageUrl: 'https://via.placeholder.com/300',
          priceRange: '₹85 - ₹110',
        ),
        Product(
          id: 'rv2',
          name: 'Tata Salt 1kg',
          brand: 'Tata',
          imageUrl: 'https://via.placeholder.com/300',
          priceRange: '₹25 - ₹30',
        ),
      ],
      recommendedProducts: [
        Product(
          id: 'r1',
          name: 'Nivea Body Lotion',
          brand: 'Nivea',
          imageUrl: 'https://via.placeholder.com/300',
          priceRange: '₹180 - ₹220',
        ),
        Product(
          id: 'r2',
          name: 'Fortune Sunflower Oil',
          brand: 'Fortune',
          imageUrl: 'https://via.placeholder.com/300',
          priceRange: '₹140 - ₹160',
        ),
      ],
      promotions: [
        Promotion(
          id: 'promo1',
          title: 'Monsoon Mega Sale',
          subtitle: 'Up to 40% off on electronics & appliances',
          imageUrl: 'https://via.placeholder.com/600x200',
          ctaLabel: 'Shop Now',
          ctaTarget: '/search',
        ),
        Promotion(
          id: 'promo2',
          title: 'Fresh Groceries',
          subtitle: 'Daily essentials delivered from nearby stores',
          imageUrl: 'https://via.placeholder.com/600x200',
          ctaLabel: 'Explore',
          ctaTarget: '/search',
        ),
      ],
    );
  }
}