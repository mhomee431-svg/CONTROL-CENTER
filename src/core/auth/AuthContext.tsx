'use client';

import React, { createContext, useContext, useEffect, useState, useCallback } from 'react';
import { useRouter, usePathname } from 'next/navigation';
import { AdminRoleInfo } from '../types/admin';
import { apiClient } from '../api/client';
import { API_ENDPOINTS } from '../api/endpoints';
import {
  clearAdminAccessToken,
  getAdminAccessToken,
  setAdminAccessToken,
} from './adminSession';

export type AdminSessionStatus = 'loading' | 'authenticated' | 'unauthenticated' | 'expired';

interface AuthContextType {
  token: string | null;
  adminRole: AdminRoleInfo | null;
  isLoading: boolean;
  status: AdminSessionStatus;
  login: (token?: string) => Promise<void>;
  logout: (preserveExpiredStatus?: boolean) => void;
  refreshProfile: () => Promise<void>;
  featureFlags: Record<string, boolean>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [token, setToken] = useState<string | null>(null);
  const [adminRole, setAdminRole] = useState<AdminRoleInfo | null>(null);
  const [featureFlags, setFeatureFlags] = useState<Record<string, boolean>>({});
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [status, setStatus] = useState<AdminSessionStatus>('loading');
  const router = useRouter();
  const pathname = usePathname();

  const logout = useCallback((preserveExpiredStatus = false) => {
    // Session state is ephemeral. Backend remains authoritative.
    clearAdminAccessToken();
    setToken(null);
    setAdminRole(null);
    if (!preserveExpiredStatus) setStatus('unauthenticated');
    if (pathname !== '/login') {
      router.push('/login');
    }
  }, [pathname, router]);

  const fetchAdminProfile = useCallback(async (sessionToken?: string) => {
    try {
      const data = await apiClient<AdminRoleInfo>(API_ENDPOINTS.AUTH.ME, sessionToken ? {
        headers: { Authorization: `Bearer ${sessionToken}` },
      } : {});
      setAdminRole(data);
      // Feature flags are optional profile context. A flags failure (a role
      // without settings access, or an older backend) must never terminate an
      // otherwise valid admin session.
      try {
        const flags = await apiClient<{ items?: Array<{ name: string; is_enabled: boolean }> }>(
          API_ENDPOINTS.SYSTEM.FEATURE_FLAGS
        );
        setFeatureFlags(
          Object.fromEntries((flags.items || []).map((flag) => [flag.name, flag.is_enabled]))
        );
      } catch {
        setFeatureFlags({});
      }
      setStatus('authenticated');
      return data;
    } catch {
      // Only an already-established runtime session is classified as expired.
      // A cold start without a session is simply unauthenticated.
      const hadRuntimeSession = Boolean(getAdminAccessToken());
      if (hadRuntimeSession) {
        setStatus('expired');
        logout(true);
      } else {
        logout();
      }
      return null;
    }
  }, [logout]);

  const login = async (newToken?: string) => {
    if (newToken) {
      setAdminAccessToken(newToken);
      setToken(newToken);
    }
    const profile = await fetchAdminProfile(newToken);
    if (!profile) {
      throw new Error('Token invalid or expired, or the backend is unavailable.');
    }
    setStatus('authenticated');
    router.push('/dashboard');
  };

  useEffect(() => {
    // The backend session cookie is authoritative. The in-memory token only
    // exists for the current runtime and cannot be restored from browser storage.
    const activeToken = getAdminAccessToken();
    if (activeToken) {
      setToken(activeToken);
      fetchAdminProfile().finally(() => setIsLoading(false));
      return;
    }

    // Ask the backend whether its HttpOnly session is still valid. If no
    // backend session exists, apiClient will reject and we redirect to login.
    fetchAdminProfile().finally(() => setIsLoading(false));
  }, [fetchAdminProfile]);

  return (
    <AuthContext.Provider
      value={{
        token,
        adminRole,
        isLoading,
        status,
        featureFlags,
        login,
        logout,
        refreshProfile: async () => {
          await fetchAdminProfile();
        },
      }}
    >
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
};
