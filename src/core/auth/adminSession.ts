/**
 * Ephemeral admin session bridge.
 *
 * Authoritative authentication remains backend-controlled. The access token is
 * intentionally kept only in memory and is never written to localStorage,
 * sessionStorage, cookies, IndexedDB, or any other browser persistence layer.
 * Production persistence across reloads must be provided by the backend via an
 * HttpOnly, Secure, SameSite cookie.
 */
let accessToken: string | null = null;

export function setAdminAccessToken(token: string): void {
  accessToken = token;
}

export function getAdminAccessToken(): string | null {
  return accessToken;
}

export function clearAdminAccessToken(): void {
  accessToken = null;
}
