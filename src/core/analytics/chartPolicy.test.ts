import { describe, it, expect } from 'vitest';
import { chartKindFor, SECTION_CHARTS } from './chartPolicy';

/**
 * The DATA VISUALIZATION RULE in enforceable form: every analytics dataset has
 * exactly one decided chart type (or none), and a single-number dataset never
 * becomes a chart.
 */
describe('chart selection policy', () => {
  it('decides a chart kind for every registered analytics dataset', () => {
    const keys = Object.keys(SECTION_CHARTS);
    expect(keys.length).toBeGreaterThan(5);
    keys.forEach((key) => {
      const kind = chartKindFor(key);
      expect(['line', 'area', 'bar', 'donut', null]).toContain(kind);
    });
  });

  it('maps time series to trend charts, not pies', () => {
    // Trends earn line/area; a pie of a time series carries no meaning.
    expect(SECTION_CHARTS['search:volume']).toBe('line');
    expect(SECTION_CHARTS['customers:activity']).toBe('line');
    expect(SECTION_CHARTS['shopkeepers:onboarding']).toBe('area');
    expect(SECTION_CHARTS['notifications:dispatch']).toBe('area');
  });

  it('maps ranked comparisons to bars', () => {
    expect(SECTION_CHARTS['customers:by-city']).toBe('bar');
    expect(SECTION_CHARTS['businesses:by-city']).toBe('bar');
    expect(SECTION_CHARTS['geography:shop-density']).toBe('bar');
  });

  it('reserves donut for genuine composition only', () => {
    // Exactly one composition chart across the platform: category shares.
    const donuts = Object.values(SECTION_CHARTS).filter((k) => k === 'donut');
    expect(donuts).toHaveLength(1);
    expect(SECTION_CHARTS['products:by-category']).toBe('donut');
  });

  it('returns null for a dataset that earns no chart', () => {
    // An unknown key must yield *no* chart, never a default chart — the rule
    // is "charts only where they add meaning", not "chart by default".
    expect(chartKindFor('not-a-real-dataset')).toBeNull();
  });
});
