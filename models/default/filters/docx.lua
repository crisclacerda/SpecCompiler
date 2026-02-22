---Native Pandoc Lua filter for DOCX output.
---Converts speccompiler format markers to OOXML for Word output.
---
---This filter is compatible with pandoc --lua-filter for external CLI execution.
---
---Features:
---  - Converts RawBlock("speccompiler", "page-break") to OOXML page break
---  - Converts RawBlock("speccompiler", "vertical-space:NNNN") to OOXML spacing (twips)
---  - Converts RawBlock("speccompiler", "bookmark-start:ID:NAME") to OOXML bookmark start
---  - Converts RawBlock("speccompiler", "bookmark-end:ID") to OOXML bookmark end
---  - Converts RawBlock("speccompiler", "math-omml:OMML") to OOXML math
---  - Converts speccompiler-caption Div to OOXML caption with SEQ field
---  - Converts speccompiler-numbered-equation Div to OOXML numbered equation
---  - Converts RawInline("speccompiler", "view:NAME:CONTENT") to OOXML inline
---
---@usage pandoc --lua-filter=docx.lua -f json -t docx input.json -o output.docx
---@module models.default.filters.docx

local xml = require("infra.format.xml")

-- ============================================================================
-- OOXML DOM Construction Helpers
-- ============================================================================

-- A4 dimensions in twips
local A4_WIDTH = 11906
local A4_HEIGHT = 16838

---Build field code run sequence (begin, instrText, separate, placeholder, end).
---@param instr string Field instruction text (e.g., " SEQ Figure \\* ARABIC ")
---@param placeholder string|nil Placeholder text (default "1")
---@return table Array of xml nodes
local function build_field_code(instr, placeholder)
    placeholder = placeholder or "1"
    return {
        xml.node("w:r", {}, {xml.node("w:fldChar", {["w:fldCharType"] = "begin"})}),
        xml.node("w:r", {}, {xml.node("w:instrText", {["xml:space"] = "preserve"}, {xml.text(instr)})}),
        xml.node("w:r", {}, {xml.node("w:fldChar", {["w:fldCharType"] = "separate"})}),
        xml.node("w:r", {}, {xml.node("w:t", {}, {xml.text(placeholder)})}),
        xml.node("w:r", {}, {xml.node("w:fldChar", {["w:fldCharType"] = "end"})}),
    }
end

---Append all elements from an array into a target array.
---@param target table Target array
---@param source table Source array of elements to append
local function append_all(target, source)
    for _, v in ipairs(source) do
        table.insert(target, v)
    end
end

---Generate OOXML for a page break.
---@return string OOXML page break paragraph
local function ooxml_page_break()
    return xml.serialize_element(xml.node("w:p", {}, {
        xml.node("w:r", {}, {
            xml.node("w:br", {["w:type"] = "page"})
        })
    }))
end

---Generate OOXML for section break with orientation change.
---Used for position="p" landscape pages.
---@param orientation string "portrait" or "landscape"
---@return string OOXML section break paragraph
local function ooxml_section_break_orientation(orientation)
    local w, h
    local pgSz_attrs
    if orientation == "landscape" then
        -- Swap dimensions for landscape
        w = A4_HEIGHT
        h = A4_WIDTH
        pgSz_attrs = {["w:w"] = tostring(w), ["w:h"] = tostring(h), ["w:orient"] = "landscape"}
    else
        w = A4_WIDTH
        h = A4_HEIGHT
        pgSz_attrs = {["w:w"] = tostring(w), ["w:h"] = tostring(h)}
    end

    return xml.serialize_element(xml.node("w:p", {}, {
        xml.node("w:pPr", {}, {
            xml.node("w:sectPr", {}, {
                xml.node("w:pgSz", pgSz_attrs),
                xml.node("w:type", {["w:val"] = "nextPage"}),
            })
        })
    }))
end

---Generate OOXML for vertical spacing.
---@param twips number Spacing in twips (1440 twips = 1 inch)
---@return string OOXML for spacing paragraph
local function ooxml_vertical_space(twips)
    return xml.serialize_element(xml.node("w:p", {}, {
        xml.node("w:pPr", {}, {
            xml.node("w:spacing", {["w:before"] = tostring(twips)})
        })
    }))
end

---Generate OOXML for bookmark start.
---@param bm_id number Bookmark ID
---@param bm_name string Bookmark name
---@return string OOXML bookmark start
local function ooxml_bookmark_start(bm_id, bm_name)
    return xml.serialize_element(xml.node("w:bookmarkStart", {
        ["w:id"] = tostring(bm_id),
        ["w:name"] = bm_name,
    }))
end

---Generate OOXML for bookmark end.
---@param bm_id number Bookmark ID
---@return string OOXML bookmark end
local function ooxml_bookmark_end(bm_id)
    return xml.serialize_element(xml.node("w:bookmarkEnd", {
        ["w:id"] = tostring(bm_id),
    }))
end

---Generate OOXML caption paragraph with SEQ field.
---@param prefix string Caption prefix (e.g., "Figure", "Table")
---@param seq_name string SEQ field name
---@param separator string Separator after number (e.g., ":", "-")
---@param caption string Caption text
---@param style string Paragraph style
---@param keep_with_next boolean|nil If true, adds keepNext to prevent orphaning
---@return string OOXML caption paragraph
local function ooxml_caption(prefix, seq_name, separator, caption, style, keep_with_next)
    local pPr_children = {
        xml.node("w:pStyle", {["w:val"] = style}),
    }
    if keep_with_next then
        table.insert(pPr_children, xml.node("w:keepNext"))
    end

    local children = {
        xml.node("w:pPr", {}, pPr_children),
        -- Prefix run (e.g., "Figure ")
        xml.node("w:r", {}, {
            xml.node("w:t", {["xml:space"] = "preserve"}, {xml.text(prefix .. " ")}),
        }),
    }

    -- SEQ field code runs
    append_all(children, build_field_code(" SEQ " .. seq_name .. " \\* ARABIC "))

    -- Separator and caption text
    table.insert(children, xml.node("w:r", {}, {
        xml.node("w:t", {["xml:space"] = "preserve"}, {xml.text(" " .. separator .. " " .. caption)}),
    }))

    return xml.serialize_element(xml.node("w:p", {}, children))
end

---Generate OOXML for numbered equation using tab-stop layout.
---Uses a single paragraph with center tab (equation) and right tab (number).
---This is the traditional academic approach - no table constraints.
---@param omml string OMML math content
---@param seq_name string SEQ field name (e.g., "Equation")
---@param number string|number Equation number
---@param identifier string|nil Bookmark identifier for cross-references
---@return string OOXML for numbered equation
local function ooxml_numbered_equation(omml, seq_name, number, identifier)
    local bookmark_start_xml = ""
    local bookmark_end_xml = ""

    -- Add bookmarks for cross-reference if identifier provided
    if identifier and identifier ~= "" then
        -- Generate simple numeric ID from identifier
        local bm_id = 0
        for i = 1, #identifier do
            bm_id = (bm_id * 31 + identifier:byte(i)) % 100000
        end
        bm_id = bm_id + 1
        bookmark_start_xml = xml.serialize_element(xml.node("w:bookmarkStart", {
            ["w:id"] = tostring(bm_id),
            ["w:name"] = identifier,
        }))
        bookmark_end_xml = xml.serialize_element(xml.node("w:bookmarkEnd", {
            ["w:id"] = tostring(bm_id),
        }))
    end

    -- Tab-stop approach: center tab at ~50% (4680 twips), right tab at 100% (9360 twips)
    -- Standard US Letter/A4 text width is ~6.5" = 9360 twips
    -- Equation centered via center tab, number right-aligned via right tab
    local children = {
        xml.node("w:pPr", {}, {
            xml.node("w:tabs", {}, {
                xml.node("w:tab", {["w:val"] = "center", ["w:pos"] = "4680"}),
                xml.node("w:tab", {["w:val"] = "right", ["w:pos"] = "9360"}),
            }),
        }),
        -- Tab to center position
        xml.node("w:r", {}, {xml.node("w:tab")}),
        -- Pre-formed OMML content
        xml.raw(omml),
        -- Tab to right position
        xml.node("w:r", {}, {xml.node("w:tab")}),
        -- Bookmark start (pre-formed OOXML, may be empty)
        xml.raw(bookmark_start_xml),
        -- Opening parenthesis
        xml.node("w:r", {}, {xml.node("w:t", {}, {xml.text("(")})}),
    }

    -- SEQ field code runs
    append_all(children, build_field_code(
        " SEQ " .. seq_name .. " \\* ARABIC ",
        tostring(number or "1")
    ))

    -- Closing parenthesis and bookmark end
    table.insert(children, xml.node("w:r", {}, {xml.node("w:t", {}, {xml.text(")")})}))
    table.insert(children, xml.raw(bookmark_end_xml))

    return xml.serialize_element(xml.node("w:p", {}, children))
end

-- ============================================================================
-- Cover Page Semantic Div Support
-- ============================================================================

---Map of cover-page semantic CSS classes to Word paragraph style IDs.
local COVER_CLASS_MAP = {
    ["cover-title"]    = "CoverTitle",
    ["cover-subtitle"] = "CoverSubtitle",
    ["cover-author"]   = "CoverAuthor",
    ["cover-date"]     = "CoverDate",
    ["cover-docid"]    = "CoverDocId",
    ["cover-version"]  = "CoverVersion",
}

---Generate OOXML for a styled paragraph (used by cover page semantic divs).
---@param text string Paragraph text
---@param style string Word paragraph style ID
---@return string OOXML styled paragraph
local function ooxml_styled_para(text, style)
    return xml.serialize_element(xml.node("w:p", {}, {
        xml.node("w:pPr", {}, {
            xml.node("w:pStyle", {["w:val"] = style})
        }),
        xml.node("w:r", {}, {
            xml.node("w:t", {["xml:space"] = "preserve"}, {xml.text(text)})
        })
    }))
end

-- ============================================================================
-- Marker Parsing
-- ============================================================================

---Parse a speccompiler marker text.
---@param text string Marker text (e.g., "page-break", "vertical-space:1440")
---@return string marker_type Type of marker
---@return string|nil value Optional value for parameterized markers
local function parse_marker(text)
    local marker_type, value = text:match("^([^:]+):?(.*)$")
    if value == "" then
        value = nil
    end
    return marker_type, value
end

---Check if a Div has a specific class.
---@param div pandoc.Div The div to check
---@param class_name string Class name to look for
---@return boolean has_class True if div has the class
local function has_class(div, class_name)
    for _, c in ipairs(div.classes or {}) do
        if c == class_name then
            return true
        end
    end
    return false
end

---Get attribute value from Div.
---@param div pandoc.Div The div
---@param attr_name string Attribute name
---@return string|nil Attribute value
local function get_attr(div, attr_name)
    if div.attr and div.attr.attributes then
        return div.attr.attributes[attr_name]
    end
    return nil
end

-- ============================================================================
-- RawBlock Handler
-- ============================================================================

---Convert a speccompiler RawBlock to OOXML.
---@param block pandoc.RawBlock The block to convert
---@return pandoc.RawBlock|nil Converted OOXML block, or nil to remove
local function convert_speccompiler_block(block)
    local text = block.text

    -- Handle bookmark-start:ID:NAME
    local bm_id, bm_name = text:match("^bookmark%-start:(%d+):(.+)$")
    if bm_id and bm_name then
        return pandoc.RawBlock("openxml", ooxml_bookmark_start(tonumber(bm_id), bm_name))
    end

    -- Handle bookmark-end:ID
    local end_id = text:match("^bookmark%-end:(%d+)$")
    if end_id then
        return pandoc.RawBlock("openxml", ooxml_bookmark_end(tonumber(end_id)))
    end

    -- Handle math-omml:OMML (for DOCX output)
    local omml = text:match("^math%-omml:(.+)$")
    if omml then
        return pandoc.RawBlock("openxml", omml)
    end

    -- Handle math-mathml:MATHML (skip for DOCX - we prefer OMML)
    if text:match("^math%-mathml:") then
        return {}  -- Remove - DOCX uses OMML
    end

    -- Parse simple markers
    local marker_type, value = parse_marker(text)

    if marker_type == "page-break" then
        return pandoc.RawBlock("openxml", ooxml_page_break())

    elseif marker_type == "vertical-space" then
        local twips = tonumber(value)
        if twips and twips > 0 then
            return pandoc.RawBlock("openxml", ooxml_vertical_space(twips))
        else
            -- Default to 1 inch (1440 twips) if no valid value
            return pandoc.RawBlock("openxml", ooxml_vertical_space(1440))
        end

    elseif marker_type == "section-break-before" then
        -- Section break with orientation for position="p"
        local orientation = value or "portrait"
        return pandoc.RawBlock("openxml", ooxml_section_break_orientation(orientation))

    elseif marker_type == "section-break-after" then
        -- Section break back to portrait after float page
        local orientation = value or "portrait"
        return pandoc.RawBlock("openxml", ooxml_section_break_orientation(orientation))

    elseif marker_type == "float-position-start" then
        -- Pass through to postprocessor as OOXML comment marker
        -- Format: float-position-start:POSITION:TYPE
        return pandoc.RawBlock("openxml",
            string.format('<!-- speccompiler:float-position-start:%s -->', value or "h:FIGURE"))

    elseif marker_type == "float-position-end" then
        -- End marker for postprocessor
        return pandoc.RawBlock("openxml", '<!-- speccompiler:float-position-end -->')

    else
        -- Unknown speccompiler marker - remove
        return {}
    end
end

---Convert a speccompiler RawInline to OOXML.
---@param inline pandoc.RawInline The inline to convert
---@return pandoc.RawInline|nil Converted OOXML inline, or nil to remove
local function convert_speccompiler_inline(inline)
    local text = inline.text

    -- Handle inline-math-omml:OMML (for DOCX output)
    local inline_omml = text:match("^inline%-math%-omml:(.+)$")
    if inline_omml then
        return pandoc.RawInline("openxml", inline_omml)
    end

    -- Handle inline-math-mathml:MATHML (skip for DOCX - we prefer OMML)
    if text:match("^inline%-math%-mathml:") then
        return {}  -- Remove - DOCX uses OMML
    end

    -- Handle view:NAME:CONTENT - view content is already OOXML
    local view_name, view_content = text:match("^view:([^:]+):(.+)$")
    if view_name and view_content then
        return pandoc.RawInline("openxml", view_content)
    end

    -- Unknown inline marker - remove
    return {}
end

-- ============================================================================
-- Div Handlers
-- ============================================================================

---Convert speccompiler-caption Div to OOXML.
---@param div pandoc.Div The caption div
---@return pandoc.RawBlock OOXML caption
local function convert_caption_div(div)
    local seq_name = get_attr(div, "seq-name") or "Figure"
    local prefix = get_attr(div, "prefix") or "Figure"
    local separator = get_attr(div, "separator") or ":"
    local style = get_attr(div, "style") or "Caption"

    -- Extract caption text from Div content
    local caption = pandoc.utils.stringify(div.content)

    -- Caption comes before content, so use keepNext to prevent orphaning
    return pandoc.RawBlock("openxml", ooxml_caption(prefix, seq_name, separator, caption, style, true))
end

---Convert speccompiler-numbered-equation Div to OOXML.
---@param div pandoc.Div The equation div
---@return pandoc.RawBlock|nil OOXML numbered equation
local function convert_equation_div(div)
    local seq_name = get_attr(div, "seq-name") or "Equation"
    local number = get_attr(div, "number") or "1"
    local identifier = get_attr(div, "identifier") or ""

    -- Extract OMML from nested math-omml RawBlock (prefer OMML for DOCX)
    local omml = ""
    for _, block in ipairs(div.content) do
        if block.t == "RawBlock" and block.format == "speccompiler" then
            local content = block.text:match("^math%-omml:(.+)$")
            if content then
                omml = content
                break
            end
        end
    end

    if omml == "" then
        -- No math content - return nil to remove
        return {}
    end

    return pandoc.RawBlock("openxml", ooxml_numbered_equation(omml, seq_name, number, identifier))
end

---Convert speccompiler-table Div.
---For now, just unwrap the content - Pandoc handles table conversion.
---@param div pandoc.Div The table div
---@return table Content blocks
local function convert_table_div(div)
    -- Just return the content; Pandoc handles table-to-OOXML conversion
    return div.content
end

---Convert speccompiler-positioned-float Div.
---Wraps content with position markers for postprocessor to convert to anchored OOXML.
---@param div pandoc.Div The positioned float div
---@return table Content blocks with position markers
local function convert_positioned_float_div(div)
    local position = get_attr(div, "data-position") or "h"
    local orientation = get_attr(div, "data-orientation")
    local float_type = get_attr(div, "data-float-type") or "FIGURE"

    local result = {}

    -- For position="p" (isolated page), add section break before (with orientation)
    if position == "p" then
        local orient = orientation or "portrait"
        -- Emit OOXML section break directly (not speccompiler marker)
        table.insert(result, pandoc.RawBlock("openxml",
            ooxml_section_break_orientation(orient)))
    end

    -- Add marker indicating float position for postprocessor
    -- Emit OOXML comment directly (not speccompiler marker, since RawBlock handler
    -- won't re-process elements returned from Div handler in same filter pass)
    table.insert(result, pandoc.RawBlock("openxml",
        string.format('<!-- speccompiler:float-position-start:%s:%s -->', position, float_type)))

    -- Include the float content
    for _, block in ipairs(div.content) do
        table.insert(result, block)
    end

    -- End position marker (OOXML comment)
    table.insert(result, pandoc.RawBlock("openxml", '<!-- speccompiler:float-position-end -->'))

    -- For position="p", add section break after to return to normal
    if position == "p" then
        table.insert(result, pandoc.RawBlock("openxml",
            ooxml_section_break_orientation("portrait")))
    end

    return result
end

-- ============================================================================
-- Link Extension Replacement
-- ============================================================================

---Replace .ext placeholder with .docx in cross-document links.
---@param link pandoc.Link The link to process
---@return pandoc.Link Modified link
local function replace_ext_placeholder(link)
    if link.target then
        link.target = link.target:gsub("%.ext#", ".docx#")
        link.target = link.target:gsub("%.ext$", ".docx")
    end
    return link
end

-- ============================================================================
-- Filter Table (shared between module API and native Pandoc mode)
-- ============================================================================

-- Pass 1: Div containers must be processed first.
-- Equation and caption Divs inspect inner speccompiler RawBlocks;
-- bottom-up traversal in a single pass would convert those RawBlocks
-- before the Div handler sees them, breaking extraction.
local FILTER_PASS1 = {
    Div = function(div)
        if has_class(div, "speccompiler-caption") then
            return convert_caption_div(div)
        elseif has_class(div, "speccompiler-numbered-equation") then
            return convert_equation_div(div)
        elseif has_class(div, "speccompiler-table") then
            return convert_table_div(div)
        elseif has_class(div, "speccompiler-positioned-float") then
            return convert_positioned_float_div(div)
        end

        -- Cover page semantic divs -> styled OOXML paragraphs
        for _, class in ipairs(div.classes or {}) do
            local style = COVER_CLASS_MAP[class]
            if style then
                local text = pandoc.utils.stringify(div.content)
                return pandoc.RawBlock("openxml", ooxml_styled_para(text, style))
            end
        end

        -- Pass through other Divs unchanged
        return div
    end,
}

-- Pass 2: Individual elements (RawBlocks now safe to convert)
local FILTER_PASS2 = {
    RawBlock = function(block)
        if block.format == "speccompiler" then
            return convert_speccompiler_block(block)
        end
        -- Pass through other RawBlocks unchanged
        return block
    end,

    RawInline = function(inline)
        if inline.format == "speccompiler" then
            return convert_speccompiler_inline(inline)
        end
        -- Pass through other RawInlines unchanged
        return inline
    end,

    Link = function(link)
        return replace_ext_placeholder(link)
    end
}

-- ============================================================================
-- Module API (used by emitter via writer.load_filter)
-- ============================================================================

local M = {}

---Apply the default DOCX filter to a Pandoc document.
---Converts speccompiler format markers to OOXML.
---@param doc table Pandoc document
---@param _config table Configuration (unused)
---@param _log table Logger (unused)
---@return table Modified Pandoc document
function M.apply(doc, _config, _log)
    return doc:walk(FILTER_PASS1):walk(FILTER_PASS2)
end

-- ============================================================================
-- Native Pandoc Filter (used when loaded via --lua-filter)
-- ============================================================================

if FORMAT then
    return {FILTER_PASS1, FILTER_PASS2}
end

return M
