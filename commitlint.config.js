/**
 * Conventional Commits rules.
 *
 * Commit messages are the only documentation a solo project keeps
 * automatically. `git log` is how "when did this break, and what touched
 * it" gets answered months later, and that answer is only possible if every
 * message says what kind of change it was. It also lets release-drafter
 * group a release and decide the next version number without being told.
 *
 * Format: <type>(optional scope): <description>
 *   fix    -> patch release    (a defect is fixed)
 *   feat   -> minor release    (capability added)
 *   ! / BREAKING CHANGE -> major release
 *   Other types carry no version meaning but still keep the log sortable.
 *
 * Enforced in CI rather than by a pre-commit hook: hooks get bypassed under
 * time pressure, and a bypassed hook teaches you to ignore it. A red CI run
 * is at least recorded.
 */
module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    // "subject" at the start of the message.
    'subject-case': [0],
    // The admin UI has many similarly named pages; a scope keeps
    // `fix(customers):` from looking identical to `fix(pos):`.
    'scope-enum': [
      0,
      'auth',
      'admin',
      'customers',
      'shops',
      'products',
      'pricing',
      'inventory',
      'imports',
      'pos',
      'notifications',
      'subscriptions',
      'search',
      'analytics',
      'verification',
      'audit',
      'system',
      'api',
      'components',
      'permissions',
      'routes',
      'realtime',
      'theme',
      'types',
      'docs',
      'deps',
    ],
    // A body or footer is optional, but if one is present it must be
    // separated by a blank line — otherwise tooling misreads it.
    'body-leading-blank': [1, 'always'],
    'footer-leading-blank': [1, 'always'],
    // No more than one ! marker.
    'header-max-length': [2, 'always', 100],
  },
};