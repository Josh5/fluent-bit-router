--[[
File: apply_graylog_formatting.lua
Project: fluent-bit
Description: Format log records for Graylog GELF payload output.
--]]

function graylog_formatting(tag, timestamp, record)
    -- Start from the (already normalized) record
    local new_record = record

    -- Ensure message / short_message are not empty
    local msg = new_record["message"]
    if type(msg) ~= "string" or msg == "" then
        new_record["message"] = "NO MESSAGE"
    end
    if type(new_record["short_message"]) ~= "string" or new_record["short_message"] == "" then
        new_record["short_message"] = new_record["message"]
    end

    -- The standard formatter already set Fluent Bit's event timestamp. GELF
    -- requires a numeric field, so create a dedicated output value without
    -- replacing the application's exact original timestamp field.
    if type(timestamp) == "table" and
        type(timestamp.sec) == "number" and type(timestamp.nsec) == "number" then
        new_record["_gelf_timestamp"] = timestamp.sec + timestamp.nsec / 1000000000
    else
        new_record["_gelf_timestamp"] = timestamp
    end

    -- Return the modified new_record
    return 1, timestamp, new_record
end
