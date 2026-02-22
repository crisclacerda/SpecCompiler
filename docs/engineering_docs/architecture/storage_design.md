## Storage Design

### FD: Spec-IR Persistence and Cache Coherency @FD-003

> traceability: [SF-002](@)

**Allocation:** Realized by [CSC-002](@) (Database Persistence) through [CSU-012](@) (Data Manager) and [CSU-010](@) (Build Cache). The database schema is defined in [CSC-006](@) (DB Schema), queries in [CSC-005](@) (DB Queries), and materialized views in [CSC-007](@) (DB Views).

The [TERM-IR](@) persistence function manages the [TERM-SQLITE](@) database that stores all parsed
specification content and provides cache coherency for incremental builds. It encompasses
schema management, the [TERM-EAV](@) storage model, build caching, and output
caching.

**SQLite Persistence**: The data manager ([CSU-012](@)) wraps all database operations,
providing a query API over the Spec-IR schema. The database file is created in the
project's output directory and persists across builds. Schema creation is executed inside
`DataManager.new()`, establishing all content and type tables. WAL mode is enabled for
concurrent read performance.

**Spec-IR Schema**: The content schema ([CSU-013](@)) defines the core entity tables:

- `specifications` — Document-level containers with header AST and metadata
- `spec_objects` — Typed content blocks with AST, file position, and specification scope
- `spec_floats` — Embedded figures, listings, tables with render state
- `spec_views` — Materialized data views (TOC, LOF, traceability matrices)
- `spec_relations` — Links between objects with type inference results
- `spec_attribute_values` — EAV-model attribute storage for object and float properties

The type schema ([CSU-014](@)) defines the metamodel tables that describe valid types,
attribute definitions, and datatype constraints.

**EAV Attribute Model**: Attributes are stored as individual rows in `spec_attribute_values`
rather than as columns, enabling dynamic schema extension through model definitions.
Each attribute row references its parent entity (object or float), attribute definition,
and stores the value as text with type casting at query time.

**[TERM-30](@)**: The build cache ([CSU-010](@)) tracks document content hashes in the
`source_files` table. Before parsing a document, the engine computes its SHA1 hash and
compares against the stored value. Unchanged documents skip parsing entirely and reuse
their cached Spec-IR state. To support incremental builds, the
`build_graph` table tracks include dependencies so that changes to included files also
trigger rebuilds. When the document hash matches, the Build Engine ([CSU-005](@)) queries
the `build_graph` table for all include dependencies recorded during the previous build.
It then computes a SHA1 hash for each include file via the Hash Utilities ([CSU-065](@)).
If an include file is missing, the hash returns nil, which forces a cache miss and a full
document rebuild. The resulting path-to-hash map is compared against the stored values; any
mismatch invalidates the cache and triggers reparsing of the root document.

**[TERM-31](@)**: The output cache tracks generated output files and their input hashes.
Before generating an output file, the emitter checks whether the input hash matches
the stored value. If current, the output generation is skipped. This provides incremental
output generation independent of the build cache.

**Component Interaction**

The storage subsystem is realized through four packages that separate runtime
operations from static definitions.

[csc:database-persistence](#) (Database Persistence) provides the runtime database layer. [csu:database-handler](#)
(Database Handler) wraps raw SQLite operations and connection management, enabling WAL mode
for concurrent reads. [csu:data-manager](#) (Data Manager) builds on the handler to provide the
high-level query API used by all pipeline phases — inserting spec entities during INITIALIZE,
updating references during ANALYZE, and reading assembled content during EMIT. [csu:build-cache](#)
(Build Cache) queries `source_files` and `build_graph` to detect changed documents via SHA1
comparison. [csu:output-cache](#) (Output Cache) tracks generated output files and their input hashes
to skip redundant generation. [csu:proof-view-definitions](#) (Proof View Definitions) materializes SQL proof
views at build time for the VERIFY phase.

[csc:db-schema](#) (DB Schema) defines the database structure through composable modules.
[csu:schema-aggregator](#) (Schema Aggregator) is the entry point, composing: [csu:content-schema](#) (Content Schema)
for the core Spec-IR tables, [csu:type-system-schema](#) (Type System Schema) for attribute and datatype
definitions, [csu:build-schema](#) (Build Schema) for source file and dependency tracking, and
[csu:search-schema](#) (Search Schema) for FTS5 virtual tables.

[csc:db-queries](#) (DB Queries) mirrors the schema structure with composable query modules.
[csu:query-aggregator](#) (Query Aggregator) combines: [csu:content-queries](#) (Content Queries) for spec entity CRUD,
[csu:resolution-queries](#) (Resolution Queries) for cross-reference and relation resolution, [csu:build-queries](#)
(Build Queries) for cache and dependency lookups, [csu:type-queries](#) (Type Queries) for type
definitions and attribute constraints, and [csu:search-queries](#) (Search Queries) for FTS5 population
and search.

[csc:db-views](#) (DB Views) provides materialized SQL views over the Spec-IR data. [csu:views-aggregator](#)
(Views Aggregator) composes: [csu:eav-pivot-views](#) (EAV Pivot Views) for pivoting attribute values into
typed columns, [csu:resolution-views](#) (Resolution Views) for joining relations with resolved targets,
and [csu:public-api-views](#) (Public API Views) for stable query interfaces used by pipeline handlers and
external tools.

```puml:fd-003-storage{caption="Spec-IR Persistence and Cache Coherency"}
@startuml
skinparam backgroundColor #FFFFFF
skinparam sequenceMessageAlign center

participant "CSU Build Engine" as E
participant "CSU Data Manager" as DB
participant "SQLite" as SQL

== Schema Initialization ==
E -> DB: new(db_handler, log)
DB -> SQL: CREATE TABLE specifications
DB -> SQL: CREATE TABLE spec_objects
DB -> SQL: CREATE TABLE spec_floats
DB -> SQL: CREATE TABLE spec_views
DB -> SQL: CREATE TABLE spec_relations
DB -> SQL: CREATE TABLE spec_attribute_values
DB -> SQL: CREATE TABLE source_files
DB -> SQL: CREATE TABLE build_graph

== Build Cache Check ==
E -> E: sha1(document_content)
E -> DB: query source_files(path)
DB --> E: cached_hash

alt hash matches
    E -> DB: query build_graph(root_path)
    DB --> E: includes[]
    E -> E: verify include hashes
    alt all match
        E -> E: skip parsing (use cached IR)
    else include changed
        E -> E: reparse document
    end
else content changed
    E -> E: reparse document
end

== After Parse ==
E -> DB: INSERT/UPDATE spec entities
E -> DB: UPDATE source_files hash
E -> DB: UPDATE build_graph entries

== Output Cache ==
E -> DB: query output_cache(spec_id, format)
alt output current
    E -> E: skip generation
else stale
    E -> E: generate output
    E -> DB: UPDATE output_cache
end
@enduml
```
