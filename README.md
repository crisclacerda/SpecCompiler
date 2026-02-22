<h3 align="center">SpecCompiler is the reference implementation of SpecIR - a relational intermediate representation for textual specifications.</em></p>
<p align="center">
  <a href="https://github.com/specIR/SpecCompiler/blob/main/LICENSE"><img src="https://img.shields.io/github/license/specIR/SpecCompiler" alt="License"></a>
  <img src="https://img.shields.io/badge/status-alpha-orange" alt="Status: Alpha">
</p>

<p align="center">
  <img src="assets/logo.jpg" alt="SpecCompiler logo" width="160"/>
</p>

## What

<p align="center"><em>An extensible type system for Markdown.</em></p>

Author specifications in Markdown. Compile them a relational model. Catch structural defects during build.

### See It in Action

<p align="center">
  <img src="assets/demo.gif" alt="SpecCompiler demo: writing specs, catching type errors, and compiling to DOCX" width="700"/>
</p>

## Why

<p align="center"><em>Well-typed specifications don't go wrong.</em></p>

> "The fundamental purpose of a type system is to prevent 
> the occurrence of execution errors during the running of 
> a program." Cardelli, [Type Systems](http://lucacardelli.name/Papers/TypeSystems.pdf)

The fundamental purpose of SpecCompiler is to prevent the occurrence of *findings* during the review of a specification.

By imposing a ReqIF-inspired Type System (Γ) on Markdown SpecCompiler guarantees referential and schema integrity: detecting invalid object kinds, missing mandatory attributes and traceability gaps at **compile time**.

## Output

**DOCX (Print & Collaboration):** Maps types directly to DOCX style presets and supports direct OOXML transformations. Generate branded corporate templates or strict academic formats (ABNT NBR 14724:2011).

**HTML + WASM (Web Native):** A self-contained html file bundled with SQLite.js enables queries directly in the browser without any server infrastructure.

**ReqIF (Downstream Interoperability):** Author and validate your specs in Git but emit industry-standard ReqIF to integrate with legacy RE tools.

**Actually, Anything:** The entire pipeline is easily extensible to support custom Lua filters and post-processing hooks for any Pandoc supported format.

## Quickstart

### Install

```bash
git clone https://github.com/specIR/SpecCompiler.git
cd speccompiler-core
```

Docker is recommended. (Linux/Mac/WSL2)
```bash
bash scripts/docker_install.sh
```

For native ubuntu/debian (builds all dependencies from source)
```bash
bash scripts/build_vendor.sh --install
```

### A Minimal Spec

**srs.md** — a requirement:

```markdown
# SRS: Login Service

## HLR: Authenticate Users @0013

The system shall authenticate users via OAuth 2.0.

> status: Draft
```

**svc.md** — a verification case that covers it:

```markdown
# SVC: Login Verification 

## VC: Verify Authentication

Verify the authentication flow works end to end.

> objective: Confirm OAuth 2.0 login succeeds

> verification_method: Test

> traceability: [0013](@)
```

### Build

```bash
specc build project.yaml
```

For project configuration, authoring syntax, and all CLI options, see the
[manual](docs/user_docs/manual.md).

## How It Works

### Under the Hood (Pandoc + a Middle-End)

SpecCompiler runs as a Pandoc Lua filter and adds a typed middle-end between
Pandoc's reader and writer:

**0. Type loading (Γ).** Before any document is parsed, SpecCompiler reads
type definitions from Lua modules and INSERTs them into the IR. A type defines
what a spec object *is*: its identifier, display name, PID format, and typed
attributes.

For example, the HLR type (`models/sw_docs/types/objects/hlr.lua`):

```lua
M.object = {
    id = "HLR",
    long_name = "High-Level Requirement",
    extends = "TRACEABLE",
    pid_prefix = "HLR",
    pid_format = "%s-%03d",
    attributes = {
        { name = "priority", type = "ENUM", values = { "High", "Mid", "Low" } },
        { name = "rationale", type = "XHTML" },
    }
}
```

Loading this module produces:

```sql
INSERT INTO spec_object_types (identifier, long_name, ...)
VALUES ('HLR', 'High-Level Requirement', ...);
```

**1. Frontend (Pandoc reader).** Parse `commonmark_x` into Pandoc AST.

**2. Middle-end (SpecCompiler).** Lower the AST into SpecIR (SQLite), apply type
rules, and assemble the transformed AST. For the two-file spec above, the
middle-end produces:

```sql
-- Specification (from the # heading)
INSERT INTO specifications (identifier, long_name, type_ref)
VALUES ('srs', 'Login Service', 'SRS');

-- Object (from the ## heading)
INSERT INTO spec_objects (specification_ref, type_ref, pid, title_text, level)
VALUES ('srs', 'HLR', '0013', 'Authenticate Users', 2);

-- Attribute (from the > blockquote)
INSERT INTO spec_attribute_values
  (specification_ref, owner_object_id, name, raw_value, enum_ref, datatype)
VALUES ('srs', 1, 'status', 'Draft', 'TRACEABLE_status_Draft', 'ENUM');

-- Relation (from [0013](@) in svc.md's traceability attribute → inferred as VERIFIES)
INSERT INTO spec_relations
  (specification_ref, source_object_id, target_text, type_ref, link_selector, source_attribute)
VALUES ('svc', 2, '0013', 'VERIFIES', '@', 'traceability');
```

Type-checking is then a query against the IR. For example, the proof view
`invalid_cast` checks whether `'Pending'` is a legal value for
`TRACEABLE.status` — it is not (only Draft, Review, Approved, Implemented are).
And `traceability_hlr_to_vc` finds HLRs that are never the target of a
VERIFIES relation.

**3. Backend (Pandoc writer).** Render the assembled AST via the Pandoc CLI.

**4. Post-processing (optional).** Format-specific adjustments to the emitted
artifacts. For example, OOXML tweaks in DOCX output or packaging sqlite.js
in HTML.

## Documentation

- **[Manual](docs/user_docs/manual.md)**, installation, authoring syntax, configuration (start here)
- **[Guides](docs/user_docs/guides/)**, DOCX customization, creating a model
- **[Architecture](docs/engineering_docs/architecture/)**, system design
- **[Engineering Specs](docs/engineering_docs/)**, SRS, SDD, SVC for SpecCompiler itself

## License

Apache License 2.0, see [LICENSE](LICENSE).

See [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES).
