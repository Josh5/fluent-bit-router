--[[
File: apply_loki_formatting.lua
Project: fluent-bit
Description: Format log records for Grafana Loki HTTP payload output.
--]]

function grafana_loki_formatting(tag, timestamp, record)
    -- Create a new record
    local new_record = record

    -- Extract and validate the "timestamp" field with nanosecond precision for Loki and apply it to the fluent-bit timestamp also
    local record_timestamp = new_record["timestamp"]
    if type(record_timestamp) == "number" then
        -- Check for valid(ish) epoch timestamp. 32503680000 = Jan 1,3000
        if record_timestamp > 0 and record_timestamp < 32503680000 then
            -- Convert the number to a string to check for nanoseconds
            local record_timestamp_string = tostring(record_timestamp)
            if not record_timestamp_string:find("%.") then
                -- No decimal point, add .000000000 for nanoseconds
                record_timestamp_string = record_timestamp_string .. ".000000000"
            else
                -- Ensure the nanoseconds are padded to 9 digits
                local seconds, nanoseconds = record_timestamp_string:match("^(%d+)%.(%d+)$")
                nanoseconds = nanoseconds or ""
                nanoseconds = nanoseconds .. string.rep("0", 9 - #nanoseconds)
                record_timestamp_string = seconds .. "." .. nanoseconds
            end

            -- Convert back to number for returning as timestamp
            timestamp = tonumber(record_timestamp_string)
        end
    end

    -- Return the modified new_record
    return 1, timestamp, new_record
end
