'use client'

import { OPERATOR_CONTACT } from '@/lib/operator-contact'

/**
 * Story 9.6 — the "account paused → recharge" screen for a tenant admin on web.
 *
 * SECURITY (AC #1): this is only the friendly FACE of a server-enforced lockout.
 * Access is cut in Postgres by the `auth_tenant_id()` chokepoint (0056); this
 * component is rendered by the SERVER layout in place of the app, and even if it
 * were removed client-side, every data RPC still fails-closed on the server.
 * Warm amber, English copy (product decision 2026-07-13). This surface is
 * admin-only, so showing the support number here is intended.
 */
export function PausedRecharge({
  planName,
  daysRemaining,
}: {
  planName: string | null
  daysRemaining: number | null
}) {
  const overdue = daysRemaining != null && daysRemaining < 0
  const windowLine =
    daysRemaining == null
      ? '—'
      : daysRemaining < 0
        ? `Overdue by ${-daysRemaining} ${-daysRemaining === 1 ? 'day' : 'days'}`
        : `${daysRemaining} ${daysRemaining === 1 ? 'day' : 'days'} remaining`

  const wa = `https://wa.me/${OPERATOR_CONTACT.phoneE164}?text=${encodeURIComponent(
    OPERATOR_CONTACT.whatsappMessage,
  )}`
  // tel: needs the leading '+' so the country code (91) isn't read as a local prefix.
  const tel = `tel:+${OPERATOR_CONTACT.phoneE164}`

  return (
    <div className="flex min-h-screen items-center justify-center bg-amber-50 px-6 py-12">
      <div className="w-full max-w-md rounded-2xl border border-amber-200 bg-white p-8 shadow-sm">
        <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-amber-100">
          <svg
            className="h-8 w-8 text-amber-600"
            fill="none"
            viewBox="0 0 24 24"
            strokeWidth={1.6}
            stroke="currentColor"
            aria-hidden="true"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              d="M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 0h10.5a2.25 2.25 0 0 1 2.25 2.25v6A2.25 2.25 0 0 1 17.25 21H6.75A2.25 2.25 0 0 1 4.5 18.75v-6a2.25 2.25 0 0 1 2.25-2.25Z"
            />
          </svg>
        </div>

        <h1 className="mt-5 text-center text-xl font-bold text-neutral-900">
          Your subscription has ended
        </h1>
        <p className="mt-2 text-center text-sm text-neutral-600">
          Access is paused until you recharge. Your data is safe — everything
          resumes exactly where you left off.
        </p>
        <p className="mt-1 text-center text-xs text-neutral-400">
          To renew, please contact {OPERATOR_CONTACT.phoneDisplay}.
        </p>

        <dl className="mt-6 space-y-2 rounded-xl border border-neutral-200 p-4 text-sm">
          <Row k="Plan" v={planName ?? '—'} />
          <Row k="Status" v={overdue ? 'Overdue' : 'Paused'} amber />
          <Row k="Window" v={windowLine} />
        </dl>

        <a
          href={wa}
          target="_blank"
          rel="noopener noreferrer"
          className="mt-6 flex w-full items-center justify-center gap-2 rounded-xl bg-green-600 px-4 py-3 text-sm font-semibold text-white hover:bg-green-700"
        >
          Recharge on WhatsApp
        </a>
        <a
          href={tel}
          className="mt-2.5 flex w-full items-center justify-center gap-2 rounded-xl border border-neutral-300 px-4 py-3 text-sm font-semibold text-neutral-800 hover:bg-neutral-50"
        >
          Call {OPERATOR_CONTACT.phoneDisplay}
        </a>

        <button
          type="button"
          onClick={() => window.location.reload()}
          className="mt-4 w-full text-center text-sm font-semibold text-amber-700 hover:underline"
        >
          I have paid — check again
        </button>
      </div>
    </div>
  )
}

function Row({ k, v, amber }: { k: string; v: string; amber?: boolean }) {
  return (
    <div className="flex items-center justify-between">
      <dt className="text-neutral-500">{k}</dt>
      <dd className={`font-semibold ${amber ? 'text-amber-600' : 'text-neutral-900'}`}>{v}</dd>
    </div>
  )
}
