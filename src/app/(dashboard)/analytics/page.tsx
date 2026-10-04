'use client';

import React from 'react';
import { useRouter } from 'next/navigation';
import { Box, Typography, Grid, Card, CardContent, CardActionArea } from '@mui/material';
import { Users, Store, Package, Building2, Search, MapPin } from 'lucide-react';
import { ROUTES } from '@/core/routes/routes';

const SECTIONS = [
  { title: 'Customers Analytics', path: ROUTES.ANALYTICS_CUSTOMERS, icon: <Users size={22} />, color: '#3B82F6', bg: '#EFF6FF' },
  { title: 'Shopkeepers Analytics', path: ROUTES.ANALYTICS_SHOPKEEPERS, icon: <Store size={22} />, color: '#10B981', bg: '#ECFDF5' },
  { title: 'Products Analytics', path: ROUTES.ANALYTICS_PRODUCTS, icon: <Package size={22} />, color: '#A855F7', bg: '#FAF5FF' },
  { title: 'Shops Analytics', path: ROUTES.ANALYTICS_SHOPS, icon: <Building2 size={22} />, color: '#F59E0B', bg: '#FFFBEB' },
  { title: 'Search Analytics', path: ROUTES.ANALYTICS_SEARCH, icon: <Search size={22} />, color: '#0F52BA', bg: '#EFF6FF' },
  { title: 'Geography Analytics', path: ROUTES.ANALYTICS_GEOGRAPHY, icon: <MapPin size={22} />, color: '#EC4899', bg: '#FDF2F8' },
];

export default function AnalyticsPage() {
  const router = useRouter();

  return (
    <Box>
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Platform Analytics
        </Typography>
        <Typography variant="body2" color="text.secondary">
          MEASURE stage: centralized business intelligence across entities, search, and geography.
        </Typography>
      </Box>

      <Grid container spacing={2.5}>
        {SECTIONS.map((s) => (
          <Grid item xs={12} sm={6} md={4} key={s.path}>
            <Card>
              <CardActionArea onClick={() => router.push(s.path)}>
                <CardContent sx={{ p: 2.5 }}>
                  <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <Typography variant="subtitle1" sx={{ fontWeight: 700 }}>
                      {s.title}
                    </Typography>
                    <Box sx={{ p: 1, backgroundColor: s.bg, borderRadius: 1.5, color: s.color }}>{s.icon}</Box>
                  </Box>
                  <Typography variant="caption" color="primary" sx={{ mt: 1.5, display: 'block', fontWeight: 600 }}>
                    Open Analytics →
                  </Typography>
                </CardContent>
              </CardActionArea>
            </Card>
          </Grid>
        ))}
      </Grid>
    </Box>
  );
}
