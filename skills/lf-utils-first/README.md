# lf-utils-first

An [Agent Skill](https://agentskills.io): instructions that ask your AI coding assistant
to check the library's `LF_INDEX.md` before writing GDScript, and to reuse a class from the library when one
fits. It is guidance, not enforcement: whether the assistant loads the skill and follows
it depends on the tool and the model, so review what it writes.

**Install:** copy this whole folder (`lf-utils-first`) into the skills folder your
assistant reads, in your project's root:

- Claude Code: `.claude/skills/`
- Other tools that support Agent Skills: the skills folder named in that tool's
  documentation (several read `.agents/skills/`)

Then add the short reminder from the library's main README (*Using it with an AI coding
assistant*) to your project's `CLAUDE.md` or `AGENTS.md`.
