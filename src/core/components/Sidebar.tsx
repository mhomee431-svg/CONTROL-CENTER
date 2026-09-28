'use client';

import React, { useState } from 'react';
import { usePathname, useRouter } from 'next/navigation';
import {
  Box,
  Drawer,
  List,
  ListItemButton,
  ListItemIcon,
  ListItemText,
  Collapse,
  Typography,
  Divider,
} from '@mui/material';
import {
  LayoutDashboard,
  Users,
  Store,
  ShieldCheck,
  Package,
  Layers,
  Tag,
  Warehouse,
  Flame,
  Search,
  AlertCircle,
  Bell,
  FileText,
  Settings,
  ChevronDown,
  ChevronRight,
  Sliders,
  DollarSign,
} from 'lucide-react';

const DRAWER_WIDTH = 250;

interface NavItem {
  title: string;
  path: string;
  icon: React.ReactNode;
}

interface NavGroup {
  group: string;
  items: NavItem[];
}

const NAV_GROUPS: NavGroup[] = [
  {
    group: 'DASHBOARD',
    items: [
      { title: 'Overview', path: '/dashboard', icon: <LayoutDashboard size={18} /> },
      { title: 'Live Operations', path: '/system/live-operations', icon: <Flame size={18} /> },
    ],
  },
  {
    group: 'PEOPLE',
    items: [
      { title: 'Customers', path: '/customers', icon: <Users size={18} /> },
      { title: 'Shopkeepers', path: '/shopkeepers', icon: <Store size={18} /> },
    ],
  },
  {
    group: 'BUSINESSES',
    items: [
      { title: 'Shops & Businesses', path: '/businesses', icon: <Store size={18} /> },
      { title: 'Verification Center', path: '/verification', icon: <ShieldCheck size={18} /> },
    ],
  },
  {
    group: 'CATALOG',
    items: [
      { title: 'Products Master', path: '/products', icon: <Package size={18} /> },
      { title: 'Categories', path: '/categories', icon: <Layers size={18} /> },
      { title: 'Brands', path: '/brands', icon: <Tag size={18} /> },
      { title: 'Approval Queue', path: '/products/approvals', icon: <ShieldCheck size={18} /> },
    ],
  },
  {
    group: 'OPERATIONS',
    items: [
      { title: 'Inventory Freshness', path: '/inventory', icon: <Warehouse size={18} /> },
      { title: 'Offers & Campaigns', path: '/offers', icon: <DollarSign size={18} /> },
      { title: 'Subscriptions', path: '/subscriptions', icon: <DollarSign size={18} /> },
    ],
  },
  {
    group: 'DISCOVERY',
    items: [
      { title: 'Search Analytics', path: '/search', icon: <Search size={18} /> },
      { title: 'Zero Results Analysis', path: '/search/zero-results', icon: <AlertCircle size={18} /> },
    ],
  },
  {
    group: 'ENGAGEMENT & GOVERNANCE',
    items: [
      { title: 'Support & Complaints', path: '/support', icon: <AlertCircle size={18} /> },
      { title: 'Push Notifications', path: '/notifications', icon: <Bell size={18} /> },
      { title: 'Audit Logs', path: '/audit', icon: <FileText size={18} /> },
    ],
  },
  {
    group: 'SYSTEM & SETTINGS',
    items: [
      { title: 'System Settings', path: '/system/settings', icon: <Settings size={18} /> },
      { title: 'Feature Flags', path: '/system/flags', icon: <Sliders size={18} /> },
    ],
  },
];

export const Sidebar: React.FC = () => {
  const pathname = usePathname();
  const router = useRouter();
  const [collapsedGroups, setCollapsedGroups] = useState<Record<string, boolean>>({});

  const toggleGroup = (group: string) => {
    setCollapsedGroups((prev) => ({ ...prev, [group]: !prev[group] }));
  };

  return (
    <Drawer
      variant="permanent"
      sx={{
        width: DRAWER_WIDTH,
        flexShrink: 0,
        [`& .MuiDrawer-paper`]: {
          width: DRAWER_WIDTH,
          boxSizing: 'border-box',
          backgroundColor: '#FFFFFF',
          borderRight: '1px solid #E2E8F0',
          top: 64, // Height of TopBar
          height: 'calc(100% - 64px)',
        },
      }}
    >
      <Box sx={{ overflowY: 'auto', py: 1.5 }}>
        {NAV_GROUPS.map((navGroup, idx) => {
          const isCollapsed = collapsedGroups[navGroup.group];

          return (
            <Box key={navGroup.group} sx={{ mb: 1 }}>
              <Box
                onClick={() => toggleGroup(navGroup.group)}
                sx={{
                  px: 2.5,
                  py: 0.75,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  cursor: 'pointer',
                  userSelect: 'none',
                  '&:hover': { opacity: 0.8 },
                }}
              >
                <Typography
                  variant="caption"
                  sx={{
                    fontWeight: 700,
                    letterSpacing: '0.06em',
                    color: '#64748B',
                  }}
                >
                  {navGroup.group}
                </Typography>
                {isCollapsed ? (
                  <ChevronRight size={14} color="#94A3B8" />
                ) : (
                  <ChevronDown size={14} color="#94A3B8" />
                )}
              </Box>

              <Collapse in={!isCollapsed} timeout="auto" unmountOnExit>
                <List dense disablePadding>
                  {navGroup.items.map((item) => {
                    const active = pathname === item.path || pathname.startsWith(`${item.path}/`);

                    return (
                      <ListItemButton
                        key={item.path}
                        onClick={() => router.push(item.path)}
                        selected={active}
                        sx={{
                          py: 0.75,
                          px: 2.5,
                          my: 0.2,
                          mx: 1,
                          borderRadius: 1.5,
                          '&.Mui-selected': {
                            backgroundColor: '#EFF6FF',
                            color: 'primary.main',
                            fontWeight: 600,
                            '&:hover': {
                              backgroundColor: '#DBEAFE',
                            },
                          },
                        }}
                      >
                        <ListItemIcon
                          sx={{
                            minWidth: 32,
                            color: active ? 'primary.main' : '#64748B',
                          }}
                        >
                          {item.icon}
                        </ListItemIcon>
                        <ListItemText
                          primary={item.title}
                          primaryTypographyProps={{
                            fontSize: '0.8125rem',
                            fontWeight: active ? 600 : 500,
                            color: active ? 'primary.main' : '#334155',
                          }}
                        />
                      </ListItemButton>
                    );
                  })}
                </List>
              </Collapse>

              {idx < NAV_GROUPS.length - 1 && <Divider sx={{ my: 1, borderColor: '#F1F5F9' }} />}
            </Box>
          );
        })}
      </Box>
    </Drawer>
  );
};
