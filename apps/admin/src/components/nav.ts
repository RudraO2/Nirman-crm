import {
  House,
  Users,
  ChartColumn,
  UsersRound,
  Building2,
  Download,
  type LucideIcon,
} from 'lucide-react'

// §2 — the 6 sidebar destinations. Each group is a set of EXISTING routes
// surfaced as a tab strip; no routes are merged. Sidebar links to the first
// route of each group and highlights when the current path is any group route.

export interface NavTab {
  label: string
  href: string // may include a query string (e.g. /leads?archived=1)
}

export interface NavGroup {
  key: string
  label: string
  hint: string // small "what lives inside" line under the nav label
  icon: LucideIcon
  href: string // sidebar destination = first tab's pathname
  match: string[] // pathnames that light this group active
  tabs: NavTab[]
}

export const NAV_GROUPS: NavGroup[] = [
  {
    key: 'home',
    label: 'Home',
    hint: 'today · activity',
    icon: House,
    href: '/',
    match: ['/', '/activity'],
    tabs: [
      { label: 'Home', href: '/' },
      { label: 'Activity', href: '/activity' },
    ],
  },
  {
    key: 'leads',
    label: 'Leads',
    hint: 'active · future · archived',
    icon: Users,
    href: '/leads',
    match: ['/leads', '/future-pool'],
    tabs: [
      { label: 'Active', href: '/leads' },
      { label: 'Future pool', href: '/future-pool' },
      { label: 'Archived', href: '/leads?archived=1' },
    ],
  },
  {
    key: 'insights',
    label: 'Insights',
    hint: 'funnel · performance',
    icon: ChartColumn,
    href: '/funnel',
    match: ['/funnel', '/performance'],
    tabs: [
      { label: 'Funnel', href: '/funnel' },
      { label: 'Performance', href: '/performance' },
    ],
  },
  {
    key: 'team',
    label: 'Team',
    hint: 'accounts · hierarchy · templates',
    icon: UsersRound,
    href: '/team',
    match: ['/team', '/hierarchy', '/templates'],
    tabs: [
      { label: 'Accounts', href: '/team' },
      { label: 'Hierarchy', href: '/hierarchy' },
      { label: 'Templates', href: '/templates' },
    ],
  },
  {
    key: 'inventory',
    label: 'Inventory',
    hint: 'units · holds · updates',
    icon: Building2,
    href: '/inventory',
    match: ['/inventory', '/holds', '/amendments', '/developer-updates', '/projects'],
    tabs: [
      { label: 'Units', href: '/inventory' },
      { label: 'Holds', href: '/holds' },
      { label: 'Amendments', href: '/amendments' },
      { label: 'Updates', href: '/developer-updates' },
      { label: 'Projects', href: '/projects' },
    ],
  },
  {
    key: 'data',
    label: 'Data',
    hint: 'import · export',
    icon: Download,
    href: '/import',
    match: ['/import', '/export'],
    tabs: [
      { label: 'Import', href: '/import' },
      { label: 'Export', href: '/export' },
    ],
  },
]

/** A group is active when the current pathname is one of its routes (or a subroute). */
export function groupIsActive(group: NavGroup, pathname: string): boolean {
  return group.match.some((base) =>
    base === '/' ? pathname === '/' : pathname === base || pathname.startsWith(base + '/'),
  )
}

/** The group that owns the current pathname (for auto-deriving the tab strip). */
export function activeGroup(pathname: string): NavGroup | undefined {
  return NAV_GROUPS.find((g) => groupIsActive(g, pathname))
}

/** Whether a given tab is the current one, disambiguating query-param tabs. */
export function tabIsActive(
  tab: NavTab,
  pathname: string,
  archived: boolean,
): boolean {
  const [tabPath, tabQuery] = tab.href.split('?')
  const pathMatches = pathname === tabPath || pathname.startsWith(tabPath + '/')
  if (!pathMatches) return false
  // Only /leads is split by the ?archived flag (Active vs Archived tabs).
  if (tabPath === '/leads') {
    const tabWantsArchived = !!tabQuery && tabQuery.includes('archived')
    return tabWantsArchived ? archived : !archived
  }
  return true
}
