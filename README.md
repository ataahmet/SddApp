## 🚀 Specification-Driven Development (SDD) — A Disciplined Development Workflow for Mobile Projects

# Core components of the project:

A terminal-first CLI workflow — runs via scripts/sdd with no IDE plugin required
AI agent support through Claude Code and GitHub Copilot CLI integration
Spec lifecycle management with draft → ready → active → done states
Alignment gate and verify gate mechanisms ensuring quality control before any code is written
A portable artifact structure — integrates into existing projects with a single install.sh command
🤖 Multi-agent architecture: Claude CLI & Copilot CLI, side by side.

SDD is not locked to a single AI provider. The SDD_AGENT environment variable lets you choose your backend per command, and sdd sync-agents keeps agent definitions in sync across both platforms. Teams can run different specs with different agents in parallel — one agent per spec, ensuring consistency.

# 📱 Android-first, but not platform-bound.

While the current implementation is built on top of the Android ecosystem, the core of SDD — the spec lifecycle, AI agent discipline, shell-based CLI tools, and template structure — is entirely platform-agnostic. Since spec templates, git integration, and lifecycle management all operate through the terminal, an iOS adaptation (Xcode / Swift / SwiftUI) is on our roadmap. The goal is to turn SDD into a platform-independent standard for mobile development.

# Why does this matter?

Because writing code with AI doesn't mean writing the right code. SDD ensures the AI agent understands what to build before it produces how to build it, preventing specification-less development at its root.