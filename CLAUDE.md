# CLAUDE.md

## Architecture & Data Flow
- Dependency direction: **presentation → domain ← data** (data and presentation don't know each other, domain is pure).
- **Each layer's job in one sentence:** `data` fetches/writes data, `domain` runs the business rule and
  produces Response→ViewEntity, `presentation` only observes the state and binds it to the UI.

## Technology (non-negotiable — verified)
- Kotlin, **Java 17**, `compileSdk 35`, `minSdk 23`, `targetSdk 35`.
- DI: **Hilt** (Koin forbidden). Async: **RxJava2** (`Single`/`Completable`); **coroutines/suspend/Flow FORBIDDEN**.
- Network: Retrofit + **Gson** (`@SerializedName`)**;
- UI: Android Views + **Compose, Navigation safeargs.
- Storage: `Source` abstraction (PaperDB). Logging: **Timber** (`Log.*`/`println` forbidden).

## Dependency Injection
- Binds dependencies with the correct lifetime.
- A feature's data/domain dependencies are **`@ActivityRetainedScoped`** (`ActivityRetainedComponent`); `@Singleton`/`@ActivityScoped` FORBIDDEN.
- Repository binding via `@Binds`; only a scope annotation on `@Inject constructor` classes (no manual `@Provides`). A Repository is bound in its feature's Module.
- Exception (stays Singleton, wider scope): /Retrofit/OkHttp, general utils.
- **DON'T (di — non-negotiable):**
  1. ✗ `@InstallIn(SingletonComponent)`/`@Singleton` for a feature Repository/DataSource/UseCase/Observer.
  2. ✗ Binding feature dependencies with `@ActivityScoped` (`ActivityComponent`).
  3. ✗ Injecting a narrow-scope (ActivityRetained/Activity) dependency into a wide-scope (Singleton) class.
  4. ✗ Writing a manual `@Provides` for constructor-injected classes.
  5. ✗ Binding the same Repository in more than one `@Module`.

## 9. Spec-Driven Development
- All new work starts with a spec under `specs/` (from the `specs/templates/` template). The spec is written/read before writing code (except hotfixes).
- Spec content: purpose, scope (in/out), affected layers/feature, contracts (DTO + entity), acceptance criteria, environment/flavour notes.
- If a deviation from these rules is needed, it is justified under the "Deviations from CLAUDE.md" heading in the spec.

### 9.1 Spec Lifecycle (agent-driven)
Each spec's `status` is kept in the front matter. The branch is **created by the agent** (`scripts/sdd start` or the AI agent), written into the spec.

```
draft ——→ ready ——→ active ——→ done
            ↓-->blocked<--↓
                   ↓
                dropped

```

| Status | Meaning | Branch | Agent action |
|--------|---------|--------|--------------|
| `draft` | Spec being written, incomplete | none | Complete the mandatory sections → `ready` |
| `ready` | Spec complete, ready to code | none | Create branch + fill `branch:` → `active` |
| `active` | Coding in progress | 🟢 yes | Apply the tasks in order, verify |
| `done` | Acceptance criteria 🟢, tests passed | merge | – |
| `blocked` | Waiting on an external dependency/decision | depends | Fill `blocked_reason:`, notify the user, stop |
| `dropped` | Cancelled/postponed | – | Fill `dropped_reason:` |


**Branch convention:** `main/{task_id}-{task_name}` (e.g., `main/001-biometric-login`, `main/017-token-loop`, `main/003-flow-migration`, `main/…`).
`: Purpose, Scope, Acceptance Criteria, Test Plan must be filled (`scripts/sdd ready`).
- **Alignment gate (`ready → active` precondition):** every `**Answer:**` line in the `## Open Decisions (Alignment)` section must be filled and the front matter must read `alignment: resolved` (`scripts/sdd align` → `align-resolve`).
- **Verify gate (`ready → active` precondition):** the spec must have `verify: passed` (`scripts/sdd verify`). If verify FAILs, stay at this stage.
- `ready → active`: `git checkout -b main/{task_id}-{task_name}` → write the `branch:` field, `status: active`.
- `active → done`: All tasks 🟢, `./gradlew checkCodeQuality assembleDevDebug` green, a line added to the Changelog.
- `* → blocked`: Don't write code; write the reason into `blocked_reason:` and stop.
**Commit format:** `[{TYPE}-{task_id}] short description` + `Spec: specs/{type}s/{task_id}-{task_name}/spec.md` in the body.
**Agent rule (non-negotiable):** Do not write code without reading the spec / checking `status`. Do not write code to a `draft`/`blocked` spec.


