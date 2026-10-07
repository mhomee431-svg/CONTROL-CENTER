/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  output: 'standalone',
  modularizeImports: {
    '@mui/icons-material': {
      transform: '@mui/icons-material/{{member}}',
    },
  },
  experimental: {
    // Enable optimizations
  },
  async rewrites() {
    const apiUrl = process.env.NEXT_PUBLIC_API_URL
      || (process.env.NODE_ENV === 'development' ? 'http://localhost:8000' : '');
    if (!apiUrl) return [];

    return [
      {
        source: '/api/v1/:path*',
        destination: `${apiUrl}/api/v1/:path*`,
      },
    ];
  },
  async headers() {
    const securityHeaders = [
      { key: 'X-Content-Type-Options', value: 'nosniff' },
      { key: 'X-Frame-Options', value: 'DENY' },
      { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
      { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=()' },
    ];
    if (process.env.NODE_ENV === 'production') {
      securityHeaders.push({
        key: 'Strict-Transport-Security',
        value: 'max-age=63072000; includeSubDomains; preload',
      });
    }

    return [
      { source: '/:path*', headers: securityHeaders },
      { source: '/login/:path*', headers: [{ key: 'Cache-Control', value: 'no-store' }] },
    ];
  },
};

export default nextConfig;
