'use client';

import React, { useState, useEffect, useCallback } from 'react';
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
  MessageSquare,
  Settings,
  ChevronDown,
  ChevronRight,
  Sliders,
  DollarSign,
  MapPin,
  Plug,
  Upload,
  TrendingUp,
  BarChart2,
  Building2,
  Activity as ActivityIcon,
  Newspaper,
  Image as ImageIcon,
  Megaphone,
  HelpCircle,
  BookOpen,
  Ticket,
  AlertTriangle,
  LayoutGrid,
} from 'lucide-react';
import { usePermissions } from '../permissions/PermissionGuard';
import { CAPABILITIES, Capability } from '../permissions/permissions';
import { ROUTES } from '../routes/routes';

const DRAWER_WIDTH = 250;
const COLLAPSE_STORAGE_KEY = 'admin_sidebar_collapsed_groups';

interface NavItem {
  title: string;
  path: string;
  icon: React.ReactNode;
  capability?: Capability;
}

interface NavGroup {
  group: string;
  items: NavItem[];
}

const NAV_GROUPS: NavGroup[] = [
  {
    group: 'DASHBOARD',
    items: [
      { title: 'Overview', path: ROUTES.DASHBOARD, icon: <LayoutDashboard size={18} /> },
      { title: 'Live Operations', path: ROUTES.SYSTEM_LIVE_OPERATIONS, icon: <Flame size={18} /> },
    ],
  },
  {
    group: 'PEOPLE',
    items: [
      { title: 'Customers', path: ROUTES.CUSTOMERS, icon: <Users size={18} />, capability: CAPABILITIES.CUSTOMERS_READ },
      { title: 'Shopkeepers', path: ROUTES.SHOPKEEPERS, icon: <Store size={18} />, capability: CAPABILITIES.SHOPS_READ },
    ],
  },
  {
    group: 'BUSINESSES',
    items: [
      { title: 'Shops & Businesses', path: ROUTES.BUSINESSES, icon: <Store size={18} />, capability: CAPABILITIES.SHOPS_READ },
      { title: 'Verification Center', path: ROUTES.VERIFICATION, icon: <ShieldCheck size={18} />, capability: CAPABILITIES.SHOPS_APPROVE },
      { title: 'Locations', path: ROUTES.LOCATIONS, icon: <MapPin size={18} />, capability: CAPABILITIES.SHOPS_READ },
    ],
  },
  {
    group: 'CATALOG',
    items: [
      { title: 'Products Master', path: ROUTES.PRODUCTS, icon: <Package size={18} />, capability: CAPABILITIES.PRODUCTS_READ },
      { title: 'Quality Control', path: ROUTES.PRODUCTS_QUALITY, icon: <AlertTriangle size={18} />, capability: CAPABILITIES.PRODUCTS_READ },
      { title: 'Product Merge', path: ROUTES.PRODUCTS_MERGE, icon: <Layers size={18} />, capability: CAPABILITIES.PRODUCTS_MERGE },
      { title: 'Categories', path: ROUTES.CATEGORIES, icon: <Layers size={18} />, capability: CAPABILITIES.TAXONOMY_READ },
      { title: 'Brands', path: ROUTES.BRANDS, icon: <Tag size={18} />, capability: CAPABILITIES.TAXONOMY_READ },
      { title: 'Approval Queue', path: ROUTES.PRODUCTS_APPROVALS, icon: <ShieldCheck size={18} />, capability: CAPABILITIES.PRODUCTS_APPROVE },
    ],
  },
  {
    group: 'OPERATIONS',
    items: [
      { title: 'Inventory Control Center', path: ROUTES.INVENTORY, icon: <Warehouse size={18} />, capability: CAPABILITIES.INVENTORY_READ },
      { title: 'Pricing Integrity', path: ROUTES.PRICING, icon: <DollarSign size={18} />, capability: CAPABILITIES.INVENTORY_READ },
      { title: 'Offers & Campaigns', path: ROUTES.OFFERS, icon: <DollarSign size={18} />, capability: CAPABILITIES.OFFERS_READ },
      { title: 'Subscriptions', path: ROUTES.SUBSCRIPTIONS, icon: <DollarSign size={18} />, capability: CAPABILITIES.SUBSCRIPTIONS_READ },
      { title: 'POS Integrations', path: ROUTES.POS, icon: <Plug size={18} />, capability: CAPABILITIES.INVENTORY_READ },
      { title: 'Data Imports', path: ROUTES.IMPORTS, icon: <Upload size={18} />, capability: CAPABILITIES.INVENTORY_READ },
    ],
  },
  {
    group: 'DISCOVERY',
    items: [
      { title: 'Search Analytics', path: ROUTES.SEARCH, icon: <Search size={18} />, capability: CAPABILITIES.ANALYTICS_READ },
      { title: 'Search Quality', path: ROUTES.SEARCH_QUALITY, icon: <Search size={18} />, capability: CAPABILITIES.ANALYTICS_READ },
      { title: 'Zero Results', path: ROUTES.SEARCH_ZERO_RESULTS, icon: <AlertCircle size={18} />, capability: CAPABILITIES.ANALYTICS_READ },
      { title: 'Search Trends', path: ROUTES.SEARCH_TRENDS, icon: <TrendingUp size={18} />, capability: CAPABILITIES.ANALYTICS_READ },
    ],
  },
  {
    group: 'ANALYTICS',
    items: [
      { title: 'Analytics Overview', path: ROUTES.ANALYTICS, icon: <BarChart2 size={18} />, capability: CAPABILITIES.ANALYTICS_READ },
      { title: 'Customers', path: ROUTES.ANALYTICS_CUSTOMERS, icon: <Users size={18} />, capability: CAPABILITIES.ANALYTICS_READ },
      { title: 'Shopkeepers', path: ROUTES.ANALYTICS_SHOPKEEPERS, icon: <Store size={18} />, capability: CAPABILITIES.ANALYTICS_READ },
      { title: 'Products', path: ROUTES.ANALYTICS_PRODUCTS, icon: <Package size={18} />, capability: CAPABILITIES.ANALYTICS_READ },
      { title: 'Shops', path: ROUTES.ANALYTICS_SHOPS, icon: <Building2 size={18} />, capability: CAPABILITIES.ANALYTICS_READ },
      { title: 'Search', path: ROUTES.ANALYTICS_SEARCH, icon: <Search size={18} />, capability: CAPABILITIES.ANALYTICS_READ },
      { title: 'Notifications', path: ROUTES.ANALYTICS_NOTIFICATIONS, icon: <Bell size={18} />, capability: CAPABILITIES.ANALYTICS_READ },
      { title: 'Geography', path: ROUTES.ANALYTICS_GEOGRAPHY, icon: <MapPin size={18} />, capability: CAPABILITIES.ANALYTICS_READ },
    ],
  },
  {
    group: 'ENGAGEMENT & GOVERNANCE',
    items: [
      { title: 'Support & Complaints', path: ROUTES.SUPPORT, icon: <AlertCircle size={18} />, capability: CAPABILITIES.SUPPORT_READ },
      { title: 'Reviews & Moderation', path: ROUTES.REVIEWS, icon: <MessageSquare size={18} />, capability: CAPABILITIES.REVIEWS_READ },
      { title: 'Push Notifications', path: ROUTES.NOTIFICATIONS, icon: <Bell size={18} />, capability: CAPABILITIES.NOTIFICATIONS_SEND },
      { title: 'Campaigns', path: ROUTES.NOTIFICATION_CAMPAIGNS, icon: <Bell size={18} />, capability: CAPABILITIES.NOTIFICATIONS_SEND },
      { title: 'Audit Logs', path: ROUTES.AUDIT, icon: <FileText size={18} />, capability: CAPABILITIES.AUDIT_READ },
    ],
  },
  {
    group: 'CONTENT & ANNOUNCEMENTS',
    items: [
      { title: 'Content Overview', path: ROUTES.CONTENT, icon: <Newspaper size={18} />, capability: CAPABILITIES.CONTENT_READ },
      { title: 'Home Banners', path: ROUTES.CONTENT_BANNERS, icon: <ImageIcon size={18} />, capability: CAPABILITIES.CONTENT_READ },
      { title: 'Announcements', path: ROUTES.CONTENT_ANNOUNCEMENTS, icon: <Megaphone size={18} />, capability: CAPABILITIES.CONTENT_READ },
      { title: 'FAQs', path: ROUTES.CONTENT_FAQS, icon: <HelpCircle size={18} />, capability: CAPABILITIES.CONTENT_READ },
      { title: 'Help Content', path: ROUTES.CONTENT_HELP, icon: <BookOpen size={18} />, capability: CAPABILITIES.CONTENT_READ },
      { title: 'Promotional Cards', path: ROUTES.CONTENT_PROMOTIONS, icon: <Ticket size={18} />, capability: CAPABILITIES.CONTENT_READ },
      { title: 'System Messages', path: ROUTES.CONTENT_SYSTEM_MESSAGES, icon: <AlertTriangle size={18} />, capability: CAPABILITIES.CONTENT_READ },
    ],
  },
  {
    group: 'ADMINISTRATION',
    items: [
      // Landing page for the whole administration area. It collects the
      // governance, config, audit and job destinations below it in one place,
      // so it opens the section rather than sitting beside the parts.
      { title: 'Settings Hub', path: ROUTES.SETTINGS, icon: <LayoutGrid size={18} />, capability: CAPABILITIES.SETTINGS_READ },
      { title: 'Admin Users', path: ROUTES.ADMIN_USERS, icon: <ShieldCheck size={18} />, capability: CAPABILITIES.ADMINS_READ },
      { title: 'System Settings', path: ROUTES.SYSTEM_SETTINGS, icon: <Settings size={18} />, capability: CAPABILITIES.SETTINGS_READ },
      { title: 'Feature Flags', path: ROUTES.SYSTEM_FLAGS, icon: <Sliders size={18} />, capability: CAPABILITIES.SETTINGS_MANAGE },
      { title: 'System Health', path: ROUTES.SYSTEM_HEALTH, icon: <ActivityIcon size={18} />, capability: CAPABILITIES.SETTINGS_READ },
      { title: 'Background Jobs', path: ROUTES.SYSTEM_JOBS, icon: <Layers size={18} />, capability: CAPABILITIES.SETTINGS_READ },
    ],
  },
];

export const Sidebar: React.FC = () => {
  const pathname = usePathname();
  const router = useRouter();
  const { can, isLoading } = usePermissions();
  const [collapsedGroups, setCollapsedGroups] = useState<Record<string, boolean>>({});
  const [prefsLoaded, setPrefsLoaded] = useState(false);

  // Restore remembered collapse state on mount (UI preference only — no platform data).
  useEffect(() => {
    try {
      const raw = window.localStorage.getItem(COLLAPSE_STORAGE_KEY);
      if (raw) setCollapsedGroups(JSON.parse(raw));
    } catch {
      // Ignore malformed preference payloads
    }
    setPrefsLoaded(true);
  }, []);

  // Persist collapse state whenever it changes.
  useEffect(() => {
    if (!prefsLoaded) return;
    try {
      window.localStorage.setItem(COLLAPSE_STORAGE_KEY, JSON.stringify(collapsedGroups));
    } catch {
      // Storage may be unavailable (private mode) — non-fatal
    }
  }, [collapsedGroups, prefsLoaded]);

  // Auto-expand the group containing the active route so the selected
  // navigation state is always visible after a reload or deep-link.
  useEffect(() => {
    const activeGroup = NAV_GROUPS.find((g) =>
      g.items.some((item) => pathname === item.path || pathname.startsWith(`${item.path}/`))
    );
    if (!activeGroup) return;
    setCollapsedGroups((prev) => {
      if (!prev[activeGroup.group]) return prev;
      return { ...prev, [activeGroup.group]: false };
    });
  }, [pathname]);

  const toggleGroup = useCallback((group: string) => {
    setCollapsedGroups((prev) => ({ ...prev, [group]: !prev[group] }));
  }, []);

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

          // Authorization-aware navigation: only render destinations the current
          // admin capability set permits. Centralized, never hardcoded per page.
          const visibleItems = isLoading
            ? []
            : navGroup.items.filter((item) => !item.capability || can(item.capability));

          if (!isLoading && visibleItems.length === 0) return null;

          return (
            <Box key={navGroup.group} sx={{ mb: 1 }}>
              <Box
                onClick={() => toggleGroup(navGroup.group)}
                role="button"
                aria-expanded={!isCollapsed}
                aria-label={`Toggle ${navGroup.group} section`}
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
                  {visibleItems.map((item) => {
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
