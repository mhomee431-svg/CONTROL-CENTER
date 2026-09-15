params(
    [Parameter(Mandatory)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'
Set-Location 'C:\Users\akash\OneDrive\Documents\hyperlocal_customer_app\apps\shopkeeper_app'

$content = Get-Content -Encoding UTF8 $Path -Raw

# --- Rewrite the guard section: from "initialLocation" up to "routes: [" ---
$guardStart = $content.IndexOf('initialLocation: Routes.splash,')
if ($guardStart -lt 0) {
  $guardStart = $content.IndexOf('initialLocation: ')
}
# back up to the start of this statement (previous newline)
$guardStart = $content.LastIndexOf("`n", $guardStart)

$routesStart = $content.IndexOf('    routes: [', $guardStart)
if ($guardStart -lt 0 -or $routesStart -le $guardStart) {
  Write-Error "Could not locate guard/routes region."
  exit 1
}

$before = $content.Substring(0, $guardStart)
$after  = $content.Substring($routesStart)

$guard = @'
    initialLocation: Routes.splash,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final selectedShop = ref.read(selectedShopProvider);
      final loc = state.matchedLocation;
      const authRoutes = [
        Routes.welcome,
        Routes.login,
        Routes.register,
        Routes.forgotPassword,
        Routes.resetPassword,
      ];
      final isSplash = loc == Routes.splash;

      if (auth.status == AuthStatus.initial || auth.isLoading) {
        if (authRoutes.contains(loc)) return null;
        return isSplash ? null : Routes.splash;
      }

      final signedOut =
          auth.status == AuthStatus.unauthenticated ||
          auth.status == AuthStatus.sessionExpired ||
          auth.status == AuthStatus.error;
      if (signedOut) {
        if (isSplash) return Routes.welcome;
        if (authRoutes.contains(loc)) return null;
        return Routes.welcome;
      }

      // Phase 23: account restricted (inactive/suspended/banned) — the ONLY
      // reachable destination is the account-status screen.
      if (auth.status == AuthStatus.accountRestricted) {
        return loc == Routes.accountStatus ? null : Routes.accountStatus;
      }

      // Authenticated. Profile does NOT exist -> Create Profile. Every other
      // authenticated destination waits until the first shop exists.
      if (!auth.profileComplete) {
        return loc == Routes.profileCreate ? null : Routes.profileCreate;
      }
      // Profile exists -> Shopkeeper Home; the create screen is finished.
      if (loc == Routes.profileCreate) return Routes.dashboard;
      String? guard(String target) {
        // Home + Account/Profile always reachable right after login -- even
        // before the first shop. Shop setup surfaces from the dashboard CTA.
        const alwaysOpen = [
          Routes.dashboard,
          Routes.account,
          Routes.shops,
          Routes.shopRegister,
          Routes.profileCreate,
          Routes.notifications,
          Routes.scanBarcode,
          Routes.support,
          Routes.features,
        ];
        if (alwaysOpen.any(target.startsWith)) return null;
        const needsShop = [
          Routes.products,
          Routes.shopProfile,
          Routes.shopSettings,
          Routes.shopLocation,
          Routes.inventoryImport,
          Routes.offers,
          Routes.pos,
          Routes.insights,
        ];
        if (!needsShop.any(target.startsWith)) return null;
        if (selectedShop != null) return null;
        return auth.shops.isEmpty ? Routes.dashboard : Routes.shops;
      }

      if (authRoutes.contains(loc) || isSplash) {
        return guard(Routes.dashboard) ?? Routes.dashboard;
      }
      return guard(loc);
    },
'@

$Set-ContentParams = @{
  Encoding = 'utf8'
  Path     = $Path
  Value    = $before + $guard + $after
}
Set-Content @Set-ContentParams

Write-Output ('Rewritten. New line count: {0}' -f (Get-Content $Path).Count)
