import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/theme/app_spacing.dart';
import 'package:hyperlocal_shopkeeper_app/features/restaurants/data/menu_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/restaurants/domain/menu_models.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/core/ui/numeric_input.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';

/// What the screen is currently doing, so the body never has to guess.
enum MenuStatus { loading, ready, noProfile, failed }

/// The owner's own menu: sections, the dishes inside them, and the edits.
///
/// Scope is deliberately the menu and nothing else. A menu item carries a
/// display price and an "available today" flag, never a quantity, so there is no
/// stock control here to reach for — and no cart or order path, because those
/// belong to the customer side and are exactly what this category must not grow.
class MenuManagementScreen extends ConsumerStatefulWidget {
  const MenuManagementScreen({super.key});

  @override
  ConsumerState<MenuManagementScreen> createState() =>
      _MenuManagementScreenState();
}

class _MenuManagementScreenState extends ConsumerState<MenuManagementScreen> {
  MenuStatus _status = MenuStatus.loading;
  String? _message;
  /// The shop this menu belongs to. Every route is shop-scoped, so the app never
  /// has to carry a restaurant id it was never given.
  int? _loadedShopId;
  List<RestaurantMenuCategory> _categories = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  int? get _shopId => ref.read(selectedShopProvider)?.id;

  Future<String?> _token() =>
      ref.read(tokenStoreProvider).readAccessToken();

  Future<void> _load() async {
    final shopId = _shopId;
    if (shopId == null) {
      setState(() {
        _status = MenuStatus.noProfile;
        _message = 'Choose a shop first';
      });
      return;
    }
    setState(() {
      _status = MenuStatus.loading;
      _message = null;
    });
    final repo = ref.read(menuRepositoryProvider);
    try {
      final token = await _token();
      final restaurant = await repo.restaurantForShop(shopId, token: token);
      final menu = await repo.fetchMenu(restaurant.shopId, token: token);
      if (!mounted) return;
      setState(() {
        _loadedShopId = restaurant.shopId;
        _categories = menu.categories;
        _status = MenuStatus.ready;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _status = MenuStatus.noProfile;
        // A shop without a restaurant profile is the expected reason this lookup
        // fails, and its wording comes straight from the backend.
        _message = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _status = MenuStatus.failed;
        _message = 'Could not load your menu. Please retry.';
      });
    }
  }

  /// Runs a write, then re-reads the menu rather than patching local state.
  ///
  /// Reloading is what keeps the screen honest: the backend soft-deletes, applies
  /// its own sort order, and may nest the items differently than we assume. A
  /// locally-patched list drifts from the server on the very first edit.
  Future<void> _guard(Future<void> Function() action) async {
    if (_busy || _loadedShopId == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      final menu = await ref
          .read(menuRepositoryProvider)
          .fetchMenu(_loadedShopId!, token: await _token());
      if (!mounted) return;
      setState(() => _categories = menu.categories);
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = _describe(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _describe(Object error) =>
      error is ApiException ? error.message : 'Could not save. Please retry.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Menu')),
      floatingActionButton: _status == MenuStatus.ready
          ? FloatingActionButton.extended(
              onPressed: _busy ? null: () => _addCategory(),
              icon: const Icon(Icons.add),
              label: const Text('Section'),
            )
          : null,
      body: SafeArea(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    switch (_status) {
      case MenuStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case MenuStatus.noProfile:
      case MenuStatus.failed:
        return _MenuMessage(
          title: _status == MenuStatus.noProfile
              ? 'No restaurant profile yet'
              : 'Menu unavailable',
          message: _message ?? '',
          onRetry: _load,
        );
      case MenuStatus.ready:
        if (_categories.isEmpty) {
          return const _MenuMessage(
            title: 'Your menu is empty',
            message: 'Add a section such as Starters or Mains, then add '
                'dishes to it.',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (_message != null) ...[
              Text(
                _message!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            for (final category in _categories) ...[
              _CategoryBlock(
                category: category,
                busy: _busy,
                onAddItem: () => _addItem(category),
                onEditItem: _editItem,
                onDeleteItem: _deleteItem,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        );
  }
}

  Future<void> _addCategory() async {
    final name = await _askName(
      title: 'New section',
      hint: 'Starters, Mains, Desserts',
    );
    if (name == null || _loadedShopId == null) return;
    await _guard(() async {
      await ref.read(menuRepositoryProvider).createCategory(
            _loadedShopId!,
            RestaurantMenuCategory(id: 0, name: name, sortOrder: _categories.length),
            token: await _token(),
          );
    });
  }

  Future<void> _addItem(RestaurantMenuCategory category) =>
      _itemSheet(category: category, existing: null);

  Future<void> _editItem(RestaurantMenuItem item) =>
      _itemSheet(category: null, existing: item);

  Future<void> _itemSheet({
    required RestaurantMenuCategory? category,
    required RestaurantMenuItem? existing,
  }) async {
    if (_loadedShopId == null) return;
    final result = await showModalBottomSheet<_ItemDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MenuItemSheet(
        categoryName: category?.name,
        existing: existing,
      ),
    );
    if (result == null) return;
    await _guard(() async {
      final repo = ref.read(menuRepositoryProvider);
      final token = await _token();
      final menuCategoryId = existing != null
          // Editing a dish must not silently re-file it into whichever section
          // happened to be tapped.
          ? existing.menuCategoryId
          : category?.id;
      final item = RestaurantMenuItem(
        id: existing?.id ?? 0,
        name: result.name,
        description: result.description,
        price: result.price,
        menuCategoryId: menuCategoryId,
        veg: result.veg,
        spicy: result.spicy,
        isAvailableToday: result.availableToday,
      );
      if (existing == null) {
        await repo.createItem(_loadedShopId!, item, token: token);
      } else {
        await repo.updateItem(_loadedShopId!, item, token: token);
      }
    });
  }

  Future<void> _deleteItem(RestaurantMenuItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${item.name}?'),
        content: const Text(
          'This takes the dish off your public menu straight away.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || _loadedShopId == null) return;
    await _guard(() async {
      await ref
          .read(menuRepositoryProvider)
          .deleteItem(_loadedShopId!, item.id, token: await _token());
    });
  }

  Future<String?> _askName({
    required String title,
    required String hint,
  }) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: TextFormField(
            key: const Key('menu-section-name'),
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(hintText: hint),
            validator: (value) =>
                (value ?? '').trim().isEmpty ? 'Enter a name' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(dialogContext).pop(controller.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }
}

/// What the item sheet collects, returned to the screen as one value.
class _ItemDraft {
  const _ItemDraft({
    required this.name,
    this.description,
    this.price,
    this.veg = false,
    this.spicy = false,
    this.availableToday = true,
  });

  final String name;
  final String? description;
  final double? price;
  final bool veg;
  final bool spicy;
  final bool availableToday;
}

/// Empty / error state, shared by "no profile" and "no menu".
class _MenuMessage extends StatelessWidget {
  const _MenuMessage({
    required this.title,
    required this.message,
    this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.restaurant_menu, size: 40, color: theme.dividerColor),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
/// One section with the dishes inside it.
class _CategoryBlock extends StatelessWidget {
  const _CategoryBlock({
    required this.category,
    required this.busy,
    required this.onAddItem,
    required this.onEditItem,
    required this.onDeleteItem,
  });

  final RestaurantMenuCategory category;
  final bool busy;
  final VoidCallback onAddItem;
  final ValueChanged<RestaurantMenuItem> onEditItem;
  final ValueChanged<RestaurantMenuItem> onDeleteItem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    category.name,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  key: Key('menu-add-item-${category.id}'),
                  onPressed: busy ? null : onAddItem,
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Add dish',
                ),
              ],
            ),
            if (category.items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text(
                  'No dishes in this section yet',
                  style: theme.textTheme.bodySmall,
                ),
              )
            else
              for (final item in category.items)
                ListTile(
                  key: Key('menu-item-${item.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.name),
                  subtitle: Text(
                    [
                      if (item.price != null)
                        '₹${item.price!.toStringAsFixed(0)}',
                      if (item.veg) 'Veg',
                      if (item.spicy) 'Spicy',
                      if (!item.isAvailableToday) 'Not available today',
                    ].join(' · '),
                  ),
                  onTap: busy ? null : () => onEditItem(item),
                  trailing: IconButton(
                    key: Key('menu-delete-item-${item.id}'),
                    onPressed: busy ? null : () => onDeleteItem(item),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Remove',
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
/// Add or edit a single dish.
///
/// Price is optional because the schema allows it, and the three switches are the
/// only flags the model has. There is deliberately no quantity field: a menu item
/// has no stock column, so offering one would be inventing storage.
class _MenuItemSheet extends StatefulWidget {
  const _MenuItemSheet({this.categoryName, this.existing});

  final String? categoryName;
  final RestaurantMenuItem? existing;

  @override
  State<_MenuItemSheet> createState() => _MenuItemSheetState();
}

class _MenuItemSheetState extends State<_MenuItemSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.existing?.description ?? '');
  late final TextEditingController _price = TextEditingController(
    text: widget.existing?.price?.toStringAsFixed(0) ?? '',
  );
  late bool _veg = widget.existing?.veg ?? false;
  late bool _spicy = widget.existing?.spicy ?? false;
  late bool _availableToday = widget.existing?.isAvailableToday ?? true;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      _ItemDraft(
        name: _name.text.trim(),
        description: _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        price: double.tryParse(_price.text.trim()),
        veg: _veg,
        spicy: _spicy,
        availableToday: _availableToday,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.existing == null ? 'New dish' : 'Edit dish',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (widget.categoryName != null)
                Text(
                  'In ${widget.categoryName}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const Key('menu-item-name'),
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Dish name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'Enter a dish name' : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                key: const Key('menu-item-price'),
                controller: _price,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: NumericInput.decimal(),
                decoration: const InputDecoration(
                  labelText: 'Price',
                  prefixText: '₹',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isEmpty) return null; // the schema allows no price
                  final parsed = double.tryParse(text);
                  if (parsed == null) return 'Enter a number';
                  if (parsed < 0) return 'Cannot be negative';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                key: const Key('menu-item-description'),
                controller: _description,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              SwitchListTile(
                key: const Key('menu-item-veg'),
                value: _veg,
                onChanged: (v) => setState(() => _veg = v),
                title: const Text('Vegetarian'),
              ),
              SwitchListTile(
                key: const Key('menu-item-spicy'),
                value: _spicy,
                onChanged: (v) => setState(() => _spicy = v),
                title: const Text('Spicy'),
              ),
              SwitchListTile(
                key: const Key('menu-item-available'),
                value: _availableToday,
                onChanged: (v) => setState(() => _availableToday = v),
                title: const Text('Available today'),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton(
                    key: const Key('menu-item-save'),
                    onPressed: _submit,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
