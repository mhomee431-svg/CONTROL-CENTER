'use client';

import React from 'react';
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
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { useSearchParams } from 'next/navigation';
import { useAuth } from '@/core/auth/AuthContext';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';

// Contract stack: React Hook Form + Zod for form state and validation
const loginSchema = z.object({
  username: z.string().trim().min(1, 'Username is required'),
  password: z.string().min(1, 'Password is required'),
});

type LoginFormValues = z.infer<typeof loginSchema>;

interface LoginResponse {
  /** Present when the approved backend uses a bearer response. */
  access_token?: string;
}

function LoginContent() {
  const { login } = useAuth();
  const searchParams = useSearchParams();
  // Expired sessions land here with ?expired=1 for explicit re-authentication.
  const sessionExpired = searchParams.get('expired') === '1';
  const [error, setError] = React.useState<string | null>(null);
  const [tokenInput, setTokenInput] = React.useState('');
  const [tokenSubmitting, setTokenSubmitting] = React.useState(false);

  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<LoginFormValues>({
    resolver: zodResolver(loginSchema),
    defaultValues: { username: '', password: '' },
  });

  const onSubmit = async (values: LoginFormValues) => {
    setError(null);
    try {
      // Single Authoritative API Client (Section 99) — handles error envelopes,
      // 401/403 mapping, and request IDs.
      const data = await apiClient<LoginResponse>(API_ENDPOINTS.AUTH.LOGIN, {
        method: 'POST',
        body: JSON.stringify({ username: values.username, password: values.password }),
        requiresAuth: false,
      });
      // The backend may establish an HttpOnly cookie (preferred) or return a
      // short-lived bearer token. Support both approved backend contracts.
      await login(data?.access_token);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Authentication failed. Check admin credentials.');
    }
  };

  const onTokenSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    setError(null);
    setTokenSubmitting(true);
    try {
      await login(tokenInput.trim());
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Token authentication failed.');
    } finally {
      setTokenSubmitting(false);
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

          {sessionExpired && !error && (
            <Alert severity="warning" sx={{ width: '100%', mb: 2, textAlign: 'left' }}>
              Your admin session expired. Please re-authenticate to continue.
            </Alert>
          )}

          {error && (
            <Alert severity="error" sx={{ width: '100%', mb: 2, textAlign: 'left' }}>
              {error}
            </Alert>
          )}

          <Box component="form" onSubmit={handleSubmit(onSubmit)} sx={{ width: '100%' }} noValidate>
            <TextField
              margin="normal"
              required
              fullWidth
              id="username"
              label="Admin Username"
              autoComplete="username"
              placeholder="Admin username"
              disabled={isSubmitting}
              error={!!errors.username}
              helperText={errors.username?.message}
              {...register('username')}
            />
            <TextField
              margin="normal"
              required
              fullWidth
              id="password"
              label="Password"
              type="password"
              autoComplete="current-password"
              placeholder="••••••••"
              disabled={isSubmitting}
              error={!!errors.password}
              helperText={errors.password?.message}
              {...register('password')}
            />

            <Button
              type="submit"
              fullWidth
              variant="contained"
              size="large"
              disabled={isSubmitting}
              startIcon={isSubmitting ? <CircularProgress size={18} color="inherit" /> : <Lock size={18} />}
              sx={{ mt: 3, mb: 2, py: 1.25 }}
            >
              {isSubmitting ? 'Authenticating...' : 'Sign In to Control Center'}
            </Button>
          </Box>

          <Divider sx={{ width: '100%', my: 2 }}>OR</Divider>

          <Box component="form" onSubmit={onTokenSubmit} sx={{ width: '100%' }}>
            <TextField
              fullWidth
              label="Admin access token"
              type="password"
              autoComplete="off"
              value={tokenInput}
              onChange={(event) => setTokenInput(event.target.value)}
              disabled={tokenSubmitting}
            />
            <Button type="submit" fullWidth variant="outlined" sx={{ mt: 2 }} disabled={!tokenInput.trim() || tokenSubmitting}>
              {tokenSubmitting ? 'Authenticating...' : 'Sign in with token'}
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

export default function LoginPage() {
  return (
    <React.Suspense fallback={null}>
      <LoginContent />
    </React.Suspense>
  );
}
