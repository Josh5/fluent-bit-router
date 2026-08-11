--[[
File: systemd_modify_records.lua
Project: fluent-bit
Description:
    Normalize systemd journal records, identify their source service,
    normalize the message field, and derive a readable log level.
--]]

local function first_non_empty(record, keys)
    for _, key in ipairs(keys) do
        local value = record[key]

        if value ~= nil and tostring(value) ~= "" then
            return value
        end
    end

    return nil
end

local function priority_to_level(priority)
    if priority == nil then
        return "info"
    end

    local value = tonumber(priority)

    if value == nil then
        return "info"
    end

    -- Syslog priorities:
    -- 0 emerg
    -- 1 alert
    -- 2 crit
    -- 3 err
    -- 4 warning
    -- 5 notice
    -- 6 info
    -- 7 debug
    if value <= 3 then
        return "error"
    elseif value == 4 then
        return "warn"
    elseif value == 7 then
        return "debug"
    end

    return "info"
end

local function upgrade_level_from_message(level, message)
    if message == nil then
        return level
    end

    -- Do not downgrade an existing error or debug classification.
    if level ~= "info" and level ~= "warn" then
        return level
    end

    local text = string.lower(tostring(message))

    if string.find(text, "error", 1, true) or string.find(text, "failed", 1, true) or
        string.find(text, "failure", 1, true) or string.find(text, "err:", 1, true) then
        return "error"
    end

    if string.find(text, "warning", 1, true) or string.find(text, "warn", 1, true) then
        return "warn"
    end

    return level
end

function systemd_modify_records(tag, timestamp, record)
    -- strip_underscores is enabled, so _SYSTEMD_UNIT normally arrives as
    -- SYSTEMD_UNIT. The underscored variant remains as a defensive fallback.
    local service = first_non_empty(record, { "SYSTEMD_UNIT", "_SYSTEMD_UNIT", "SYSLOG_IDENTIFIER", "COMM" })

    record["service_name"] = service or "systemd"
    record["source_category"] = "system"

    -- Normalize the journald MESSAGE field while preserving an existing
    -- lowercase message field if another parser already supplied one.
    if record["message"] == nil and record["MESSAGE"] ~= nil then
        record["message"] = record["MESSAGE"]
        record["MESSAGE"] = nil
    end

    local priority = record["PRIORITY"] or record["priority"]
    local level = priority_to_level(priority)

    level = upgrade_level_from_message(level, record["message"])
    record["level"] = level

    -- Record modified, timestamp unchanged.
    return 2, timestamp, record
end

function system_log_add_unit(tag, timestamp, record)
    local process = first_non_empty(record, { "process" })

    if process ~= nil then
        local unit = tostring(process):gsub("%[%d+%]$", "")
        if not string.match(unit, "%.service$") then
            unit = unit .. ".service"
        end
        record["SYSTEMD_UNIT"] = unit
    end

    return 2, timestamp, record
end
