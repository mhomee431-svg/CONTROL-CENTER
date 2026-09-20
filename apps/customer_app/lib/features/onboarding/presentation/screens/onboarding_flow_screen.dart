import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/illustrations.dart';

/// Onboarding Flow Screen — shows the complete customer journey as
/// swipeable steps with phone mockups, matching the reference design.
class OnboardingFlowScreen extends StatefulWidget {
  const OnboardingFlowScreen({super.key});

  @override
  State<OnboardingFlowScreen> createState() => _OnboardingFlowScreenState();
}

class _OnboardingFlowScreenState extends State<OnboardingFlowScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  late final List<OnboardingStep> _steps;

  @override
  void initState() {
    super.initState();
    _steps = _buildSteps();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<OnboardingStep> _buildSteps() {
    return const [
      OnboardingStep(
        number: '1',
        title: 'App Launch & Onboarding',
        subtitle: 'Welcome to Your Nearby Product World',
        headerColor: Color(0xFF1E3A8A),
        illustration: AppLaunchIllustration(),
        sideIcons: [
          FlowIcon(icon: Icons.water_drop, label: 'Splash Screen'),
          FlowIcon(icon: Icons.tour, label: 'App Introduction'),
          FlowIcon(icon: Icons.star, label: 'Key Features'),
          FlowIcon(icon: Icons.rocket_launch, label: 'Get Started'),
        ],
      ),
      OnboardingStep(
        number: '2',
        title: 'Customer Registration / Login',
        subtitle: 'Quick & Secure Access',
        headerColor: Color(0xFF7C3AED),
        illustration: RegistrationIllustration(),
        sideIcons: [
          FlowIcon(icon: Icons.phone_android, label: 'Mobile Login'),
          FlowIcon(icon: Icons.lock, label: 'OTP Verification'),
          FlowIcon(icon: Icons.person_add, label: 'New Registration'),
          FlowIcon(icon: Icons.security, label: 'Secure Session'),
        ],
      ),
      OnboardingStep(
        number: '3',
        title: 'Location Selection',
        subtitle: 'Find Shops Near You',
        headerColor: Color(0xFF059669),
        illustration: LocationIllustration(),
        sideIcons: [
          FlowIcon(icon: Icons.my_location, label: 'Auto Location'),
          FlowIcon(icon: Icons.edit_location, label: 'Manual Selection'),
          FlowIcon(icon: Icons.bookmark, label: 'Saved Addresses'),
          FlowIcon(icon: Icons.search, label: 'Nearby Search'),
        ],
      ),
      OnboardingStep(
        number: '4',
        title: 'Home Screen - Product Discovery',
        subtitle: 'Explore Products & Shops',
        headerColor: Color(0xFFDC2626),
        illustration: ListScreenIllustration(
          heroIcon: Icons.home,
          accent: Color(0xFFDC2626),
          title: 'Discover Nearby Products',
        ),
        sideIcons: [
          FlowIcon(icon: Icons.home, label: 'Home Feed'),
          FlowIcon(icon: Icons.category, label: 'Categories'),
          FlowIcon(icon: Icons.local_offer, label: 'Offers'),
          FlowIcon(icon: Icons.store, label: 'Nearby Shops'),
        ],
      ),
      OnboardingStep(
        number: '5',
        title: 'Product Search',
        subtitle: 'Find What You Need',
        headerColor: Color(0xFF2563EB),
        illustration: ListScreenIllustration(
          heroIcon: Icons.search,
          accent: Color(0xFF2563EB),
          title: 'Search Products',
        ),
        sideIcons: [
          FlowIcon(icon: Icons.search, label: 'Search Products'),
          FlowIcon(icon: Icons.auto_awesome, label: 'Suggestions'),
          FlowIcon(icon: Icons.history, label: 'Recent Searches'),
          FlowIcon(icon: Icons.label, label: 'Quick Tags'),
        ],
      ),
      OnboardingStep(
        number: '6',
        title: 'Search Results',
        subtitle: 'Compare Prices & Availability',
        headerColor: Color(0xFFEA580C),
        illustration: ListScreenIllustration(
          heroIcon: Icons.storefront,
          accent: Color(0xFFEA580C),
          title: 'Results & Shops',
        ),
        sideIcons: [
          FlowIcon(icon: Icons.filter_list, label: 'Filter Results'),
          FlowIcon(icon: Icons.sort, label: 'Sort by Price'),
          FlowIcon(icon: Icons.storefront, label: 'Shop List'),
          FlowIcon(icon: Icons.map, label: 'Map View'),
        ],
      ),
      OnboardingStep(
        number: '7',
        title: 'Product Details',
        subtitle: 'Complete Information',
        headerColor: Color(0xFF0891B2),
        illustration: ListScreenIllustration(
          heroIcon: Icons.inventory_2,
          accent: Color(0xFF0891B2),
          title: 'Product Details',
        ),
        sideIcons: [
          FlowIcon(icon: Icons.image, label: 'Images'),
          FlowIcon(icon: Icons.info, label: 'Details'),
          FlowIcon(icon: Icons.star_rate, label: 'Reviews'),
          FlowIcon(icon: Icons.store, label: 'Available Shops'),
        ],
      ),
      OnboardingStep(
        number: '8',
        title: 'Shop Profile & Directions',
        subtitle: 'Visit Your Shop',
        headerColor: Color(0xFFDB2777),
        illustration: ListScreenIllustration(
          heroIcon: Icons.store,
          accent: Color(0xFFDB2777),
          title: 'Shop Profile',
        ),
        sideIcons: [
          FlowIcon(icon: Icons.store, label: 'Shop Info'),
          FlowIcon(icon: Icons.directions, label: 'Directions'),
          FlowIcon(icon: Icons.call, label: 'Contact'),
          FlowIcon(icon: Icons.share, label: 'Share'),
        ],
      ),
      OnboardingStep(
        number: '9',
        title: 'Favorites & History',
        subtitle: 'Track Your Activity',
        headerColor: Color(0xFF7C3AED),
        illustration: ListScreenIllustration(
          heroIcon: Icons.favorite,
          accent: Color(0xFF7C3AED),
          title: 'Saved & Viewed',
        ),
        sideIcons: [
          FlowIcon(icon: Icons.favorite, label: 'Favorites'),
          FlowIcon(icon: Icons.bookmark, label: 'Saved Items'),
          FlowIcon(icon: Icons.history, label: 'Search History'),
          FlowIcon(icon: Icons.visibility, label: 'Recently Viewed'),
        ],
      ),
      OnboardingStep(
        number: '10',
        title: 'Notifications & Updates',
        subtitle: 'Stay Informed',
        headerColor: Color(0xFF16A34A),
        illustration: ListScreenIllustration(
          heroIcon: Icons.notifications,
          accent: Color(0xFF16A34A),
          title: 'Your Updates',
        ),
        sideIcons: [
          FlowIcon(icon: Icons.local_offer, label: 'Offers'),
          FlowIcon(icon: Icons.price_change, label: 'Price Drops'),
          FlowIcon(icon: Icons.store, label: 'Shop Updates'),
          FlowIcon(icon: Icons.directions, label: 'Visit Reminders'),
        ],
      ),
      OnboardingStep(
        number: '11',
        title: 'Account & Settings',
        subtitle: 'Manage Profile',
        headerColor: Color(0xFF6366F1),
        illustration: ListScreenIllustration(
          heroIcon: Icons.person,
          accent: Color(0xFF6366F1),
          title: 'Account Settings',
        ),
        sideIcons: [
          FlowIcon(icon: Icons.person, label: 'Profile'),
          FlowIcon(icon: Icons.location_on, label: 'Addresses'),
          FlowIcon(icon: Icons.notifications, label: 'Alert Prefs'),
          FlowIcon(icon: Icons.settings, label: 'Settings'),
        ],
      ),
      OnboardingStep(
        number: '12',
        title: 'Real-World Purchase Flow',
        subtitle: 'From Search to Visit',
        headerColor: Color(0xFF0EA5E9),
        illustration: ListScreenIllustration(
          heroIcon: Icons.compare_arrows,
          accent: Color(0xFF0EA5E9),
          title: 'Compare & Visit',
        ),
        sideIcons: [
          FlowIcon(icon: Icons.search, label: 'Search'),
          FlowIcon(icon: Icons.store, label: 'Find Shops'),
          FlowIcon(icon: Icons.compare_arrows, label: 'Compare'),
          FlowIcon(icon: Icons.directions_walk, label: 'Visit'),
        ],
      ),
      OnboardingStep(
        number: '13',
        title: 'Complete Journey',
        subtitle: 'Hyperlocal Experience Delivered',
        headerColor: Color(0xFF1E3A8A),
        illustration: ListScreenIllustration(
          heroIcon: Icons.emoji_events,
          accent: Color(0xFF1E3A8A),
          title: 'Journey Complete',
        ),
        sideIcons: [
          FlowIcon(icon: Icons.map, label: 'Discover'),
          FlowIcon(icon: Icons.storefront, label: 'Shop Local'),
          FlowIcon(icon: Icons.thumb_up, label: 'Trust'),
          FlowIcon(icon: Icons.emoji_events, label: 'Success'),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopHeader(),
            _buildPageIndicator(),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _steps.length,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemBuilder: (context, index) =>
                    _buildOnboardingPage(_steps[index]),
              ),
            ),
            _buildBottomNavigation(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.phone_android, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  'Customer App Flow',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Text(
            '${_currentPage + 1} / ${_steps.length}',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_steps.length, (index) {
          return GestureDetector(
            onTap: () => _pageController.animateToPage(
              index,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            ),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: _currentPage == index ? 32 : 12,
              height: 12,
              decoration: BoxDecoration(
                color: _currentPage == index
                    ? _steps[_currentPage].headerColor
                    : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildOnboardingPage(OnboardingStep step) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              children: [
                _buildStepHeader(step),
                const SizedBox(height: 16),
                Expanded(child: _buildPhoneMockup(step)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _buildSideIcons(step.sideIcons, step.headerColor),
        ],
      ),
    );
  }

  Widget _buildStepHeader(OnboardingStep step) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: step.headerColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: step.headerColor.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                step.number,
                style: TextStyle(
                  color: step.headerColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  step.subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneMockup(OnboardingStep step) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 30,
            offset: Offset(0, 15),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            Container(
              height: 24,
              color: const Color(0xFF1E293B),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.signal_cellular_4_bar,
                      color: Colors.white, size: 12),
                  SizedBox(width: 4),
                  Icon(Icons.wifi, color: Colors.white, size: 12),
                  SizedBox(width: 4),
                  Icon(Icons.battery_full, color: Colors.white, size: 12),
                ],
              ),
            ),
            Expanded(child: step.illustration),
          ],
        ),
      ),
    );
  }

  Widget _buildSideIcons(List<FlowIcon> icons, Color headerColor) {
    return SizedBox(
      width: 110,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: icons.map((item) {
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0D000000),
                  blurRadius: 10,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: headerColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(item.icon, color: headerColor, size: 22),
                ),
                const SizedBox(height: 8),
                Text(
                  item.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBottomNavigation() {
    final bool isLast = _currentPage >= _steps.length - 1;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 10,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _currentPage > 0
                  ? () => _pageController.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut)
                  : null,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Previous'),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: () {
                if (isLast) {
                  context.go('/');
                } else {
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              },
              icon: Icon(isLast ? Icons.check : Icons.arrow_forward, size: 18),
              label: Text(isLast ? 'Get Started' : 'Next'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _steps[_currentPage].headerColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OnboardingStep {
  final String number;
  final String title;
  final String subtitle;
  final Color headerColor;
  final Widget illustration;
  final List<FlowIcon> sideIcons;

  const OnboardingStep({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.headerColor,
    required this.illustration,
    required this.sideIcons,
  });
}

class FlowIcon {
  final IconData icon;
  final String label;

  const FlowIcon({required this.icon, required this.label});
}
