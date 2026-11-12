import { test, expect, type Page } from '@playwright/test';

// Screenshots every page at 375 and 1280 px; fails on any error alert or console error.
const PUBLIC = ['/', '/subscribe?app=1', '/subscribe?app=1&paused=1', '/privacy', '/terms', '/delete-account', '/report-content', '/d', '/p/00000000-0000-0000-0000-000000000000', '/control-7x2k/login'];
const ADMIN = ['/control-7x2k', '/control-7x2k/channels', '/control-7x2k/channels?edit=new', '/control-7x2k/posts', '/control-7x2k/approvals', '/control-7x2k/payments',
  '/control-7x2k/users', '/control-7x2k/requests', '/control-7x2k/plans', '/control-7x2k/meta', '/control-7x2k/admins'];

async function check(page: Page, path: string, name: string) {
  const errors: string[] = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto(path);
  await page.waitForLoadState('networkidle');
  await page.screenshot({ path: `screenshots/${test.info().project.name}/${name}.png`, fullPage: true });
  await expect(page.locator('.error-alert'), `error alert on ${path}`).toHaveCount(0);
  expect(errors, `page errors on ${path}`).toEqual([]);
  // no horizontal scroll on phones
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  if (test.info().project.name === 'mobile' && !path.startsWith('/control-7x2k')) expect(overflow).toBeLessThanOrEqual(1);
}

for (const p of PUBLIC) {
  test(`public ${p}`, async ({ page }) => check(page, p, `public${p.replace(/[^\w]+/g, '_')}`));
}

test.describe('admin', () => {
  test.skip(!process.env.ADMIN_EMAIL, 'ADMIN_EMAIL/ADMIN_PASSWORD not set');
  test.beforeEach(async ({ page }) => {
    await page.goto('/control-7x2k/login');
    await page.getByLabel('Email').fill(process.env.ADMIN_EMAIL!);
    await page.getByLabel('Password').fill(process.env.ADMIN_PASSWORD!);
    await page.getByRole('button', { name: 'Sign in' }).click();
    await page.waitForURL('**/control-7x2k');
  });
  for (const p of ADMIN) {
    test(`admin ${p}`, async ({ page }) => check(page, p, `admin${p.replace(/[^\w]+/g, '_')}`));
  }
});
