// Story 8.5 — transactional email helper (Resend HTTP API; free tier).
//
// DORMANT until secrets are set — sendEmail() logs a skip and returns false
// when RESEND_API_KEY is absent, so callers can ship before the provider
// account exists. To activate:
//   supabase secrets set RESEND_API_KEY='re_...' EMAIL_FROM='Nirman CRM <notify@nirman.in>'
// (Resend requires the FROM domain to be verified in their dashboard; until a
// domain is verified, their sandbox sender 'onboarding@resend.dev' works for
// testing to the account-owner address.)
//
// Deliberately minimal: one function, plain-text + optional HTML, no queue —
// call sites must treat email as best-effort (never fail the main operation).

export interface EmailMessage {
  to: string;
  subject: string;
  text: string;
  html?: string;
}

export async function sendEmail(msg: EmailMessage): Promise<boolean> {
  const apiKey = Deno.env.get('RESEND_API_KEY');
  const from = Deno.env.get('EMAIL_FROM') ?? 'Nirman CRM <onboarding@resend.dev>';
  if (!apiKey) {
    console.log(JSON.stringify({
      ts: new Date().toISOString(), level: 'info', event: 'email_skipped_no_provider',
      subject: msg.subject, // never log recipient or body
    }));
    return false;
  }
  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${apiKey}` },
      body: JSON.stringify({
        from,
        to: [msg.to],
        subject: msg.subject,
        text: msg.text,
        ...(msg.html ? { html: msg.html } : {}),
      }),
    });
    if (!res.ok) {
      console.error(JSON.stringify({
        ts: new Date().toISOString(), level: 'error', event: 'email_send_failed',
        status: res.status, subject: msg.subject,
      }));
      return false;
    }
    return true;
  } catch (e) {
    console.error(JSON.stringify({
      ts: new Date().toISOString(), level: 'error', event: 'email_send_failed',
      error: String(e), subject: msg.subject,
    }));
    return false;
  }
}
