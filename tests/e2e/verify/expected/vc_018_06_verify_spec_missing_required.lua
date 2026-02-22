-- Test oracle for VC-VERIFY-005: Specification-level required attribute errors.

return function(_, helpers)
    if not helpers.expect_errors then
        return false, "This test requires expect_errors mode"
    end

    local diag = helpers.diagnostics
    if not diag then
        return false, "No diagnostics available"
    end

    local detected_codes = {}
    for _, e in ipairs(diag.errors or {}) do
        if e.code then
            detected_codes[e.code] = (detected_codes[e.code] or 0) + 1
        end
    end
    for _, w in ipairs(diag.warnings or {}) do
        if w.code then
            detected_codes[w.code] = (detected_codes[w.code] or 0) + 1
        end
    end

    if not detected_codes["spec_missing_required"] then
        local detected_list = {}
        for code, count in pairs(detected_codes) do
            detected_list[#detected_list + 1] = string.format("%s (%d)", code, count)
        end
        table.sort(detected_list)
        return false, "Expected spec_missing_required but it was not detected. Detected: " .. table.concat(detected_list, ", ")
    end

    return true
end
