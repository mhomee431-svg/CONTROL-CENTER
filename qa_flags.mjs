export default async function run(page, ui) {
  // Log in.
  await page.locator('#username').fill('admin');
  await page.locator('#password').fill('admin123');
  await page.getByRole('button', { name: 'Sign In to Control Center' }).click();
  await page.waitForURL((u) => !u.pathname.includes('/login'), { timeout: 60000 });

  // Feature flags — wait for the grid to actually contain a row.
  await page.goto(new URL('/system/flags', page.url()).toString());
  await page
    .waitForFunction(() => document.body.innerText.includes('BARCODE_SEARCH'), { timeout: 30000 })
    .catch(() => { });
  const flags = await ui.snapshot({ full: true });

  // Audit log — wait for a table/heading to settle.
  await page.goto(new URL('/audit', page.url()).toString());
  await page
    .waitForFunction(() => document.body.innerText.includes('Audit Log Center'), { timeout: 30000 })
    .catch(() => { });
  const audit = await ui.snapshot({ full: true });

  return {
    flags_hasBarcodeSearch: flags.includes('BARCODE_SEARCH'),
    flags_hasEnvironment: flags.includes('Environment') || flags.includes('PRODUCTION'),
    flags_hasChangedBy: flags.includes('Changed By'),
    flags_hasLastChanged: flags.includes('Last Changed'),
    audit_hasReason: audit.includes('Reason'),
    audit_hasSeverity: audit.includes('Severity'),
    audit_hasResult: audit.includes('Result'),
    audit_hasCorrelation: audit.includes('Correlation'),
  };
}
