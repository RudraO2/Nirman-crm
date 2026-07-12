'use client'

import { createContext, useContext } from 'react'

// Progressive disclosure (ux-progressive-disclosure.md §1) — the one canonical
// tenant_uses_inventory read for the admin app. The server layout calls the RPC
// once per render and provides it here; AppSidebar and TabStrip consume it rather
// than each guessing independently. Default (and read-error fallback) is TRUE —
// fail-open: a transient error must never hide navigation from a tenant that has
// earned it; a new tenant briefly seeing the full group is just today's behavior.
const InventorySignalContext = createContext<boolean>(true)

export function InventorySignalProvider({
  usesInventory,
  children,
}: {
  usesInventory: boolean
  children: React.ReactNode
}) {
  return (
    <InventorySignalContext.Provider value={usesInventory}>
      {children}
    </InventorySignalContext.Provider>
  )
}

/** True once the tenant has ever created a project (one-way, server-truth). */
export function useTenantUsesInventory(): boolean {
  return useContext(InventorySignalContext)
}
