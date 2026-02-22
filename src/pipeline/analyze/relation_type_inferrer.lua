---Relation Type Inferrer Handler for SpecCompiler.
---Pipeline handler for ANALYZE phase.
---
---Runs after relation_resolver within ANALYZE phase.
---Infers relation types using 4-dimension specificity matching:
---  (selector, source_attribute, source_type, target_type)
---Each non-null rule constraint must match; most specific rule wins.
---If top specificity ties between two rules, inference is ambiguous.
---
---@module relation_type_inferrer
local logger = require("infra.logger")
local Queries = require("db.queries")

local M = {
    name = "relation_type_inferrer",
    prerequisites = {"relation_resolver"}
}

-- Cache for inference rules (loaded from database)
local inference_rules_cache = nil

---Clear module-level caches (required for re-entrant engine.run_project calls).
function M.clear_cache()
    inference_rules_cache = nil
end

---Load relation inference rules from the database.
---Rules are matched by selector/source_attribute/source_type/target_type specificity.
---@param data DataManager
---@return table rules Array of {source, target, attr, rel_type, selector}
local function load_inference_rules(data)
    if inference_rules_cache then
        return inference_rules_cache
    end

    inference_rules_cache = data:query_all(Queries.resolution.inference_rules) or {}
    return inference_rules_cache
end

---Match a CSV or scalar constraint against an input value.
---@param csv_or_scalar string|nil
---@param value string|nil
---@param case_insensitive boolean|nil
---@return boolean
local function csv_matches(csv_or_scalar, value, case_insensitive)
    if csv_or_scalar == nil then
        return true
    end
    if not value then
        return false
    end
    local needle = value
    if case_insensitive then
        needle = needle:lower()
    end
    for item in csv_or_scalar:gmatch("[^,]+") do
        local candidate = item:match("^%s*(.-)%s*$")
        if case_insensitive then
            candidate = candidate:lower()
        end
        if candidate == needle then
            return true
        end
    end
    return false
end

---Infer relation type with 4-dimension specificity matching.
---Each non-null rule constraint must match; most specific rule wins.
---If top specificity ties between two rules, inference is ambiguous.
---@param data DataManager
---@param source_type string|nil Source object's type_ref (pre-resolved)
---@param source_attribute string|nil Attribute name containing the link (nil for body text)
---@param link_selector string|nil Link selector ("@", "#", "@cite", "@citep", ...)
---@param target_type string|nil Resolved target's type (nil if not yet resolved)
---@return string|nil inferred_type
---@return string|nil tie_type_a
---@return string|nil tie_type_b
local function match_relation_type(data, source_type, source_attribute, link_selector, target_type)

    -- Load inference rules (cached)
    local rules = load_inference_rules(data)

    local candidates = {}

    for _, rule in ipairs(rules) do
        local specificity = 0
        local matches = true

        -- 1. Selector
        if rule.selector ~= nil then
            if csv_matches(rule.selector, link_selector, false) then
                specificity = specificity + 1
            else
                matches = false
            end
        end

        -- 2. Source attribute
        if matches and rule.attr ~= nil then
            if csv_matches(rule.attr, source_attribute, true) then
                specificity = specificity + 1
            else
                matches = false
            end
        end

        -- 3. Source type
        if matches and rule.source ~= nil then
            if csv_matches(rule.source, source_type, false) then
                specificity = specificity + 1
            else
                matches = false
            end
        end

        -- 4. Target type
        if matches and rule.target ~= nil then
            if csv_matches(rule.target, target_type, false) then
                specificity = specificity + 1
            else
                matches = false
            end
        end

        if matches then
            table.insert(candidates, { rule = rule, specificity = specificity })
        end
    end

    table.sort(candidates, function(a, b)
        return a.specificity > b.specificity
    end)

    if #candidates >= 2 and candidates[1].specificity == candidates[2].specificity then
        return nil, candidates[1].rule.rel_type, candidates[2].rule.rel_type
    end

    return candidates[1] and candidates[1].rule.rel_type or nil, nil, nil
end

---Single inference point for relation types.
---Process ALL untyped relations using 4-dimension scoring.
---Runs after relation_resolver within ANALYZE phase.
function M.on_analyze(data, contexts, diagnostics)
    data:begin_transaction()
    for _, ctx in ipairs(contexts) do
        local spec_id = ctx.spec_id or "default"

        local untyped = data:query_all(Queries.resolution.select_untyped_relations_for_inference, { spec_id = spec_id })

        local inferred_count = 0
        for _, rel in ipairs(untyped or {}) do
            -- Single inference with 4 dimensions and tie detection
            local inferred, tie_a, tie_b = match_relation_type(
                data, rel.source_type, rel.source_attribute,
                rel.link_selector, rel.target_type
            )
            if inferred then
                data:execute(Queries.resolution.update_relation_type, { id = rel.id, type_ref = inferred })
                inferred_count = inferred_count + 1
            elseif tie_a and tie_b then
                -- Ambiguous inference: mark for view_relation_ambiguous proof in VERIFY
                data:execute(Queries.resolution.mark_relation_ambiguous, { id = rel.id })
            end
            -- No match -> type stays NULL -> VERIFY flags it
        end

        if inferred_count > 0 then
            logger.info(string.format("Inferred type for %d relations in %s", inferred_count, spec_id))
        end
    end
    data:commit()
end

return M
