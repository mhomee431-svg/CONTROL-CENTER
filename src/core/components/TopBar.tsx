'use client';

import React, { useState } from 'react';
import {
  AppBar,
  Toolbar,
  Typography,
  Box,
  IconButton,
  Menu,
  MenuItem,
  Chip,
  Tooltip,
  Button,
} from '@mui/material';
import {
  Search as SearchIcon,
  Bell as BellIcon,
  User as UserIcon,
  LogOut as LogOutIcon,
  Activity as ActivityIcon,
} from 'lucide-react';
import { useAuth } from '../auth/AuthContext';

interface TopBarProps {
  onOpenSearch: () => void;
}

export const TopBar: React.FC<TopBarProps> = ({ onOpenSearch }) => {
  const { adminRole, logout } = useAuth();
  const [anchorEl, setAnchorEl] = useState<null | HTMLElement>(null);

  const handleMenuOpen = (event: React.MouseEvent<HTMLElement>) => {
    setAnchorEl(event.currentTarget);
  };

  const handleMenuClose = () => {
    setAnchorEl(null);
  };

  const handleLogout = () => {
    handleMenuClose();
    logout();
  };

  return (
    <AppBar
      position="sticky"
      color="inherit"
      elevation={0}
      sx={{
        backgroundColor: '#FFFFFF',
        borderBottom: '1px solid #E2E8F0',
        zIndex: (theme) => theme.zIndex.drawer + 1,
      }}
    >
      <Toolbar sx={{ justifyContent: 'space-between', px: { xs: 2, sm: 3 } }}>
        {/* Brand */}
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
          <Box
            sx={{
              width: 32,
              height: 32,
              borderRadius: 1.5,
              backgroundColor: 'primary.main',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              color: '#FFFFFF',
              fontWeight: 800,
              fontSize: '1rem',
            }}
          >
            H
          </Box>
          <Box>
            <Typography variant="subtitle1" sx={{ fontWeight: 700, lineHeight: 1.1 }}>
              HyperLocal Control Center
            </Typography>
            <Typography variant="caption" color="text.secondary">
              Enterprise Operations
            </Typography>
          </Box>
        </Box>

        {/* Global Search / Command Bar (Section 14 & 196) */}
        <Button
          onClick={onOpenSearch}
          variant="outlined"
          size="small"
          startIcon={<SearchIcon size={16} />}
          sx={{
            width: { xs: 200, sm: 360 },
            justifyContent: 'space-between',
            color: 'text.secondary',
            borderColor: '#CBD5E1',
            backgroundColor: '#F8FAFC',
            textTransform: 'none',
            fontSize: '0.8125rem',
            py: 0.75,
            px: 1.5,
          }}
        >
          <span>Search customers, shops, products...</span>
          <Chip
            label="Ctrl+K"
            size="small"
            sx={{
              height: 18,
              fontSize: '0.6875rem',
              backgroundColor: '#E2E8F0',
              fontWeight: 600,
            }}
          />
        </Button>

        {/* Status Indicators & Profile Actions (Section 198) */}
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
          {/* Health Indicator */}
          <Tooltip title="Backend API Connected">
            <Box
              sx={{
                display: { xs: 'none', md: 'flex' },
                alignItems: 'center',
                gap: 0.75,
                px: 1.25,
                py: 0.5,
                borderRadius: 1,
                backgroundColor: '#ECFDF5',
                border: '1px solid #A7F3D0',
              }}
            >
              <ActivityIcon size={14} color="#10B981" />
              <Typography variant="caption" sx={{ color: '#047857', fontWeight: 600 }}>
                API Live
              </Typography>
            </Box>
          </Tooltip>

          {/* Notifications */}
          <IconButton size="small" sx={{ color: 'text.secondary' }}>
            <BellIcon size={18} />
          </IconButton>

          {/* Admin User Chip */}
          {adminRole && (
            <Chip
              label={adminRole.level === 'SUPER' ? 'SUPER ADMIN' : adminRole.name || 'ADMIN'}
              size="small"
              color={adminRole.level === 'SUPER' ? 'primary' : 'default'}
              sx={{ fontWeight: 700, fontSize: '0.75rem' }}
            />
          )}

          {/* Profile Menu */}
          <IconButton onClick={handleMenuOpen} size="small" sx={{ p: 0.5 }}>
            <Box
              sx={{
                width: 32,
                height: 32,
                borderRadius: '50%',
                backgroundColor: '#E2E8F0',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                color: '#475569',
              }}
            >
              <UserIcon size={18} />
            </Box>
          </IconButton>

          <Menu
            anchorEl={anchorEl}
            open={Boolean(anchorEl)}
            onClose={handleMenuClose}
            transformOrigin={{ horizontal: 'right', vertical: 'top' }}
            anchorOrigin={{ horizontal: 'right', vertical: 'bottom' }}
          >
            <MenuItem disabled sx={{ opacity: 1, minWidth: 160 }}>
              <Box>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {adminRole?.name || 'Administrator'}
                </Typography>
                <Typography variant="caption" color="text.secondary">
                  Role: {adminRole?.role_name || 'admin'}
                </Typography>
              </Box>
            </MenuItem>
            <MenuItem onClick={handleLogout} sx={{ color: 'error.main' }}>
              <LogOutIcon size={16} style={{ marginRight: 8 }} />
              Secure Logout
            </MenuItem>
          </Menu>
        </Box>
      </Toolbar>
    </AppBar>
  );
};
