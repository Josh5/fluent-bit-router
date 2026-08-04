---[[
File: systemd_modify_records.lua
Project: fluent-bit
Description: Modify systemd journal log records with source_* attributes and level normalisation.
--]]

function systemd_modify_records(tag, timestamp, record)
    local unit = record["SYSTEMD_UNIT"] or record["_SYSTEMD_UNIT"] or record["SYSLOG_IDENTIFIER"] or record["COMM"]

    if unit ~= nil and unit ~= "" then
        record["source_service"] = unit
    else
        record["source_service"] = "systemd"
    end

    record["source_category"] = "system"

    if record["MESSAGE"] ~= nil and record["message"] == nil then
        record["message"] = record["MESSAGE"]
        record["MESSAGE"] = nil
    end

    -- Determine log level
    local level = "info"
    local prio = record["PRIORITY"] or record["priority"]
    if prio ~= nil then
        local prio_str = tostring(prio)
        if prio_str == "0" or prio_str == "1" or prio_str == "2" or prio_str == "3" then
            level = "error"
        elseif prio_str == "4" then
            level = "warn"
        elseif prio_str == "7" then
            level = "debug"
        end
    end

    -- Upgrade log level if message contains explicit error/warning indicators
    local msg = record["message"]
    if msg ~= nil and (level == "info" or level == "warn") then
        local msg_lower = string.lower(tostring(msg))
        if string.find(msg_lower, "error") or string.find(msg_lower, "failed") or string.find(msg_lower, "err:") or string.find(msg_lower, "failure") then
            level = "error"
        elseif string.find(msg_lower, "warn") or string.find(msg_lower, "warning") then
            level = "warn"
        end
    end

    record["level"] = level

    return 1, timestamp, record
end
