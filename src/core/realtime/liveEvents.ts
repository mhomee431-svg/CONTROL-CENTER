/**
 * Live operational event contract.
 *
 * Kept outside the page module because Next.js App Router pages may only
 * export `default` (plus a small allowlist). The sample payload is retained
 * here as documentation of the expected backend shape.
 */

export interface LiveEvent {
  id: string;
  type: 'SEARCH' | 'SHOP_UPDATE' | 'REGISTRATION' | 'VERIFICATION' | string;
  title: string;
  timestamp: string;
}

/**
 * Documented sample events — reference only, never rendered.
 *
 * A live-operations feed showing invented registrations and inventory updates
 * is actively dangerous: operators would believe the platform received
 * activity that never happened. When the stream is down the UI says so.
 */
export const SAMPLE_EVENT_SHAPE: readonly LiveEvent[] = [
  {
    id: 'example-1',
    type: 'SEARCH',
    title: 'Shopper searched for "pain relief spray" in Saket, New Delhi',
    timestamp: new Date().toISOString(),
  },
  {
    id: 'example-2',
    type: 'SHOP_UPDATE',
    title: 'Shop updated stock count on multiple SKUs',
    timestamp: new Date().toISOString(),
  },
  {
    id: 'example-3',
    type: 'REGISTRATION',
    title: 'New customer registration completed',
    timestamp: new Date().toISOString(),
  },
  {
    id: 'example-4',
    type: 'VERIFICATION',
    title: 'Merchant onboarding submitted for review',
    timestamp: new Date().toISOString(),
  },
] as const;