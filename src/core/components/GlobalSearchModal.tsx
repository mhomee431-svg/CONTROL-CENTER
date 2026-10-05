'use client';

import React, { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import {
  Dialog,
  DialogContent,
  TextField,
  InputAdornment,
  List,
  ListItemButton,
  ListItemIcon,
  ListItemText,
  Typography,
  Box,
  Chip,
  CircularProgress,
} from '@mui/material';
import {
  Search as SearchIcon,
  Store,
  Users,
  Package,
  AlertCircle,
  FileText,
  Warehouse,
  Upload,
  ShieldCheck,
  BadgeCheck,
  Tag,
  Barcode,
  Terminal,
} from 'lucide-react';
import { apiClient } from '../api/client';
import { API_ENDPOINTS } from '../api/endpoints';
import { ShopInventoryItem, ShopItem } from '../types/admin';
import { ROUTES } from '../routes/routes';

interface GlobalSearchModalProps {
  open: boolean;
  onClose: () => void;
}

/**
 * Global admin search entity types (per contract):
 * Customer, Shopkeeper, Business, Product, Barcode, Inventory, Price History,
 * Verification, Import, Support Ticket, Audit Event.
 */
export type SearchEntityType =
  | 'CUSTOMER'
  | 'SHOPKEEPER'
  | 'BUSINESS'
  | 'PRODUCT'
  | 'BARCODE'
  | 'INVENTORY'
  | 'PRICE'
  | 'VERIFICATION'
  | 'IMPORT'
  | 'SUPPORT'
  | 'AUDIT'
  | 'COMMAND';

interface SearchResult {
  id: string;
  type: SearchEntityType;
  title: string;
  subtitle?: string;
  url: string;
}

interface UserRow {
  id: number;
  name: string | null;
  phone: string | null;
  role: string;
}

interface ShopRow {
  id: number;
  name: string;
  city?: string;
}

interface ProductRow {
  id: number;
  name: string;
  barcode?: string | null;
  brand_name?: string | null;
}

interface InventoryRow {
  shop_product_id: number;
  product_name: string;
  shop_name: string;
  quantity?: number;
}

interface ComplaintRow {
  id: number;
  ticket_number?: string;
  complaint_type: string;
}

interface AuditRow {
  id: number;
  action: string;
  entity_type: string;
  entity_id?: number | null;
}

interface ImportRow {
  id: number;
  source?: string;
  status?: string;
}

/** Inventory-shaped row returned by the freshness/pricing endpoints. */
interface BarcodeInventoryRow {
  shop_product_id: number;
  product_name: string;
  shop_id?: number;
  shop_name: string;
  quantity?: number;
  price?: number | null;
  mrp?: number | null;
}

/* ------------------------------------------------------------------
 * Command palette mode (Global Command Center).
 * Deliberately small — two command families only:
 *   open <entity> <id>  → deep-link straight to the record
 *                         (Open Customer / Shop / Product / Ticket)
 *   go <destination>    → jump to an ops destination
 *                         (Verification / Imports / System Health / …)
 * Commands are pure string matches (zero HTTP) and render above the
 * entity results. An exact command suppresses the entity fan-out so a
 * typed command never also fires a noisy backend search.
 * ---------------------------------------------------------------- */
export interface PaletteCommand {
  id: string;
  label: string;
  hint: string;
  url: string;
  /** True when the term fully resolves to an action (entity search skipped). */
  exact: boolean;
}

interface OpenPattern {
  re: RegExp;
  label: (id: string) => string;
  build: (id: string) => string;
}

const OPEN_PATTERNS: OpenPattern[] = [
  {
    re: /^(?:open\s+)?(?:customer|cust)\s+([\w-]+)$/i,
    label: (id) => `Open Customer #${id}`,
    build: (id) => ROUTES.CUSTOMER_DETAIL(id),
  },
  {
    re: /^(?:open\s+)?(?:shop|store|business)\s+([\w-]+)$/i,
    label: (id) => `Open Shop #${id}`,
    build: (id) => ROUTES.BUSINESS_DETAIL(id),
  },
  {
    re: /^(?:open\s+)?(?:product|prod|sku)\s+([\w-]+)$/i,
    label: (id) => `Open Product #${id}`,
    build: (id) => ROUTES.PRODUCT_DETAIL(id),
  },
  {
    re: /^(?:open\s+)?(?:ticket|support|complaint)\s+([\w-]+)$/i,
    label: (id) => `Open Ticket #${id}`,
    build: (id) => ROUTES.SUPPORT_DETAIL(id),
  },
];

interface NavCommand {
  keys: string[];
  label: string;
  url: string;
}

const NAV_COMMANDS: NavCommand[] = [
  { keys: ['dashboard', 'home', 'overview'], label: 'Go to Dashboard', url: ROUTES.DASHBOARD },
  { keys: ['verification', 'verify', 'approvals'], label: 'Go to Verification', url: ROUTES.VERIFICATION },
  { keys: ['imports', 'import', 'ingestion'], label: 'Go to Imports', url: ROUTES.IMPORTS },
  { keys: ['health', 'system health', 'status'], label: 'Go to System Health', url: ROUTES.SYSTEM_HEALTH },
  { keys: ['customers', 'customer'], label: 'Go to Customers', url: ROUTES.CUSTOMERS },
  { keys: ['shops', 'businesses', 'stores'], label: 'Go to Shops', url: ROUTES.BUSINESSES },
  { keys: ['products', 'catalog'], label: 'Go to Products', url: ROUTES.PRODUCTS },
  { keys: ['tickets', 'support'], label: 'Go to Support Tickets', url: ROUTES.SUPPORT },
];

export function matchPaletteCommands(raw: string): PaletteCommand[] {
  const term = raw.trim();
  if (!term) return [];

  const firstWord = term.split(/\s+/, 1)[0].toLowerCase();
  const saysOpen = firstWord === 'open';

  // Family 1 — direct record open. Always exact: the id is fully specified.
  for (const pattern of OPEN_PATTERNS) {
    const m = pattern.re.exec(term);
    if (m) {
      const id = m[1];
      return [
        {
          id: `cmd_open_${id}`,
          label: pattern.label(id),
          hint: 'Command · press Enter to open',
          url: pattern.build(id),
          exact: true,
        },
      ];
    }
  }

  // A leading "open" never falls through to navigation: either Family 1
  // resolved it, or it is a failed direct open and returns here. Only an
  // explicit "go"/"goto" prefix forces the navigation family. This keeps
  // "open product 123" from ever becoming "Go to Products".
  if (saysOpen) {
    return [];
  }

  // Family 2 — destination navigation.
  const lowered = term.toLowerCase();
  const goMatch = /^(?:go|goto)(?:\s+to)?\s+(.+)$/.exec(lowered);
  if (goMatch) {
    const needle = (goMatch[1] || '').trim();
    if (!needle) return [];
    return navHits(needle, true);
  }

  const needle = lowered.trim();
  if (needle.length < 2) return [];
  return navHits(needle, false);
}

function navHits(needle: string, forced: boolean): PaletteCommand[] {
  const hits: PaletteCommand[] = [];
  for (const nav of NAV_COMMANDS) {
    const keyHit = nav.keys.find(
      (k) => k === needle || k.startsWith(needle) || needle.startsWith(k)
    );
    if (keyHit) {
      hits.push({
        id: `cmd_go_${keyHit.replace(/\s+/g, '_')}`,
        label: nav.label,
        hint: 'Command · press Enter to go',
        url: nav.url,
        // An explicit "go <destination>" is an unambiguous command intent, so
        // it suppresses the backend entity search. Bare keyword matches stay
        // advisory (exact: false) and entity results still load beneath.
        exact: forced,
      });
    }
  }
  return hits.slice(0, 4);
}

const MAX_PER_TYPE = 4;

export const GlobalSearchModal: React.FC<GlobalSearchModalProps> = ({ open, onClose }) => {
  const router = useRouter();
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<SearchResult[]>([]);
  const [commands, setCommands] = useState<PaletteCommand[]>([]);
  const [loading, setLoading] = useState(false);

  // Debounced multi-entity search. All sources are queried in parallel and each
  // source degrades independently (a failing endpoint never blocks the others).
  // Command matches are synchronous and render instantly, before entity data.
  useEffect(() => {
    const term = query.trim();
    const matched = matchPaletteCommands(term);
    setCommands(matched);
    if (!term) {
      setResults([]);
      return;
    }

    let cancelled = false;
    const timer = setTimeout(async () => {
      // An exact command fully resolves the intent — skip the backend fan-out.
      if (matched.some((c) => c.exact)) {
        setResults([]);
        setLoading(false);
        return;
      }
      setLoading(true);
      try {
        const looksLikeBarcode = /^\d{6,14}$/.test(term);
        // Round-2 fan-out is bounded so the palette stays under ~12 HTTP calls
        // in the common case and never above ~20 in the worst case.
        const MAX_ROUND_2 = 2;

        const safe = async <T,>(p: Promise<T>, fallback: T): Promise<T> => {
          try {
            return await p;
          } catch {
            return fallback;
          }
        };

        const [products, barcodeHits, shops, users, inventory, complaints, audit, imports] = await Promise.all([
          safe(
            apiClient<{ items: ProductRow[] }>(API_ENDPOINTS.PRODUCTS.LIST, {
              params: { search: term, limit: MAX_PER_TYPE },
            }),
            { items: [] }
          ),
          // Dedicated barcode lookup — only attempted when the term looks like a barcode.
          looksLikeBarcode
            ? safe(
                apiClient<{ items: ProductRow[] }>(API_ENDPOINTS.PRODUCTS.BARCODE_SEARCH, {
                  params: { barcode: term, limit: MAX_PER_TYPE },
                }),
                { items: [] }
              )
            : Promise.resolve({ items: [] as ProductRow[] }),
          safe(
            apiClient<{ items: ShopRow[] }>(API_ENDPOINTS.SHOPS.LIST, {
              params: { search: term, limit: MAX_PER_TYPE },
            }),
            { items: [] }
          ),
          safe(
            apiClient<{ items: UserRow[] }>(API_ENDPOINTS.CUSTOMERS.LIST, {
              params: { search: term, limit: MAX_PER_TYPE * 2 },
            }),
            { items: [] }
          ),
          safe(
            apiClient<{ items: InventoryRow[] }>(API_ENDPOINTS.INVENTORY.STALE, {
              params: { search: term, limit: MAX_PER_TYPE },
            }),
            { items: [] }
          ),
          safe(
            apiClient<{ items: ComplaintRow[] }>(API_ENDPOINTS.COMPLAINTS.LIST, {
              params: { search: term, limit: MAX_PER_TYPE },
            }),
            { items: [] }
          ),
          safe(
            apiClient<{ items: AuditRow[] }>(API_ENDPOINTS.AUDIT.LOGS, {
              params: { search: term, limit: MAX_PER_TYPE },
            }),
            { items: [] }
          ),
          // Imports come from the ingestion registry. This previously read
          // /admin/reports, which returns report rows with none of ImportRow's
          // fields, so import search silently returned nothing.
          safe(
            apiClient<{ items: ImportRow[] }>(API_ENDPOINTS.INGESTION.IMPORTS, {
              params: { search: term, limit: MAX_PER_TYPE },
            }),
            { items: [] }
          ),
        ]);

        if (cancelled) return;

        /* ---------------------------------------------------------------
         * Round 2 — bounded entity expansion drill-downs.
         * A name/barcode hit rarely matches the owning shop's inventory row
         * by the same term, so the top shops and top barcode products seed
         * a second bounded lookup wave:
         *   shop        → shopkeeper (owner) + verification case +
         *                 shop inventory (stock/price history)
         *   barcode row → missing-prices + audit footprint
         * Everything degrades independently and respects `cancelled`.
         * ------------------------------------------------------------- */
        const round2Shops = (shops.items ?? [])
          .slice(0, MAX_ROUND_2)
          .map((s) => ({ id: s.id, name: s.name }));
        const matchedShopIds = new Set(round2Shops.map((s) => s.id));
        const round2Barcodes = (barcodeHits.items ?? []).slice(0, MAX_ROUND_2);

        const round2 = await Promise.all([
          ...round2Shops.map((s) =>
            safe(apiClient<ShopItem>(API_ENDPOINTS.SHOPS.DETAIL(s.id)), null as ShopItem | null)
          ),
          ...round2Barcodes.map((p) =>
            safe(
              apiClient<{ items: BarcodeInventoryRow[] }>(API_ENDPOINTS.INVENTORY.MISSING_PRICES, {
                params: { search: p.name, limit: MAX_PER_TYPE },
              }),
              { items: [] as BarcodeInventoryRow[] }
            )
          ),
          ...round2Barcodes.map((p) =>
            safe(
              apiClient<{ items: AuditRow[] }>(API_ENDPOINTS.AUDIT.LOGS, {
                params: { search: p.name, limit: MAX_PER_TYPE },
              }),
              { items: [] as AuditRow[] }
            )
          ),
        ]);

        if (cancelled) {
          setLoading(false);
          return;
        }

        const shopDetails = round2.slice(0, round2Shops.length) as Array<ShopItem | null>;
        const barcodePriceRows = round2.slice(
          round2Shops.length,
          round2Shops.length + round2Barcodes.length
        ) as Array<{ items: BarcodeInventoryRow[] }>;
        const barcodeAuditRows = round2.slice(round2Shops.length + round2Barcodes.length) as Array<{
          items: AuditRow[];
        }>;

        const found: SearchResult[] = [];

        products.items?.forEach((p) => {
          const barcodeHit = looksLikeBarcode && p.barcode && p.barcode.includes(term);
          found.push({
            id: `prod_${p.id}`,
            type: barcodeHit ? 'BARCODE' : 'PRODUCT',
            title: p.name,
            subtitle: p.barcode
              ? `Barcode: ${p.barcode}${p.brand_name ? ` · ${p.brand_name}` : ''}`
              : p.brand_name || 'Master catalog',
            url: ROUTES.PRODUCT_DETAIL(p.id),
          });
        });

        // Dedicated barcode matches take priority and are labelled explicitly.
        barcodeHits.items?.forEach((p) => {
          found.unshift({
            id: `barcode_${p.id}`,
            type: 'BARCODE',
            title: p.name,
            subtitle: `Barcode match: ${p.barcode ?? term}`,
            url: ROUTES.PRODUCT_DETAIL(p.id),
          });
        });

        // Price-history rows for scanned barcodes (missing-price / freshness feed).
        barcodePriceRows.forEach((res) => {
          res.items?.slice(0, MAX_ROUND_2).forEach((row) => {
            found.push({
              id: `price_${row.shop_product_id}`,
              type: 'PRICE',
              title: `Price: ${row.product_name}`,
              subtitle: [
                `Price history · ${row.shop_name}`,
                row.price != null ? `Price ₹${row.price}` : null,
                row.mrp != null ? `MRP ₹${row.mrp}` : null,
              ]
                .filter(Boolean)
                .join(' · '),
              url: ROUTES.PRICING_DETAIL(row.shop_product_id),
            });
          });
        });

        // Audit footprint for scanned barcodes (product lifecycle trail).
        barcodeAuditRows.forEach((res) => {
          res.items?.slice(0, MAX_ROUND_2).forEach((a) => {
            found.push({
              id: `barcode_audit_${a.id}`,
              type: 'AUDIT',
              title: `Barcode trail: ${a.action}`,
              subtitle: `Audit · ${a.entity_type}${a.entity_id ? ` #${a.entity_id}` : ''}`,
              url: ROUTES.AUDIT,
            });
          });
        });

        shops.items?.forEach((s) => {
          found.push({
            id: `shop_${s.id}`,
            type: 'BUSINESS',
            title: s.name,
            subtitle: s.city ? `Business · ${s.city}` : 'Business',
            url: ROUTES.BUSINESS_DETAIL(s.id),
          });
        });

        // Expanded coverage for each matched business: owning shopkeeper,
        // verification case, and shop inventory (stock + price history).
        for (const detail of shopDetails) {
          if (!detail || cancelled) continue;
          const label = detail.name || `Shop #${detail.id}`;

          if (detail.owner_id != null) {
            found.push({
              id: `shopkeeper_${detail.id}_${detail.owner_id}`,
              type: 'SHOPKEEPER',
              title: detail.owner_name || `Shopkeeper #${detail.owner_id}`,
              subtitle: `Owns ${label}`,
              url: ROUTES.SHOPKEEPER_DETAIL(detail.owner_id),
            });
          }

          found.push({
            id: `verify_${detail.id}`,
            type: 'VERIFICATION',
            title: `Verification: ${label}`,
            subtitle: detail.verification_status
              ? `Verification · ${detail.verification_status}`
              : 'Verification case',
            url: ROUTES.VERIFICATION_DETAIL(detail.id),
          });

          const stock = await safe(
            apiClient<{ items: ShopInventoryItem[] }>(API_ENDPOINTS.INVENTORY.SHOP_INVENTORY(detail.id), {
              params: { limit: MAX_PER_TYPE },
            }),
            { items: [] as ShopInventoryItem[] }
          );
          if (cancelled) {
            setLoading(false);
            return;
          }
          stock.items?.slice(0, MAX_ROUND_2).forEach((row) => {
            found.push({
              id: `shopinv_${detail.id}_${row.shop_product_id}`,
              type: 'INVENTORY',
              title: row.product_name,
              subtitle: [
                `Stock at ${label}`,
                row.quantity != null ? `Qty ${row.quantity}` : null,
                row.price != null ? `Price ₹${row.price}` : null,
              ]
                .filter(Boolean)
                .join(' · '),
              url: ROUTES.INVENTORY_DETAIL(row.shop_product_id),
            });
          });
        }

        // Shops surfacing as inventory-stock parents (e.g. barcode chains) still
        // get full Business records so every result is clickable end-to-end.
        for (const res of barcodePriceRows) {
          for (const row of res.items?.slice(0, MAX_ROUND_2) ?? []) {
            if (!row.shop_id || matchedShopIds.has(row.shop_id) || cancelled) continue;
            matchedShopIds.add(row.shop_id);
            const info = await safe(
              apiClient<ShopItem>(API_ENDPOINTS.SHOPS.DETAIL(row.shop_id)),
              null as ShopItem | null
            );
            if (cancelled) {
              setLoading(false);
              return;
            }
            if (!info) continue;
            found.push({
              id: `stockshop_${info.id}`,
              type: 'BUSINESS',
              title: info.name,
              subtitle: info.city ? `Stocks scanned product · ${info.city}` : 'Stocks scanned product',
              url: ROUTES.BUSINESS_DETAIL(info.id),
            });
          }
        }

        users.items?.forEach((u) => {
          const isShopkeeper = (u.role || '').toLowerCase().includes('shopkeeper');
          found.push({
            id: `user_${u.id}`,
            type: isShopkeeper ? 'SHOPKEEPER' : 'CUSTOMER',
            title: u.name || u.phone || `User #${u.id}`,
            subtitle: `Role: ${u.role}`,
            url: isShopkeeper ? ROUTES.SHOPKEEPER_DETAIL(u.id) : ROUTES.CUSTOMER_DETAIL(u.id),
          });
        });

        inventory.items?.forEach((inv) => {
          found.push({
            id: `inv_${inv.shop_product_id}`,
            type: 'INVENTORY',
            title: inv.product_name,
            subtitle: `Inventory · ${inv.shop_name}${inv.quantity != null ? ` · Qty ${inv.quantity}` : ''}`,
            url: ROUTES.INVENTORY_DETAIL(inv.shop_product_id),
          });
        });

        complaints.items?.forEach((c) => {
          found.push({
            id: `ticket_${c.id}`,
            type: 'SUPPORT',
            title: c.ticket_number ? `Ticket ${c.ticket_number}` : `Ticket #${c.id}`,
            subtitle: c.complaint_type || 'Support complaint',
            url: ROUTES.SUPPORT_DETAIL(c.id),
          });
        });

        audit.items?.forEach((a) => {
          found.push({
            id: `audit_${a.id}`,
            type: 'AUDIT',
            title: a.action,
            subtitle: `Audit · ${a.entity_type}${a.entity_id ? ` #${a.entity_id}` : ''}`,
            url: ROUTES.AUDIT,
          });
        });

        imports.items?.forEach((job) => {
          found.push({
            id: `import_${job.id}`,
            type: 'IMPORT',
            title: job.source ? `Import: ${job.source}` : `Import Job #${job.id}`,
            subtitle: job.status ? `Status: ${job.status}` : 'Data ingestion',
            url: ROUTES.IMPORT_DETAIL(job.id),
          });
        });

        setResults(found);
      } finally {
        if (!cancelled) setLoading(false);
      }
    }, 300);

    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [query]);

  const handleSelect = (url: string) => {
    onClose();
    setQuery('');
    router.push(url);
  };

  const getIcon = (type: SearchEntityType) => {
    switch (type) {
      case 'COMMAND':
        return <Terminal size={18} color="#0F52BA" />;
      case 'BUSINESS':
        return <Store size={18} color="#0F52BA" />;
      case 'PRODUCT':
        return <Package size={18} color="#10B981" />;
      case 'BARCODE':
        return <Barcode size={18} color="#10B981" />;
      case 'CUSTOMER':
        return <Users size={18} color="#6366F1" />;
      case 'SHOPKEEPER':
        return <ShieldCheck size={18} color="#6366F1" />;
      case 'INVENTORY':
        return <Warehouse size={18} color="#F59E0B" />;
      case 'PRICE':
        return <Tag size={18} color="#F59E0B" />;
      case 'VERIFICATION':
        return <BadgeCheck size={18} color="#0F52BA" />;
      case 'SUPPORT':
        return <AlertCircle size={18} color="#EF4444" />;
      case 'IMPORT':
        return <Upload size={18} color="#8B5CF6" />;
      case 'AUDIT':
        return <FileText size={18} color="#64748B" />;
      default:
        return <FileText size={18} color="#64748B" />;
    }
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogContent sx={{ p: 2 }}>
        <TextField
          autoFocus
          fullWidth
          placeholder="Search entities, or type a command — e.g. “open product 42”, “go to verification”…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={(e) => {
            // Enter jumps straight to the top command (record open or "go to…")
            // without waiting for the debounced backend fan-out.
            if (e.key === 'Enter' && commands.length > 0) {
              e.preventDefault();
              handleSelect(commands[0].url);
            }
          }}
          slotProps={{
            input: {
              startAdornment: (
                <InputAdornment position="start">
                  <SearchIcon size={18} color="#64748B" />
                </InputAdornment>
              ),
              endAdornment: loading ? <CircularProgress size={16} /> : null,
            },
          }}
          sx={{ mb: 2 }}
        />

        {/* Command hits render first — a dedicated section above entity results. */}
        {commands.length > 0 && (
          <Box sx={{ mb: results.length > 0 ? 1.5 : 0 }}>
            <Typography
              variant="caption"
              sx={{ fontWeight: 700, letterSpacing: '0.06em', color: '#64748B', px: 1 }}
            >
              COMMANDS
            </Typography>
            <List dense disablePadding sx={{ maxHeight: 220, overflowY: 'auto' }}>
              {commands.map((command) => (
                <ListItemButton
                  key={command.id}
                  onClick={() => handleSelect(command.url)}
                  sx={{ borderRadius: 1, my: 0.5, display: 'flex', justifyContent: 'space-between' }}
                >
                  <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, minWidth: 0 }}>
                    <ListItemIcon sx={{ minWidth: 28 }}>{getIcon('COMMAND')}</ListItemIcon>
                    <ListItemText
                      primary={command.label}
                      secondary={command.hint}
                      primaryTypographyProps={{ fontSize: '0.875rem', fontWeight: 600 }}
                      secondaryTypographyProps={{ fontSize: '0.75rem' }}
                    />
                  </Box>
                  <Chip label="COMMAND" size="small" sx={{ fontSize: '0.6875rem', height: 20 }} />
                </ListItemButton>
              ))}
            </List>
          </Box>
        )}

        {results.length > 0 ? (
          <List dense disablePadding sx={{ maxHeight: 420, overflowY: 'auto' }}>
            {results.map((item) => (
              <ListItemButton
                key={item.id}
                onClick={() => handleSelect(item.url)}
                sx={{
                  borderRadius: 1,
                  my: 0.5,
                  display: 'flex',
                  justifyContent: 'space-between',
                }}
              >
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, minWidth: 0 }}>
                  <ListItemIcon sx={{ minWidth: 28 }}>{getIcon(item.type)}</ListItemIcon>
                  <ListItemText
                    primary={item.title}
                    secondary={item.subtitle}
                    primaryTypographyProps={{ fontSize: '0.875rem', fontWeight: 600 }}
                    secondaryTypographyProps={{ fontSize: '0.75rem' }}
                  />
                </Box>
                <Chip label={item.type} size="small" sx={{ fontSize: '0.6875rem', height: 20 }} />
              </ListItemButton>
            ))}
          </List>
        ) : query && !loading && commands.length === 0 ? (
          <Typography variant="body2" color="text.secondary" sx={{ textAlign: 'center', py: 3 }}>
            No matching entities found for &quot;{query}&quot;
          </Typography>
        ) : null}
      </DialogContent>
    </Dialog>
  );
};