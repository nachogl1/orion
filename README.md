<p align="center">
  <img src="assets/orion-twinkle.gif" alt="orion — a repo-level utility framework for Claude Code projects" width="520"/>
</p>

# orion

> [!CAUTION]
> orion tells an AI assistant how to work in your project, and the assistant will run commands and edit files on your machine. Review what you install, keep your work saved, and use it at your own risk. It is under constant improvement and is provided as-is.

**orion is a framework you install into your own project** to help you build software better and faster with [Claude Code](https://claude.com/claude-code), Anthropic's AI coding assistant.

Once installed, it gives the assistant a shared set of working rules and ready-made abilities for the everyday tasks of a software project, so every person on the team gets the same, consistent help from day one. It lives inside the project itself, so there is nothing for teammates to set up: whoever clones the project gets orion with it, and improvements arrive with a normal update.

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

Prefer to let the assistant do it? Open Claude Code in your project and say *"set up orion in this project"*.

## Keeping it up to date

orion checks for a newer version when you start a session and asks whether you want to update. Say yes and it updates itself, then you save the result to the project as usual. Nothing is ever changed without your say-so.

## License

[MIT](LICENSE) — free to use, modify and redistribute with attribution.
