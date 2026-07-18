# Agent workflows

The system currently has two operational modes that converge on the same data model.

In the application workflow, which requires `FEATURE_FLAGS=automatic_verifications=false`, separate workers discover candidate quotations, link them to relevant statements, verify source fidelity, assess relevance, infer stance, and synthesize collections of records. The separation allows the verification passes to run not only on machine-discovered records but also on quotations contributed through the interface or external tools.

For larger collections, such as the Future of Life Foundation Epistack competition case studies, scheduled coding-agent jobs perform bulk discovery and insertion using skills. Records then pass through the same structured verification. This mode is currently more cost-effective for large searches, although it is less encapsulated than the repository-native workflow.

## Simplified pipeline

> source discovery → quote extraction and attribution → statement linking + stance inference → source-fidelity check → quote-statement relevance check → stance check → label as "ai verified" → export

These are separate task passes, not independent evidence sources. Agreement among automated passes should not be interpreted as human validation. However, humans can manually assess records in the UI, and authors can claim their profiles by logging in with X to update or delete their quotations.

## Reusable Codex skills

The skills used for the scheduled workflow are versioned here so contributors can inspect and reuse them:

- [youcongress-topic-quotes](skills/youcongress-topic-quotes/SKILL.md) discovers eligible, sourced quotes, links each to an existing statement, and infers a candidate stance.
- [youcongress-verify-quotes](skills/youcongress-verify-quotes/SKILL.md) performs the structured source-fidelity, quote-statement relevance, and stance checks on pending records.

To make these available to Codex locally, copy the two skill directories into `~/.codex/skills/`, preserving their directory names and contents. They require access to the YouCongress MCP tools; the verification skill also includes its validation references under `references/`.
