import { expect, mock, test } from 'claude-code/testing'

const PANE = {
  plugin: 'control-tower',
  component: 'Pane',
  requestId: 'control-tower',
  surface: 'terminal',
  props: {
    title: 'Orion Control Tower',
    isFocused: false,
    bodyColumns: 96,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 60 },
    view: {},
  },
} as const

const START = Date.parse('2025-01-01T10:00:00Z')
const POLL_MS = 20_000
const SUMMARY_DELAY_MS = 100
const FORK_MS = 1_000
const NAMED_ROOT = 'Worktree root (outside the project): `<wt-root>`.'
const HOME = '<home>'
const IN_FLIGHT = JSON.stringify({
  issues: [{ issue: 7, run: '<repo>-20250101-095000-ab12', startedAt: '2025-01-01T09:50:00Z' }],
  merging: null,
})
const PULL_REQUESTS = JSON.stringify([
  {
    number: 9, title: 'Add the thing', isDraft: false, author: { login: '<gh-login>' },
    closingIssuesReferences: [{ number: 7 }],
    statusCheckRollup: [{ conclusion: 'SUCCESS' }, { status: 'IN_PROGRESS' }],
  },
])

// The person typing /control-tower at the terminal.
const TOGGLE = {
  command: 'control-tower', args: '', origin: { kind: 'composer' },
  presentation: { isFullscreen: true, columns: 200 },
} as const
const NO_USAGE = { input_tokens: 0, output_tokens: 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 }
const shownPane = (id: string) => ({ id, title: 'Orion Control Tower', isShown: true, isFocused: false, isPlaced: true })
const turnEnd = (agentId?: string) =>
  ({ answer: 'done', text: 'done', durationMs: 1, isAborted: false, turnId: 't1', reason: 'end_turn', agentId }) as any
const SESSION = { cwd: '/', surface: 'terminal', isInteractive: true } as const

type World = {
  rules?: string; inFlightAt?: string; summary?: string; forkMs?: number; refused?: string[]
  helpers?: { id: string; description: string }[]
}

// The engine hands file hooks absolute paths with the platform's separators.
const slashed = (path: string) => path.replaceAll('\\', '/')

// Everything outside the mod: the project's rules, the in-flight file, gh, the clock, panes and the model.
// The hooks read `world` when called, so a test may change it between steps.
const outsideWorld = (on: any, world: World = {}) => {
  const clock = mock.clock(on, { now: START })
  mock.env(on, { HOME })
  const forks: string[] = []
  const toggles: string[] = []
  const prLists: number[] = []
  let panes: ReturnType<typeof shownPane>[] = []
  const isInFlight = (path: string) => slashed(path).endsWith(world.inFlightAt ?? '<wt-root>/in-flight.json')
  on('fs.read', (_: unknown, e: { path: string }) =>
    ({ value: isInFlight(e.path) ? IN_FLIGHT : world.rules ?? NAMED_ROOT }))
  on('fs.exists', (_: unknown, e: { path: string }) => ({ value: isInFlight(e.path) }))
  on('process.run', (_: unknown, e: { argv: string[] }) => {
    const isPrList = e.argv.includes('pr')
    if (isPrList) prLists.push(clock.now())
    return { value: { exitCode: 0, stderr: '', stdout: isPrList ? PULL_REQUESTS : 'Build the thing' } }
  })
  on('agent.list', () => ({ value: world.helpers ?? [] }))
  on('command.register', () => ({ value: { command: 'control-tower' } }))
  on('session.start', (_: unknown, e: { cwd: string }) => ({ cwd: e.cwd }))
  on('ui.open', (_: unknown, e: { id: string }) => {
    toggles.push(`open ${e.id}`); panes = [shownPane(e.id)]; return { value: { isPlaced: true } }
  })
  on('ui.close', (_: unknown, e: { id: string }) => { toggles.push(`close ${e.id}`); panes = []; return { value: undefined } })
  on('ui.panes', () => ({ value: panes }))
  on('model.fork', async (_: unknown, e: { prompt: string }) => {
    forks.push(e.prompt)
    if (world.forkMs) await clock.sleep(world.forkMs)
    return { value: { isAnswered: true, text: world.summary ?? 'NOTHING_PENDING', usage: NO_USAGE } }
  })
  on('turn.complete', (_: unknown, e: { answer: string }) => ({ ...e, text: e.answer }))
  on('tool.call', (_: unknown, e: { tool: string }) => {
    if (world.refused?.includes(e.tool)) return { deny: 'refused' }
    if (e.tool === 'TaskCreate') return { result: { task: { id: '1', subject: 'Ship it' } } }
    return { result: e.tool === 'TaskUpdate' ? { success: true } : {} }
  })
  return { clock, forks, toggles, prLists }
}

const texts = async (ui: any, pattern: RegExp): Promise<string[]> =>
  (await ui.findAll({ type: 'Text', text: pattern })).map((t: { text: string }) => t.text)

test('the command shows the pane, then hides it', async ($, on) => {
  const { toggles } = outsideWorld(on)
  await $.session.start(SESSION)

  const shown = await $.command.run(TOGGLE)
  const hidden = await $.command.run(TOGGLE)

  expect(toggles).toEqual(['open control-tower', 'close control-tower'])
  expect(shown.text).toContain('Ctrl+X then P hides it')
  expect(hidden.text).toContain('Ctrl+X then P shows it again')
})

test('GitHub is asked for pull requests only while the pane is open', async ($, on) => {
  const { clock, prLists } = outsideWorld(on)
  await $.session.start(SESSION)

  await clock.advance(POLL_MS * 2)
  const whileHidden = prLists.length
  await $.command.run(TOGGLE)
  await clock.advance(POLL_MS * 2)

  expect(whileHidden).toBe(0)
  expect(prLists.length).toBe(3)
})

test('the pane shows each run with its pull request, wherever the in-flight file lives', async ($, on) => {
  const roots = [
    { rules: NAMED_ROOT, inFlightAt: '<wt-root>/in-flight.json' },
    { rules: 'No worktree root named here.', inFlightAt: `${HOME}/wt/in-flight.json` },
  ]
  const world: World = {}
  const { clock } = outsideWorld(on, world)
  await $.session.start(SESSION)
  for (const root of roots) {
    Object.assign(world, root)
    await $.command.run(TOGGLE)
    await clock.settle()
    const ui = await $.ui.mount(PANE)

    expect(await texts(ui, /^Orion Control Tower$/)).toEqual(['Orion Control Tower'])
    expect((await texts(ui, /Build the thing/)).length).toBe(1)
    expect((await texts(ui, /checks running 1\/2/)).length).toBe(2)
    expect((await texts(ui, /not reported yet/)).length).toBe(2)
    await ui.unmount()
    await $.command.run(TOGGLE)
  }
})

test('after each reply the session says what is pending, or that the terminal can be closed', async ($, on) => {
  const cases = [
    { summary: 'NOTHING_PENDING', shown: 'Nothing pending. You can close this terminal.' },
    { summary: 'NOTHING_PENDING.', shown: 'Nothing pending. You can close this terminal.' },
    { summary: 'Answer the merge question.', shown: 'Answer the merge question.' },
  ]
  const world: World = {}
  const { clock } = outsideWorld(on, world)
  for (const c of cases) {
    world.summary = c.summary
    await $.turn.complete(turnEnd())
    await clock.advance(SUMMARY_DELAY_MS)
    const ui = await $.ui.mount(PANE)

    expect(await texts(ui, /pending|Answer/)).toEqual([c.shown])
    await ui.unmount()
  }
})

test('a reply that ends while a summary is being written gets a summary of its own afterwards', async ($, on) => {
  const { clock, forks } = outsideWorld(on, { forkMs: FORK_MS })

  await $.turn.complete(turnEnd())
  await clock.advance(SUMMARY_DELAY_MS)
  await $.turn.complete(turnEnd())
  await clock.advance(SUMMARY_DELAY_MS)
  await clock.advance(FORK_MS * 2)
  const ui = await $.ui.mount(PANE)

  expect(forks.length).toBe(2)
  expect(await texts(ui, /updating/)).toEqual([])
  await ui.unmount()
})

test('a summary cut short by a reload is not left marked as being written', async ($, on) => {
  const { clock } = outsideWorld(on, { forkMs: FORK_MS })
  await $.turn.complete(turnEnd())
  await clock.advance(SUMMARY_DELAY_MS)
  const ui = await $.ui.mount(PANE)
  const midway = await texts(ui, /updating/)

  await $.session.start(SESSION)

  expect(midway).toEqual(['updating…'])
  expect(await texts(ui, /updating/)).toEqual([])
  await ui.unmount()
})

test("a helper's turn writes no summary and is logged as finished", async ($, on) => {
  const { clock, forks } = outsideWorld(on, { helpers: [{ id: 'h1', description: 'review the change' }] })

  await $.turn.complete(turnEnd('h1'))
  await clock.advance(SUMMARY_DELAY_MS)
  const ui = await $.ui.mount(PANE)

  expect(forks).toEqual([])
  expect((await texts(ui, /helper "review the change" finished/)).length).toBe(1)
  await ui.unmount()
})

test('activities show helpers sent and CI waits with their progress, and open tasks are counted', async ($, on) => {
  const { clock } = outsideWorld(on)
  await $.session.start(SESSION)
  await $.command.run(TOGGLE)

  await $.tool.call({ tool: 'Agent', description: 'review the change', prompt: 'Review it.' } as any)
  await $.tool.call({ tool: 'Bash', command: 'gh pr checks 9 --watch' } as any)
  await $.tool.call({ tool: 'TaskCreate', subject: 'Ship it', description: 'Ship it.' } as any)
  await clock.settle()
  const ui = await $.ui.mount(PANE)

  expect((await texts(ui, /sent helper "review the change"/)).length).toBe(1)
  expect((await texts(ui, /waiting for CI/)).length).toBe(1)
  expect((await texts(ui, /^PR #9 $/)).length).toBeGreaterThan(0)
  expect(await texts(ui, /Still working/)).toEqual(['Still working: 1 task open'])
  await ui.unmount()
})

test('a completed task stops counting, and a refused one never counts', async ($, on) => {
  const world: World = {}
  const { clock } = outsideWorld(on, world)
  const ui = await $.ui.mount(PANE)

  await $.tool.call({ tool: 'TaskCreate', subject: 'Ship it', description: 'Ship it.' } as any)
  await clock.settle()
  const whileOpen = await texts(ui, /Still working/)
  await $.tool.call({ tool: 'TaskUpdate', taskId: '1', status: 'completed' } as any)
  world.refused = ['TaskCreate']
  await $.tool.call({ tool: 'TaskCreate', subject: 'Refused', description: 'Refused.' } as any)
  await clock.settle()

  expect(whileOpen).toEqual(['Still working: 1 task open'])
  expect(await texts(ui, /Still working/)).toEqual([])
  await ui.unmount()
})
