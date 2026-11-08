import { expect, test } from 'claude-code/testing'

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

const RULES = 'Worktree root (outside the project): `<wt-root>`.'
const startedAt = new Date().toISOString()
const IN_FLIGHT = JSON.stringify({
  issues: [{ issue: 7, run: '<repo>-20250101-000000-ab12', startedAt }],
  merging: null,
})
const PULL_REQUESTS = JSON.stringify([
  {
    number: 9, title: 'Add the thing', isDraft: false, author: { login: '<gh-login>' },
    closingIssuesReferences: [{ number: 7 }],
    statusCheckRollup: [{ conclusion: 'SUCCESS' }, { status: 'IN_PROGRESS' }],
  },
])

// The test runner's timer; the mod itself only uses the engine's clock.
declare const setTimeout: (done: () => void, ms: number) => unknown
// The pane refreshes in the background: let that work land before reading it.
const settle = () => new Promise<void>(done => setTimeout(done, 50))

// The person typing /control-tower at the terminal.
const TOGGLE = {
  command: 'control-tower', args: '', origin: { kind: 'composer' },
  presentation: { isFullscreen: true, columns: 200 },
} as const
const NO_USAGE = { input_tokens: 0, output_tokens: 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 }
const shownPane = (id: string) => ({ id, title: 'Orion Control Tower', isShown: true, isFocused: false, isPlaced: true })

const outsideWorld = (on: any) => {
  on('fs.read', (_: unknown, e: { path: string }) =>
    ({ value: e.path.endsWith('in-flight.json') ? IN_FLIGHT : RULES }))
  on('process.run', (_: unknown, e: { argv: string[] }) => ({
    value: {
      exitCode: 0, stderr: '',
      stdout: e.argv.includes('pr') ? PULL_REQUESTS : 'Build the thing',
    },
  }))
  on('agent.list', () => ({ value: [] }))
  on('clock.now', () => ({ value: Date.now() }))
  on('clock.every', () => ({ value: undefined }))
  on('command.register', () => ({ value: { command: 'control-tower' } }))
  on('session.start', (_: unknown, e: { cwd: string }) => ({ cwd: e.cwd }))
}

test('the command shows the pane, then hides it', async ($, on) => {
  outsideWorld(on)
  const opened: string[] = []
  const closed: string[] = []
  let panes: ReturnType<typeof shownPane>[] = []
  on('ui.open', (_, e) => { opened.push(e.id); panes = [shownPane(e.id)]; return { value: { isPlaced: true } } })
  on('ui.close', (_, e) => { closed.push(e.id); panes = []; return { value: undefined } })
  on('ui.panes', () => ({ value: panes }))

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  const shown = await $.command.run(TOGGLE)
  const hidden = await $.command.run(TOGGLE)

  expect(opened).toEqual(['control-tower'])
  expect(closed).toEqual(['control-tower'])
  expect(shown.text).toContain('Ctrl+X then P hides it')
  expect(hidden.text).toContain('Ctrl+X then P shows it again')
})

test('the pane shows the run, its pull request and the checks still running', async ($, on) => {
  outsideWorld(on)
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('ui.panes', () => ({ value: [] }))

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await $.command.run(TOGGLE)
  await settle()
  const ui = await $.ui.mount(PANE)

  expect((await ui.find({ type: 'Text', text: /^Orion Control Tower$/ }))?.text).toBe('Orion Control Tower')
  expect((await ui.find({ type: 'Text', text: /Ctrl\+X then P hides/ }))).toBeTruthy()
  expect((await ui.find({ type: 'Text', text: /Build the thing/ }))).toBeTruthy()
  expect((await ui.findAll({ type: 'Text', text: /checks running 1\/2/ })).length).toBe(2)
  expect((await ui.findAll({ type: 'Text', text: /not reported yet/ })).length).toBe(2)
  await ui.unmount()
})

test('with nothing pending the session says the terminal can be closed', async ($, on) => {
  outsideWorld(on)
  on('clock.after', () => ({ value: undefined }))
  on('model.fork', () => ({ value: { isAnswered: true, text: 'NOTHING_PENDING', usage: NO_USAGE } }))
  on('turn.complete', (_, e) => ({ ...e, text: e.answer }))

  await $.turn.complete({ answer: 'done', text: 'done', durationMs: 1, isAborted: false, turnId: 't1', reason: 'end_turn' } as any)
  await settle()
  const ui = await $.ui.mount(PANE)

  expect((await ui.find({ type: 'Text', text: /You can close this terminal/ }))?.text)
    .toBe('Nothing pending. You can close this terminal.')
  await ui.unmount()
})
