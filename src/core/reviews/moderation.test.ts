import { describe, it, expect } from 'vitest';
import {
  assertNoDestructiveAction,
  availableDecisions,
  canApplyDecision,
  decisionCopy,
  displayRating,
  isEscalated,
  isFlagged,
  isHidden,
  isReported,
  needsModeration,
  normalizeReviewState,
  reportCount,
  requiresReason,
  resolveReviewState,
} from './moderation';
import { REVIEW_DECISIONS, ReviewItem, REVIEW_DELETE_SUPPORTED } from '../types/reviews';

const review = (over: Partial<ReviewItem> = {}): ReviewItem => ({ id: 1, ...over });

describe('Moderation state resolution', () => {
  it('normalizes known states case-insensitively', () => {
    expect(normalizeReviewState('reported')).toBe('REPORTED');
    expect(normalizeReviewState('HIDDEN')).toBe('HIDDEN');
    expect(normalizeReviewState('Escalated')).toBe('ESCALATED');
    expect(normalizeReviewState('nonsense')).toBe('UNKNOWN');
    expect(normalizeReviewState(null)).toBe('UNKNOWN');
  });

  it('prefers the explicit moderation_state', () => {
    expect(resolveReviewState(review({ moderation_state: 'HIDDEN', is_flagged: true }))).toBe('HIDDEN');
  });

  it('falls back to flags when moderation_state is absent', () => {
    expect(resolveReviewState(review({ is_hidden: true }))).toBe('HIDDEN');
    expect(resolveReviewState(review({ is_flagged: true }))).toBe('FLAGGED');
    expect(resolveReviewState(review({ report_count: 3 }))).toBe('REPORTED');
    expect(resolveReviewState(review({}))).toBe('VISIBLE');
  });

  it('classifies each state', () => {
    expect(isHidden(review({ moderation_state: 'HIDDEN' }))).toBe(true);
    expect(isReported(review({ report_count: 2 }))).toBe(true);
    expect(isFlagged(review({ moderation_state: 'FLAGGED' }))).toBe(true);
    expect(isEscalated(review({ moderation_state: 'ESCALATED' }))).toBe(true);
  });

  it('flags reviews still needing attention', () => {
    expect(needsModeration(review({ moderation_state: 'REPORTED' }))).toBe(true);
    expect(needsModeration(review({ moderation_state: 'FLAGGED' }))).toBe(true);
    expect(needsModeration(review({ moderation_state: 'VISIBLE' }))).toBe(false);
    expect(needsModeration(review({ moderation_state: 'HIDDEN' }))).toBe(false);
  });

  it('counts reports defensively', () => {
    expect(reportCount(review({ report_count: 4 }))).toBe(4);
    expect(reportCount(review({ report_count: 0 }))).toBe(0);
    expect(reportCount(review({ report_count: -2 }))).toBe(0);
    expect(reportCount(null)).toBe(0);
  });

  it('clamps ratings to the 1-5 range', () => {
    expect(displayRating(review({ rating: 4 }))).toBe(4);
    expect(displayRating(review({ rating: 0 }))).toBeNull();
    expect(displayRating(review({ rating: 6 }))).toBeNull();
    expect(displayRating(review({}))).toBeNull();
  });
});

describe('Permanent deletion is never permitted', () => {
  it('declares delete as unsupported', () => {
    expect(REVIEW_DELETE_SUPPORTED).toBe(false);
  });

  it('throws on any destructive action name', () => {
    ['DELETE', 'delete', 'PURGE_REVIEW', 'destroy', 'REMOVE', 'erase'].forEach((action) => {
      expect(() => assertNoDestructiveAction(action)).toThrow();
    });
  });

  it('allows the three supported decisions', () => {
    expect(() => assertNoDestructiveAction('KEEP')).not.toThrow();
    expect(() => assertNoDestructiveAction('HIDE')).not.toThrow();
    expect(() => assertNoDestructiveAction('ESCALATE')).not.toThrow();
  });

  it('guards the decision gate itself', () => {
    expect(() => canApplyDecision('DELETE' as never, review())).toThrow();
  });

  it('offers only reversible decisions for any state', () => {
    const states = ['VISIBLE', 'REPORTED', 'FLAGGED', 'HIDDEN', 'ESCALATED'];
    states.forEach((state) => {
      availableDecisions(review({ moderation_state: state })).forEach((decision) => {
        expect(['KEEP', 'HIDE', 'ESCALATE']).toContain(decision);
      });
    });
  });
});

describe('Decision gating', () => {
  it('offers HIDE for anything not already hidden', () => {
    expect(canApplyDecision(REVIEW_DECISIONS.HIDE, review({ moderation_state: 'VISIBLE' }))).toBe(true);
    expect(canApplyDecision(REVIEW_DECISIONS.HIDE, review({ moderation_state: 'REPORTED' }))).toBe(true);
    expect(canApplyDecision(REVIEW_DECISIONS.HIDE, review({ moderation_state: 'HIDDEN' }))).toBe(false);
  });

  it('offers KEEP only when something is suppressed or queued', () => {
    expect(canApplyDecision(REVIEW_DECISIONS.KEEP, review({ moderation_state: 'HIDDEN' }))).toBe(true);
    expect(canApplyDecision(REVIEW_DECISIONS.KEEP, review({ moderation_state: 'REPORTED' }))).toBe(true);
    expect(canApplyDecision(REVIEW_DECISIONS.KEEP, review({ moderation_state: 'VISIBLE' }))).toBe(false);
  });

  it('offers ESCALATE unless already escalated', () => {
    expect(canApplyDecision(REVIEW_DECISIONS.ESCALATE, review({ moderation_state: 'REPORTED' }))).toBe(true);
    expect(canApplyDecision(REVIEW_DECISIONS.ESCALATE, review({ moderation_state: 'ESCALATED' }))).toBe(false);
  });

  it('honours an explicit backend denial over any state heuristic', () => {
    const item = review({ moderation_state: 'REPORTED', can_hide: false, can_keep: false, can_escalate: false });
    expect(canApplyDecision(REVIEW_DECISIONS.HIDE, item)).toBe(false);
    expect(canApplyDecision(REVIEW_DECISIONS.KEEP, item)).toBe(false);
    expect(canApplyDecision(REVIEW_DECISIONS.ESCALATE, item)).toBe(false);
    expect(availableDecisions(item)).toEqual([]);
  });

  it('returns nothing for a missing review', () => {
    expect(availableDecisions(null)).toEqual([]);
    expect(canApplyDecision(REVIEW_DECISIONS.HIDE, null)).toBe(false);
  });
});

describe('Reason capture and copy', () => {
  it('requires a reason for visibility-changing decisions only', () => {
    expect(requiresReason(REVIEW_DECISIONS.HIDE)).toBe(true);
    expect(requiresReason(REVIEW_DECISIONS.ESCALATE)).toBe(true);
    expect(requiresReason(REVIEW_DECISIONS.KEEP)).toBe(false);
  });

  it('describes HIDE as reversible and never as deletion', () => {
    const copy = decisionCopy(REVIEW_DECISIONS.HIDE);
    expect(copy.dangerous).toBe(true);
    expect(copy.consequence.toLowerCase()).toContain('not deleted');
  });

  it('provides copy for every decision', () => {
    Object.values(REVIEW_DECISIONS).forEach((decision) => {
      const copy = decisionCopy(decision);
      expect(copy.title.length).toBeGreaterThan(0);
      expect(copy.consequence.length).toBeGreaterThan(0);
    });
  });
});
