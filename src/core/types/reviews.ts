/**
 * REVIEW / MODERATION — Platform-Neutral Review Models
 * ====================================================
 *
 * Covers customer-submitted reviews across any reviewable entity (product,
 * shop, order). Moderation states are deliberately explicit so the UI can
 * always explain *why* a review is in the queue.
 *
 * SAFETY CONTRACT (non-negotiable):
 *   - A review is NEVER permanently deleted from the Admin UI. The strongest
 *     available action is HIDE, which is reversible.
 *   - HIDE and ESCALATE are high-impact and require an operator reason that is
 *     recorded in the audit log.
 *   - The backend remains authoritative: capability flags (`can_*`) returned by
 *     the API gate every control. When a flag is explicitly false the control
 *     is hidden, never silently attempted.
 */

/** What kind of thing was reviewed. Neutral — no vendor/product assumptions. */
export type ReviewEntityType = 'PRODUCT' | 'SHOP' | 'ORDER' | string;

/**
 * Moderation state of a review.
 *
 * VISIBLE  — live on the platform, no outstanding reports.
 * REPORTED — users have reported it; awaiting a moderation decision.
 * FLAGGED  — automatically or manually flagged by the platform; needs review.
 * HIDDEN   — suppressed from public view by a moderator. Reversible.
 * ESCALATED— handed to a senior reviewer / trust & safety queue.
 */
export type ReviewModerationState =
  | 'VISIBLE'
  | 'REPORTED'
  | 'FLAGGED'
  | 'HIDDEN'
  | 'ESCALATED';

/** The moderation actions an operator may take. */
export const REVIEW_DECISIONS = {
  /** Approve / keep the review public. Reverses a previous HIDE. */
  KEEP: 'KEEP',
  /** Suppress from public view. Reversible. */
  HIDE: 'HIDE',
  /** Hand to a senior reviewer. Does not change visibility by itself. */
  ESCALATE: 'ESCALATE',
} as const;

export type ReviewDecision = (typeof REVIEW_DECISIONS)[keyof typeof REVIEW_DECISIONS];

export const ALL_REVIEW_DECISIONS: ReadonlyArray<ReviewDecision> = Object.values(REVIEW_DECISIONS);

/** Why a review entered the moderation queue. */
export interface ReviewReportReason {
  reason: string;
  count?: number | null;
}

export interface ReviewItem {
  id: number;

  /** Reviewed entity — neutral identifiers only. */
  entity_type?: ReviewEntityType | null;
  entity_id?: number | string | null;
  entity_name?: string | null;

  /** Reviewer — surfaced only for moderation triage. */
  reviewer_id?: number | null;
  reviewer_name?: string | null;

  /** Review content. */
  rating?: number | null;
  title?: string | null;
  body?: string | null;

  /** Moderation state + provenance. */
  moderation_state?: ReviewModerationState | string;
  is_hidden?: boolean | null;
  is_flagged?: boolean | null;
  report_count?: number | null;
  report_reasons?: ReviewReportReason[];

  /** Latest moderation decision, for audit context. */
  moderated_by?: string | null;
  moderated_at?: string | null;
  moderation_notes?: string | null;

  created_at?: string;
  updated_at?: string;

  /**
   * Backend-advertised capabilities. A control is only offered when the backend
   * allows it; `false` always wins over any client-side heuristic.
   */
  can_keep?: boolean;
  can_hide?: boolean;
  can_escalate?: boolean;
}

/**
 * There is intentionally no delete capability anywhere in this module.
 * Exposed as a constant so a future change is a deliberate, reviewable edit
 * rather than an accidental addition.
 */
export const REVIEW_DELETE_SUPPORTED = false as const;