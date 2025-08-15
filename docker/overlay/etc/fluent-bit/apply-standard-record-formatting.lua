--[[
--File: apply-standard-record-formatting.lua
--Project: fluent-bit
--File Created: Tuesday, 29th October 2024 3:18:29 pm
--Author: Josh5 (jsunnex@gmail.com)
-------
--Last Modified: Friday, 15th August 2025 7:31:32 pm
--Modified By: Josh.5 (jsunnex@gmail.com)
--]]

local cjson = require "cjson"

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

-- Function to check if a string is valid JSON and decode it
local function is_json(str)
    local success, result = pcall(cjson.decode, str)
    return success, result -- Return both success status and decoded result
end

-- Function to convert any value to logfmt-safe text
local function to_logfmt_value(v)
    local t = type(v)
    if t == "boolean" then
        return v and "true" or "false"
    elseif t == "number" then
        return tostring(v)
    elseif t == "string" then
        -- unquoted if safe (no spaces, quotes, or equals)
        if v:match('^[%w%._:/%-]+$') then
            return v
        else
            -- escape backslashes and quotes
            v = v:gsub('\\', '\\\\'):gsub('"', '\\"')
            return '"' .. v .. '"'
        end
    elseif v == cjson.null then
        return "null"
    else
        -- nil or other types
        return "null"
    end
end

-- Function to build logfmt from a table, recursing; arrays become key.1, key.2 ...
local function table_to_logfmt(t, prefix, parts)
    parts = parts or {}
    for k, v in pairs(t) do
        local key = prefix and (prefix .. "." .. k) or k
        if type(v) == "table" then
            if #v > 0 then
                -- array
                for i, item in ipairs(v) do
                    if type(item) == "table" then
                        table_to_logfmt(item, key .. "." .. i, parts)
                    else
                        table.insert(parts, key .. "." .. i .. "=" .. to_logfmt_value(item))
                    end
                end
            else
                -- object
                table_to_logfmt(v, key, parts)
            end
        else
            table.insert(parts, key .. "=" .. to_logfmt_value(v))
        end
    end
    return parts
end

-- Function to provide conflict-aware extraction key/value write: 
--  - prefer key; if occupied by the same value, skip;
--  - else try key_extracted, key_extracted2, ...; if any holds the same value, skip;
--  - else write to the first free slot
local function set_kv(parent, key, value)
    local extracted = key .. "_extracted"

    -- Only override values if not present or explicitly empty.
    local existing = parent[key]
    if existing == nil or existing == "" then
        parent[key] = value
        return
    end
    -- Never create extracted if values will be the same
    if tostring(existing) == tostring(value) then
        -- Same value already present at base key then skip further processing
        return
    end

    -- Apply a "_extracted" suffix (if not yet exists)
    existing = parent[extracted]
    if existing == nil or existing == "" then
        parent[extracted] = value
        return
    end
    if tostring(existing) == tostring(value) then
        -- Same value already present at _extracted then skip
        return
    end

    -- Finally, if _extracted exists, the apply it with additional numbered suffixes
    local i = 2
    while true do
        local k = extracted .. tostring(i)
        existing = parent[k]
        if existing == nil or existing == "" then
            parent[k] = value
            return
        end
        if tostring(existing) == tostring(value) then
            -- Same value already present at a numbered slot -> skip
            return
        end
        i = i + 1
    end
end

-- Level/levelname normalisation map
local LEVEL_MAP = {
    [0] = "fatal",
    [1] = "alert",
    [2] = "critical",
    [3] = "error",
    [4] = "warn",
    [5] = "notice",
    [6] = "info",
    [7] = "debug",
    fatal = 0,
    emerg = 0,
    emergency = 0,
    alert = 1,
    crit = 2,
    critical = 2,
    err = 3,
    eror = 3,
    error = 3,
    warn = 4,
    warning = 4,
    notice = 5,
    informational = 6,
    information = 6,
    info = 6,
    dbug = 7,
    debug = 7,
    trace = 7
}

-- Function to provide a normalised level pair
local function normalise_level_pair(val)
    if type(val) == "number" then
        local nn = math.floor(val)
        if LEVEL_MAP[nn] then
            return nn, LEVEL_MAP[nn]
        end
    end
    local s = tostring(val or ""):gsub("^%s*(.-)%s*$", "%1")
    local lower = s:lower()
    if LEVEL_MAP[lower] then
        local n = LEVEL_MAP[lower]
        return n, lower
    end
    return 6, "info"
end

-- Function to flatten any table to parent using dotted keys; arrays produce key.1, key.2...
-- Special-case: "level" / "levelname" always normalise+overwrite
local function flatten_into(parent, record, parent_key)
    for key, value in pairs(record) do
        local new_key = parent_key and (parent_key .. "." .. key) or key
        if type(value) == "table" then
            if #value > 0 then
                for index, item in ipairs(value) do
                    local idx_key = new_key .. "." .. index
                    if type(item) == "table" then
                        flatten_into(parent, item, idx_key)
                    else
                        -- Special handling of level and levelname keys
                        if idx_key == "level" or idx_key == "levelname" then
                            local lvl, lname = normalise_level_pair(item)
                            parent["level"] = lvl
                            parent["levelname"] = lname
                        else
                            set_kv(parent, idx_key, item)
                        end
                    end
                end
            else
                flatten_into(parent, value, new_key)
            end
        else
            if new_key == "level" or new_key == "levelname" then
                local lvl, lname = normalise_level_pair(value)
                parent["level"] = lvl
                parent["levelname"] = lname
            else
                -- coerce non-strings to strings for set_kv (its contract)
                set_kv(parent, new_key, value)
            end
        end
    end
end

-- Function to normalise timestamp to unix timestamp with ns precision
local function to_unix_timestamp(ts)
    if type(ts) == "number" then
        -- Check for valid(ish) epoch timestamp. 32503680000 = Jan 1,3000
        if ts > 0 and ts < 32503680000 then
            -- Convert the number to a string to check for nanoseconds
            local ts_str = tostring(ts)
            if not ts_str:find("%.") then
                -- No decimal point, add .000000000 for nanoseconds
                ts_str = ts_str .. ".000000000"
            else
                -- Ensure the nanoseconds are padded to 9 digits
                local seconds, nanoseconds = ts_str:match("^(%d+)%.(%d+)$")
                nanoseconds = nanoseconds or ""
                nanoseconds = nanoseconds .. string.rep("0", 9 - #nanoseconds)
                ts_str = seconds .. "." .. nanoseconds
            end
            return tonumber(ts_str)
        end
        return ts
    elseif type(ts) == "string" then
        -- Try parsing ISO 8601 with optional fractional seconds
        local pattern = "(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+%.?%d*)Z"
        local year, month, day, hour, min, sec = ts:match(pattern)
        if year then
            local sec_int, sec_frac = math.modf(tonumber(sec))
            local time_table = {
                year = tonumber(year),
                month = tonumber(month),
                day = tonumber(day),
                hour = tonumber(hour),
                min = tonumber(min),
                sec = sec_int
            }
            local utc = os.time(time_table)
            if utc then
                return tonumber(string.format("%d.%09d", utc, math.floor(sec_frac * 1e9)))
            end
        end
    end
    return nil
end

----------------------------------------------------------------------
-- Main processor
----------------------------------------------------------------------

function standard_record_formatting(tag, timestamp, record)
    ------------------------------------------------------------------
    -- 1) Decode any string JSON into a new "decoded" table
    ------------------------------------------------------------------
    local decoded = {}
    for key, value in pairs(record) do
        -- Only attempt to decode if the value is a string
        if type(value) == "string" then
            local success, decoded_value = is_json(value)
            if success and type(decoded_value) == "table" then
                -- If the value is valid JSON, merge it into new_record
                for k, v in pairs(decoded_value) do
                    decoded[k] = v
                end
            else
                -- If it's not valid JSON, keep the original value
                decoded[key] = value
            end
        else
            -- If the value is not a string, keep the original value
            decoded[key] = value
        end
    end

    ------------------------------------------------------------------
    -- 2) If "message" does not exist, but "log" does, move "log" to "message"
    ------------------------------------------------------------------
    if (not decoded["message"] or decoded["message"] == "") and decoded["log"] and type(decoded["log"]) == "string" and
        decoded["log"] ~= "" then
        decoded["message"] = decoded["log"]
        decoded["log"] = nil
    end

    ------------------------------------------------------------------
    -- 3) If "message" is a table, flatten it into root and build logfmt
    ------------------------------------------------------------------
    local flat_record = {}

    if decoded["message"] ~= nil then
        local message_val = decoded["message"]
        if type(message_val) == "table" then
            -- First do direct scalars so they are in-place in flat_record before we start flattening
            for k, v in pairs(message_val) do
                if type(v) ~= "table" then
                    if k == "level" or k == "levelname" then
                        local lvl, lname = normalise_level_pair(v)
                        flat_record["level"] = lvl
                        flat_record["levelname"] = lname
                    else
                        set_kv(flat_record, k, v)
                    end
                end
            end
            -- Flatten nested tables/arrays next (no "message." prefix)
            for k, v in pairs(message_val) do
                if type(v) == "table" then
                    flatten_into(flat_record, v, k)
                end
            end

            -- Build logfmt string for the entire message object
            local parts = table_to_logfmt(message_val, nil, {})
            flat_record["message"] = table.concat(parts, " ")

        elseif type(message_val) == "string" then
            -- Preserve the string as-is
            flat_record["message"] = message_val
        else
            -- Non-table, non-string: render as logfmt scalar
            flat_record["message"] = to_logfmt_value(message_val)
        end

        -- Remove original message to avoid duplicate nesting later
        decoded["message"] = nil
    else
        -- No message provided at all
        flat_record["message"] = "NO MESSAGE"
    end

    -- Flatten the remainder of the record with dotted keys
    flatten_into(flat_record, decoded, nil)

    ------------------------------------------------------------------
    -- 3) Convert any "source." keys to "source_" (conflict-aware)
    ------------------------------------------------------------------
    local new_record = {}
    for key, value in pairs(flat_record) do
        -- Convert any "source." keys to "source_",
        if key:sub(1, 7) == "source." then
            local suffix = key:sub(8)
            local normalised = "source_" .. suffix

            -- Use conflict-aware write
            set_kv(new_record, normalised, value)

            -- Don't copy the original dotted key
            new_record[key] = null
        else
            -- copy as-is
            new_record[key] = value
        end
    end

    ------------------------------------------------------------------
    -- 4) Run short_message cleanup (remove if empty string)
    ------------------------------------------------------------------
    if new_record["short_message"] == "" then
        new_record["short_message"] = nil -- Remove if it's an empty string
    end

    ------------------------------------------------------------------
    -- 5) Ensure "source" tag exists
    ------------------------------------------------------------------
    if not new_record["source"] or type(new_record["source"]) ~= "string" or new_record["source"] == "" then
        if tag and (type(tag) == "string" and tag ~= "") then
            new_record["source"] = tag -- Use tag if it exists and is not empty
        else
            new_record["source"] = "unknown" -- Default to "unknown"
        end
    end

    ------------------------------------------------------------------
    -- 6) Ensure "service_name" tag exists
    ------------------------------------------------------------------
    if not new_record["service_name"] or
        (type(new_record["service_name"]) ~= "string" or new_record["service_name"] == "") then
        if new_record["source_service"] and
            (type(new_record["source_service"]) == "string" and new_record["source_service"] ~= "") then
            new_record["service_name"] = new_record["source_service"] -- Use "source_service" record if it exists and is not empty
        else
            new_record["service_name"] = new_record["source"] -- Default to "source" record
        end
    end

    ------------------------------------------------------------------
    -- 7) Normalise timestamp
    ------------------------------------------------------------------
    new_record["timestamp"] = to_unix_timestamp(new_record["timestamp"]) or timestamp
    timestamp = new_record["timestamp"]

    ------------------------------------------------------------------
    -- 8) Normalise level/levelname
    ------------------------------------------------------------------
    local lvl, lname = normalise_level_pair(new_record["level"] ~= nil and new_record["level"] or
                                                new_record["levelname"])
    new_record["level"] = lvl
    new_record["levelname"] = lname

    return 1, timestamp, new_record
end
