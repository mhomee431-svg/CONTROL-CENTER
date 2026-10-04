'use client';

import React from 'react';
import { Box, Typography, Grid, Card, CardContent, CardActionArea } from '@mui/material';
import { useRouter } from 'next/navigation';
import { Settings, Sliders, Users, ShieldCheck, Activity, Layers } from 'lucide-react';
import { ROUTES } from '@/core/routes/routes';

const LINKS = [
  { title: 'System Settings', path: ROUTES.SYSTEM_SETTINGS, icon: <Settings size={22} />, color: '#0F52BA', bg: '#EFF6FF', desc: 'Runtime configuration parameters' },
  { title: 'Feature Flags', path: ROUTES.SYSTEM_FLAGS, icon: <Sliders size={22} />, color: '#10B981', bg: '#ECFDF5', desc: 'Dynamic platform feature toggles' },
  { title: 'Admin Users', path: ROUTES.ADMIN_USERS, icon: <Users size={22} />, color: '#6366F1', bg: '#EEF2FF', desc: 'RBAC administrators & roles' },
  { title: 'Audit Logs', path: ROUTES.AUDIT, icon: <ShieldCheck size={22} />, color: '#F59E0B', bg: '#FFFBEB', desc: 'Immutable administrative trail' },
  { title: 'System Health', path: ROUTES.SYSTEM_HEALTH, icon: <Activity size={22} />, color: '#EF4444', bg: '#FEF2F2', desc: 'Service & dependency status' },
  { title: 'Background Jobs', path: ROUTES.SYSTEM_JOBS, icon: <Layers size={22} />, color: '#EC4899', bg: '#FDF2F8', desc: 'Scheduled & async job monitor' },
];

export default function SettingsHubPage() {
  const router = useRouter();

  return (
    <Box>
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Settings & Administration
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Centralized configuration, governance, and platform administration.
        </Typography>
      </Box>

      <Grid container spacing={2.5}>
        {LINKS.map((link) => (
          <Grid item xs={12} sm={6} md={4} key={link.path}>
            <Card>
              <CardActionArea onClick={() => router.push(link.path)}>
                <CardContent sx={{ p: 2.5 }}>
                  <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 1 }}>
                    <Typography variant="subtitle1" sx={{ fontWeight: 700 }}>
                      {link.title}
                    </Typography>
                    <Box sx={{ p: 1, backgroundColor: link.bg, borderRadius: 1.5, color: link.color }}>{link.icon}</Box>
                  </Box>
                  <Typography variant="caption" color="text.secondary">
                    {link.desc}
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
