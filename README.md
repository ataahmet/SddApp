# Android için Specification-Driven Development

Claude Code CLI ile çalışan, plugin gerektirmeyen, terminal-first bir SDD akışı.

## Kurulum

### 1. Gereksinimler

```bash
# git zaten varsa atla
brew install git                                   # macOS

# Claude Code CLI (align/implement/verify komutları bunu kullanır)
curl -fsSL https://claude.ai/install.sh | bash     # önerilen (Node gerekmez)
# alternatifler:
#   brew install --cask claude-code
#   npm install -g @anthropic-ai/claude-code       # Node 22+ ister

claude --version        # sürüm güncel olmalı
claude doctor           # kurulum/ayar teşhisi
```

Bu kit `claude` CLI'ın `--agent`, `--tools` ve `--permission-mode` bayraklarını kullanır;
Claude Code **v2.1.x** ve üzeri gerekir.

1. Terminal'e `claude` yaz (güncel sürüm önerilir).

2. Giriş: CLI içinde `/login`, ya da doğrudan `claude auth login`.
   Gün içinde bir kez yapman yeterli; `claude auth status` ile kontrol edebilirsin.

3. Login başarılı olduktan sonra CLI'ı kapatabilir veya arka planda bırakabilirsin.

4. `scripts/sdd` komutlarını çalıştıracağın terminalde yukarıdaki proxy export'larını
   tekrar yap ve bu oturumu kullan.

*CI/pipeline:* interaktif login yerine `claude setup-token` ile uzun ömürlü token üret.

## Klasör Yapısı

```
proje-kökü/
├── CLAUDE.md                      #  proje mimari kuralları (araçtan bağımsız, tek kaynak)
├── .claude/
│   ├── settings.json              # proje izinleri (allow / ask / deny)
│   ├── agents/                    # özel Claude Code agent'ları (subagent)
│   │   ├── sdd-align.md           # `sdd align` bu agent'ı kullanır
│   │   ├── sdd-implement.md       # `sdd implement` bu agent'ı kullanır
│   │   ├── sdd-verify.md          # `sdd verify` bu agent'ı kullanır
│   │   └── kotlin-ktlint.md       # `sdd fix-ktlint` bu agent'ı kullanır
│   └── commands/                  # interaktif oturum için slash komutları
│       ├── sdd-align.md           # /sdd-align
│       ├── sdd-verify.md          # /sdd-verify
│       ├── sdd-implement.md       # /sdd-implement
│       └── sdd-fix-ktlint.md      # /sdd-fix-ktlint
├── scripts/
│   └── sdd                        # ana CLI script (chmod +x)
└── specs/
    ├── templates/
    │   ├── feature.md
    │   ├── bug.md
    │   ├── test.md
    │   └── refactor.md
    ├── features/
    │   └── 001-kullanici-girisi/
    │       └── spec.md
    ├── bugs/
    ├── tests/
    └── refactors/
```

Kurulumdan sonra bir kez: `chmod +x scripts/sdd`.

## Komutlar

> **Akış sırası:** `new → ready → align → align-resolve → verify → start → implement → done`

İlk iş: `./scripts/sdd doctor` — CLI, oturum, agent dosyaları ve proxy kontrolü.

### Yeni Spec Oluştur

```bash
./scripts/sdd new feature "Kullanıcı Girişi"
./scripts/sdd new bug "Token refresh sonsuz döngü"
./scripts/sdd new test "LoginViewModel coverage"
./scripts/sdd new refactor "Repository'leri Flow'a geçir"
```

Bu komut:
1. `specs/{type}s/{task_id}-{task_name}/spec.md` oluşturur — **`task_id`'yi sana sorar**
   (Enter'a basınca sıradaki numarayı varsayılan kullanır)
2. Şablonu kopyalar, front matter'ı doldurur (`status: draft`)
3. **Branch oluşturmaz** — branch `sdd start` adımında açılır

Türkçe başlıklar doğru slug'a çevrilir: "Kullanıcı Girişi" → `kullanici-girisi`.

### Hazır Kapısı — draft → ready

```bash
./scripts/sdd ready specs/features/{task_id}-{task_name}/spec.md
```

Şu bölümleri kontrol eder, boşsa geçişi durdurur:
1. **§1 Amaç / Problem / Motivasyon**
2. **Kabul Kriterleri** — en az bir madde
3. **Test Planı** — (bölüm varsa)

Yorum (`<!-- … -->`), boş madde (`-`), boş checkbox (`- [ ]`) ve `{placeholder}` "dolu"
sayılmaz. `start` yalnız `ready` spec'te çalışır.

### Alignment — Sorular + Cevaplar

```bash
./scripts/sdd align specs/features/{task_id}-{task_name}/spec.md
```

Bu komut iki aşamada çalışır, **chat ekranı açmaz**:

1. **Adım 1 — Soru üretimi (headless):** `sdd-align` agent'ı `claude -p` ile çalışır, spec'i
   ve CLAUDE.md kurallarını okuyarak açık kararları/soruları üretir ve spec'in
   `## Open Decisions (Alignment)` bölümüne yazar.

2. **Adım 2 — Cevap toplama (terminal):** Bash script, agent'ın yazdığı soruları sırayla
   terminale basar ve `read` ile cevabını alır. Cevapları spec'e yazar, sonra
   `align-resolve` çağırıp `alignment: resolved` yapar.

```
→ Alignment (adım 1/2): sorular üretiliyor ...
  5 soru üretildi.
→ Alignment (adım 2/2): soruları terminalde cevaplayın (boş = atla)
────────────────────────────────────────
  1. Agent sorusu?
  →  Cevap: Developer cevabı
  2. Agent sorusu
  →  Cevap: Developer cevabı
────────────────────────────────────────
✓ Tüm alignment soruları cevaplandı → alignment: resolved (2/2).
```

Terminal interaktif değilse (CI vb.) script soruları üretir ama cevap sormaz;
cevapları elle doldurup `./scripts/sdd align-resolve <spec>` çalıştırırsın.

### Alignment'ı Kapat — align-resolve

Normalde `sdd align` bunu otomatik çağırır. Cevapları elle doldurduysan veya sonradan
değiştirdiysen:

```bash
./scripts/sdd align-resolve specs/features/{task_id}-{task_name}/spec.md
```

Eksik cevap varsa durur ve **hangi sorunun** boş olduğunu yazar. `alignment: resolved`
olmadan `start`/`implement` çalışmaz.

### Doğrula (zorunlu kapı)

```bash
./scripts/sdd verify specs/features/{task_id}-{task_name}/spec.md
```

`sdd-verify` agent'ı salt-okunur çalışır (`--tools "Read,Grep,Glob"`), spec'i CLAUDE.md ile
karşılaştırır ve ilk satırda `VERIFY: PASS` / `VERIFY: FAIL` basar. Script bu verdict'i yakalar
ve front matter'a `verify: passed` / `verify: failed` yazar.

**`verify: passed` olmadan `start` ve `implement` çalışmaz.** Agent bir çelişki ya da en ufak
belirsizlik bulursa FAIL verir; ilgili noktaları netleştirip tekrar çalıştır. `sdd align`
yeniden koşarsa spec değiştiği için `verify` otomatik `pending`'e döner.

### Branch Aç (start)

```bash
./scripts/sdd start specs/features/{task_id}-{task_name}/spec.md
```

1. `git checkout -b main/{task_id}-{task_name}`
2. Spec front matter'ında `branch:` alanını doldurur
3. `status: active` yapar

> **Not:** `main` adında bir branch varsa git `main/...` ref'ini oluşturamaz. Bu durumda
> `SDD_BRANCH_PREFIX=feature ./scripts/sdd start …` kullan (veya CLAUDE.md §9.1 kuralını güncelle).

> **Kapılar:** `alignment: resolved` + `verify: passed` olmadan branch açılmaz.
> Sıra her zaman `align → verify → start`.

### Task Implement Et

```bash
./scripts/sdd implement specs/features/{task_id}-{task_name}/spec.md T3
```

Task verilmezse `## Task List`'teki tüm task'lar sırayla uygulanır.

Varsayılan olarak headless çalışır (`claude -p --agent sdd-implement`). Agent'ı izleyerek
müdahale etmek istersen:

```bash
SDD_IMPLEMENT_INTERACTIVE=1 ./scripts/sdd implement <spec> T3
```

> **Commit formatı (CLAUDE.md §9.1):** `[{KOD}-{task_id}] {task} – kısa açıklama` + gövdede
> `Spec: specs/{type}s/{task_id}-{task_name}/spec.md`. KOD: feature→`FEAT`, bug→`BUG`,
> refactor→`REF`, test→`TEST`. `sdd implement` bitişte doğru komutu hazır basar.
> Commit'i agent atmaz, sen atarsın.

### Listele

```bash
./scripts/sdd list              # hepsi (status + alignment + verify kolonlarıyla)
./scripts/sdd list feature
./scripts/sdd list bug
```

### ktlint Düzelt (fix-ktlint)

```bash
./scripts/sdd fix-ktlint                  # varsayılan: ./gradlew app:ktlint
./scripts/sdd fix-ktlint checkCodeQuality # farklı gradle task ile
```

1. `./gradlew app:ktlint` çalıştırıp ihlalleri toplar
2. İhlal içeren `.kt` dosyalarını çıkarır (ihlal yoksa "temiz" der)
3. Dosya listesi + ihlalleri `kotlin-ktlint` agent'ına gönderir; agent yalnız stil/format
   düzeltir (Bash tool'u yoktur, iş mantığına dokunmaz, yeni dosya oluşturmaz)

Lifecycle'ın parçası değildir; her aşamada çağrılabilir.

### Durum Geçişleri

```bash
./scripts/sdd ready          <spec.md>          # draft → ready (zorunlu bölüm kapısı)
./scripts/sdd align          <spec.md>          # alignment sorularını üret/sor (interaktif)
./scripts/sdd align-resolve  <spec.md>          # tüm cevaplar dolu mu? → alignment: resolved
./scripts/sdd verify         <spec.md>          # zorunlu kapı → verify: passed/failed
./scripts/sdd start          <spec.md>          # ready → active (+branch)
./scripts/sdd done           <spec.md>          # kalite kapıları + active → done
./scripts/sdd block          <spec.md> "neden"  # → blocked
./scripts/sdd drop           <spec.md> "neden"  # → dropped
./scripts/sdd doctor                            # ortam kontrolü
```

## Tipik İş Akışı

```bash
# 0. Ortam kontrolü (ilk kurulumdan sonra bir kez)
./scripts/sdd doctor

# 1. Yeni feature başlat (status: draft, branch yok)
./scripts/sdd new feature "Biometric Login"

# 2. Spec'i editörde aç, Goal / Scope / Acceptance Criteria'yı doldur
$EDITOR specs/features/001-biometric-login/spec.md

# 3. Zorunlu bölüm kapısı: draft → ready
./scripts/sdd ready specs/features/001-biometric-login/spec.md

# 4. Alignment: agent soruları üretir, sana sorar, cevapları yazar ve resolved yapar
./scripts/sdd align specs/features/001-biometric-login/spec.md

# 5. Zorunlu kapı: verify passed olmadan start/implement çalışmaz
./scripts/sdd verify specs/features/001-biometric-login/spec.md

# 6. Spec'i commit'le
git add specs/features/001-biometric-login/
git commit -m "docs(spec): Biometric Login spec"

# 7. Branch aç, kodlamaya geç (status: active)
./scripts/sdd start specs/features/001-biometric-login/spec.md

# 8. Task'ları sırayla implement et
./scripts/sdd implement specs/features/001-biometric-login/spec.md T1
./gradlew checkCodeQuality
git add . && git commit -m "[FEAT-001] T1 – ..." -m "Spec: specs/features/001-biometric-login/spec.md"
# … her task için tekrarla

# (Opsiyonel) ktlint ihlallerini agent ile düzelt
./scripts/sdd fix-ktlint

# 9. Bitir: kalite kapıları + status: done
./scripts/sdd done specs/features/001-biometric-login/spec.md
```

## Özel Agent'lar (.claude/agents/)

Claude Code `.claude/agents/*.md` altındaki agent'ları **otomatik tanır**; ama kendiliğinden
devreye girmezler — `--agent <ad>` ile açıkça seçilirler. `scripts/sdd` bu seçimi senin yerine
yapar. İnteraktif oturumda `@agent-sdd-verify` ile de çağırabilirsin.

| Agent | Kullanan komut | Model (varsayılan) | Tool'lar | Görev |
|-------|---------------|--------------------|----------|-------|
| `sdd-align` | `sdd align` | `opus` (en güçlü) | Read, Grep, Glob, Edit, Write, AskUserQuestion, Bash | Açık kararları üretir, kullanıcıya sorar, cevapları yazar |
| `sdd-implement` | `sdd implement` | `sonnet` (orta) | Read, Grep, Glob, Edit, Write, Bash | Spec'teki tek task'ı CLAUDE.md kurallarıyla uygular |
| `sdd-verify` | `sdd verify` | `sonnet` (orta) | Read, Grep, Glob | Spec'i CLAUDE.md ile karşılaştırır, salt-okunur denetim |
| `kotlin-ktlint` | `sdd fix-ktlint` | `haiku` (en ucuz) | Read, Grep, Glob, Edit | ktlint stil/format ihlallerini düzeltir (mekanik) |

Modeller `scripts/sdd` başındaki `SDD_MODEL_*` değişkenlerinde; env ile override edilebilir:

```bash
SDD_MODEL_KTLINT=haiku ./scripts/sdd fix-ktlint
SDD_MODEL_VERIFY=opus  ./scripts/sdd verify <spec>
```

Alias (`opus` / `sonnet` / `haiku`) ya da tam model id (`claude-sonnet-5`) kullanılabilir.
Premium kotayı yalnız değer kattığı yerde harca (align = en güçlü); mekanik iş (ktlint) en ucuz
modelde.

## İzinler

`.claude/settings.json` proje düzeyinde izinleri tanımlar: `./gradlew` ve `./scripts/sdd`
serbest, `git push/commit/checkout/reset` sorar, `secrets.properties` / `local.properties` /
keystore okumaları **yasak**.

```bash
SDD_PERM_IMPLEMENT=acceptEdits ./scripts/sdd implement <spec> T1
```

`deny` kuralları her modda geçerlidir; `bypassPermissions` bile onları aşamaz.

## Slash Komutları (interaktif oturum)

Terminalden `claude` ile girdiğinde:

```
/sdd-align      specs/features/001-x/spec.md
/sdd-verify     specs/features/001-x/spec.md
/sdd-implement  specs/features/001-x/spec.md T1
/sdd-fix-ktlint app:ktlint
```

Bunlar kolaylık içindir; **front matter kapılarını güncellemezler**. `verify: passed` gibi
alanların yazılması için komutu `scripts/sdd` üzerinden çalıştır.

## Spec Tipleri Ne Zaman Kullanılır

| Durum | Tip |
|-------|-----|
| Yeni davranış ekliyorum | feature |
| Mevcut davranış yanlış | bug |
| Mevcut davranışı koruyorum | test |
| Davranış aynı, kod yapısı değişiyor | refactor |
| 1 saatten kısa cleanup | spec'siz commit |

## İpuçları

**Bir spec, bir tip.** Hibrit durumlar için iki ayrı spec aç ve birbirine link ver.

**Task'ları küçük tut.** 2 günden büyük ise spec'i böl.

**Refactor'da test güvenlik ağı şart.** Coverage yetersizse, refactor öncesi test spec'i aç.

**CLAUDE.md'yi tekrar etme.** Spec'lerde sadece referans ver. Sapma varsa "Deviations from
CLAUDE.md" bölümünde gerekçele.

**Implement öncesi temiz oturum.** Her `sdd implement` çağrısı kendi oturumunu açar; uzun
sohbetlerde `/clear` ile başla.

**CLAUDE.md'yi şişirmeyin.** İçeriği büyüdükçe kurallara uyum düşer; kural eklemek gerekiyorsa
CLAUDE.md'ye ekle, CLAUDE.md sadece import + Claude'a özgü notlar kalsın.

## Sınırlamalar

- Bu kit Claude Code CLI'a optimize. Copilot/Cursor/Aider kullanıyorsan `scripts/sdd`'nin
  `claude` çağrılarını ilgili tool'a çevir (CLAUDE.md ve spec'ler aynı kalır).
- `sdd align` interaktif terminal ister; CI'da çalışmaz (manuel protokol basar).
- CLAUDE.md değişikliği takım onayı gerektirir — solo proje değilsen.
- Spec yazmak overhead. Çok küçük işler için zorlama.
- **Alignment kapısı tüm tiplerde geçerli.** Tüm şablonlarda `## Open Decisions (Alignment)`
  bölümü var; bu yüzden `start`/`implement` her zaman cevapların dolu olmasını bekler.
