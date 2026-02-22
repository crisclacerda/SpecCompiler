## DIC: Syntax Reference @DIC-SYN-001

This section defines the SpecCompiler grammar at the **Pandoc AST level**. SpecCompiler documents are standard Markdown processed through Pandoc; the parser recognizes specific AST patterns and promotes them to specification elements. Everything else accumulates as content to the current owner.

The formal grammar is maintained in `definitive_grammar.md` (verified against `src/pipeline/initialize/*.lua`). Railroad diagrams are in `docs/grammar/railroad/`.

---

### AST Mapping

```list-table:tbl-ast-mapping{caption="Pandoc AST to SpecCompiler Mapping"}
> header-rows: 1
> aligns: l,l,l,l,l

* - Markdown
  - Pandoc Element
  - Properties
  - SpecCompiler Type
  - Match Condition
* - `# type: Title @PID`
  - Header
  - level: Int, inlines: [Inline]
  - Specification
  - level == 1
* - `## type: Title @PID`
  - Header
  - level: Int, inlines: [Inline]
  - SpecObject
  - level > 1
* - `> key: value`
  - BlockQuote
  - blocks: [Block]
  - Attribute
  - first Para matches `/^[%w_]+:/` pattern
* - ` ```type.lang:label{attrs}``` `
  - CodeBlock
  - classes: [String], text: String
  - SpecFloat
  - first class matches FloatSig AND type exists in `spec_float_types`
* - `` `PREFIX: content` ``
  - Code
  - text: String
  - SpecView (inline)
  - prefix is a registered `inline_prefix` in `spec_view_types`
* - `[target_text](selector)`
  - Link
  - text: [Inline], target: String
  - SpecRelation
  - target starts with `@` or `#` (stored as `link_selector`); reference is in link text (stored as `target_text`)
* - Para, BulletList, etc.
  - Block
  - (varies)
  - Content
  - no special pattern (accumulates to owner)
```

---

### Railroad Diagrams

The grammar produces the following railroad diagrams (generated from PlantUML EBNF in `docs/grammar/railroad/`):

#### Document Structure

```plantuml:fig-rr-document{caption="Document and Specification productions"}
@startebnf
title SpecCompiler: Document Structure
(* What you type in Markdown to create specifications and objects *)

Document = Specification;

Specification = "#", HeaderSig, { spec_attribute_values | spec_objects | spec_floats | spec_views | ProseBlock };

spec_objects = "##...######", HeaderSig, { spec_attribute_values | spec_floats | spec_views | ProseBlock };

(* TypeRef checked against spec_specification_types (H1) or spec_object_types (H2+) *)
(* When TypeRef is omitted, the type with is_default = 1 in the type table is used *)
HeaderSig = [ TypeRef, ":" ], Text, [ "@", PID ];

@endebnf
```

#### SpecObjects

```plantuml:fig-rr-objects{caption="SpecObject structure and body content"}
@startebnf
title SpecCompiler: SpecObject (spec_objects)
(* Any header level 2-6 creates a traceable specification object *)
(* The object accumulates content until the next header at equal or higher level *)

spec_objects = "##...######", HeaderSig, ObjectBody;

(* TypeRef checked against spec_object_types *)
(* When TypeRef is omitted, the type with is_default = 1 is used *)
HeaderSig = [ TypeRef, ":" ], Text, [ "@", PID ];

ObjectBody = { spec_attribute_values | spec_floats | spec_views | spec_relations | ProseBlock };

@endebnf
```

#### Attributes

```plantuml:fig-rr-attributes{caption="Attribute extraction from BlockQuote"}
@startebnf
title SpecCompiler: Attributes (spec_attribute_values)
(* A blockquote whose first paragraph starts with TypeRef ":" *)
(* Otherwise the blockquote is plain prose content *)

(* TypeRef checked against spec_attribute_types for the owner's type *)
spec_attribute_values = ">", TypeRef, ":", ProseBlock;

@endebnf
```

#### Floating Objects

```plantuml:fig-rr-floats{caption="Float syntax in fenced code block"}
@startebnf
title SpecCompiler: Floating Objects (spec_floats)
(* Fenced code blocks with type:label become numbered, captioned elements *)

spec_floats = "```", FloatSig, [ FloatMeta ], Content, "```";

(* TypeRef checked against spec_float_types (includes aliases) *)
FloatSig = TypeRef, [ ".", Language ], ":", Label;

FloatMeta = "{", { Key, "=", QuotedValue }, "}";

@endebnf
```

#### Relations

```plantuml:fig-rr-relations{caption="Relation link syntax"}
@startebnf
title SpecCompiler: Relations (spec_relations)
(* Every relation is a Markdown link: [target_text](TypeRef) *)
(* Relation type is inferred by specificity matching, not explicit in syntax *)

spec_relations = "[", TargetText, "]", "(", TypeRef, ")";

(* TypeRef here is the link selector, checked against spec_relation_types.link_selector *)
(* Stored as link_selector in spec_relations — e.g. @, #, @cite, @citep *)

(* TargetText stored as target_text in spec_relations *)
(* For # selectors: optionally scoped, optionally typed label *)
(* TypeRef here checked against spec_float_types (float type prefix) *)
TargetText = PID
           | [ Scope, ":" ], [ TypeRef, ":" ], Label;

@endebnf
```

#### Views

```plantuml:fig-rr-views{caption="View syntax (inline)"}
@startebnf
title SpecCompiler: Views (spec_views)
(* Views are dynamic queries materialized at build time *)
(* e.g. `toc: depth=2`, `math: E = mc^2`, `abbrev: Random Access Memory (RAM)` *)

spec_views = InlineView;

(* TypeRef checked against spec_view_types.inline_prefix *)
(* ViewParam semantics depend on the view type — may be key=value, expression, or text *)
InlineView = "`", TypeRef, ":", [ ViewParam ], "`";

@endebnf
```

#### Content Accumulation

```plantuml:fig-rr-prose{caption="Content accumulation (ProseBlock)"}
@startebnf
title SpecCompiler: Content Accumulation (ProseBlock)
(* Any Markdown block that does not match a SpecCompiler pattern *)
(* accumulates as content to the current Specification or SpecObject *)

ProseBlock = Paragraph
           | BulletList
           | OrderedList
           | DefinitionList
           | BlockQuote
           | Table
           | CodeBlock
           | HorizontalRule
           | Figure
           | Div;

@endebnf
```

---

### Syntax Quick Reference

#### Specification (H1)

```markdown
# type: Title @PID
# srs: Software Requirements Specification @SRS-001
# My Document
```

See [specIR-01](@) for full semantics.

#### SpecObject (H2-H6)

```markdown
## type: Title @PID
## hlr: User Authentication @HLR-AUTH-001
```

See [specIR-02](@) for full semantics.

#### Attribute (BlockQuote)

```markdown
> priority: high

> status: draft

> rationale: Safety-critical requirement
>
> Extended content with paragraphs and lists.
```

See [DIC-ATTR-001](@) for full semantics and datatypes.

#### SpecFloat (CodeBlock)

````markdown
```type.lang:label{key="val"}
content
```
````

See [specIR-03](@) for full semantics.

#### SpecView (Code)

```markdown
`toc:`
`lof:`
```

See [DIC-VW-001](@) for full semantics.

#### SpecRelation (Link)

```markdown
[HLR-001](@)
[fig:auth-flow](#)
[scope:type:label](#)
[smith2024](@cite)
```

See [DIC-REL-001](@) for full semantics and inference algorithm.

---

### Content Accumulation

Any block that does not match the patterns above is treated as **Content** and appended to the currently active owner (Specification or SpecObject). The accumulation rule:

- **H1** opens a Specification context — all content accumulates to it
- **H2+** opens a SpecObject context — content accumulates to it until the next header at equal or higher level

---

### Worked Example: Markdown to Spec-IR

#### Input Markdown

```markdown
# srs: Battery Monitor @SRS-001

> status: draft

This specification defines the battery monitoring subsystem.

## hlr: Voltage Check @HLR-001

> priority: high

> rationale: Safety-critical monitoring

The system shall check battery voltage every 100ms.

- Voltage range: 2.5V to 4.2V
- Alert threshold: below 3.0V

See [fig:voltage-flow](#) for the monitoring diagram.

```plantuml:fig-voltage-flow{caption="Voltage Monitoring Flow"}
@startuml
start
:Read ADC;
if (voltage < 3.0V?) then (yes)
  :Trigger Alert;
else (no)
  :Log Normal;
endif
stop
@enduml
`` `

This requirement traces to [SYS-SAFETY-001](@).

## hlr: Temperature Check @HLR-002

> priority: medium

The system shall monitor battery temperature.
```

#### What the Parser Produces

The input above populates the Spec-IR with:

- 1 Specification (SRS-001)
- 2 SpecObjects (HLR-001, HLR-002)
- 4 Attributes (status, priority x2, rationale)
- 1 SpecFloat (fig-voltage-flow, PLANTUML type)
- 2 SpecRelations (XREF_FIGURE to fig-voltage-flow, inferred reference to SYS-SAFETY-001)
- Prose content accumulated to each object's `ast` field

See the dedicated dictionary entries ([specIR-01](@) through [DIC-ATTR-001](@)) for the complete schema of each table.
