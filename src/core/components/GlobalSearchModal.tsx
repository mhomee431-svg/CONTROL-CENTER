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
  Barcode,
} from 'lucide-react';
import { apiClient } from '../api/client';
import { API_ENDPOINTS } from '../api/endpoints';
import { ROUTES } from '../routes/routes';

interface GlobalSearchModalProps {
  open: boolean;
  onClose: () => void;
}

/**
 * Global admin search entity types (per contract):
 * Customer, Shopkeeper, Business, Product, Barcode, Import, Support Ticket, Audit Event.
 */
export type SearchEntityType =
  | 'CUSTOMER'
  | 'SHOPKEEPER'
  | 'BUSINESS'
  | 'PRODUCT'
  | 'BARCODE'
  | 'INVENTORY'
  | 'IMPORT'
  | 'SUPPORT'
  | 'AUDIT';

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

const MAX_PER_TYPE = 4;

export const GlobalSearchModal: React.FC<GlobalSearchModalProps> = ({ open, onClose }) => {
  const router = useRouter();
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<SearchResult[]>([]);
  const [loading, setLoading] = useState(false);

  // Debounced multi-entity search. All sources are queried in parallel and each
  // source degrades independently (a failing endpoint never blocks the others).
  useEffect(() => {
    const term = query.trim();
    if (!term) {
      setResults([]);
      return;
    }

    let cancelled = false;
    const timer = setTimeout(async () => {
      setLoading(true);
      try {
        const looksLikeBarcode = /^\d{6,14}$/.test(term);

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
          safe(
            apiClient<{ items: ImportRow[] }>(API_ENDPOINTS.SYSTEM.REPORTS, {
              params: { search: term, limit: MAX_PER_TYPE },
            }),
            { items: [] }
          ),
        ]);

        if (cancelled) return;

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

        shops.items?.forEach((s) => {
          found.push({
            id: `shop_${s.id}`,
            type: 'BUSINESS',
            title: s.name,
            subtitle: s.city ? `Business · ${s.city}` : 'Business',
            url: ROUTES.BUSINESS_DETAIL(s.id),
          });
        });

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
          placeholder="Search customers, shopkeepers, businesses, products, barcode, imports, tickets, audit..."
          value={query}
          onChange={(e) => setQuery(e.target.value)}
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
        ) : query && !loading ? (
          <Typography variant="body2" color="text.secondary" sx={{ textAlign: 'center', py: 3 }}>
            No matching entities found for &quot;{query}&quot;
          </Typography>
        ) : null}
      </DialogContent>
    </Dialog>
  );
};