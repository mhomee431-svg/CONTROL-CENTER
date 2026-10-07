/**
 * REVIEW / MODERATION — Safety & Gating Helpers
 *
 * Pure functions behind the review moderation queue.
 *
 * The single most important rule in this module: THERE IS NO DELETE.
 * `assertNoDestructiveAction` exists as an executable guard so any future
 * attempt to wire a permanent-delete control into the review UI fails loudly
 * instead of silently shipping.
 *
 * The backend stays authoritative — these helpers only decide what the operator
 * may be *offered*, and every mutation is still re-checked server-side.
 */

import {
  ALL_REVIEW_DECISIONS,
  ReviewDecision,
  ReviewItem,
  ReviewModerationState,
  REVIEW_DECISIONS,
} from '../types/reviews';

const KNOWN_STATES: ReviewModerationState[] = ['VISIBLE', 'REPORTED', 'FLAGGED', 'HIDDEN', 'ESCALATED'];

/** Normalize a possibly-missing moderation state to the known set. */
export function normalizeReviewState(state?: string | null): ReviewModerationState | 'UNKNOWN' {
  const upper = (state || '').toUpperCase();
  return KNOWN_STATES.includes(upper as ReviewModerationState)
    ? (upper as ReviewModerationState)
    : 'UNKNOWN';
}

/**
 * Derive the moderation state.
 *
 * Prefers the explicit `moderation_state`; falls back to the boolean flags so
 * older backend payloads still render a meaningful state instead of "UNKNOWN".
 */
export function resolveReviewState(item?: ReviewItem | null): ReviewModerationState | 'UNKNOWN' {
  if (!item) return 'UNKNOWN';

  const explicit = normalizeReviewState(item.moderation_state);
  if (explicit !== 'UNKNOWN') return explicit;

  if (item.is_hidden) return 'HIDDEN';
  if (item.is_flagged) return 'FLAGGED';
  if ((item.report_count ?? 0) > 0) return 'REPORTED';
  return 'VISIBLE';
}

/** True when the review is currently suppressed from public view. */
export function isHidden(item?: ReviewItem | null): boolean {
  return resolveReviewState(item) === 'HIDDEN';
}

/** True when the review has at least one user report. */
export function isReported(item?: ReviewItem | null): boolean {
  return (item?.report_count ?? 0) > 0;
}

/** True when the platform (or a moderator) flagged the review. */
export function isFlagged(item?: ReviewItem | null): boolean {
  const state = resolveReviewState(item);
  return state === 'FLAGGED' || item?.is_flagged === true;
}

/** True when the review has been handed to a senior reviewer. */
export function isEscalated(item?: ReviewItem | null): boolean {
  return resolveReviewState(item) === 'ESCALATED';
}

/** True when the review still needs a moderator's attention. */
export function needsModeration(item?: ReviewItem | null): boolean {
  const state = resolveReviewState(item);
  return state === 'REPORTED' || state === 'FLAGGED' || state === 'UNKNOWN';
}

/** Total reports, defaulting to zero. */
export function reportCount(item?: ReviewItem | null): number {
  const value = item?.report_count;
  return typeof value === 'number' && Number.isFinite(value) && value > 0 ? value : 0;
}

/** Clamp a rating to the 1–5 display range, or null when absent/invalid. */
export function displayRating(item?: ReviewItem | null): number | null {
  const value = item?.rating;
  if (typeof value !== 'number' || !Number.isFinite(value)) return null;
  if (value < 1 || value > 5) return null;
  return value;
}

/**
 * Executable guard against permanent deletion.
 *
 * Any action name that implies destructive/irreversible removal is rejected.
 * This is intentionally a runtime throw so a regression is caught by tests
 * rather than discovered in production.
 */
export function assertNoDestructiveAction(action: string): void {
  const normalized = String(action || '').toUpperCase();
  const destructive = ['DELETE', 'DESTROY', 'PURGE', 'REMOVE', 'ERASE'];
  if (destructive.some((word) => normalized.includes(word))) {
    throw new Error(
      `Permanent deletion is not supported for reviews. Received destructive action "${action}". ` +
      'Use HIDE (reversible) instead.'
    );
  }
}

/**
 * Is a decision permitted for this review?
 *
 * Backend capability flags win. When a flag is explicitly false the action is
 * denied regardless of state; when absent, a conservative state-based default
 * applies.
 */
export function canApplyDecision(decision: ReviewDecision, item?: ReviewItem | null): boolean {
  if (!item) return false;
  assertNoDestructiveAction(decision);

  const state = resolveReviewState(item);

  switch (decision) {
    case REVIEW_DECISIONS.KEEP: {
      if (item.can_keep === false) return false;
      // KEEP restores visibility — only meaningful when something is suppressed
      // or queued for attention.
      return state === 'HIDDEN' || state === 'REPORTED' || state === 'FLAGGED' || state === 'ESCALATED';
    }
    case REVIEW_DECISIONS.HIDE: {
      if (item.can_hide === false) return false;
      // Already hidden — nothing to do.
      return state !== 'HIDDEN';
    }
    case REVIEW_DECISIONS.ESCALATE: {
      if (item.can_escalate === false) return false;
      // Already escalated — avoid duplicate escalations.
      return state !== 'ESCALATED';
    }
    default:
      return false;
  }
}

/** Decisions currently offered for a review, in a stable display order. */
export function availableDecisions(item?: ReviewItem | null): ReviewDecision[] {
  return ALL_REVIEW_DECISIONS.filter((decision) => canApplyDecision(decision, item));
}

/**
 * Decisions that mutate public visibility or route work elsewhere.
 *
 * These require the reason-capturing confirmation dialog so every state change
 * is attributable in the audit log.
 */
export function requiresReason(decision: ReviewDecision): boolean {
  return decision === REVIEW_DECISIONS.HIDE || decision === REVIEW_DECISIONS.ESCALATE;
}

/**
 * Human label + severity for the decision, used by the confirmation dialog.
 * Kept here so wording stays consistent between the queue and detail views.
 */
export function decisionCopy(decision: ReviewDecision): {
  title: string;
  consequence: string;
  dangerous: boolean;
} {
  switch (decision) {
    case REVIEW_DECISIONS.KEEP:
      return {
        title: 'Keep Review Public',
        consequence:
          'This review will remain (or be restored to) public visibility. It stays reversible — you can hide it again later.',
        dangerous: false,
      };
    case REVIEW_DECISIONS.HIDE:
      return {
        title: 'Hide Review',
        consequence:
          'This review will be suppressed from public view. It is NOT deleted and can be restored by choosing Keep later.',
        dangerous: true,
      };
    case REVIEW_DECISIONS.ESCALATE:
      return {
        title: 'Escalate Review',
        consequence:
          'This review will be handed to a senior reviewer / trust & safety queue. Visibility is unchanged until they decide.',
        dangerous: false,
      };
    default:
      return { title: 'Moderate Review', consequence: 'Apply the moderation decision.', dangerous: false };
  }
}