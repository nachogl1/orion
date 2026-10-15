<p align="center">
  <img src="assets/orion-twinkle.gif" alt="orion — a repo-level utility framework for Claude Code projects" width="520"/>
</p>

# orion

> [!CAUTION]
> orion tells an AI assistant how to work in your project, and the assistant will run commands and edit files on your machine. Review what you install, keep your work saved, and use it at your own risk. It is under constant improvement and is provided as-is.

**orion is a framework you install into your own project** to help you build software better and faster with [Claude Code](https://claude.com/claude-code), Anthropic's AI coding assistant.

Once installed, it lives inside the project itself, so there is nothing for teammates to set up: whoever clones the project gets orion with it, and improvements arrive with a normal update.

## What you get

- **Skills** – ready-made abilities for the everyday tasks of a software project, which the assistant can run on request.
- **Working rules** – a set of mandatory good practices your project's own instructions file (`CLAUDE.md`) imports, so the assistant works the same careful way for everyone on the team. Your `CLAUDE.md` holds the facts that are specific to your project and stays yours.
- **A status bar** (optional, per computer) – a one-line display at the bottom of the assistant that shows useful live information such as time, cost and usage while you work.

## Install

You need two things on your computer first:

1. **Git** – the tool that downloads and tracks code. On Windows, install [Git for Windows](https://git-scm.com/download/win).
2. **Claude Code** – the AI assistant itself. Follow the [Claude Code setup guide](https://docs.anthropic.com/en/docs/claude-code/setup) and open it once inside your project.

Then open a terminal **in your project folder** and paste one line:

**Mac, Linux or Git Bash**

```sh
curl -fsSL https://raw.githubusercontent.com/nachogl1/orion/main/orion.sh | bash -s -- init
```

**Windows PowerShell**

```powershell
irm https://raw.githubusercontent.com/nachogl1/orion/main/orion.ps1 | iex
```

That is all. The command fetches the latest orion, puts it into your project and tells you what it added. Save (commit) those files to your project so your teammates get them too.

The next time you open Claude Code in the project, the assistant runs a one-time check that everything fits together: your project's instructions file, the rules it now imports, the skills (orion's and any you already had) and the settings. It repairs what is mechanical by itself, asks before changing anything that is yours, and tells you what is left. You can repeat the check any time by typing `/orion-verify`.

Prefer to let the assistant do it? Open Claude Code in your project and say *"set up orion in this project"*.

The status bar is not installed by default, because it is a personal setting rather than part of the project. If you want it, add `--statusline` to the end of the Mac/Linux command above, or answer *yes* when the installer asks.

## Keeping it up to date

orion checks for a newer version when you start a session and asks whether you want to update. Say yes and it updates itself, then you save the result to the project as usual. Nothing is ever changed without your say-so.

If you would rather have updates applied without being asked each time, choose *auto* when the installer asks during install (or add `--update-mode auto` to the install command). You can change your mind later by editing `updateMode` in `.claude/orion/config.json` to `ask`, `auto` or `off`.

## License

[MIT](LICENSE) — free to use, modify and redistribute with attribution.
