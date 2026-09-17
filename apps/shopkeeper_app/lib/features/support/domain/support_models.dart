/// Support-domain single source of truth for the Help & Support module.
///
/// The FAQ content, the published support channels and the report-issue
/// taxonomies are declared ONCE here and rendered by every support surface
/// (`SupportScreen`, `SupportFaqScreen`, `ContactSupportScreen`,
/// `ReportIssueScreen`). Keeping them together means a copy or phone-number
/// change can never drift between the support hub and the detail screens.
library;

/// Published Help-centre contact channels. Constants on purpose — these are
/// quoted verbatim in `ContactSupportScreen`, which lets a shopkeeper copy them
/// straight into their mail/phone app.
abstract final class SupportContact {
  SupportContact._();

  static const String email = 'support@passly.biz';
  static const String phone = '+91 90000 00000';
  static const String hours = 'Mon-Sat, 9:00 AM - 7:00 PM IST';
}

/// One frequently asked question with its answer and filter category.
class FaqEntry {
  const FaqEntry({
    required this.category,
    required this.question,
    required this.answer,
  });

  final String category;
  final String question;
  final String answer;

  /// True when [query] (already trimmed + lower-cased by the caller) appears in
  /// the question, the answer or the category.
  bool matches(String query) =>
      question.toLowerCase().contains(query) ||
      answer.toLowerCase().contains(query) ||
      category.toLowerCase().contains(query);
}

/// FAQ categories in display order — the help centre renders these as filter
/// chips, so the order here IS the order on screen.
const List<String> faqCategories = [
  'Getting started',
  'Products',
  'Inventory',
  'Offers & pricing',
  'POS sync',
  'Account',
];

/// The complete in-app help centre.
///
/// Answers are deliberately short and point at the screen that does the job —
/// a FAQ that paraphrases a workflow drifts out of sync with the app.
const List<FaqEntry> supportFaqs = [
  FaqEntry(
    category: 'Getting started',
    question: 'How do I set up my shop?',
    answer:
        'Open the Account tab, tap "My business" and follow the setup steps: '
        'business details, category, operating hours and shop location. Your '
        'shop appears in customer searches once the details are saved.',
  ),
  FaqEntry(
    category: 'Products',
    question: 'How do I add products?',
    answer:
        'Tap the "+" button on the Products screen. You can add items one by '
        'one, scan a product barcode, or import a whole catalogue from Excel '
        'in the Import Centre.',
  ),
  FaqEntry(
    category: 'Products',
    question: 'Can I import my full catalogue from Excel?',
    answer:
        'Yes. Open Account > Import Centre, download the sample workbook, fill '
        'it in and upload it. Every row is shown in a preview before anything '
        'is saved, so a bad file cannot overwrite live prices.',
  ),
  FaqEntry(
    category: 'Inventory',
    question: 'How do I update stock?',
    answer:
        'Tap any product on the Products screen (or in Inventory) and change '
        'its quantity. Every adjustment is recorded in that product\'s stock '
        'history so you can trace what changed and when.',
  ),
  FaqEntry(
    category: 'Inventory',
    question: 'What does "needs refresh" mean in Inventory?',
    answer:
        'It marks products whose stock or price has not been confirmed '
        'recently. Customers see stale results for those items, so the '
        'Inventory freshness view lists them first.',
  ),
  FaqEntry(
    category: 'Offers & pricing',
    question: 'How do I run a discount?',
    answer:
        'Go to Offers, tap "Create offer", choose the discount and the '
        'products it applies to, then publish it. Active offers are listed '
        'with their end date, so you always know what customers are seeing.',
  ),
  FaqEntry(
    category: 'Offers & pricing',
    question: 'Why did my price change not show up for customers?',
    answer:
        'Price updates apply as soon as they are saved; ask the customer to '
        'pull-to-refresh. The product\'s price history confirms the new value '
        'was recorded.',
  ),
  FaqEntry(
    category: 'POS sync',
    question: 'How do I connect my billing software (POS)?',
    answer:
        'Open Account > All features > POS, pick your billing provider, enter '
        'its credentials and connect. The first sync pulls your bill items '
        'into the catalogue.',
  ),
  FaqEntry(
    category: 'POS sync',
    question: 'A POS sync failed. What should I do?',
    answer:
        'Open the POS screen — the failed job shows why it stopped. Fix the '
        'credentials or the rejected item, then retry the job. Already synced '
        'data is never rolled back.',
  ),
  FaqEntry(
    category: 'Account',
    question: 'How do I change the phone number or e-mail on my account?',
    answer:
        'Your sign-in identity is verified by Google, so these cannot be '
        'edited in the app. Contact support and we will update them for you.',
  ),
  FaqEntry(
    category: 'Account',
    question: 'I was signed out unexpectedly.',
    answer:
        'Sessions expire for security, and signing in on another device can '
        'end the previous one. Sign in again with the same Google account — '
        'your shop data is untouched.',
  ),
  FaqEntry(
    category: 'Account',
    question: 'Which documents do I need for shop verification?',
    answer:
        'A government-issued business or shop licence plus a matching address '
        'proof. Upload them from the shop profile; the verification badge on '
        'your shop turns green once the team approves them.',
  ),
];

/// What a report is about — drives the category picker on the report screen.
enum IssueCategory {
  products('Products & catalogue'),
  inventory('Inventory & stock'),
  offers('Offers & pricing'),
  pos('POS / billing sync'),
  payments('Payments & subscription'),
  account('Account & sign-in'),
  other('Something else');

  const IssueCategory(this.label);

  final String label;
}

/// How badly the issue blocks the shopkeeper — sets the triage priority of the
/// report that gets sent to support.
enum IssueSeverity {
  low('Low - annoying but workable'),
  medium('Medium - slows me down'),
  high('High - I cannot use the app');

  const IssueSeverity(this.label);

  final String label;
}