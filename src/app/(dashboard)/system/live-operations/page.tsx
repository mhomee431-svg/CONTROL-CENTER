'use client';

import React from 'react';
import {
  Box,
  Typography,
  Card,
  CardContent,
  List,
  ListItem,
  ListItemIcon,
  ListItemText,
  Chip,
  Button,
  Tooltip,
} from '@mui/material';
import { Flame, Store, Search, User, ShieldCheck, RefreshCw, WifiOff, Zap } from 'lucide-react';
import { useRealtimeEvents } from '@/core/realtime/useRealtimeEvents';

interface LiveEvent {
  id: string;
  type: 'SEARCH' | 'SHOP_UPDATE' | 'REGISTRATION' | 'VERIFICATION' | string;
  title: string;
  timestamp: string;
}

/** Sample events preserved as graceful fallback when the realtime stream is not connected. */
const SAMPLE_EVENTS: LiveEvent[] = [
  {
    id: '1',
    type: 'SEARCH',
    title: 'Shopper searched for "pain relief spray" in Saket, New Delhi (4 nearby stores found)',
    timestamp: new Date().toISOString(),
  },
  {
    id: '2',
    type: 'SHOP_UPDATE',
    title: 'Shop "Gupta Chemist" updated stock count on 14 SKUs',
    timestamp: new Date(Date.now() - 2 * 60 * 1000).toISOString(),
  },
  {
    id: '3',
    type: 'REGISTRATION',
    title: 'New customer registration via OTP (+91 9811XXXX82)',
    timestamp: new Date(Date.now() - 5 * 60 * 1000).toISOString(),
  },
  {
    id: '4',
    type: 'VERIFICATION',
    title: 'Merchant onboarding submitted for "Sharma Hardware Store"',
    timestamp: new Date(Date.now() - 9 * 60 * 1000).toISOString(),
  },
];

function timeAgo(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return 'Just now';
  if (mins < 60) return `${mins} min${mins === 1 ? '' : 's'} ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours} hr${hours === 1 ? '' : 's'} ago`;
  return new Date(iso).toLocaleString();
}

export default function LiveOperationsPage() {
  const { events, transport, connected, reconnect } = useRealtimeEvents();
  const displayEvents: LiveEvent[] = events.length > 0 ? events : SAMPLE_EVENTS;

  const getIcon = (type: LiveEvent['type'] | string) => {
    switch (type) {
      case 'SEARCH':
        return <Search size={18} color="#0F52BA" />;
      case 'SHOP_UPDATE':
        return <Store size={18} color="#10B981" />;
      case 'REGISTRATION':
        return <User size={18} color="#6366F1" />;
      case 'VERIFICATION':
        return <ShieldCheck size={18} color="#F59E0B" />;
      default:
        return <Flame size={18} color="#EF4444" />;
    }
  };

  return (
    <Box>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', mb: 3, flexWrap: 'wrap', gap: 2 }}>
        <Box>
          <Typography variant="h5" sx={{ fontWeight: 700 }}>
            Live Platform Operations
          </Typography>
          <Typography variant="body2" color="text.secondary">
            Section 80: Real-time operational stream for searches, registrations, and merchant inventory events.
          </Typography>
        </Box>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
          <Tooltip
            title={
              transport === 'websocket'
                ? 'Live WebSocket stream connected'
                : transport === 'sse'
                ? 'Connected via SSE fallback stream'
                : 'Stream offline — showing latest known events'
            }
          >
            <Chip
              size="small"
              icon={connected ? <Zap size={14} /> : <WifiOff size={14} />}
              color={connected ? 'success' : 'default'}
              label={transport === 'websocket' ? 'LIVE (WS)' : transport === 'sse' ? 'LIVE (SSE)' : 'OFFLINE'}
              sx={{ fontWeight: 700 }}
            />
          </Tooltip>
          <Button size="small" variant="outlined" onClick={reconnect} startIcon={<RefreshCw size={14} />}>
            Reconnect
          </Button>
        </Box>
      </Box>

      <Card>
        <CardContent sx={{ p: 2 }}>
          <List>
            {displayEvents.map((ev) => (
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
                <Chip
                  label={events.length > 0 ? timeAgo(ev.timestamp) : 'Sample'}
                  size="small"
                  sx={{ fontSize: '0.75rem', height: 22 }}
                />
              </ListItem>
            ))}
          </List>
        </CardContent>
      </Card>
    </Box>
  );
}
