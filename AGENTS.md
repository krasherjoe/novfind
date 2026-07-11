# novfind — Project Guide

## Core Value

「Google検索にsite:演算子を手動で貼り付ける」を、キーワード登録→ワンタップ検索に置き換える

## Current Phase

**Phase 2: Android Platform Config** — NetworkSecurityConfig/INTERNET/package visibility設定

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

## Stack

- Flutter (Android only for v1)
- State: flutter_riverpod
- HTTP: dio
- HTML parsing: html
- Persistence: shared_preferences
- Sharing: share_plus
- Env: flutter_dotenv
