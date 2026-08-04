--[[
File: traefik_modify_records.lua
Project: fluent-bit
Description: Parse and normalize Traefik reverse proxy access log records with category=proxy.
--]]

local cjson = require("cjson")

if type(cjson.decode_array_with_array_mt) == "function" then
    pcall(cjson.decode_array_with_array_mt, true)
end

local function has_value(value)
    return value ~= nil and value ~= cjson.null
end

local function access_value(record, parsed_message, key)
    if has_value(record[key]) then
        return record[key]
    end
    if parsed_message ~= nil and has_value(parsed_message[key]) then
        return parsed_message[key]
    end
    return nil
end

function traefik_modify_records(tag, timestamp, record)
    local new_record = record
    local parsed_message = nil

    -- Set category strictly to "proxy"
    new_record["source_category"] = "proxy"

    -- Default service name to "proxy" if unassigned or generic docker
    if new_record["source_service"] == nil or new_record["source_service"] == "" or new_record["source_service"] == "docker" then
        new_record["source_service"] = "proxy"
    end

    -- Decode only as a local read view. Returning CJSON-created nested tables
    -- through a Lua-filter boundary discards cjson.array_mt. The standard
    -- formatter decodes the original message later and flattens it in one call.
    if type(record["message"]) == "string" and string.sub(record["message"], 1, 1) == "{" then
        local success, parsed = pcall(cjson.decode, record["message"])
        if success and type(parsed) == "table" then
            parsed_message = parsed
        end
    end

    -- Extract Traefik access log JSON fields if present
    local client_addr = access_value(new_record, parsed_message, "ClientAddr") or
        access_value(new_record, parsed_message, "ClientHost")
    if type(client_addr) == "string" then
        -- Strip port if present in IP:port string
        local ip = string.match(client_addr, "^([^:]+)")
        new_record["source_client_ip"] = ip or client_addr
    end

    local request_method = access_value(new_record, parsed_message, "RequestMethod")
    if request_method ~= nil then
        new_record["source_http_method"] = request_method
    end

    local request_path = access_value(new_record, parsed_message, "RequestPath")
    if request_path ~= nil then
        new_record["source_http_path"] = request_path
    end

    local status = tonumber(
        access_value(new_record, parsed_message, "DownstreamStatus") or
        access_value(new_record, parsed_message, "OriginStatus") or
        access_value(new_record, parsed_message, "Status")
    )
    if status ~= nil then
        new_record["source_http_status"] = status

        -- Infer severity level from HTTP status code
        if status >= 500 then
            new_record["level"] = "error"
            new_record["levelname"] = "error"
        elseif status >= 400 then
            new_record["level"] = "warn"
            new_record["levelname"] = "warn"
        else
            new_record["level"] = "info"
            new_record["levelname"] = "info"
        end
    end

    local duration = access_value(new_record, parsed_message, "Duration")
    if duration ~= nil then
        new_record["source_request_duration"] = duration
    end

    local router_name = access_value(new_record, parsed_message, "RouterName")
    if router_name ~= nil then
        new_record["source_proxy_router"] = router_name
    end

    local service_name = access_value(new_record, parsed_message, "ServiceName")
    if service_name ~= nil then
        new_record["source_proxy_service"] = service_name
    end

    return 1, timestamp, new_record
end
