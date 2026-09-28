'use client';

import React from 'react';
import { useRouter } from 'next/navigation';
import { Box, Typography, Grid, Card, CardContent, Button } from '@mui/material';
import { Search, AlertCircle, TrendingUp, BarChart2 } from 'lucide-react';

export default function SearchAnalyticsPage() {
  const router = useRouter();

  return (
    <Box>
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Search & Discovery Control Center
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Section 41 & 43: Local search funnel, product matching accuracy, latency, and discovery efficiency.
        </Typography>
      </Box>

      <Grid container spacing={3} sx={{ mb: 4 }}>
        <Grid item xs={12} sm={6} md={3}>
          <Card>
            <CardContent sx={{ p: 2.5 }}>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <Box>
                  <Typography variant="caption" color="text.secondary" sx={{ fontWeight: 600 }}>
                    SEARCH SUCCESS RATE
                  </Typography>
                  <Typography variant="h5" sx={{ fontWeight: 800, mt: 0.5 }}>
                    86.4%
                  </Typography>
                </Box>
                <TrendingUp size={22} color="#10B981" />
              </Box>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} sm={6} md={3}>
          <Card>
            <CardContent sx={{ p: 2.5 }}>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <Box>
                  <Typography variant="caption" color="text.secondary" sx={{ fontWeight: 600 }}>
                    AVG SEARCH LATENCY
                  </Typography>
                  <Typography variant="h5" sx={{ fontWeight: 800, mt: 0.5 }}>
                    42 ms
                  </Typography>
                </Box>
                <BarChart2 size={22} color="#0F52BA" />
              </Box>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} sm={6} md={3}>
          <Card>
            <CardContent sx={{ p: 2.5 }}>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <Box>
                  <Typography variant="caption" color="text.secondary" sx={{ fontWeight: 600 }}>
                    ZERO RESULT QUERIES
                  </Typography>
                  <Typography variant="h5" sx={{ fontWeight: 800, mt: 0.5 }}>
                    424
                  </Typography>
                </Box>
                <AlertCircle size={22} color="#EF4444" />
              </Box>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} sm={6} md={3}>
          <Card>
            <CardContent sx={{ p: 2.5 }}>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <Box>
                  <Typography variant="caption" color="text.secondary" sx={{ fontWeight: 600 }}>
                    STORE DIRECTIONS TAPS
                  </Typography>
                  <Typography variant="h5" sx={{ fontWeight: 800, mt: 0.5 }}>
                    1,890
                  </Typography>
                </Box>
                <Search size={22} color="#8B5CF6" />
              </Box>
            </CardContent>
          </Card>
        </Grid>
      </Grid>

      {/* Funnel Card */}
      <Card sx={{ p: 3 }}>
        <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 1 }}>
          Hyperlocal Offline Discovery Funnel (Section 43)
        </Typography>
        <Typography variant="body2" color="text.secondary" sx={{ mb: 3 }}>
          Customer Search $\rightarrow$ Products Found $\rightarrow$ Product Opened $\rightarrow$ Physical Store Directions Clicked.
        </Typography>

        <Box sx={{ display: 'flex', alignItems: 'center', gap: 2, flexWrap: 'wrap' }}>
          <Button
            variant="contained"
            color="primary"
            onClick={() => router.push('/search/zero-results')}
          >
            Investigate Zero-Result Searches →
          </Button>
        </Box>
      </Card>
    </Box>
  );
}
