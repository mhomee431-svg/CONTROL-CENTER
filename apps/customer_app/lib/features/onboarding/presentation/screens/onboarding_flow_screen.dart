import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../controllers/onboarding_controller.dart';
import '../widgets/illustrations.dart';

/// Onboarding Flow — exactly the five spec screens, kept simple.
///
/// 1. Welcome
/// 2. Search Nearby Products
/// 3. Compare Price & Availability
/// 4. Find Shop & Get Directions
/// 5. Get Started
///
/// No permission is requested here: location is only asked later from
/// the location screens where its purpose is clear on screen.
class OnboardingFlowScreen extends ConsumerStatefulWidget {
  const OnboardingFlowScreen({super.key});

  @override
  ConsumerState<OnboardingFlowScreen> createState() =>
      _OnboardingFlowScreenState();
}

class _OnboardingFlowScreenState extends ConsumerState<OnboardingFlowScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  late final List<OnboardingStep> _steps = _buildSteps();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<OnboardingStep> _buildSteps() {
    return const [
      OnboardingStep(
        number: '1',
        title: 'Welcome',
        subtitle: 'Find products in shops around you',
        headerColor: Color(0xFF1E3A8A),
        illustration: AppLaunchIllustration(),
        sideIcons: [
          FlowIcon(icon: Icons.store, label: 'Local Shops'),
          FlowIcon(icon: Icons.location_on, label: 'Nearby First'),
          FlowIcon(icon: Icons.search, label: 'Fast Search'),
          FlowIcon(icon: Icons.rocket_launch, label: 'Get Started'),
        ],
      ),
      OnboardingStep(
        number: '2',
        title: 'Search Nearby Products',
        subtitle: 'Type what you need, see it around you',
        headerColor: Color(0xFF7C3AED),
        illustration: ListScreenIllustration(
          heroIcon: Icons.search,
          accent: Color(0xFF2563EB),
          title: 'Search Nearby Products',
        ),
        sideIcons: [
          FlowIcon(icon: Icons.search, label: 'Search Bar'),
          FlowIcon(icon: Icons.my_location, label: 'Around You'),
          FlowIcon(icon: Icons.category, label: 'Categories'),
          FlowIcon(icon: Icons.bolt, label: 'Instant Results'),
        ],
      ),
      OnboardingStep(
        number: '3',
        title: 'Compare Price & Availability',
        subtitle: 'Compare shops before you step out',
        headerColor: Color(0xFF059669),
        illustration: ListScreenIllustration(
          heroIcon: Icons.compare_arrows,
          accent: Color(0xFF059669),
          title: 'Compare Price & Availability',
        ),
        sideIcons: [
          FlowIcon(icon: Icons.local_offer, label: 'Best Price'),
          FlowIcon(icon: Icons.check_circle, label: 'In Stock'),
          FlowIcon(icon: Icons.compare_arrows, label: 'Compare'),
          FlowIcon(icon: Icons.savings, label: 'Save More'),
        ],
      ),
      OnboardingStep(
        number: '4',
        title: 'Find Shop & Get Directions',
        subtitle: 'Pick a shop, navigate straight there',
        headerColor: Color(0xFFDC2626),
        illustration: LocationIllustration(),
        sideIcons: [
          FlowIcon(icon: Icons.store, label: 'Choose Shop'),
          FlowIcon(icon: Icons.map, label: 'Map Preview'),
          FlowIcon(icon: Icons.directions, label: 'Directions'),
          FlowIcon(icon: Icons.navigation, label: 'Reach Fast'),
        ],
      ),

      OnboardingStep(
        number: '5',
        title: 'Get Started',
        subtitle: 'Browse nearby products right away',
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
    ];
  }

  Future<void> _finishOnboarding() async {
    await ref.read(onboardingCompletedProvider.notifier).completeOnboarding();
    if (mounted) context.go('/welcome');
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
                  'HyperLocal',
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
      padding: const EdgeInsets.all(AppSpacing.md),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final content = Column(
            children: [
              _buildStepHeader(step),
              const SizedBox(height: AppSpacing.md),
              Expanded(child: _buildPhoneMockup(step)),
            ],
          );

          if (constraints.maxWidth < 720) return content;

          return Row(
            children: [
              Expanded(flex: 3, child: content),
              const SizedBox(width: AppSpacing.md),
              _buildSideIcons(step.sideIcons, step.headerColor),
            ],
          );
        },
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
                  key: const Key('onboardingStepTitle'),
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
                  Icon(
                    Icons.signal_cellular_4_bar,
                    color: Colors.white,
                    size: 12,
                  ),
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
      // Scrollable so short viewports (small phones, landscape, and the test
      // harness' 600px height) never trigger a RenderFlex overflow.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                mainAxisSize: MainAxisSize.min,
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
                      curve: Curves.easeInOut,
                    )
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
                  _finishOnboarding();
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
