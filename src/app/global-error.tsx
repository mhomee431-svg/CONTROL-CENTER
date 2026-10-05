'use client';

/**
 * Root error boundary.
 *
 * This catches failures in the root layout itself (theme, providers, auth),
 * which no nested boundary can intercept. It must render its own <html> and
 * <body> because the root layout that normally provides them has already
 * failed.
 */
export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <html lang="en">
      <body
        style={{
          margin: 0,
          fontFamily: 'system-ui, -apple-system, Segoe UI, Roboto, sans-serif',
          backgroundColor: '#0F172A',
          color: '#F8FAFC',
          minHeight: '100vh',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        <div style={{ maxWidth: 560, padding: 32, textAlign: 'center' }}>
          <h1 style={{ fontSize: 22, margin: '0 0 12px' }}>Admin Control Center failed to start</h1>
          <p style={{ color: '#94A3B8', fontSize: 14, lineHeight: 1.6, margin: '0 0 24px' }}>
            A critical error occurred before the control center could render. This usually indicates
            a configuration or dependency problem rather than a data issue.
          </p>
          <pre
            style={{
              backgroundColor: '#1E293B',
              padding: 16,
              borderRadius: 8,
              fontSize: 12,
              textAlign: 'left',
              overflowX: 'auto',
              color: '#FCA5A5',
            }}
          >
            {error.message || 'Unknown fatal error'}
            {error.digest && `\n\nDigest: ${error.digest}`}
          </pre>
          <button
            onClick={() => reset()}
            style={{
              marginTop: 24,
              padding: '10px 22px',
              borderRadius: 8,
              border: 'none',
              backgroundColor: '#2563EB',
              color: '#fff',
              fontSize: 14,
              fontWeight: 600,
              cursor: 'pointer',
            }}
          >
            Reload Control Center
          </button>
        </div>
      </body>
    </html>
  );
}