---Relation Resolver Handler for SpecCompiler.
---Pipeline handler for ANALYZE phase.
---
---ANALYZE phase mutates data (resolves references).
---Validation is done in VERIFY phase via SQL proof views.
---
---Resolution for # selector uses scoped resolution (closest to global):
---  Step 1: Local float scope (same parent_object_id as source)
---  Step 2: Same specification (unified objects + floats)
---  Step 3: Cross-document (global fallback)
---  At each step: 1 match = resolved, >1 = ambiguous, 0 = next step.
---
---@module relation_resolver
local Queries = require("db.queries")

local M = {
    name = "relation_resolver",
    prerequisites = {"pid_generator"}  -- Runs after PID auto-generation in ANALYZE
}

-- ============================================================================
-- Target Resolution Logic
-- ============================================================================

---Find target for a relation based on selector type and target_text.
---Dispatches to resolver functions registered on data by base relation types.
---@param data DataManager
---@param spec_id string Specification ID
---@param target_text string Raw link target text
---@param selector string Link selector ('@' or '#')
---@param source_object_id integer|nil Source object ID
---@return table|nil target {id, type_ref, kind='object'|'float'}
---@return boolean is_ambiguous
local function find_target(data, spec_id, target_text, selector, source_object_id)
    if not target_text or target_text == "" then
        return nil, false
    end

    local resolver = data:get_resolver(selector)
    if resolver then
        return resolver(data, spec_id, target_text, source_object_id)
    end

    return nil, false
end

---Resolve all unresolved relations for a specification.
---Excludes external relation types (citations) which target external resources.
---Only resolves target columns; type_ref is preserved from insertion-time inference.
---@param data DataManager
---@param spec_id string Specification ID
---@param diagnostics Diagnostics|nil
local function resolve_all_relations(data, spec_id, diagnostics)
    -- Get unresolved relations eligible for object/float target resolution.
    -- Extended selectors like @cite/@citep do not resolve into target columns.
    local unresolved = data:query_all(Queries.resolution.unresolved_relations_standard,
        { spec = spec_id })

    for _, rel in ipairs(unresolved or {}) do
        local target, is_ambiguous = find_target(
            data, spec_id, rel.target_text, rel.link_selector, rel.source_object_id
        )

        if target then
            if target.kind == "object" then
                data:execute(Queries.resolution.resolve_relation_to_object, {
                    id = rel.id,
                    target_object_id = target.id,
                    is_ambiguous = is_ambiguous and 1 or 0
                })
            elseif target.kind == "float" then
                data:execute(Queries.resolution.resolve_relation_to_float, {
                    id = rel.id,
                    target_float_id = target.id,
                    is_ambiguous = is_ambiguous and 1 or 0
                })
            end
        end
        -- Note: Unresolved references are reported via view_relation_unresolved proof in VERIFY phase
    end
end

-- ============================================================================
-- Pipeline Handler
-- ============================================================================

---@param data DataManager
---@param contexts Context[]
---@param diagnostics Diagnostics
function M.on_analyze(data, contexts, diagnostics)
    data:begin_transaction()

    -- Pre-pass: null out stale cross-doc references from cached documents.
    -- When a dirty document's objects are deleted and re-created with new IDs,
    -- cached documents' relations still hold the old target_object_id values.
    data:execute(Queries.resolution.null_dangling_object_targets)
    data:execute(Queries.resolution.null_dangling_float_targets)

    -- Collect specs to resolve: dirty contexts + any cached specs with
    -- newly-unresolved relations (from the null-out above)
    local specs_to_resolve = {}
    for _, ctx in ipairs(contexts) do
        specs_to_resolve[ctx.spec_id or "default"] = true
    end

    local stale_specs = data:query_all(Queries.resolution.specs_with_unresolved_relations)
    for _, row in ipairs(stale_specs or {}) do
        specs_to_resolve[row.specification_ref] = true
    end

    -- Resolve all affected specs
    for spec_id in pairs(specs_to_resolve) do
        resolve_all_relations(data, spec_id, diagnostics)
    end

    data:commit()
end

return M
