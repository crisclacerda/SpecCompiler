## SPEC-IR Database Schema

### Overview

The Specification [TERM-IR](@) (SPEC-IR) is implemented as a [TERM-SQLITE](@) schema composed from:

- `src/db/schema/types.lua`
- `src/db/schema/content.lua`
- `src/db/schema/build.lua`
- `src/db/schema/search.lua`
- `src/db/schema/init.lua` (combines all schema modules, initializes EAV pivot views)

The schema has four domains:

| Domain | Tables |
|---|---|
| Type system | `spec_specification_types`, `spec_object_types`, `spec_float_types`, `spec_relation_types`, `spec_view_types`, `datatype_definitions`, `spec_attribute_types`, `enum_values`, `implicit_type_aliases`, `implicit_spec_type_aliases` |
| Content | `specifications`, `spec_objects`, `spec_floats`, `spec_relations`, `spec_views`, `spec_attribute_values` |
| Build cache | `build_graph`, `source_files`, `output_cache` |
| Search (FTS5) | `fts_objects`, `fts_attributes`, `fts_floats` |

> Note: FTS5 creates shadow tables (`*_data`, `*_idx`, `*_docsize`, etc.) automatically; they are managed by SQLite internals.

### ER-001: Type + Content

```plantuml:er-specir-core
@startuml
title SPEC-IR ER (Core Types + Content)

hide methods
hide stereotypes
skinparam linetype ortho

entity "spec_specification_types" as spec_specification_types {
  * identifier : TEXT
  --
  long_name : TEXT
  description : TEXT
  extends : TEXT
  is_default : INTEGER
}

entity "spec_object_types" as spec_object_types {
  * identifier : TEXT
  --
  long_name : TEXT
  description : TEXT
  extends : TEXT
  is_composite : INTEGER
  is_required : INTEGER
  is_default : INTEGER
  pid_prefix : TEXT
  pid_format : TEXT
  aliases : TEXT
}

entity "spec_float_types" as spec_float_types {
  * identifier : TEXT
  --
  long_name : TEXT
  description : TEXT
  caption_format : TEXT
  counter_group : TEXT
  aliases : TEXT
  needs_external_render : INTEGER
}

entity "spec_relation_types" as spec_relation_types {
  * identifier : TEXT
  --
  long_name : TEXT
  description : TEXT
  extends : TEXT
  source_type_ref : TEXT
  target_type_ref : TEXT
  link_selector : TEXT
  source_attribute : TEXT
}

entity "spec_view_types" as spec_view_types {
  * identifier : TEXT
  --
  long_name : TEXT
  description : TEXT
  counter_group : TEXT
  aliases : TEXT
  inline_prefix : TEXT
  materializer_type : TEXT
  view_subtype_ref : TEXT
  needs_external_render : INTEGER
}

entity "datatype_definitions" as datatype_definitions {
  * identifier : TEXT
  --
  long_name : TEXT
  type : TEXT
}

entity "spec_attribute_types" as spec_attribute_types {
  * identifier : TEXT
  --
  owner_type_ref : TEXT
  long_name : TEXT
  datatype_ref : TEXT
  min_occurs : INTEGER
  max_occurs : INTEGER
  min_value : REAL
  max_value : REAL
}

entity "enum_values" as enum_values {
  * identifier : TEXT
  --
  datatype_ref : TEXT
  key : TEXT
  sequence : INTEGER
}

entity "specifications" as specifications {
  * identifier : TEXT
  --
  root_path : TEXT
  long_name : TEXT
  type_ref : TEXT
  pid : TEXT
  header_ast : JSON
  body_ast : JSON
}

entity "spec_objects" as spec_objects {
  * id : INTEGER
  --
  content_sha : TEXT
  specification_ref : TEXT
  type_ref : TEXT
  from_file : TEXT
  file_seq : INTEGER
  pid : TEXT
  pid_prefix : TEXT
  pid_sequence : INTEGER
  pid_auto_generated : INTEGER
  title_text : TEXT
  label : TEXT
  level : INTEGER
  start_line : INTEGER
  end_line : INTEGER
  ast : JSON
  content_xhtml : TEXT
}

entity "spec_floats" as spec_floats {
  * id : INTEGER
  --
  content_sha : TEXT
  specification_ref : TEXT
  type_ref : TEXT
  from_file : TEXT
  file_seq : INTEGER
  start_line : INTEGER
  label : TEXT
  number : INTEGER
  caption : TEXT
  pandoc_attributes : JSON
  raw_content : TEXT
  raw_ast : JSON
  resolved_ast : JSON
  parent_object_id : INTEGER
  anchor : TEXT
  syntax_key : TEXT
}

entity "spec_relations" as spec_relations {
  * id : INTEGER
  --
  content_sha : TEXT
  specification_ref : TEXT
  source_object_id : INTEGER
  target_text : TEXT
  target_object_id : INTEGER
  target_float_id : INTEGER
  type_ref : TEXT
  is_ambiguous : INTEGER
  from_file : TEXT
  link_line : INTEGER
  source_attribute : TEXT
  link_selector : TEXT
}

entity "spec_views" as spec_views {
  * id : INTEGER
  --
  content_sha : TEXT
  specification_ref : TEXT
  view_type_ref : TEXT
  from_file : TEXT
  file_seq : INTEGER
  start_line : INTEGER
  raw_ast : JSON
  resolved_ast : JSON
  resolved_data : JSON
}

entity "spec_attribute_values" as spec_attribute_values {
  * id : INTEGER
  --
  content_sha : TEXT
  specification_ref : TEXT
  owner_object_id : INTEGER
  owner_float_id : INTEGER
  name : TEXT
  raw_value : TEXT
  string_value : TEXT
  int_value : INTEGER
  real_value : REAL
  bool_value : INTEGER
  date_value : TEXT
  enum_ref : TEXT
  ast : JSON
  datatype : TEXT
  xhtml_value : TEXT
}

entity "implicit_type_aliases" as implicit_type_aliases {
  * alias : TEXT
  --
  object_type_id : TEXT
}

entity "implicit_spec_type_aliases" as implicit_spec_type_aliases {
  * alias : TEXT
  --
  spec_type_id : TEXT
}

specifications }o--|| spec_specification_types : type_ref
spec_objects }o--|| specifications : specification_ref
spec_objects }o--|| spec_object_types : type_ref
spec_floats }o--|| specifications : specification_ref
spec_floats }o--|| spec_float_types : type_ref
spec_floats }o--o| spec_objects : parent_object_id
spec_relations }o--|| specifications : specification_ref
spec_relations }o--|| spec_objects : source_object_id
spec_relations }o--o| spec_objects : target_object_id
spec_relations }o--o| spec_floats : target_float_id
spec_relations }o--o| spec_relation_types : type_ref
spec_views }o--|| specifications : specification_ref
spec_views }o--|| spec_view_types : view_type_ref
spec_attribute_values }o--|| specifications : specification_ref
spec_attribute_values }o--o| spec_objects : owner_object_id
spec_attribute_values }o--o| spec_floats : owner_float_id
spec_attribute_values }o--o| enum_values : enum_ref
spec_attribute_types }o--|| spec_object_types : owner_type_ref
spec_attribute_types }o--|| datatype_definitions : datatype_ref
enum_values }o--|| datatype_definitions : datatype_ref
implicit_type_aliases }o--|| spec_object_types : object_type_id
implicit_spec_type_aliases }o--|| spec_specification_types : spec_type_id
spec_relation_types }o--o| spec_object_types : source_type_ref
spec_relation_types }o--o| spec_object_types : target_type_ref

@enduml
```

### ER-002: Build + Search

```plantuml:er-specir-build-search
@startuml
title SPEC-IR ER (Build Cache + Search)

hide methods
hide stereotypes
skinparam linetype ortho

entity "build_graph" as build_graph {
  * root_path : TEXT
  * node_path : TEXT
  --
  node_sha1 : TEXT
}

entity "source_files" as source_files {
  * path : TEXT
  --
  sha1 : TEXT
}

entity "output_cache" as output_cache {
  * spec_id : TEXT
  * output_path : TEXT
  --
  pir_hash : TEXT
  generated_at : TEXT
}

entity "fts_objects" as fts_objects <<FTS5>> {
  identifier : TEXT (UNINDEXED)
  object_type : TEXT (UNINDEXED)
  spec_id : TEXT (UNINDEXED)
  title : TEXT
  content : TEXT
  raw_source : TEXT
}

entity "fts_attributes" as fts_attributes <<FTS5>> {
  owner_ref : TEXT (UNINDEXED)
  spec_id : TEXT (UNINDEXED)
  attr_name : TEXT (UNINDEXED)
  attr_type : TEXT (UNINDEXED)
  attr_value : TEXT
}

entity "fts_floats" as fts_floats <<FTS5>> {
  identifier : TEXT (UNINDEXED)
  float_type : TEXT (UNINDEXED)
  spec_id : TEXT (UNINDEXED)
  parent_ref : TEXT (UNINDEXED)
  caption : TEXT
  raw_source : TEXT
}

entity "specifications" as specifications {
  * identifier : TEXT
}

entity "spec_objects" as spec_objects {
  * id : INTEGER
}

entity "spec_floats" as spec_floats {
  * id : INTEGER
}

specifications ||..o{ output_cache : spec_id
spec_objects ||..o{ fts_objects : identifier
spec_floats ||..o{ fts_floats : identifier
spec_objects ||..o{ fts_attributes : owner_ref

@enduml
```

### Notes

- ReqIF cache columns (`spec_objects.content_xhtml`, `spec_attribute_values.xhtml_value`) are part of the main `src/db/schema/content.lua` schema.
- `build_graph`, `source_files`, and `output_cache` support incremental builds and output invalidation.
- FTS tables are populated for cross-document search and may be absent/empty until indexing runs.
