# CLAUDE.md

## Architecture & Data Flow
- Dependency direction: **presentation → domain ← data** (data and presentation don't know each other, domain is pure).
- **Each layer's job in one sentence:** `data` fetches/writes data, `domain` runs the business rule and
  produces Response→ViewEntity, `presentation` only observes the state and binds it to the UI.

## Technology (non-negotiable)
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

## Spec-Driven Development
- All new work starts with a spec under `specs/` (from the `specs/templates/` template). The spec is written/read before writing code (except hotfixes).
- If a deviation from these rules is needed, it is justified under the "Deviations from CLAUDE.md" heading in the spec.
- **Agent rule (non-negotiable):** Do not write code without reading the spec / checking `status`. Do not write code to a `draft`/`blocked` spec.
