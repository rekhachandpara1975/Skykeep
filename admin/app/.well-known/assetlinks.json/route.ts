import { NextResponse } from 'next/server';
import { DIRECT_PACKAGE, PLAY_PACKAGE } from '@/lib/site';

// Digital Asset Links for both Android packages. Fingerprints come from ANDROID_SIGNING_SHA256 (comma-separated).
export function GET() {
  const fingerprints = (process.env.ANDROID_SIGNING_SHA256 ?? '').split(',').map((s) => s.trim().toUpperCase()).filter(Boolean);
  const body = [DIRECT_PACKAGE, PLAY_PACKAGE].map((package_name) => ({
    relation: ['delegate_permission/common.handle_all_urls'],
    target: { namespace: 'android_app', package_name, sha256_cert_fingerprints: fingerprints },
  }));
  return NextResponse.json(body, { headers: { 'Cache-Control': 'public, max-age=3600' } });
}
