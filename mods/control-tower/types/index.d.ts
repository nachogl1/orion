export type TaskRow = { id: string; subject: string; status: string }
export type Helper = { name: string; status: string }
export type RunRow = {
  run: string; terminal: string; helpers: Helper[]; step: string
  issue: number | null; title: string; pr: number | null; stage: string; tone: string
}
export type PrRow = {
  number: number; title: string; issues: number[]; status: string; tone: string; agent: string
  checksDone: number; checksTotal: number
}
export type Outside = { runs: RunRow[]; prs: PrRow[]; checkedAt: number; note: string }
export type Summary = { text: string; isWriting: boolean }
export type Activity = { at: number; text: string; pr: number | null }

declare module 'claude-code' {
  interface PluginState {
    'control-tower': {
      tasks: Shaped<TaskRow[]>; outside: Shaped<Outside>; summary: Shaped<Summary>; activities: Shaped<Activity[]>
    }
  }
}
