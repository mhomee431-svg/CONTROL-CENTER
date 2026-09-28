'use client';

import React, { useState } from 'react';
import { Box } from '@mui/material';
import { TopBar } from '@/core/components/TopBar';
import { Sidebar } from '@/core/components/Sidebar';
import { GlobalSearchModal } from '@/core/components/GlobalSearchModal';

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  const [searchOpen, setSearchOpen] = useState(false);

  return (
    <Box sx={{ display: 'flex', flexDirection: 'column', minHeight: '100vh', backgroundColor: '#F8FAFC' }}>
      <TopBar onOpenSearch={() => setSearchOpen(true)} />
      <Box sx={{ display: 'flex', flex: 1 }}>
        <Sidebar />
        <Box
          component="main"
          sx={{
            flexGrow: 1,
            p: { xs: 2, sm: 3, md: 4 },
            maxWidth: '1600px',
            margin: '0 auto',
            width: '100%',
            boxSizing: 'border-box',
          }}
        >
          {children}
        </Box>
      </Box>
      <GlobalSearchModal open={searchOpen} onClose={() => setSearchOpen(false)} />
    </Box>
  );
}
