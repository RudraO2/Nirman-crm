// Shared FCM HTTP v1 API helper for Supabase Edge Functions.
// Requires env var FCM_SERVICE_ACCOUNT = JSON string of Firebase service account key.
// Run: supabase secrets set FCM_SERVICE_ACCOUNT='{"type":"service_account",...}'

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

interface FcmMessage {
  token: string;
  title: string;
  body: string;
  data?: Record<string, string>;
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '');
  const binary = atob(base64);
  const buf = new ArrayBuffer(binary.length);
  const view = new Uint8Array(buf);
  for (let i = 0; i < binary.length; i++) view[i] = binary.charCodeAt(i);
  return buf;
}

function uint8ToBase64Url(bytes: Uint8Array): string {
  let s = '';
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

function jsonToBase64Url(obj: unknown): string {
  return btoa(JSON.stringify(obj)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

async function signedJwt(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = jsonToBase64Url({ alg: 'RS256', typ: 'JWT' });
  const payload = jsonToBase64Url({
    iss: sa.client_email,
    sub: sa.client_email,
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
  });
  const sigInput = `${header}.${payload}`;
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(sigInput),
  );
  return `${sigInput}.${uint8ToBase64Url(new Uint8Array(sig))}`;
}

let _cachedToken: { value: string; expiresAt: number } | null = null;

async function getAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Date.now();
  if (_cachedToken && _cachedToken.expiresAt > now + 60_000) return _cachedToken.value;

  const jwt = await signedJwt(sa);
  const resp = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  if (!resp.ok) throw new Error(`OAuth token error: ${await resp.text()}`);
  const json = await resp.json() as { access_token: string; expires_in: number };
  _cachedToken = { value: json.access_token, expiresAt: now + json.expires_in * 1000 };
  return _cachedToken.value;
}

export async function sendFcmNotification(msg: FcmMessage): Promise<boolean> {
  const saJson = Deno.env.get('FCM_SERVICE_ACCOUNT');
  if (!saJson) throw new Error('FCM_SERVICE_ACCOUNT env var not set');
  const sa = JSON.parse(saJson) as ServiceAccount;
  const accessToken = await getAccessToken(sa);

  const resp = await fetch(
    `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({
        message: {
          token: msg.token,
          notification: { title: msg.title, body: msg.body },
          data: msg.data ?? {},
          android: { priority: 'HIGH' },
          apns: { headers: { 'apns-priority': '10' } },
        },
      }),
    },
  );
  if (resp.status === 404) return false; // token unregistered — caller should clean up
  if (!resp.ok) {
    console.error('FCM send error:', await resp.text());
    return false;
  }
  return true;
}
