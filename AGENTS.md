# novfind — Project Guide

## Core Value

「Google検索にsite:演算子を手動で貼り付ける」を、キーワード登録→ワンタップ検索に置き換える

## Current Phase

**v1 MVP Complete 🎉** — 全20要件実装済み

## Key Files

| Artifact | Location |
|----------|----------|
| Project context | `.planning/PROJECT.md` |
| Config | `.planning/config.json` |
| Requirements | `.planning/REQUIREMENTS.md` |
| Roadmap | `.planning/ROADMAP.md` |
| State | `.planning/STATE.md` |
| Research | `.planning/research/` |

## Workflow

- Plan phases with `/gsd-plan-phase N`
- Execute plans with `/gsd-execute-phase N`
- Use `run: test` after changes

## Remote

- `origin` → `https://github.com/krasherjoe/novfind.git`

## Stack

- Flutter (Android only for v1)
- State: flutter_riverpod
- HTTP: dio
- HTML parsing: html
- Persistence: shared_preferences
- Sharing: share_plus
- Config: assets/search_query.txt
- Env: .env (git-ignored), copy from .env.example
