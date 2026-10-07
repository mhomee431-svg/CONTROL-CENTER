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
import { Store, Search, User, ShieldCheck, RefreshCw, WifiOff, Zap, AlertCircle } from 'lucide-react';
import { useRealtimeEvents } from '@/core/realtime/useRealtimeEvents';
import { LiveEvent } from '@/core/realtime/liveEvents';
import { getOperationalEventMeta } from '@/core/realtime/eventTaxonomy';

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
  // Only genuine streamed events are ever displayed.
  const displayEvents: LiveEvent[] = events;

  const getIcon = (type: LiveEvent['type'] | string) => {
    switch (type) {
      case 'CUSTOMER_SEARCH':
      case 'SEARCH':
        return <Search size={18} color="#0F52BA" />;
      case 'INVENTORY_UPDATE':
      case 'PRICE_UPDATE':
      case 'IMPORT_COMPLETION':
      case 'SHOP_UPDATE':
        return <Store size={18} color="#10B981" />;
      case 'SHOPKEEPER_REGISTRATION':
      case 'REGISTRATION':
        return <User size={18} color="#6366F1" />;
      case 'VERIFICATION_SUBMISSION':
      case 'VERIFICATION':
        return <ShieldCheck size={18} color="#F59E0B" />;
      case 'SUPPORT_TICKET':
        return <AlertCircle size={18} color="#EC4899" />;
      default:
        return <Zap size={18} color="#EF4444" />;
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
                : 'Stream offline — no events are being received'
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
          {displayEvents.length === 0 ? (
            <Box sx={{ py: 5, textAlign: 'center' }}>
              <Typography variant="body1" sx={{ fontWeight: 600, mb: 0.5 }}>
                No operational events received
              </Typography>
              <Typography variant="body2" color="text.secondary">
                {connected
                  ? 'Stream is connected. Waiting for the next platform event…'
                  : 'The realtime stream is not connected. The hook retries automatically — use Reconnect to retry now.'}
              </Typography>
            </Box>
          ) : (
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
                      secondary={timeAgo(ev.timestamp)}
                      primaryTypographyProps={{ fontSize: '0.875rem', fontWeight: 500 }}
                      secondaryTypographyProps={{ fontSize: '0.75rem' }}
                    />
                  </Box>
                  <Chip
                    label={getOperationalEventMeta(ev.type)?.label ?? ev.type}
                    size="small"
                    sx={{ fontSize: '0.75rem', height: 22 }}
                  />
                </ListItem>
              ))}
            </List>
          )}
        </CardContent>
      </Card>
    </Box>
  );
}
