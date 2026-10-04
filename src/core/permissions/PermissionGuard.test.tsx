import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { ThemeProvider } from '@mui/material/styles';
import { theme } from '@/core/theme/theme';
import { PermissionGuard } from './PermissionGuard';
import { CAPABILITIES } from './permissions';
import { AdminRoleInfo } from '@/core/types/admin';

const mockAuth = vi.fn();
vi.mock('../auth/AuthContext', () => ({
  useAuth: () => mockAuth(),
}));

vi.mock('next/navigation', () => ({
  useRouter: () => ({ replace: vi.fn(), push: vi.fn() }),
}));

const renderGuard = (props: { capability?: string; children: React.ReactNode }) =>
  render(
    <ThemeProvider theme={theme}>
      <PermissionGuard capability={props.capability}>{props.children}</PermissionGuard>
    </ThemeProvider>
  );

const authed = (role: Partial<AdminRoleInfo>) => ({
  adminRole: { user_id: 1, name: 'X', role_name: 'ANALYST', level: 'SUB' as const, permissions: [], ...role },
  isLoading: false,
});

describe('PermissionGuard — forbidden routing (403)', () => {
  it('renders children when the capability is granted', () => {
    mockAuth.mockReturnValue(authed({ role_name: 'OWNER', level: 'SUPER' }));
    renderGuard({ capability: CAPABILITIES.SETTINGS_MANAGE, children: <div>secret</div> });
    expect(screen.getByText('secret')).toBeInTheDocument();
  });

  it('renders the 403 Access Denied screen when forbidden', () => {
    mockAuth.mockReturnValue(authed({ role_name: 'ANALYST' }));
    renderGuard({ capability: CAPABILITIES.SETTINGS_MANAGE, children: <div>secret</div> });
    expect(screen.queryByText('secret')).not.toBeInTheDocument();
    expect(screen.getByText(/Access Denied \(403\)/i)).toBeInTheDocument();
  });

  it('renders nothing while the session is loading', () => {
    mockAuth.mockReturnValue({ adminRole: null, isLoading: true });
    const { container } = renderGuard({ capability: CAPABILITIES.SETTINGS_MANAGE, children: <div>secret</div> });
    expect(container).toBeEmptyDOMElement();
  });

  it('uses an explicit fallback when provided', () => {
    mockAuth.mockReturnValue(authed({ role_name: 'ANALYST' }));
    render(
      <ThemeProvider theme={theme}>
        <PermissionGuard capability={CAPABILITIES.SETTINGS_MANAGE} fallback={<span>no access</span>}>
          <div>secret</div>
        </PermissionGuard>
      </ThemeProvider>
    );
    expect(screen.getByText('no access')).toBeInTheDocument();
  });
});
