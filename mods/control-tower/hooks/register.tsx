import { atom, read, update } from 'claude-code'
import type { Hook, Register } from 'claude-code'

import type { Activity, Helper, Outside, PrRow, RunRow, Summary, TaskRow } from '../types'

const PANE = 'control-tower'
const TITLE = 'Orion Control Tower'
const TOGGLE_KEYS = 'Ctrl+X then P'
const SCROLL_KEYS = 'Ctrl+X then Tab, then arrows, to scroll'
const DOCK_COLUMNS = 96
const INLINE_ROWS = 60
const POLL_MS = 20_000
const STALE_RUN_MIN = 240
const MS_PER_MIN = 60_000
const PR_LIST_LIMIT = 200
const SUMMARY_DELAY_MS = 100
const ACTIVITY_KEEP = 40
const TASK_KEEP = 30
const TITLE_CHARS = 40
const ACTIVITY_ROWS = 8
const NOT_REPORTED = 'not reported yet'
const NOTHING = 'NOTHING_PENDING'
const SUMMARY_PROMPT = 'Answer in at most two short lines of plain words, no markdown. ' +
  'List only errors that are still unresolved and things the person must still do or answer in this session. ' +
  `If nothing is pending for the person and no work is still running, answer exactly ${NOTHING}.`
const FAILED = ['FAILURE', 'ERROR', 'CANCELLED', 'TIMED_OUT']
const PASSED = ['SUCCESS', 'SKIPPED', 'NEUTRAL']
// dev-next's own default worktree roots, used when the project's CLAUDE.md names none.
const DEFAULT_ROOTS = ['C:/wt', '~/wt']

// The engine handle every hook receives, named once for the helpers below.
type Engine = Parameters<Hook<'session.start'>>[0]
type Part = { text: string; color?: string; bold?: boolean }
type Check = { conclusion?: string; state?: string; status?: string }
type GhPr = {
  number: number; title: string; isDraft: boolean; author?: { login?: string }
  closingIssuesReferences?: { number: number }[]; statusCheckRollup?: Check[]
}
type InFlightEntry = {
  issue: number | null; run: string; startedAt: string
  terminal?: string; step?: string; agents?: { name?: string; status?: string }[]
}
type InFlight = { issues?: InFlightEntry[]; merging?: { issue?: number | null } | null }

const tasks = atom({ plugin: 'control-tower', key: 'tasks' } as const, [] as TaskRow[], { shape: 'tasks-1' })
const outside = atom({ plugin: 'control-tower', key: 'outside' } as const,
  { runs: [], prs: [], checkedAt: 0, note: 'not checked yet' } as Outside, { shape: 'outside-3' })
const summary = atom({ plugin: 'control-tower', key: 'summary' } as const,
  { text: '', isWriting: false } as Summary, { shape: 'summary-1' })
const activities = atom({ plugin: 'control-tower', key: 'activities' } as const, [] as Activity[], { shape: 'activities-1' })
const titles = new Map<number, string>()
// A turn that ends while a summary is being written asks for one more afterwards.
let isSummaryDue = false

const openPane = ($: Engine) => $.ui.open({ id: PANE, title: TITLE, columns: DOCK_COLUMNS, rows: INLINE_ROWS })
const shortRun = (run: string) => `run ${run.split('-').pop()}`
const clockTime = (ms: number) => new Date(ms).toTimeString().slice(0, 5)

const logActivity = async ($: Engine, text: string, pr: number | null = null) => {
  const at = await $.clock.now()
  await update($, activities, l => [...l, { at, text, pr }].slice(-ACTIVITY_KEEP))
}

const checkStatus = (rollup: Check[] | undefined, isDraft: boolean) => {
  const states: string[] = (rollup ?? []).map(c => c.conclusion || c.state || c.status || '')
  const checksTotal = states.length
  const checksDone = states.filter(s => PASSED.includes(s) || FAILED.includes(s)).length
  const counts = { checksDone, checksTotal }
  if (isDraft) return { status: 'draft', tone: 'gray', ...counts }
  if (checksTotal === 0) return { status: 'no checks yet', tone: 'gray', ...counts }
  if (states.some(s => FAILED.includes(s))) return { status: 'checks failing', tone: 'red', ...counts }
  if (checksDone === checksTotal) return { status: 'checks green', tone: 'green', ...counts }
  return { status: `checks running ${checksDone}/${checksTotal}`, tone: 'yellow', ...counts }
}

const namedRoot = async ($: Engine): Promise<string | undefined> => {
  try {
    return /Worktree root[^`]*`([^`]+)`/.exec(await $.fs.read('CLAUDE.md'))?.[1]
  } catch { return undefined }
}

// The in-flight file of the root the project names, else of dev-next's default root.
const inFlightFile = async ($: Engine): Promise<string | undefined> => {
  const home = (await $.env.get('HOME')) ?? (await $.env.get('USERPROFILE')) ?? ''
  const named = await namedRoot($)
  for (const root of named ? [named] : DEFAULT_ROOTS) {
    const file = `${root.replace(/^~(?=\/|$)/, home).replace(/\/$/, '')}/in-flight.json`
    if (await $.fs.exists(file)) return file
  }
  return undefined
}

const issueTitle = async ($: Engine, n: number): Promise<string> => {
  if (titles.has(n)) return titles.get(n)!
  const r = await $.process.run(['gh', 'issue', 'view', String(n), '--json', 'title', '--jq', '.title'])
  const t = r.exitCode === 0 ? r.stdout.trim() : '(title not found)'
  titles.set(n, t)
  return t
}

const refreshOutside = async ($: Engine) => {
  const notes: string[] = []
  const now = await $.clock.now()

  let flight: InFlight = { issues: [], merging: null }
  const file = await inFlightFile($)
  if (!file) notes.push('no in-flight file')
  else {
    try { flight = JSON.parse(await $.fs.read(file)) } catch { notes.push('in-flight file unreadable') }
  }
  const live = (flight.issues ?? []).filter(it => (now - Date.parse(it.startedAt)) / MS_PER_MIN <= STALE_RUN_MIN)
  const runByIssue = new Map<number, InFlightEntry>(
    live.filter(it => it.issue != null).map(it => [it.issue as number, it]))

  let raw: GhPr[] = []
  const pr = await $.process.run(['gh', 'pr', 'list', '--state', 'open', '--limit', String(PR_LIST_LIMIT), '--json',
    'number,title,author,isDraft,closingIssuesReferences,statusCheckRollup'])
  if (pr.exitCode !== 0) notes.push('gh pr list failed')
  else raw = JSON.parse(pr.stdout)

  const prs: PrRow[] = raw.map(p => {
    const issues: number[] = (p.closingIssuesReferences ?? []).map(i => i.number)
    const run = issues.map(i => runByIssue.get(i)).find(Boolean)
    return {
      number: p.number, title: p.title, issues, ...checkStatus(p.statusCheckRollup, p.isDraft),
      agent: run ? (run.terminal ?? shortRun(run.run)) : `no run · ${p.author?.login ?? '?'}`,
    }
  })
  const prByIssue = new Map<number, PrRow>()
  for (const p of prs) for (const i of p.issues) prByIssue.set(i, p)

  const runs: RunRow[] = []
  for (const it of live) {
    const isMerging = flight.merging?.issue != null && flight.merging.issue === it.issue
    const linked = it.issue == null ? undefined : prByIssue.get(it.issue)
    const stage = it.issue == null ? { stage: 'starting, picking an issue', tone: 'gray' }
      : isMerging ? { stage: 'merging', tone: 'magenta' }
      : linked ? { stage: linked.status, tone: linked.tone }
      : { stage: 'building, no pull request yet', tone: 'cyan' }
    const helpers: Helper[] = Array.isArray(it.agents)
      ? it.agents.map(a => ({ name: String(a.name ?? '?'), status: String(a.status ?? '?') })) : []
    runs.push({
      run: shortRun(it.run), terminal: it.terminal ?? NOT_REPORTED, helpers, step: it.step ?? '',
      issue: it.issue, pr: linked?.number ?? null,
      title: it.issue == null ? '' : await issueTitle($, it.issue), ...stage,
    })
  }
  await update($, outside, () => ({ runs, prs, checkedAt: now, note: notes.join('; ') }))
}

// A low-effort answer may decorate the marker ("NOTHING_PENDING."): read it as the marker.
const asSummary = (answer: string) => {
  const text = answer.trim()
  return text.toUpperCase().startsWith(NOTHING) ? NOTHING : text
}

const writeSummary = async ($: Engine): Promise<void> => {
  if ((await read($, summary)).isWriting) {
    isSummaryDue = true
    return
  }
  isSummaryDue = false
  await update($, summary, s => ({ ...s, isWriting: true }))
  try {
    const r = await $.model.fork({ prompt: SUMMARY_PROMPT, effort: 'low' })
    if (r.isAnswered) await update($, summary, s => ({ ...s, text: asSummary(r.text) }))
  } finally {
    await update($, summary, s => ({ ...s, isWriting: false }))
  }
  if (isSummaryDue) await writeSummary($)
}

const isPaneOpen = async ($: Engine) => (await $.ui.panes()).some(p => p.id === PANE)

// The timer only reaches GitHub while the pane is open.
const refreshIfOpen = async ($: Engine) => {
  if (await isPaneOpen($)) await refreshOutside($)
}

// Background work never throws into the engine: a failed refresh is dropped and the next one tries again.
const inBackground = (work: Promise<unknown>) => {
  work.catch(() => undefined)
}

const prNumberIn = (text: string): number | null => {
  const m = /(?:pull\/|gh pr \w+\s+#?)(\d+)/.exec(text)
  return m?.[1] ? Number(m[1]) : null
}

const bashActivity = (command: string): string | undefined => {
  if (/gh pr checks|gh run watch/.test(command)) return 'waiting for CI'
  if (/gh pr merge/.test(command)) return 'merging the pull request'
  if (/gh pr create/.test(command)) return 'opened a pull request'
  if (/git push/.test(command)) return 'pushed the branch, CI starts'
  return undefined
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await $.command.register({ name: 'control-tower', description: `Show or hide ${TITLE} (${TOGGLE_KEYS})` })
    // A reload can cut a summary short: never leave it marked as being written.
    await update($, summary, s => ({ ...s, isWriting: false }))
    $.clock.every(POLL_MS, () => { inBackground(refreshIfOpen($)) })
    return started
  })

  on('command.run', { command: 'control-tower' }, async $ => {
    if (await isPaneOpen($)) {
      await $.ui.close({ id: PANE })
      return { text: `${TITLE} hidden. ${TOGGLE_KEYS} shows it again.` }
    }
    await openPane($)
    inBackground(refreshOutside($))
    return { text: `${TITLE} shown. ${TOGGLE_KEYS} hides it.` }
  })

  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    if (e.agentId === undefined) {
      if (!e.isAborted) $.clock.after(SUMMARY_DELAY_MS, () => { inBackground(writeSummary($)) })
    } else {
      const helper = (await $.agent.list()).find(a => a.id === e.agentId)
      await logActivity($, `helper "${helper?.description ?? e.agentId}" ${e.isAborted ? 'stopped' : 'finished'}`)
    }
    return done
  })

  on('tool.call', { tool: 'Agent' }, async ($, e, next) => {
    const ran = await next(e)
    if (ran.deny === undefined) await logActivity($, `sent helper "${e.description}"`)
    return ran
  })

  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const what = bashActivity(e.command)
    const ran = await next(e)
    if (what && ran.deny === undefined) {
      await logActivity($, ran.isError ? `${what} (failed)` : what,
        prNumberIn(e.command) ?? prNumberIn(JSON.stringify(ran.result ?? '')))
    }
    return ran
  })

  on('tool.call', { tool: 'TaskCreate' }, async ($, e, next) => {
    const ran = await next(e)
    if (ran.deny !== undefined || ran.isError) return ran
    const id = ran.result.task.id
    await update($, tasks, l => [...l, { id, subject: e.subject, status: 'pending' }].slice(-TASK_KEEP))
    return ran
  })

  on('tool.call', { tool: 'TaskUpdate' }, async ($, e, next) => {
    const ran = await next(e)
    if (ran.deny !== undefined || ran.isError || !ran.result.success) return ran
    await update($, tasks, l => l.map(t => t.id === e.taskId
      ? { ...t, subject: e.subject ?? t.subject, status: e.status ?? t.status } : t)
      .filter(t => t.status !== 'deleted'))
    return ran
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const out = await read($, outside)
    const sum = await read($, summary)
    const log = (await read($, activities)).slice(-ACTIVITY_ROWS)
    const agents = await $.agent.list()
    const open = (await read($, tasks)).filter(t => t.status !== 'completed').length
    const busy = agents.filter(a => a.status === 'running' || a.status === 'pending')
    const isIdle = sum.text === NOTHING && busy.length === 0 && open === 0
    const work = [busy.length ? `${busy.length} helper${busy.length > 1 ? 's' : ''} running` : '',
      open ? `${open} task${open > 1 ? 's' : ''} open` : ''].filter(Boolean).join(' · ')
    const prByNumber = new Map(out.prs.map(p => [p.number, p]))
    const row = (parts: Part[]) => (
      <Box flexDirection="row" flexWrap="wrap">
        {parts.filter(p => p.text).map(p => <Text color={p.color} bold={p.bold}>{p.text + ' '}</Text>)}
      </Box>
    )

    return (
      <Box flexDirection="column">
        <Box flexDirection="row" justifyContent="space-between">
          <Text bold>{TITLE}</Text>
          <Box flexDirection="column" alignItems="flex-end">
            <Text color="cyan" bold>{TOGGLE_KEYS} hides</Text>
            <Text dimColor>{SCROLL_KEYS}</Text>
          </Box>
        </Box>
        <Box flexDirection="row">
          <Box flexDirection="column" width="50%" paddingRight={1}>
            <Text bold>This session (TLDR)</Text>
            {sum.text === '' && <Text dimColor>No summary yet; written after each reply.</Text>}
            {isIdle && <Text color="green">Nothing pending. You can close this terminal.</Text>}
            {sum.text !== '' && sum.text !== NOTHING && <Text color="yellow">{sum.text}</Text>}
            {work !== '' && <Text color="cyan">Still working: {work}</Text>}
            {sum.isWriting && <Text dimColor>updating…</Text>}
          </Box>
          <Box flexDirection="column" width="50%">
            <Text bold>Activities and progress</Text>
            {log.length === 0 && busy.length === 0 && <Text dimColor>Nothing yet.</Text>}
            {log.map(a => {
              const p = a.pr == null ? undefined : prByNumber.get(a.pr)
              return row([
                { text: clockTime(a.at), color: 'gray' },
                { text: a.text },
                { text: a.pr == null ? '' : `PR #${a.pr}`, color: 'cyan' },
                { text: p ? `· ${p.status}` : '', color: p?.tone },
              ])
            })}
            {busy.map(a => row([{ text: 'now', color: 'gray' }, { text: `helper "${a.description}" ${a.status}`, color: 'yellow' }]))}
          </Box>
        </Box>
        <Text> </Text>
        <Text bold>dev-next runs on this computer</Text>
        {out.runs.length === 0 && <Text dimColor>None in flight.</Text>}
        {out.runs.map(r => (
          <Box flexDirection="column">
            {row([
              { text: r.issue == null ? '' : `#${r.issue}`, color: 'magenta', bold: true },
              { text: r.title.slice(0, TITLE_CHARS) },
              { text: r.pr == null ? '' : `PR #${r.pr}`, color: 'cyan' },
              { text: `· ${r.stage}`, color: r.tone },
            ])}
            {row([
              { text: '  orchestrator:', color: 'gray' },
              { text: r.terminal, color: r.terminal === NOT_REPORTED ? 'gray' : 'blue', bold: r.terminal !== NOT_REPORTED },
              { text: `(${r.run})`, color: 'gray' },
              { text: r.step ? `· ${r.step}` : '', color: 'cyan' },
            ])}
            {row([
              { text: '  helpers:', color: 'gray' },
              { text: r.helpers.length ? r.helpers.map(h => `${h.name} (${h.status})`).join(', ') : NOT_REPORTED,
                color: r.helpers.length ? 'blue' : 'gray' },
            ])}
          </Box>
        ))}
        <Text> </Text>
        <Text bold>Open pull requests ({out.prs.length})</Text>
        {out.prs.length === 0 && <Text dimColor>None open.</Text>}
        {out.prs.map(p => row([
          { text: `#${p.number}`, color: 'cyan', bold: true },
          { text: p.title.slice(0, TITLE_CHARS) },
          { text: p.issues.length ? `issue ${p.issues.map(i => `#${i}`).join(' ')}` : 'no issue', color: 'magenta' },
          { text: `· ${p.status}`, color: p.tone },
          { text: `· ${p.agent}`, color: 'blue' },
        ]))}
        <Text> </Text>
        <Text dimColor>Runs and pull requests refresh every {POLL_MS / 1000} s{out.note ? ` · ${out.note}` : ''}</Text>
      </Box>
    )
  })
}
