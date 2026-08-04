--[[
File: apply_standard_record_formatting.lua
Project: fluent-bit
Description: Core Lua filter for flattening objects, parsing JSON, and normalizing fields and log levels.
--]]

local cjson = require "cjson"

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local ENVELOPE_FIELDS = {
    log = true,
    message = true,
    msg = true
}

local function is_null(v)
    return v == cjson.null
end

-- A JSON null is a cjson sentinel, not Lua nil. Treat both as absent.
local function has_value(v)
    if v == nil or is_null(v) then
        return false
    end
    if type(v) == "string" then
        return v:match("%S") ~= nil
    end
    return true
end

local function decode_json(value)
    if type(value) ~= "string" then
        return false, nil
    end
    local success, decoded = pcall(cjson.decode, value)
    return success, decoded
end

local function sorted_keys(t)
    local keys = {}
    for key in pairs(t) do
        table.insert(keys, key)
    end
    table.sort(keys, function(a, b)
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
    end)
    return keys
end

local function to_logfmt_value(v)
    local value_type = type(v)
    if value_type == "boolean" then
        return v and "true" or "false"
    elseif value_type == "number" then
        return tostring(v)
    elseif value_type == "string" then
        if v:match('^[%w%._:/%-]+$') then
            return v
        end
        v = v:gsub('\\', '\\\\'):gsub('"', '\\"')
        return '"' .. v .. '"'
    end
    return '""'
end

-- Build deterministic logfmt. Arrays use key.1, key.2, ...
local function table_to_logfmt(t, prefix, parts)
    parts = parts or {}
    for _, key_part in ipairs(sorted_keys(t)) do
        local value = t[key_part]
        local key = prefix and (prefix .. "." .. tostring(key_part)) or tostring(key_part)
        if type(value) == "table" then
            if next(value) == nil then
                local success, encoded = pcall(cjson.encode, value)
                table.insert(parts, key .. "=" .. to_logfmt_value(success and encoded or ""))
            else
                table_to_logfmt(value, key, parts)
            end
        elseif not is_null(value) then
            table.insert(parts, key .. "=" .. to_logfmt_value(value))
        end
    end
    return parts
end

local function values_equal(a, b, seen_a, seen_b)
    if rawequal(a, b) then
        return true
    end
    if type(a) ~= type(b) or type(a) ~= "table" then
        return false
    end

    seen_a = seen_a or {}
    seen_b = seen_b or {}
    if seen_a[a] or seen_b[b] then
        return seen_a[a] == b and seen_b[b] == a
    end
    seen_a[a] = b
    seen_b[b] = a

    for key, value in pairs(a) do
        if b[key] == nil or not values_equal(value, b[key], seen_a, seen_b) then
            return false
        end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end
    return true
end

-- Write extracted values without replacing data that was already present.
local function set_kv(parent, key, value)
    if key == nil or not has_value(value) then
        return
    end
    key = tostring(key)

    if not has_value(parent[key]) then
        parent[key] = value
        return
    end
    if values_equal(parent[key], value) then
        return
    end

    local extracted = key .. "_extracted"
    local candidate = extracted
    local index = 2
    while has_value(parent[candidate]) do
        if values_equal(parent[candidate], value) then
            return
        end
        candidate = extracted .. tostring(index)
        index = index + 1
    end
    parent[candidate] = value
end

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

local function normalise_level_pair(value)
    local numeric_level
    if type(value) == "number" then
        numeric_level = math.floor(value)
    else
        local name = tostring(value or ""):gsub("^%s*(.-)%s*$", "%1"):lower()
        numeric_level = LEVEL_MAP[name]
        if numeric_level == nil then
            numeric_level = tonumber(name)
            if numeric_level ~= nil then
                numeric_level = math.floor(numeric_level)
            end
        end
    end

    if LEVEL_MAP[numeric_level] then
        return numeric_level, LEVEL_MAP[numeric_level]
    end
    return 6, LEVEL_MAP[6]
end

local function is_leap_year(year)
    return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

local function days_in_month(year, month)
    local days = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if month == 2 and is_leap_year(year) then
        return 29
    end
    return days[month]
end

-- Convert a civil UTC date to days since 1970-01-01 without consulting the
-- process timezone. Based on the proleptic Gregorian calendar.
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

local function parse_fraction_to_nanoseconds(fraction)
    if fraction == nil or fraction == "" then
        return 0
    end
    fraction = fraction:sub(1, 9)
    fraction = fraction .. string.rep("0", 9 - #fraction)
    return tonumber(fraction)
end

local function make_timestamp(seconds, nanoseconds)
    if seconds <= 0 or seconds >= 32503680000 or
        nanoseconds < 0 or nanoseconds >= 1000000000 then
        return nil
    end
    return {
        sec = seconds,
        nsec = nanoseconds
    }
end

local function parse_numeric_epoch_string(value)
    local integer, fraction = value:match("^(%d+)%.?(%d*)$")
    if not integer then
        return nil
    end

    local digits = #integer
    local seconds
    local nanoseconds
    if digits <= 10 then
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
    return make_timestamp(seconds, nanoseconds)
end

-- Parse an epoch number or RFC3339 timestamp. Unlike os.time(), this handles Z
-- and explicit offsets independently of the Fluent Bit container's timezone.
local function to_unix_timestamp(value)
    if type(value) == "table" then
        local seconds = tonumber(value.sec)
        local nanoseconds = tonumber(value.nsec)
        if seconds and nanoseconds then
            return make_timestamp(math.floor(seconds), math.floor(nanoseconds))
        end
        return nil
    end
    if type(value) == "number" then
        -- Large Lua numbers may already have lost low-order digits. String
        -- timestamps are preferred for exact nanosecond values.
        if value >= 1000000000000000000 then
            local seconds = math.floor(value / 1000000000)
            local nanoseconds = math.floor(value % 1000000000)
            return make_timestamp(seconds, nanoseconds)
        elseif value >= 1000000000000000 then
            local seconds = math.floor(value / 1000000)
            local nanoseconds = math.floor(value % 1000000) * 1000
            return make_timestamp(seconds, nanoseconds)
        elseif value >= 1000000000000 then
            local seconds = math.floor(value / 1000)
            local nanoseconds = math.floor(value % 1000) * 1000000
            return make_timestamp(seconds, nanoseconds)
        end

        local seconds = math.floor(value)
        local nanoseconds = math.floor((value - seconds) * 1000000000 + 0.5)
        if nanoseconds == 1000000000 then
            seconds = seconds + 1
            nanoseconds = 0
        end
        return make_timestamp(seconds, nanoseconds)
    end
    if type(value) ~= "string" then
        return nil
    end

    local trimmed = value:match("^%s*(.-)%s*$")
    local numeric_timestamp = parse_numeric_epoch_string(trimmed)
    if numeric_timestamp then
        return numeric_timestamp
    end

    local year, month, day, hour, minute, second, suffix = trimmed:match(
        "^(%d%d%d%d)%-(%d%d)%-(%d%d)[Tt ](%d%d):(%d%d):(%d%d)(.*)$"
    )
    if not year then
        return nil
    end

    year = tonumber(year)
    month = tonumber(month)
    day = tonumber(day)
    hour = tonumber(hour)
    minute = tonumber(minute)
    second = tonumber(second)
    if month < 1 or month > 12 or day < 1 or day > days_in_month(year, month) or
        hour > 23 or minute > 59 or second > 60 then
        return nil
    end

    local fraction = ""
    local timezone = suffix
    local parsed_fraction, parsed_timezone = suffix:match("^%.(%d+)(.*)$")
    if parsed_fraction then
        fraction = parsed_fraction
        timezone = parsed_timezone
    end

    local offset_seconds = 0
    if timezone ~= "Z" and timezone ~= "z" then
        local sign, offset_hour, offset_minute = timezone:match("^([+-])(%d%d):?(%d%d)$")
        offset_hour = tonumber(offset_hour)
        offset_minute = tonumber(offset_minute)
        if not sign or offset_hour > 23 or offset_minute > 59 then
            return nil
        end
        offset_seconds = (offset_hour * 60 + offset_minute) * 60
        if sign == "-" then
            offset_seconds = -offset_seconds
        end
    end

    local epoch_seconds = days_since_unix_epoch(year, month, day) * 86400 +
        hour * 3600 + minute * 60 + second - offset_seconds
    return make_timestamp(epoch_seconds, parse_fraction_to_nanoseconds(fraction))
end

-- Flatten a table while retaining its dotted namespace. Severity is deliberately
-- not handled here: only the final root-level level/levelname pair is normalized.
local function flatten_into(parent, record, parent_key)
    if next(record) == nil then
        if parent_key then
            set_kv(parent, parent_key, record)
        end
        return
    end
    for _, key_part in ipairs(sorted_keys(record)) do
        local value = record[key_part]
        local key = tostring(key_part)
        local new_key = parent_key and (parent_key .. "." .. key) or key
        if type(value) == "table" then
            if parent_key == nil and key == "timestamp" then
                set_kv(parent, new_key, value)
            else
                flatten_into(parent, value, new_key)
            end
        else
            set_kv(parent, new_key, value)
        end
    end
end

-- Expand a decoded log/message/msg object into the root. Existing root values
-- win; collisions are retained as key_extracted, key_extracted2, and so on.
local function expand_envelope(parent, envelope)
    flatten_into(parent, envelope, nil)

    local message_value
    if has_value(envelope.message) then
        message_value = envelope.message
    elseif has_value(envelope.log) then
        message_value = envelope.log
    else
        message_value = envelope.msg
    end
    if has_value(message_value) then
        if type(message_value) == "table" then
            message_value = table.concat(table_to_logfmt(message_value), " ")
        elseif type(message_value) ~= "string" then
            message_value = to_logfmt_value(message_value)
        end
        set_kv(parent, "message", message_value)
    else
        local generated_message = table.concat(table_to_logfmt(envelope), " ")
        set_kv(parent, "message", generated_message)
    end
end

----------------------------------------------------------------------
-- Main processor
----------------------------------------------------------------------

function standard_record_formatting(tag, timestamp, record)
    local flat_record = {}

    -- Preserve non-envelope JSON under its original namespace. Process these
    -- fields first so values explicitly supplied at the root win over anything
    -- subsequently extracted from an envelope.
    for _, key in ipairs(sorted_keys(record)) do
        if not ENVELOPE_FIELDS[key] then
            local value = record[key]
            local json_success, decoded = decode_json(value)
            if key == "timestamp" and type(value) == "table" then
                set_kv(flat_record, key, value)
            elseif json_success and type(decoded) == "table" then
                flatten_into(flat_record, decoded, tostring(key))
            elseif json_success and is_null(decoded) then
                -- A JSON-encoded null is empty just like a native cjson.null.
            elseif type(value) == "table" then
                flatten_into(flat_record, value, tostring(key))
            else
                set_kv(flat_record, key, value)
            end
        end
    end

    -- Treat level and levelname as one root-level pair. Reserving both fields
    -- here prevents an envelope's severity alias from replacing either half.
    local root_level_value = record.level
    if not has_value(root_level_value) then
        root_level_value = record.levelname
    end
    if has_value(root_level_value) then
        local root_level, root_levelname = normalise_level_pair(root_level_value)
        flat_record.level = root_level
        flat_record.levelname = root_levelname
    end

    -- Envelope precedence is message, then log, then msg. Conflicting values
    -- from lower-priority envelopes are retained in _extracted fields.
    for _, key in ipairs({ "message", "log", "msg" }) do
        local value = record[key]
        local json_success, decoded = decode_json(value)
        if json_success and type(decoded) == "table" then
            expand_envelope(flat_record, decoded)
        elseif json_success and is_null(decoded) then
            -- Ignore JSON-encoded null envelope values.
        elseif type(value) == "table" then
            expand_envelope(flat_record, value)
        elseif has_value(value) then
            if type(value) ~= "string" then
                value = to_logfmt_value(value)
            end
            set_kv(flat_record, "message", value)
        end
    end

    if not has_value(flat_record.message) then
        flat_record.message = "NO MESSAGE"
    end

    -- Convert source.* keys to source_* without losing collisions.
    local new_record = {}
    -- Copy explicit keys first so a renamed source.* field cannot displace one.
    for _, key in ipairs(sorted_keys(flat_record)) do
        local value = flat_record[key]
        if key:sub(1, 7) ~= "source." then
            set_kv(new_record, key, value)
        end
    end
    for _, key in ipairs(sorted_keys(flat_record)) do
        if key:sub(1, 7) == "source." then
            set_kv(new_record, "source_" .. key:sub(8), flat_record[key])
        end
    end

    if not has_value(new_record.short_message) then
        new_record.short_message = nil
    end

    if type(new_record.source) ~= "string" or not has_value(new_record.source) then
        new_record.source = type(tag) == "string" and has_value(tag) and tag or "unknown"
    end

    if type(new_record.service_name) ~= "string" or not has_value(new_record.service_name) then
        if type(new_record.source_service) == "string" and has_value(new_record.source_service) then
            new_record.service_name = new_record.source_service
        else
            new_record.service_name = new_record.source
        end
    end

    -- Prefer a valid timestamp supplied by the log itself as Fluent Bit's event
    -- time. Preserve its exact representation; otherwise expose the fallback
    -- Fluent Bit event timestamp in the record as previous versions did.
    local original_timestamp = new_record.timestamp
    local record_timestamp = to_unix_timestamp(original_timestamp)
    if record_timestamp then
        timestamp = record_timestamp
        new_record.timestamp = original_timestamp
    else
        new_record.timestamp = timestamp
    end

    local level_value = new_record.level
    if not has_value(level_value) then
        level_value = new_record.levelname
    end
    local level, levelname = normalise_level_pair(level_value)
    new_record.level = level
    new_record.levelname = levelname

    return 1, timestamp, new_record
end
