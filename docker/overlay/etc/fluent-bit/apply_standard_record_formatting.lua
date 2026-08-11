--[[
File: apply_standard_record_formatting.lua
Project: fluent-bit
Description: Bounded record flattening, envelope decoding, timestamp parsing, and severity normalization.
--]]

local cjson = require "cjson"

local MAX_ENVELOPE_DEPTH = 5
local MAX_NESTING_DEPTH = 64
local MAX_FLATTENED_FIELDS = 2048
local MAX_TABLE_ENTRIES = 4096
local MAX_ARRAY_ELEMENTS = 1024
local MAX_JSON_BYTES = 1048576
local MAX_LOGFMT_FIELDS = 256
local MAX_MESSAGE_LENGTH = 8192
local MAX_COLLISIONS_PER_KEY = 32

local ENVELOPE_FIELDS = {
    log = true,
    message = true,
    msg = true
}

-- Some Lua CJSON variants can retain array identity with a metatable. Enable it
-- when available; the fallback treats an unmarked empty table as an object.
if type(cjson.decode_array_with_array_mt) == "function" then
    pcall(cjson.decode_array_with_array_mt, true)
end

local function is_null(value)
    return value == cjson.null
end

local function has_value(value)
    if value == nil or is_null(value) then
        return false
    end
    if type(value) == "string" then
        return value:match("%S") ~= nil
    end
    return true
end

local function is_array(value)
    if type(value) ~= "table" then
        return false
    end
    local metatable = getmetatable(value)
    if cjson.array_mt and metatable == cjson.array_mt then
        return true
    end
    -- Fluent Bit gives MessagePack arrays a private metatable whose type field
    -- is 1 (maps use 2). This survives filters which mutate records in place.
    if type(metatable) == "table" and metatable.type == 1 then
        return true
    end

    local count = 0
    local max_index = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            return false
        end
        count = count + 1
        if key > max_index then
            max_index = key
        end
    end
    return count > 0 and max_index == count
end

local function empty_container_value(value)
    return is_array(value) and "[]" or "{}"
end

local function mark_error(state, code)
    state.errors[code] = true
end

local function compare_keys(a, b)
    local type_a = type(a)
    local type_b = type(b)
    if type_a ~= type_b then
        return type_a < type_b
    elseif type_a == "number" or type_a == "string" then
        return a < b
    elseif type_a == "boolean" then
        return a == false and b == true
    end
    return tostring(a) < tostring(b)
end

-- Sorting is reserved for generated logfmt output. The limit bounds allocation
-- even when an attacker supplies an exceptionally wide object.
local function sorted_keys(value, limit)
    local keys = {}
    local truncated = false
    for key in pairs(value) do
        if #keys >= limit then
            truncated = true
            break
        end
        table.insert(keys, key)
    end
    table.sort(keys, compare_keys)
    return keys, truncated
end

local function values_equal(a, b, seen_a, seen_b, depth)
    if rawequal(a, b) then
        return true
    end
    if type(a) ~= type(b) or type(a) ~= "table" then
        return false
    end
    depth = depth or 0
    if depth >= MAX_NESTING_DEPTH then
        return false
    end

    seen_a = seen_a or {}
    seen_b = seen_b or {}
    if seen_a[a] or seen_b[b] then
        return seen_a[a] == b and seen_b[b] == a
    end
    seen_a[a] = b
    seen_b[b] = a

    local count = 0
    for key, value in pairs(a) do
        count = count + 1
        if count > MAX_TABLE_ENTRIES or b[key] == nil or
            not values_equal(value, b[key], seen_a, seen_b, depth + 1) then
            return false
        end
    end
    count = 0
    for key in pairs(b) do
        count = count + 1
        if count > MAX_TABLE_ENTRIES or a[key] == nil then
            return false
        end
    end
    return true
end

-- Returns true only when a new value was written. Collision scans are bounded.
local function set_kv(parent, key, value)
    if key == nil or not has_value(value) then
        return false
    end
    key = tostring(key)
    if not has_value(parent[key]) then
        parent[key] = value
        return true
    end
    if values_equal(parent[key], value) then
        return false
    end

    local extracted = key .. "_extracted"
    local candidate = extracted
    for index = 1, MAX_COLLISIONS_PER_KEY do
        if not has_value(parent[candidate]) then
            parent[candidate] = value
            return true
        end
        if values_equal(parent[candidate], value) then
            return false
        end
        candidate = extracted .. tostring(index + 1)
    end
    return false, "collision_limit"
end

local function put_flat(parent, key, value, state)
    if state.fields >= MAX_FLATTENED_FIELDS then
        mark_error(state, "max_flattened_fields")
        return false
    end
    local written, reason = set_kv(parent, key, value)
    if reason then
        mark_error(state, reason)
    elseif written then
        state.fields = state.fields + 1
    end
    return written
end

local function decode_json(value)
    if type(value) ~= "string" then
        return false, nil
    end
    if #value > MAX_JSON_BYTES then
        return false, nil, "max_json_bytes"
    end
    local success, decoded = pcall(cjson.decode, value)
    return success, decoded
end

local function to_logfmt_value(value)
    local value_type = type(value)
    if value_type == "boolean" then
        return value and "true" or "false"
    elseif value_type == "number" then
        return tostring(value)
    elseif value_type == "string" then
        if #value > MAX_MESSAGE_LENGTH then
            value = value:sub(1, MAX_MESSAGE_LENGTH)
        end
        if value:match('^[%w%._:/%-]+$') then
            return value
        end
        value = value:gsub('\\', '\\\\'):gsub('"', '\\"')
        return '"' .. value .. '"'
    end
    return '""'
end

local function append_logfmt_part(parts, logfmt_state, part)
    if logfmt_state.fields >= MAX_LOGFMT_FIELDS then
        logfmt_state.truncated = true
        return false
    end
    local separator_length = #parts > 0 and 1 or 0
    local remaining = MAX_MESSAGE_LENGTH - logfmt_state.length - separator_length
    if remaining <= 0 then
        logfmt_state.truncated = true
        return false
    end
    if #part > remaining then
        part = part:sub(1, remaining)
        logfmt_state.truncated = true
    end
    table.insert(parts, part)
    logfmt_state.fields = logfmt_state.fields + 1
    logfmt_state.length = logfmt_state.length + separator_length + #part
    return not logfmt_state.truncated
end

local function table_to_logfmt(value, prefix, parts, logfmt_state, depth, seen)
    parts = parts or {}
    logfmt_state = logfmt_state or { fields = 0, length = 0, truncated = false }
    depth = depth or 0
    seen = seen or {}
    if depth >= MAX_NESTING_DEPTH or seen[value] then
        logfmt_state.truncated = true
        return parts, logfmt_state
    end
    seen[value] = true

    local keys, keys_truncated = sorted_keys(value, MAX_TABLE_ENTRIES)
    if keys_truncated then
        logfmt_state.truncated = true
    end
    local array_items = 0
    for _, key_part in ipairs(keys) do
        if type(key_part) == "number" then
            array_items = array_items + 1
            if array_items > MAX_ARRAY_ELEMENTS then
                logfmt_state.truncated = true
                break
            end
        end
        local item = value[key_part]
        local key = prefix and (prefix .. "." .. tostring(key_part)) or tostring(key_part)
        if is_null(item) then
            -- JSON null is empty.
        elseif type(item) == "table" then
            if next(item) == nil then
                if not append_logfmt_part(parts, logfmt_state,
                        key .. "=" .. to_logfmt_value(empty_container_value(item))) then
                    break
                end
            else
                table_to_logfmt(item, key, parts, logfmt_state, depth + 1, seen)
                if logfmt_state.truncated then
                    break
                end
            end
        else
            if not append_logfmt_part(parts, logfmt_state,
                    key .. "=" .. to_logfmt_value(item)) then
                break
            end
        end
    end
    seen[value] = nil
    return parts, logfmt_state
end

local function generated_logfmt(value, state)
    local parts, logfmt_state = table_to_logfmt(value)
    if logfmt_state.truncated then
        mark_error(state, "generated_message_truncated")
    end
    return table.concat(parts, " ")
end

local LEVEL_NAMES = {
    emerg = { 0, "fatal" },
    emergency = { 0, "fatal" },
    fatal = { 0, "fatal" },
    alert = { 1, "critical" },
    crit = { 2, "critical" },
    critical = { 2, "critical" },
    err = { 3, "error" },
    eror = { 3, "error" },
    error = { 3, "error" },
    warn = { 4, "warn" },
    warning = { 4, "warn" },
    notice = { 5, "info" },
    info = { 6, "info" },
    information = { 6, "info" },
    informational = { 6, "info" },
    dbug = { 7, "debug" },
    debug = { 7, "debug" },
    trace = { 7, "trace" }
}

local NUMERIC_LEVELS = {
    [0] = { 0, "fatal" },
    [1] = { 1, "critical" },
    [2] = { 2, "critical" },
    [3] = { 3, "error" },
    [4] = { 4, "warn" },
    [5] = { 5, "info" },
    [6] = { 6, "info" },
    [7] = { 7, "debug" }
}

local function normalise_level_pair(value)
    if type(value) == "string" then
        local name = value:match("^%s*(.-)%s*$"):lower()
        if LEVEL_NAMES[name] then
            return LEVEL_NAMES[name][1], LEVEL_NAMES[name][2]
        end
        local numeric = tonumber(name)
        if numeric and numeric % 1 == 0 and NUMERIC_LEVELS[numeric] then
            return NUMERIC_LEVELS[numeric][1], NUMERIC_LEVELS[numeric][2]
        end
        return nil
    elseif type(value) == "number" and value % 1 == 0 and NUMERIC_LEVELS[value] then
        return NUMERIC_LEVELS[value][1], NUMERIC_LEVELS[value][2]
    end
    return nil
end

local function find_normalised_level(record)
    local named_fields = {
        "levelname", "severity_text", "SeverityText", "severity", "lvl"
    }
    local supplied = false
    for _, key in ipairs(named_fields) do
        if has_value(record[key]) then
            supplied = true
            local level, levelname = normalise_level_pair(record[key])
            if level then
                return level, levelname, supplied
            end
        end
    end
    if has_value(record.level) then
        supplied = true
        local level, levelname = normalise_level_pair(record.level)
        if level then
            return level, levelname, supplied
        end
    end
    return nil, nil, supplied
end

local function apply_normalised_level(record)
    local level, levelname, supplied = find_normalised_level(record)
    if not level and not supplied then
        level, levelname = 6, "info"
    end
    if not level then
        return
    end

    local previous_level = record.level
    local previous_levelname = record.levelname
    record.level = level
    record.levelname = levelname
    if has_value(previous_level) then
        local old_level, old_levelname = normalise_level_pair(previous_level)
        if old_level ~= level or old_levelname ~= levelname then
            set_kv(record, "level", previous_level)
        end
    end
    if has_value(previous_levelname) then
        local old_level, old_levelname = normalise_level_pair(previous_levelname)
        if old_level ~= level or old_levelname ~= levelname then
            set_kv(record, "levelname", previous_levelname)
        end
    end
end

local function is_leap_year(year)
    return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

local function days_in_month(year, month)
    local days = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    return month == 2 and is_leap_year(year) and 29 or days[month]
end

local function days_since_unix_epoch(year, month, day)
    if month <= 2 then
        year = year - 1
    end
    local era = math.floor(year / 400)
    local year_of_era = year - era * 400
    local shifted_month = month + (month > 2 and -3 or 9)
    local day_of_year = math.floor((153 * shifted_month + 2) / 5) + day - 1
    local day_of_era = year_of_era * 365 + math.floor(year_of_era / 4) -
        math.floor(year_of_era / 100) + day_of_year
    return era * 146097 + day_of_era - 719468
end

local function civil_from_days(days)
    local shifted = days + 719468
    local era = math.floor(shifted / 146097)
    local day_of_era = shifted - era * 146097
    local year_of_era = math.floor((day_of_era - math.floor(day_of_era / 1460) +
        math.floor(day_of_era / 36524) - math.floor(day_of_era / 146096)) / 365)
    local year = year_of_era + era * 400
    local day_of_year = day_of_era - (365 * year_of_era + math.floor(year_of_era / 4) -
        math.floor(year_of_era / 100))
    local shifted_month = math.floor((5 * day_of_year + 2) / 153)
    local day = day_of_year - math.floor((153 * shifted_month + 2) / 5) + 1
    local month = shifted_month + (shifted_month < 10 and 3 or -9)
    year = year + (month <= 2 and 1 or 0)
    return year, month, day
end

local function parse_fraction_to_nanoseconds(fraction)
    if fraction == nil or fraction == "" then
        return 0
    end
    if #fraction > 9 then
        return nil
    end
    return tonumber(fraction .. string.rep("0", 9 - #fraction))
end

local function make_timestamp(seconds, nanoseconds)
    if type(seconds) ~= "number" or type(nanoseconds) ~= "number" or
        seconds < -62135596800 or seconds >= 32503680000 or
        nanoseconds < 0 or nanoseconds >= 1000000000 then
        return nil
    end
    return { sec = math.floor(seconds), nsec = math.floor(nanoseconds) }
end

local function parse_numeric_epoch_string(value)
    local integer, fraction = value:match("^(%d+)%.?(%d*)$")
    if not integer then
        return nil
    end
    local digits = #integer
    local seconds
    local nanoseconds
    if digits <= 11 then
        seconds = tonumber(integer)
        nanoseconds = parse_fraction_to_nanoseconds(fraction)
    elseif digits == 13 and fraction == "" then
        seconds = tonumber(integer:sub(1, -4))
        nanoseconds = tonumber(integer:sub(-3)) * 1000000
    elseif digits == 16 and fraction == "" then
        seconds = tonumber(integer:sub(1, -7))
        nanoseconds = tonumber(integer:sub(-6)) * 1000
    elseif digits == 19 and fraction == "" then
        seconds = tonumber(integer:sub(1, -10))
        nanoseconds = tonumber(integer:sub(-9))
    else
        return nil
    end
    if nanoseconds == nil then
        return nil
    end
    return make_timestamp(seconds, nanoseconds)
end

local function to_event_timestamp(value)
    if type(value) == "table" then
        local seconds = tonumber(value.sec)
        local nanoseconds = tonumber(value.nsec)
        return seconds and nanoseconds and
            make_timestamp(math.floor(seconds), math.floor(nanoseconds)) or nil
    elseif type(value) == "number" then
        if value >= 1000000000000000000 then
            return make_timestamp(math.floor(value / 1000000000), math.floor(value % 1000000000))
        elseif value >= 1000000000000000 then
            return make_timestamp(math.floor(value / 1000000), math.floor(value % 1000000) * 1000)
        elseif value >= 1000000000000 then
            return make_timestamp(math.floor(value / 1000), math.floor(value % 1000) * 1000000)
        end
        local seconds = math.floor(value)
        local nanoseconds = math.floor((value - seconds) * 1000000000 + 0.5)
        if nanoseconds == 1000000000 then
            seconds, nanoseconds = seconds + 1, 0
        end
        return make_timestamp(seconds, nanoseconds)
    elseif type(value) ~= "string" then
        return nil
    end

    local trimmed = value:match("^%s*(.-)%s*$")
    local numeric = parse_numeric_epoch_string(trimmed)
    if numeric then
        return numeric
    end

    local year, month, day, hour, minute, second, suffix = trimmed:match(
        "^(%d%d%d%d)%-(%d%d)%-(%d%d)[Tt](%d%d):(%d%d):(%d%d)(.*)$"
    )
    if not year then
        return nil
    end
    year, month, day = tonumber(year), tonumber(month), tonumber(day)
    hour, minute, second = tonumber(hour), tonumber(minute), tonumber(second)
    if month < 1 or month > 12 or day < 1 or day > days_in_month(year, month) or
        hour > 23 or minute > 59 or second > 59 then
        return nil
    end

    local fraction = ""
    local timezone = suffix
    local parsed_fraction, parsed_timezone = suffix:match("^%.(%d+)(.*)$")
    if parsed_fraction then
        if #parsed_fraction > 9 then
            return nil
        end
        fraction, timezone = parsed_fraction, parsed_timezone
    end

    local offset_seconds = 0
    if timezone ~= "Z" and timezone ~= "z" then
        local sign, offset_hour, offset_minute = timezone:match("^([+-])(%d%d):?(%d%d)$")
        offset_hour, offset_minute = tonumber(offset_hour), tonumber(offset_minute)
        if not sign or offset_hour > 14 or offset_minute > 59 or
            (offset_hour == 14 and offset_minute ~= 0) then
            return nil
        end
        offset_seconds = (offset_hour * 60 + offset_minute) * 60
        if sign == "-" then
            offset_seconds = -offset_seconds
        end
    end

    local nanoseconds = parse_fraction_to_nanoseconds(fraction)
    local seconds = days_since_unix_epoch(year, month, day) * 86400 +
        hour * 3600 + minute * 60 + second - offset_seconds
    return nanoseconds and make_timestamp(seconds, nanoseconds) or nil
end

local function timestamp_to_rfc3339(timestamp)
    local days = math.floor(timestamp.sec / 86400)
    local seconds_of_day = timestamp.sec - days * 86400
    local year, month, day = civil_from_days(days)
    local hour = math.floor(seconds_of_day / 3600)
    local minute = math.floor((seconds_of_day % 3600) / 60)
    local second = seconds_of_day % 60
    return string.format("%04d-%02d-%02dT%02d:%02d:%02d.%09dZ",
        year, month, day, hour, minute, second, timestamp.nsec)
end

local function flatten_into(parent, record, parent_key, state, depth, seen)
    depth = depth or 0
    seen = seen or {}
    if depth >= MAX_NESTING_DEPTH then
        mark_error(state, "max_nesting_depth")
        if parent_key then
            put_flat(parent, parent_key, "[truncated:max_nesting_depth]", state)
        end
        return
    end
    if seen[record] then
        mark_error(state, "cyclic_table")
        if parent_key then
            put_flat(parent, parent_key, "[truncated:cyclic_table]", state)
        end
        return
    end
    if next(record) == nil then
        if parent_key then
            put_flat(parent, parent_key, empty_container_value(record), state)
        end
        return
    end

    seen[record] = true
    local entries = 0
    local array_entries = 0
    local array = is_array(record)
    for key_part, value in pairs(record) do
        entries = entries + 1
        if entries > MAX_TABLE_ENTRIES then
            mark_error(state, "max_table_entries")
            break
        end
        if array then
            array_entries = array_entries + 1
            if array_entries > MAX_ARRAY_ELEMENTS then
                mark_error(state, "max_array_elements")
                break
            end
        end

        local key = tostring(key_part)
        local new_key = parent_key and (parent_key .. "." .. key) or key
        if is_null(value) then
            -- JSON null is empty.
        elseif type(value) == "table" then
            if parent_key == nil and key == "timestamp" then
                put_flat(parent, new_key, value, state)
            else
                flatten_into(parent, value, new_key, state, depth + 1, seen)
            end
        else
            put_flat(parent, new_key, value, state)
        end
        if state.fields >= MAX_FLATTENED_FIELDS then
            break
        end
    end
    seen[record] = nil
end

local expand_envelope

local function process_envelope_value(parent, value, state, depth)
    if depth > MAX_ENVELOPE_DEPTH then
        mark_error(state, "max_envelope_depth")
        if has_value(value) then
            put_flat(parent, "message", type(value) == "string" and value or
                to_logfmt_value(value), state)
        end
        return
    end

    if type(value) == "table" then
        expand_envelope(parent, value, state, depth)
    elseif type(value) == "string" then
        local success, decoded, reason = decode_json(value)
        if reason then
            mark_error(state, reason)
            put_flat(parent, "message", value, state)
        elseif success and is_null(decoded) then
            return
        elseif success and type(decoded) == "table" then
            expand_envelope(parent, decoded, state, depth)
        elseif success and type(decoded) == "string" then
            process_envelope_value(parent, decoded, state, depth + 1)
        elseif success then
            put_flat(parent, "message", to_logfmt_value(decoded), state)
        else
            put_flat(parent, "message", value, state)
        end
    elseif has_value(value) then
        put_flat(parent, "message", to_logfmt_value(value), state)
    end
end

expand_envelope = function(parent, envelope, state, depth)
    if depth > MAX_ENVELOPE_DEPTH then
        mark_error(state, "max_envelope_depth")
        return
    end

    local entries = 0
    for key, value in pairs(envelope) do
        entries = entries + 1
        if entries > MAX_TABLE_ENTRIES then
            mark_error(state, "max_table_entries")
            break
        end
        if not ENVELOPE_FIELDS[key] then
            local root_key = tostring(key)
            if is_null(value) then
                -- JSON null is empty.
            elseif type(value) == "table" then
                if root_key == "timestamp" then
                    put_flat(parent, root_key, value, state)
                else
                    flatten_into(parent, value, root_key, state, 1, {})
                end
            else
                put_flat(parent, root_key, value, state)
            end
        end
    end

    local found_message = false
    for _, key in ipairs({ "message", "log", "msg" }) do
        if has_value(envelope[key]) then
            found_message = true
            process_envelope_value(parent, envelope[key], state, depth + 1)
        end
    end
    if not found_message then
        put_flat(parent, "message", generated_logfmt(envelope, state), state)
    end
end

local function add_formatting_errors(record, state)
    local errors = {}
    for code in pairs(state.errors) do
        table.insert(errors, code)
    end
    table.sort(errors)
    if #errors > 0 then
        set_kv(record, "formatting_error", table.concat(errors, ","))
    end
end

function standard_record_formatting(tag, timestamp, record)
    local state = { fields = 0, errors = {} }
    local flat_record = {}

    -- Explicit root fields are processed first. Ordinary flattening intentionally
    -- avoids sorting; deterministic ordering is only needed for generated logfmt.
    for key, value in pairs(record) do
        if not ENVELOPE_FIELDS[key] then
            local success, decoded, reason = decode_json(value)
            if reason then
                mark_error(state, reason)
                put_flat(flat_record, key, value, state)
            elseif key == "timestamp" and type(value) == "table" then
                put_flat(flat_record, key, value, state)
            elseif success and is_null(decoded) then
                -- JSON null is empty.
            elseif success and type(decoded) == "table" then
                flatten_into(flat_record, decoded, tostring(key), state, 0, {})
            elseif type(value) == "table" then
                flatten_into(flat_record, value, tostring(key), state, 0, {})
            else
                put_flat(flat_record, key, value, state)
            end
        end
    end

    -- Envelope precedence is message, then log, then msg. Lower-priority
    -- conflicts remain available in _extracted fields.
    for _, key in ipairs({ "message", "log", "msg" }) do
        if has_value(record[key]) then
            process_envelope_value(flat_record, record[key], state, 1)
        end
    end
    if not has_value(flat_record.message) then
        flat_record.message = "NO MESSAGE"
    end

    local new_record = {}
    for key, value in pairs(flat_record) do
        if key:sub(1, 7) ~= "source." then
            set_kv(new_record, key, value)
        end
    end
    for key, value in pairs(flat_record) do
        if key:sub(1, 7) == "source." then
            set_kv(new_record, "source_" .. key:sub(8), value)
        end
    end

    if not has_value(new_record.short_message) then
        new_record.short_message = nil
    end

    -- Input-specific filters and Docker metadata provide service_name as soon
    -- as the emitting service is known. The source is only a final fallback
    -- for unclassified records.
    if type(new_record.source) ~= "string" or not has_value(new_record.source) then
        new_record.source = nil
    end
    if type(new_record.service_name) ~= "string" or not has_value(new_record.service_name) then
        if type(new_record.source) == "string" and has_value(new_record.source) then
            new_record.service_name = new_record.source
        else
            new_record.service_name = type(tag) == "string" and has_value(tag) and tag or "unknown"
        end
    end

    local original_timestamp = new_record.timestamp
    local application_timestamp = to_event_timestamp(original_timestamp)
    local fluent_bit_timestamp = to_event_timestamp(timestamp)
    local final_timestamp = application_timestamp or fluent_bit_timestamp
    if final_timestamp then
        timestamp = final_timestamp
        new_record.timestamp = timestamp_to_rfc3339(final_timestamp)
    end
    if has_value(original_timestamp) then
        set_kv(new_record, "source_timestamp", original_timestamp)
    end
    if application_timestamp then
        new_record.timestamp_source = "application"
    else
        new_record.timestamp_source = "fluent-bit"
        if has_value(original_timestamp) then
            set_kv(new_record, "timestamp_invalid", original_timestamp)
        end
    end

    apply_normalised_level(new_record)
    add_formatting_errors(new_record, state)
    return 1, timestamp, new_record
end
