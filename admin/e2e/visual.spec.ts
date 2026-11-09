import { test, expect, type Page } from '@playwright/test';

// Screenshots every page at 375 and 1280 px; fails on any error alert or console error.
const PUBLIC = ['/', '/subscribe?app=1', '/subscribe?app=1&paused=1', '/privacy', '/terms', '/delete-account', '/report-content', '/d', '/p/00000000-0000-0000-0000-000000000000', '/admin/login'];
const ADMIN = ['/admin', '/admin/channels', '/admin/channels?edit=new', '/admin/posts', '/admin/approvals', '/admin/payments',
  '/admin/users', '/admin/requests', '/admin/plans', '/admin/play', '/admin/meta', '/admin/admins'];

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
  if (test.info().project.name === 'mobile' && !path.startsWith('/admin')) expect(overflow).toBeLessThanOrEqual(1);
}

for (const p of PUBLIC) {
  test(`public ${p}`, async ({ page }) => check(page, p, `public${p.replace(/[^\w]+/g, '_')}`));
}

test.describe('admin', () => {
  test.skip(!process.env.ADMIN_EMAIL, 'ADMIN_EMAIL/ADMIN_PASSWORD not set');
  test.beforeEach(async ({ page }) => {
    await page.goto('/admin/login');
    await page.getByLabel('Email').fill(process.env.ADMIN_EMAIL!);
    await page.getByLabel('Password').fill(process.env.ADMIN_PASSWORD!);
    await page.getByRole('button', { name: 'Sign in' }).click();
    await page.waitForURL('**/admin');
  });
  for (const p of ADMIN) {
    test(`admin ${p}`, async ({ page }) => check(page, p, `admin${p.replace(/[^\w]+/g, '_')}`));
  }
});
