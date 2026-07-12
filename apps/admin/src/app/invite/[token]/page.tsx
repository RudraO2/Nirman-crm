import { AcceptInviteForm } from './accept-invite-form'

// Story 8.4 — public invite-acceptance page (whitelisted in proxy.ts).
// The token stays in the URL only; the form posts it to the accept-invite
// edge fn, which validates + burns it server-side.
export default async function InvitePage({
  params,
}: {
  params: Promise<{ token: string }>
}) {
  const { token } = await params
  return <AcceptInviteForm token={token} />
}
