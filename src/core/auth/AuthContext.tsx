'use client';

import React, { createContext, useContext, useEffect, useState, useCallback } from 'react';
import { useRouter, usePathname } from 'next/navigation';
import { AdminRoleInfo } from '../types/admin';
import { apiClient } from '../api/client';
import { API_ENDPOINTS } from '../api/endpoints';

interface AuthContextType {
  token: string | null;
  adminRole: AdminRoleInfo | null;
  isLoading: boolean;
  login: (token: string) => Promise<void>;
  logout: () => void;
  refreshProfile: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [token, setToken] = useState<string | null>(null);
  const [adminRole, setAdminRole] = useState<AdminRoleInfo | null>(null);
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const router = useRouter();
  const pathname = usePathname();

  const fetchAdminProfile = useCallback(async () => {
    try {
      const data = await apiClient<AdminRoleInfo>(API_ENDPOINTS.AUTH.ME);
      setAdminRole(data);
      localStorage.setItem('admin_role_cache', JSON.stringify(data));
      return data;
    } catch {
      // If /admin/me fails or token invalid
      logout();
      return null;
    }
  }, []);

  const login = async (newToken: string) => {
    localStorage.setItem('admin_access_token', newToken);
    setToken(newToken);
    const profile = await fetchAdminProfile();
    if (profile) {
      router.push('/dashboard');
    }
  };

  const logout = useCallback(() => {
    // Section 150 & 151: Security Cache Clearing on logout
    localStorage.removeItem('admin_access_token');
    localStorage.removeItem('admin_role_cache');
    setToken(null);
    setAdminRole(null);
    if (pathname !== '/login') {
      router.push('/login');
    }
  }, [pathname, router]);

  useEffect(() => {
    const savedToken = localStorage.getItem('admin_access_token');
    if (savedToken) {
      setToken(savedToken);
      fetchAdminProfile().finally(() => {
        setIsLoading(false);
      });
    } else {
      setIsLoading(false);
      if (pathname !== '/login') {
        router.push('/login');
      }
    }
  }, [fetchAdminProfile, pathname, router]);

  return (
    <AuthContext.Provider
      value={{
        token,
        adminRole,
        isLoading,
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
