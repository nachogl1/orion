// TEMPLATE — per-issue Workflow for /fable-sequential-gh-orion-v1.
// The ORCHESTRATOR adapts this per issue: substitute <N>, <slug>, paths, branch names, and
// inline the prompt files' contents (prompts/ are not readable from inside the workflow
// sandbox — bake them into the agent prompts). Pass run-specific values via `args`:
//   { issue: <N>, worktree: "...", batchBranch: "...", sessionFolder: "...", specPrompt: "...",
//     implementerPrompt: "...", reviewerPrompt: "...", standards: "..." }
// Models below mirror the family default (spec/review strong, implement/fix mechanical);
// omit `model` to inherit the session model if the user prefers.

export const meta = {
  name: 'fable-per-issue-pipeline',
  description: 'Spec -> implement -> adversarial review panel -> fix -> finalize for one issue',
  phases: [
    { title: 'Spec', detail: 'ground the issue, post spec comment' },
    { title: 'Implement', detail: 'build to spec in the worktree' },
    { title: 'Review', detail: '3 parallel adversarial lenses + fix agent' },
    { title: 'Finalize', detail: 'audit, commit, push, open PR' },
  ],
}

const SPEC_SCHEMA = {
  type: 'object',
  properties: {
    status: { type: 'string', enum: ['done', 'noop', 'blocked'] },
    specCommentUrl: { type: 'string' },
    expectedDiff: { type: 'string' },
    riskFlags: { type: 'array', items: { type: 'string' } },
    groundingCorrections: { type: 'array', items: { type: 'object' } },
    edgeCases: { type: 'array', items: { type: 'string' } },
    carryForwardGaps: { type: 'array', items: { type: 'string' } },
    evidence: { type: 'string' },
  },
  required: ['status'],
}

const IMPL_SCHEMA = {
  type: 'object',
  properties: {
    status: { type: 'string', enum: ['done', 'failed'] },
    filesChanged: { type: 'array', items: { type: 'string' } },
    testsAdded: { type: 'array', items: { type: 'string' } },
    acStatus: { type: 'array', items: { type: 'object' } },
    deferralCandidates: { type: 'array', items: { type: 'object' } },
    newMarkers: { type: 'array', items: { type: 'object' } },
    skippedChecks: { type: 'array', items: { type: 'object' } },
    diagnosis: { type: 'string' },
  },
  required: ['status'],
}

const REVIEW_SCHEMA = {
  type: 'object',
  properties: {
    lens: { type: 'string' },
    findings: { type: 'array', items: { type: 'object' } },
    newMarkers: { type: 'array', items: { type: 'object' } },
    verdict: { type: 'string', enum: ['clean', 'findings'] },
  },
  required: ['lens', 'findings', 'verdict'],
}

const FIX_SCHEMA = {
  type: 'object',
  properties: {
    status: { type: 'string', enum: ['done', 'failed'] },
    applied: { type: 'array', items: { type: 'object' } },
    deferred: { type: 'array', items: { type: 'object' } },
    diagnosis: { type: 'string' },
  },
  required: ['status'],
}

const FINAL_SCHEMA = {
  type: 'object',
  properties: {
    status: { type: 'string', enum: ['pr-opened', 'failed'] },
    prNumber: { type: 'number' },
    prUrl: { type: 'string' },
    diffStats: { type: 'object' },
    deferralsInBody: { type: 'array', items: { type: 'string' } },
    diagnosis: { type: 'string' },
  },
  required: ['status'],
}

// One bounded retry per stage; a second failure ends the issue as 'failed' for the
// orchestrator to park. The script NEVER asks the user anything.
async function tryTwice(label, phaseName, prompt, schema, model) {
  const opts = { label, phase: phaseName, schema }
  if (model) opts.model = model
  let r = await agent(prompt, opts)
  if (r && r.status !== 'failed') return r
  log(`${label}: first attempt failed — one retry with the failure context`)
  const retryPrompt = prompt + '\n\nPREVIOUS ATTEMPT FAILED: ' +
    JSON.stringify(r && r.diagnosis ? r.diagnosis : 'agent crashed / returned null') +
    '\nDiagnose what went wrong first, then complete the job.'
  r = await agent(retryPrompt, { ...opts, label: label + ':retry' })
  return r
}

phase('Spec')
const spec = await tryTwice(`spec:#${args.issue}`, 'Spec',
  args.standards + '\n\n' + args.specPrompt, SPEC_SCHEMA, 'opus')
if (!spec || spec.status === 'blocked') {
  return { issue: args.issue, outcome: 'failed', stage: 'spec',
    diagnosis: spec ? ('blocked on a human decision: ' + (spec.evidence || '')) : 'spec agent failed twice' }
}
if (spec.status === 'noop') {
  return { issue: args.issue, outcome: 'noop', evidence: spec.evidence, spec }
}

phase('Implement')
const impl = await tryTwice(`implement:#${args.issue}`, 'Implement',
  args.standards + '\n\n' + args.implementerPrompt +
  '\n\nSPEC (authoritative): ' + JSON.stringify(spec), IMPL_SCHEMA, 'sonnet')
if (!impl || impl.status === 'failed') {
  return { issue: args.issue, outcome: 'failed', stage: 'implement',
    diagnosis: impl ? impl.diagnosis : 'implementer failed twice', spec }
}

phase('Review')
const LENSES = ['correctness', 'security-and-edge-cases', 'conventions-and-tests']
const reviews = (await parallel(LENSES.map(lens => () =>
  agent(args.standards + '\n\n' + args.reviewerPrompt.replaceAll('<LENS>', lens) +
        '\n\nSPEC: ' + JSON.stringify(spec) + '\nIMPLEMENTER HANDOFF: ' + JSON.stringify(impl),
        { label: `review:${lens}:#${args.issue}`, phase: 'Review', schema: REVIEW_SCHEMA, model: 'opus' })
))).filter(Boolean)
// Barrier is correct here: the fix agent needs ALL findings together to dedupe and order them.
const allFindings = reviews.flatMap(r => r.findings)
let fix = { status: 'done', applied: [], deferred: [] }
if (allFindings.length > 0) {
  fix = await tryTwice(`fix:#${args.issue}`, 'Review',
    args.standards + `\n\nYou are the FIX AGENT for issue #${args.issue} in the worktree ${args.worktree}. ` +
    'Apply EVERY confirmed finding below. For each: fix it if the cheap-and-safe test passes; ' +
    'otherwise record it as deferred naming the single failing criterion. Dedupe overlapping ' +
    'findings across lenses. Re-run targeted tests after fixing; full compile before returning. ' +
    'Findings: ' + JSON.stringify(allFindings), FIX_SCHEMA, 'sonnet')
  if (!fix || fix.status === 'failed') {
    return { issue: args.issue, outcome: 'failed', stage: 'fix',
      diagnosis: fix ? fix.diagnosis : 'fix agent failed twice', spec, impl, reviews }
  }
}

phase('Finalize')
const fin = await tryTwice(`finalize:#${args.issue}`, 'Finalize',
  args.standards + `\n\nYou are the FINALIZE AGENT for issue #${args.issue} in ${args.worktree}. Steps: ` +
  '(1) Auto-close-keyword audit: grep every unmerged commit message AND your draft PR body with ' +
  "grep -iE '\\b(close[sd]?|fix(es|ed)?|resolve[sd]?)\\s+#[0-9]+' (never grep -P on Windows " +
  'Git-Bash) and rewrite any leak to Refs #N. (2) Precise staging of exactly the intended files; ' +
  'ONE Conventional-Commits commit. (3) git push -u. (4) Open the PR feature-branch -> ' + args.batchBranch +
  ' with Refs #' + args.issue + ' and a structured body: spec comment link; review findings ' +
  'disposition (applied vs deferred-with-#N); "## Out of scope / Follow-ups (tracked)" where ' +
  'EVERY line ends with a #N; new TODO/FIXME markers (file:line). (5) Return the PR number and ' +
  'diff stats (files, additions, deletions, touchesMigrations/sharedContracts/publicApi/auth booleans). ' +
  'STOP at PR-open — the orchestrator owns CI and merge. Context: ' +
  JSON.stringify({ impl: impl, deferred: fix.deferred }), FINAL_SCHEMA, 'sonnet')
if (!fin || fin.status === 'failed') {
  return { issue: args.issue, outcome: 'failed', stage: 'finalize',
    diagnosis: fin ? fin.diagnosis : 'finalize agent failed twice', spec, impl, reviews, fix }
}

return {
  issue: args.issue, outcome: 'pr-opened', pr: fin.prNumber, prUrl: fin.prUrl,
  diffStats: fin.diffStats, spec, impl,
  reviewSummary: reviews.map(r => ({ lens: r.lens, count: r.findings.length, verdict: r.verdict })),
  deferred: fix.deferred, newMarkers: [...(impl.newMarkers || []), ...reviews.flatMap(r => r.newMarkers || [])],
}
