'use client';
import { createBrowserClient } from '@supabase/ssr';

export const supabaseBrowser = () =>
  createBrowserClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!);

/** Upload with progress straight to Supabase Storage (RLS checks the signed-in admin). */
export async function uploadWithProgress(bucket: string, path: string, file: Blob, onProgress: (pct: number) => void, upsert = false) {
  const sb = supabaseBrowser();
  const { data: { session } } = await sb.auth.getSession();
  if (!session) throw new Error('Session expired, log in again');
  const url = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/${bucket}/${path.split('/').map(encodeURIComponent).join('/')}`;
  await new Promise<void>((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open('POST', url);
    xhr.setRequestHeader('Authorization', `Bearer ${session.access_token}`);
    xhr.setRequestHeader('apikey', process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!);
    xhr.setRequestHeader('x-upsert', String(upsert));
    if (file.type) xhr.setRequestHeader('Content-Type', file.type);
    xhr.upload.onprogress = (e) => e.lengthComputable && onProgress(Math.round((e.loaded / e.total) * 100));
    xhr.onload = () => (xhr.status < 300 ? resolve() : reject(new Error(xhr.responseText || `Upload failed (${xhr.status})`)));
    xhr.onerror = () => reject(new Error('Network error during upload'));
    xhr.send(file);
  });
  return path;
}

/** Grab a frame ~1s into a video as a JPEG thumbnail. */
export function videoThumbnail(file: File): Promise<Blob | null> {
  return new Promise((resolve) => {
    if (!file.type.startsWith('video/')) return resolve(null);
    const v = document.createElement('video');
    v.preload = 'metadata'; v.muted = true; v.src = URL.createObjectURL(file);
    v.onloadedmetadata = () => { v.currentTime = Math.min(1, (v.duration || 2) / 2); };
    v.onseeked = () => {
      const c = document.createElement('canvas');
      c.width = Math.min(640, v.videoWidth); c.height = Math.round((c.width / v.videoWidth) * v.videoHeight);
      c.getContext('2d')!.drawImage(v, 0, 0, c.width, c.height);
      c.toBlob((b) => { URL.revokeObjectURL(v.src); resolve(b); }, 'image/jpeg', 0.8);
    };
    v.onerror = () => resolve(null);
  });
}

export function videoDuration(file: File): Promise<number | null> {
  return new Promise((resolve) => {
    if (!file.type.startsWith('video/')) return resolve(null);
    const v = document.createElement('video');
    v.preload = 'metadata'; v.src = URL.createObjectURL(file);
    v.onloadedmetadata = () => { URL.revokeObjectURL(v.src); resolve(Math.round(v.duration)); };
    v.onerror = () => resolve(null);
  });
}
