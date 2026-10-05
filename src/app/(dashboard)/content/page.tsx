'use client';

import React from 'react';
import { useRouter } from 'next/navigation';
import { Box, Typography, Card, CardContent, Grid, Chip } from '@mui/material';
import {
  Image as ImageIcon,
  Megaphone,
  HelpCircle,
  BookOpen,
  Ticket,
  AlertTriangle,
  ChevronRight,
} from 'lucide-react';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { usePermissions } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES } from '@/core/permissions/permissions';
import { ROUTES } from '@/core/routes/routes';

interface ContentSection {
  title: string;
  description: string;
  path: string;
  icon: React.ReactNode;
  color: string;
}

const SECTIONS: ContentSection[] = [
  {
    title: 'Home Banners',
    description: 'Manage the promotional banners shown on the customer home screen.',
    path: ROUTES.CONTENT_BANNERS,
    icon: <ImageIcon size={22} />,
    color: '#0F52BA',
  },
  {
    title: 'Announcements',
    description: 'Publish targeted platform announcements to customers and shopkeepers.',
    path: ROUTES.CONTENT_ANNOUNCEMENTS,
    icon: <Megaphone size={22} />,
    color: '#8B5CF6',
  },
  {
    title: 'FAQs',
    description: 'Curate the frequently asked questions surfaced in the help centre.',
    path: ROUTES.CONTENT_FAQS,
    icon: <HelpCircle size={22} />,
    color: '#10B981',
  },
  {
    title: 'Help Content',
    description: 'Author structured help articles and onboarding guides.',
    path: ROUTES.CONTENT_HELP,
    icon: <BookOpen size={22} />,
    color: '#F59E0B',
  },
  {
    title: 'Promotional Cards',
    description: 'Design in-app promotional cards with validated deep links.',
    path: ROUTES.CONTENT_PROMOTIONS,
    icon: <Ticket size={22} />,
    color: '#EF4444',
  },
  {
    title: 'System Messages',
    description: 'Broadcast operational banners such as maintenance and outage notices.',
    path: ROUTES.CONTENT_SYSTEM_MESSAGES,
    icon: <AlertTriangle size={22} />,
    color: '#6366F1',
  },
];

export default function ContentOverviewPage() {
  const router = useRouter();
  const { can } = usePermissions();

  return (
    <Box>
      <DrillDownBreadcrumbs items={[{ label: 'Dashboard', href: ROUTES.DASHBOARD }, { label: 'Content & Announcements' }]} />

      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Content & Announcements
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Manage home banners, announcements, FAQs, help content, promotional cards and system messages. All content is
          served by the backend content API — this console only authors and controls it.
        </Typography>
      </Box>

      <PermissionGuard capability={CAPABILITIES.CONTENT_READ}>
        <Grid container spacing={2}>
          {SECTIONS.map((section) => {
            const allowed = can(CAPABILITIES.CONTENT_READ);
            return (
              <Grid item xs={12} sm={6} md={4} key={section.path}>
                <Card
                  onClick={() => allowed && router.push(section.path)}
                  sx={{
                    cursor: allowed ? 'pointer' : 'not-allowed',
                    height: '100%',
                    transition: 'all 0.15s ease',
                    '&:hover': allowed ? { boxShadow: 4, transform: 'translateY(-2px)' } : {},
                  }}
                >
                  <CardContent sx={{ p: 2.5 }}>
                    <Box
                      sx={{
                        width: 44,
                        height: 44,
                        borderRadius: 2,
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        backgroundColor: `${section.color}14`,
                        color: section.color,
                        mb: 1.5,
                      }}
                    >
                      {section.icon}
                    </Box>
                    <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                      <Typography variant="subtitle1" sx={{ fontWeight: 700 }}>
                        {section.title}
                      </Typography>
                      <ChevronRight size={18} color="#94A3B8" />
                    </Box>
                    <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
                      {section.description}
                    </Typography>
                  </CardContent>
                </Card>
              </Grid>
            );
          })}
        </Grid>
      </PermissionGuard>
    </Box>
  );
}