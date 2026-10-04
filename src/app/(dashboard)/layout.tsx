'use client';

import React, { useState, useEffect } from 'react';
import { Box } from '@mui/material';
import { TopBar } from '@/core/components/TopBar';
import { Sidebar } from '@/core/components/Sidebar';
import { GlobalSearchModal } from '@/core/components/GlobalSearchModal';
import { useAuth } from '@/core/auth/AuthContext';
import { CircularProgress } from '@mui/material';

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  const [searchOpen, setSearchOpen] = useState(false);
  const { isLoading, status } = useAuth();

  // Global Ctrl+K / Cmd+K command-bar shortcut (Section 196)
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        setSearchOpen((prev) => !prev);
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, []);

  if (isLoading || status === 'loading') {
    return (
      <Box sx={{ minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <CircularProgress aria-label="Loading admin session" />
      </Box>
    );
  }

  if (status !== 'authenticated') return null;

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
      <GlobalSearchModal open={searchOpen} onClose={() => setSearchOpen(false)} />    </Box>
  );
}
