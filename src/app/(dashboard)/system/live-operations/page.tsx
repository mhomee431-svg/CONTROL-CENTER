'use client';

import React from 'react';
import { Box, Typography, Card, CardContent, List, ListItem, ListItemIcon, ListItemText, Chip } from '@mui/material';
import { Flame, Store, Search, User, ShieldCheck } from 'lucide-react';

interface LiveEvent {
  id: string;
  type: 'SEARCH' | 'SHOP_UPDATE' | 'REGISTRATION' | 'VERIFICATION';
  title: string;
  timestamp: string;
}

export default function LiveOperationsPage() {
  const events: LiveEvent[] = [
    {
      id: '1',
      type: 'SEARCH',
      title: 'Shopper searched for "pain relief spray" in Saket, New Delhi (4 nearby stores found)',
      timestamp: 'Just now',
    },
    {
      id: '2',
      type: 'SHOP_UPDATE',
      title: 'Shop "Gupta Chemist" updated stock count on 14 SKUs',
      timestamp: '2 mins ago',
    },
    {
      id: '3',
      type: 'REGISTRATION',
      title: 'New customer registration via OTP (+91 9811XXXX82)',
      timestamp: '5 mins ago',
    },
    {
      id: '4',
      type: 'VERIFICATION',
      title: 'Merchant onboarding submitted for "Sharma Hardware Store"',
      timestamp: '9 mins ago',
    },
  ];

  const getIcon = (type: LiveEvent['type']) => {
    switch (type) {
      case 'SEARCH':
        return <Search size={18} color="#0F52BA" />;
      case 'SHOP_UPDATE':
        return <Store size={18} color="#10B981" />;
      case 'REGISTRATION':
        return <User size={18} color="#6366F1" />;
      case 'VERIFICATION':
        return <ShieldCheck size={18} color="#F59E0B" />;
    }
  };

  return (
    <Box>
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Live Platform Operations
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Section 80: Real-time operational stream for searches, registrations, and merchant inventory events.
        </Typography>
      </Box>

      <Card>
        <CardContent sx={{ p: 2 }}>
          <List>
            {events.map((ev) => (
              <ListItem
                key={ev.id}
                sx={{
                  borderBottom: '1px solid #F1F5F9',
                  py: 1.5,
                  display: 'flex',
                  justifyContent: 'space-between',
                }}
              >
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                  <ListItemIcon sx={{ minWidth: 28 }}>{getIcon(ev.type)}</ListItemIcon>
                  <ListItemText
                    primary={ev.title}
                    primaryTypographyProps={{ fontSize: '0.875rem', fontWeight: 500 }}
                  />
                </Box>
                <Chip label={ev.timestamp} size="small" sx={{ fontSize: '0.75rem', height: 22 }} />
              </ListItem>
            ))}
          </List>
        </CardContent>
      </Card>
    </Box>
  );
}
