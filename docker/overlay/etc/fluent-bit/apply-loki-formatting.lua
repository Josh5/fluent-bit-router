--[[
--File: apply-loki-formatting.lua
--Project: fluent-bit
--File Created: Friday, 6th December 2024 7:35:45 am
--Author: Josh5 (jsunnex@gmail.com)
-------
--Last Modified: Wednesday, 20th August 2025 11:14:28 am
--Modified By: Josh.5 (jsunnex@gmail.com)
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
