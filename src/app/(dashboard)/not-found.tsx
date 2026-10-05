import Link from 'next/link';
import { Box, Typography, Button, Paper } from '@mui/material';
import { SearchX } from 'lucide-react';

/**
 * 404 for unmatched console routes. Without this Next.js renders its bare
 * default page, which looks broken inside the themed admin shell.
 */
export default function DashboardNotFound() {
  return (
    <Box sx={{ p: 3, display: 'flex', justifyContent: 'center' }}>
      <Paper sx={{ p: 5, maxWidth: 520, width: '100%', textAlign: 'center' }}>
        <Box sx={{ display: 'flex', justifyContent: 'center', mb: 2 }}>
          <SearchX size={40} color="#64748B" />
        </Box>
        <Typography variant="h5" sx={{ fontWeight: 700, mb: 1 }}>
          Page not found
        </Typography>
        <Typography variant="body2" color="text.secondary" sx={{ mb: 3 }}>
          This route does not exist in the Admin Control Center. It may have been moved, or the link
          may be out of date.
        </Typography>
        <Box component={Link} href="/dashboard">
          <Button variant="contained">Return to Dashboard</Button>
        </Box>
      </Paper>
    </Box>
  );
}