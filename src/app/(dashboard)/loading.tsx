import { Skeleton, Box, Card, CardContent, Stack } from '@mui/material';

/**
 * Route-level loading skeleton for the dashboard shell.
 *
 * React Query already keeps previously-fetched data visible during refetch, so
 * this only appears on first navigation into a section. It gives the operator
 * structural feedback immediately instead of an empty frame while the request
 * is in flight.
 */
export default function DashboardLoading() {
  return (
    <Box>
      <Skeleton variant="text" width={280} height={44} />
      <Skeleton variant="text" width={420} height={24} sx={{ mb: 3 }} />

      <Stack direction="row" spacing={2.5} sx={{ mb: 3, flexWrap: 'wrap' }}>
        {[0, 1, 2, 3].map((i) => (
          <Box key={i} sx={{ flex: '1 1 220px' }}>
            <Card>
              <CardContent sx={{ p: 2.5 }}>
                <Skeleton variant="text" width="45%" height={18} />
                <Skeleton variant="text" width="65%" height={40} />
              </CardContent>
            </Card>
          </Box>
        ))}
      </Stack>

      <Card>
        <CardContent sx={{ p: 2 }}>
          <Stack spacing={1}>
            {Array.from({ length: 8 }).map((_, i) => (
              <Skeleton key={i} variant="rounded" height={44} />
            ))}
          </Stack>
        </CardContent>
      </Card>
    </Box>
  );
}