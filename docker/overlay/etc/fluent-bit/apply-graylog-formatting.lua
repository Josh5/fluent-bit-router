--[[
--File: apply-graylog-formatting.lua
--Project: fluent-bit
--File Created: Tuesday, 29th October 2024 3:18:29 pm
--Author: Josh5 (jsunnex@gmail.com)
-------
--Last Modified: Wednesday, 20th August 2025 10:44:56 am
--Modified By: Josh.5 (jsunnex@gmail.com)
--]]

local function to_unix_timestamp(ts)
    -- Minimal ISO8601 Z → epoch.nanoseconds parser, used only if someone upstream
    -- sneaks a string timestamp through (shouldn't happen after standard formatter).

    if type(ts) == "number" then
        -- Ensure it has 9-digit fractional nanos for GELF-friendly float
        local s = tostring(ts)
        if not s:find("%.") then
            return tonumber(s .. ".000000000")
        else
            local seconds, nanos = s:match("^(%d+)%.(%d+)$")
            if seconds then
                nanos = nanos .. string.rep("0", math.max(0, 9 - #nanos))
                return tonumber(seconds .. "." .. nanos)
            end
            return ts
        end
    elseif type(ts) == "string" then
        local y, m, d, H, M, S = ts:match("^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+%.?%d*)Z$")
        if y then
            local s_num = tonumber(S)
            local s_int = math.floor(s_num)
            local s_frac = s_num - s_int
            local tt = {
                year = tonumber(y),
                month = tonumber(m),
                day = tonumber(d),
                hour = tonumber(H),
                min = tonumber(M),
                sec = s_int,
                isdst = false
            }
            local base = os.time(tt)
            if base then
                local nanos = string.format("%09d", math.floor(s_frac * 1e9))
                return tonumber(tostring(base) .. "." .. nanos)
            end
        end
    end
    return nil
end

function graylog_formatting(tag, timestamp, record)
    -- Start from the (already normalized) record
    local new_record = record

    -- Ensure message / short_message are not empty
    local msg = new_record["message"]
    if type(msg) ~= "string" or msg == "" then
        new_record["message"] = "NO MESSAGE"
    end
    if type(new_record["short_message"]) ~= "string" or new_record["short_message"] == "" then
        new_record["short_message"] = msg
    end

    -- Check if "timestamp" exists; if not, use the provided timestamp from Fluent Bit
    local rec_ts = new_record["timestamp"]
    if rec_ts ~= nil then
        local parsed = to_unix_timestamp(rec_ts)
        if parsed then
            timestamp = parsed
        end
    end
    new_record["timestamp"] = timestamp

    -- Return the modified new_record
    return 1, timestamp, new_record
end
