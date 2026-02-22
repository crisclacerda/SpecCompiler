---Simplified IR Data Manager for SpecCompiler.

local Schema = require('db.schema')

local M = {}

function M.new(db_handler, log)
    local self = setmetatable({}, { __index = M })
    self.db = db_handler
    self.log = log
    self._resolvers = {}

    -- Initialize schema from domain-specific modules
    self.db:exec_sql(Schema.SQL)

    return self
end

---Register a link-selector resolver function.
---Called by type_loader when loading base relation types (e.g. PID_REF, LABEL_REF).
---@param selector string Link selector ("@", "#", etc.)
---@param fn function Resolver function(data, spec_id, target_text, source_object_id)
function M:register_resolver(selector, fn)
    self._resolvers[selector] = fn
end

---Get the resolver function for a link selector.
---@param selector string|nil Link selector
---@return function|nil resolver
function M:get_resolver(selector)
    return selector and self._resolvers[selector] or nil
end

function M:query_all(sql, params)
    return self.db:query_all(sql, params or {})
end

function M:query_one(sql, params)
    local results = self.db:query_all(sql, params or {})
    return results and results[1] or nil
end

function M:execute(sql, params)
    local stmt = self.db:prepare_statement(sql, "execute")
    local res = self.db:execute_prepared(stmt, params)
    stmt:finalize()
    return res
end

---Begin a transaction for batch operations.
---Dramatically improves performance for multiple INSERTs (100x or more).
---@return boolean success
function M:begin_transaction()
    return self.db:begin_transaction()
end

---Commit the current transaction.
---@return boolean success
function M:commit()
    return self.db:commit()
end

---Rollback the current transaction on error.
---@return boolean success
function M:rollback()
    return self.db:rollback()
end

---Get the rowid of the last INSERT.
---Used with INTEGER PRIMARY KEY tables to retrieve auto-assigned ids.
---@return integer rowid
function M:last_insert_rowid()
    return self.db:last_insert_rowid()
end

return M
