# Android SDD Artifact

Bu repository, Android projelerinde kullanılacak taşınabilir SDD artifact'inin kaynağıdır.
Mevcut SDD akışını bu repository içinde kullanmak için `scripts/sdd` komutunu çalıştırabilirsin.

## Artifact oluşturma

```bash
./scripts/sdd-artifact
```

Varsayılan çıktı:

```text
dist/sdd-artifact/
```

Özel çıktı yolu:

```bash
./scripts/sdd-artifact /tmp/sdd-artifact
```

Artifact paketinin kurulum dokümanı, bu dosyanın artifact içindeki kopyası olan
`dist/sdd-artifact/README.md` dosyasında bulunur. Bu doküman hedef projeye kurulmaz.

## Başka Android projesine kurma

```bash
dist/sdd-artifact/install.sh /path/to/target-android-project
```

Kurulum hedef projeye `CLAUDE.md`, `SDD-README.md`, `.claude/`, `.github/`, `scripts/` ve
`specs/templates/` yapısını ekler. Mevcut dosyaların üzerine varsayılan olarak yazmaz.

Mevcut SDD dosyalarını bilinçli olarak güncellemek için:

```bash
dist/sdd-artifact/install.sh --force /path/to/target-android-project
```

Kurulum hedef `.gitignore` dosyasındaki mevcut içeriği korur ve eksik SDD kurallarını ekler:

```text
dist
specs/features
specs/bugs
specs/refactors
specs/tests
```

Kurulum ayrıca hedef projeye `SDD-README.md` dosyasını ekler. Bu dosya hedef projede SDD'nin
günlük kullanımını anlatır.
