'use client';

import { useEffect, useRef, useState, useCallback } from 'react';
import { isOperationalEventType } from './eventTaxonomy';

/**
 * Section 80: Real-time operational event stream.
 * Contract: browser → approved backend WS/SSE endpoint → FastAPI. No direct infra access.
 *
 * Strategy:
 *  - Primary: WebSocket (NEXT_PUBLIC_WS_URL or same-origin endpoint) — reconnect with exponential backoff.
 *  - Fallback: authenticated Server-Sent Events after two WebSocket failures.
 *  - Consumers must handle absence gracefully (sample data fallback on pages).
 */

export interface RealtimeEvent {
  id: string;
  /** Always a declared operational event type — see eventTaxonomy.ts. */
  type: string;
  title: string;
  timestamp: string;
}

type Transport = 'websocket' | 'sse' | 'offline';

interface UseRealtimeEventsResult {
  events: RealtimeEvent[];
  transport: Transport;
  connected: boolean;
  reconnect: () => void;
}

const MAX_BUFFER = 50;

function parseMessage(raw: string): RealtimeEvent | null {
  try {
    const parsed = JSON.parse(raw);
    // Backend envelope: { success, message, data: { type, title, ... } } OR flat event object
    const payload = parsed?.data ?? parsed;
    if (!payload || (!payload.type && !payload.title)) return null;

    // Allowlist enforcement at the transport boundary. Raw DB/ORM noise and
    // heartbeats are dropped here so they never reach the UI or trigger a
    // dashboard refresh — only meaningful operational events pass through.
    const type = String(payload.type ?? '');
    if (type && !isOperationalEventType(type)) return null;

    return {
      id: String(payload.id ?? `${Date.now()}_${Math.random().toString(36).slice(2, 8)}`),
      type: type || 'OPERATIONAL',
      title: payload.title ?? payload.message ?? 'Operational event',
      timestamp: payload.timestamp ?? new Date().toISOString(),
    };
  } catch {
    return null;
  }
}

export function useRealtimeEvents(enabled = true): UseRealtimeEventsResult {
  const [events, setEvents] = useState<RealtimeEvent[]>([]);
  const [transport, setTransport] = useState<Transport>('offline');
  const wsRef = useRef<WebSocket | null>(null);
  const esRef = useRef<EventSource | null>(null);
  const retryRef = useRef(0);
  const closedRef = useRef(false);
  const [reconnectTick, setReconnectTick] = useState(0);

  const pushEvent = useCallback((event: RealtimeEvent) => {
    setEvents((prev) => [event, ...prev].slice(0, MAX_BUFFER));
  }, []);

  useEffect(() => {
    if (!enabled) return;
    closedRef.current = false;
    const wsUrl = process.env.NEXT_PUBLIC_WS_URL
      || `${window.location.protocol === 'https:' ? 'wss:' : 'ws:'}//${window.location.host}/api/v1/ws`;

    const startSseFallback = () => {
      if (closedRef.current || esRef.current) return;
      const base = (wsUrl ?? '').replace(/^ws/, 'http').replace(/\/api\/v1\/ws.*$/, '');
      const es = new EventSource(`${base}/api/v1/admin/events/stream`);
      esRef.current = es;
      es.onopen = () => setTransport('sse');
      es.addEventListener('operational', (msg) => {
        if (!(msg instanceof MessageEvent)) return;
        const event = parseMessage(msg.data);
        if (event) pushEvent(event);
      });
      es.onerror = () => {
        es.close();
        esRef.current = null;
        setTransport('offline');
      };
    };

    const connectWs = () => {
      if (closedRef.current || !wsUrl) {
        if (!wsUrl) startSseFallback();
        return;
      }
      try {
        const ws = new WebSocket(wsUrl);
        wsRef.current = ws;

        ws.onopen = () => {
          retryRef.current = 0;
          setTransport('websocket');
        };

        ws.onmessage = (msg) => {
          const event = parseMessage(typeof msg.data === 'string' ? msg.data : '');
          if (event) pushEvent(event);
        };

        ws.onclose = () => {
          wsRef.current = null;
          setTransport('offline');
          if (closedRef.current) return;
          retryRef.current += 1;
          if (retryRef.current >= 2) {
            startSseFallback();
          } else {
            const delay = Math.min(1000 * 2 ** retryRef.current, 15000);
            setTimeout(() => {
              if (!closedRef.current) connectWs();
            }, delay);
          }
        };

        ws.onerror = () => ws.close();
      } catch {
        startSseFallback();
      }
    };

    connectWs();

    return () => {
      closedRef.current = true;
      wsRef.current?.close();
      wsRef.current = null;
      esRef.current?.close();
      esRef.current = null;
      setTransport('offline');
    };
  }, [enabled, pushEvent, reconnectTick]);

  const reconnect = useCallback(() => {
    setEvents([]);
    retryRef.current = 0;
    setReconnectTick((t) => t + 1);
  }, []);

  return { events, transport, connected: transport !== 'offline', reconnect };
}
