import { describe, it, expect, beforeEach } from 'vitest';
import {
  setAdminAccessToken,
  getAdminAccessToken,
  clearAdminAccessToken,
} from './adminSession';

describe('adminSession — ephemeral, no browser persistence', () => {
  beforeEach(() => clearAdminAccessToken());

  it('starts with no token', () => {
    expect(getAdminAccessToken()).toBeNull();
  });

  it('stores and reads a token in memory', () => {
    setAdminAccessToken('tok_123');
    expect(getAdminAccessToken()).toBe('tok_123');
  });

  it('clears the token on logout', () => {
    setAdminAccessToken('tok_123');
    clearAdminAccessToken();
    expect(getAdminAccessToken()).toBeNull();
  });

  it('never touches browser storage', () => {
    setAdminAccessToken('tok_123');
    expect(window.localStorage.length).toBe(0);
    expect(window.sessionStorage.length).toBe(0);
  });
});
