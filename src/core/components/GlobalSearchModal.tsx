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
} from 'lucide-react';
import { apiClient } from '../api/client';
import { API_ENDPOINTS } from '../api/endpoints';

interface GlobalSearchModalProps {
  open: boolean;
  onClose: () => void;
}

interface SearchResult {
  id: string | number;
  type: 'CUSTOMER' | 'SHOP' | 'PRODUCT' | 'COMPLAINT' | 'AUDIT';
  title: string;
  subtitle?: string;
  url: string;
}

export const GlobalSearchModal: React.FC<GlobalSearchModalProps> = ({ open, onClose }) => {
  const router = useRouter();
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<SearchResult[]>([]);
  const [loading, setLoading] = useState(false);

  // Debounced search
  useEffect(() => {
    if (!query.trim()) {
      setResults([]);
      return;
    }

    const timer = setTimeout(async () => {
      setLoading(true);
      try {
        const found: SearchResult[] = [];

        // Search products
        const products = await apiClient<{ items: Array<{ id: number; name: string; barcode?: string }> }>(
          API_ENDPOINTS.PRODUCTS.LIST,
          { params: { search: query, limit: 5 } }
        ).catch(() => ({ items: [] }));

        products.items?.forEach((p) => {
          found.push({
            id: `prod_${p.id}`,
            type: 'PRODUCT',
            title: p.name,
            subtitle: p.barcode ? `Barcode: ${p.barcode}` : undefined,
            url: `/products/${p.id}`,
          });
        });

        // Search shops
        const shops = await apiClient<{ items: Array<{ id: number; name: string; city: string }> }>(
          API_ENDPOINTS.SHOPS.LIST,
          { params: { search: query, limit: 5 } }
        ).catch(() => ({ items: [] }));

        shops.items?.forEach((s) => {
          found.push({
            id: `shop_${s.id}`,
            type: 'SHOP',
            title: s.name,
            subtitle: s.city,
            url: `/businesses/${s.id}`,
          });
        });

        // Search users
        const users = await apiClient<{ items: Array<{ id: number; name: string; phone: string; role: string }> }>(
          API_ENDPOINTS.CUSTOMERS.LIST,
          { params: { search: query, limit: 5 } }
        ).catch(() => ({ items: [] }));

        users.items?.forEach((u) => {
          found.push({
            id: `user_${u.id}`,
            type: 'CUSTOMER',
            title: u.name || u.phone || `User #${u.id}`,
            subtitle: `Role: ${u.role}`,
            url: `/customers/${u.id}`,
          });
        });

        setResults(found);
      } finally {
        setLoading(false);
      }
    }, 300);

    return () => clearTimeout(timer);
  }, [query]);

  // Global Ctrl+K keyboard shortcut
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        // Trigger modal toggle handled by parent or listener
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, []);

  const handleSelect = (url: string) => {
    onClose();
    router.push(url);
  };

  const getIcon = (type: SearchResult['type']) => {
    switch (type) {
      case 'SHOP':
        return <Store size={18} color="#0F52BA" />;
      case 'PRODUCT':
        return <Package size={18} color="#10B981" />;
      case 'CUSTOMER':
        return <Users size={18} color="#6366F1" />;
      case 'COMPLAINT':
        return <AlertCircle size={18} color="#EF4444" />;
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
          placeholder="Search products, shops, customers..."
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
          <List dense disablePadding>
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
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
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
