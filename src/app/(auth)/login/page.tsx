'use client';

import React, { useState } from 'react';
import {
  Box,
  Card,
  CardContent,
  Typography,
  TextField,
  Button,
  Alert,
  CircularProgress,
  Divider,
} from '@mui/material';
import { ShieldCheck, Lock } from 'lucide-react';
import { useAuth } from '@/core/auth/AuthContext';

export default function LoginPage() {
  const { login } = useAuth();
  const [tokenInput, setTokenInput] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!tokenInput.trim()) {
      setError('Please provide a valid Admin Bearer Token');
      return;
    }
    setError(null);
    setLoading(true);
    try {
      await login(tokenInput.trim());
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Authentication failed. Check admin credentials.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Box
      sx={{
        minHeight: '100vh',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: '#0F172A', // Slate 900
        p: 2,
      }}
    >
      <Card sx={{ maxWidth: 420, width: '100%', p: 2, borderRadius: 3, boxShadow: '0 25px 50px -12px rgba(0,0,0,0.25)' }}>
        <CardContent sx={{ display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center' }}>
          <Box
            sx={{
              width: 56,
              height: 56,
              borderRadius: 2,
              backgroundColor: '#EFF6FF',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              color: 'primary.main',
              mb: 2,
            }}
          >
            <ShieldCheck size={32} />
          </Box>

          <Typography variant="h5" sx={{ fontWeight: 700, mb: 0.5 }}>
            HyperLocal Admin
          </Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 3 }}>
            Platform Control & Governance Portal
          </Typography>

          {error && (
            <Alert severity="error" sx={{ width: '100%', mb: 2, textAlign: 'left' }}>
              {error}
            </Alert>
          )}

          <Box component="form" onSubmit={handleSubmit} sx={{ width: '100%' }}>
            <TextField
              margin="normal"
              required
              fullWidth
              name="token"
              label="Admin Access Token / Bearer Token"
              type="password"
              id="token"
              autoComplete="current-password"
              value={tokenInput}
              onChange={(e) => setTokenInput(e.target.value)}
              placeholder="Paste JWT / Bearer token"
              helperText="Validated authoritative against /api/v1/admin/me"
              disabled={loading}
            />

            <Button
              type="submit"
              fullWidth
              variant="contained"
              size="large"
              disabled={loading}
              startIcon={loading ? <CircularProgress size={18} color="inherit" /> : <Lock size={18} />}
              sx={{ mt: 3, mb: 2, py: 1.25 }}
            >
              {loading ? 'Authenticating...' : 'Sign In to Control Center'}
            </Button>
          </Box>

          <Divider sx={{ width: '100%', my: 2 }} />

          <Typography variant="caption" color="text.secondary">
            Enterprise Operations • Single Source of Truth • Strict RBAC
          </Typography>
        </CardContent>
      </Card>
    </Box>
  );
}
