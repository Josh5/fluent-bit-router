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

local function promote_parsed_fields(record, parsed_message)
    if parsed_message == nil then
        return
    end

    for key, value in pairs(parsed_message) do
        if key ~= "message" and key ~= "log" and key ~= "msg" and not has_value(record[key]) then
            -- Keep nested values as JSON strings. The standard formatter decodes
            -- and flattens them while preserving empty array/object identity.
            if type(value) == "table" then
                record[key] = cjson.encode(value)
            elseif has_value(value) then
                record[key] = value
            end
        end
    end
end

local function client_ip(client_address)
    if type(client_address) ~= "string" then
        return nil
    end

    local bracketed_ipv6 = string.match(client_address, "^%[([^%]]+)%]:%d+$")
    if bracketed_ipv6 ~= nil then
        return bracketed_ipv6
    end

    local host_without_port = string.match(client_address, "^(.-):%d+$")
    return host_without_port or client_address
end

function traefik_modify_records(tag, timestamp, record)
    local new_record = record
    local parsed_message = nil

    -- Docker metadata is authoritative. Tags and container names may contain
    -- "traefik" for related services such as a watchdog, but those records must
    -- not be treated as Traefik access logs.
    if tostring(new_record["service_name"] or "") ~= "traefik" then
        return 0, timestamp, record
    end

    -- Set category strictly to "proxy"
    new_record["source_category"] = "proxy"

    -- Decode the access log payload locally. Nested values are re-encoded before
    -- crossing the Lua filter boundary and are flattened by the global formatter.
    if type(record["message"]) == "string" and string.sub(record["message"], 1, 1) == "{" then
        local success, parsed = pcall(cjson.decode, record["message"])
        if success and type(parsed) == "table" then
            parsed_message = parsed
            promote_parsed_fields(new_record, parsed_message)
        end
    end

    -- Extract Traefik access log JSON fields if present
    local client_addr = access_value(new_record, parsed_message, "ClientAddr") or
        access_value(new_record, parsed_message, "ClientHost")
    local ip = client_ip(client_addr)
    if ip ~= nil then
        new_record["source_client_ip"] = ip
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

    if parsed_message ~= nil and (
            has_value(parsed_message["OriginStatus"]) or
            has_value(parsed_message["DownstreamStatus"]) or
            has_value(parsed_message["ClientHost"]) or
            has_value(parsed_message["ClientAddr"]) or
            has_value(parsed_message["RequestMethod"]) or
            has_value(parsed_message["ServiceAddr"]) or
            has_value(parsed_message["ServiceURL"])
        ) then
        local origin_status = access_value(new_record, parsed_message, "OriginStatus") or
            access_value(new_record, parsed_message, "DownstreamStatus") or "-"
        local client_host = access_value(new_record, parsed_message, "ClientHost") or
            access_value(new_record, parsed_message, "ClientAddr") or "-"
        local request_method = access_value(new_record, parsed_message, "RequestMethod") or "-"
        local request_addr = access_value(new_record, parsed_message, "RequestAddr") or
            access_value(new_record, parsed_message, "RequestHost") or ""
        local request_path = access_value(new_record, parsed_message, "RequestPath") or ""
        local service_addr = access_value(new_record, parsed_message, "ServiceAddr") or
            access_value(new_record, parsed_message, "ServiceURL") or "-"

        new_record["message"] = string.format(
            "Status:%s Client From %s %s %s%s Route To %s",
            tostring(origin_status),
            tostring(client_host),
            tostring(request_method),
            tostring(request_addr),
            tostring(request_path),
            tostring(service_addr)
        )
    elseif parsed_message ~= nil and has_value(parsed_message["msg"]) then
        new_record["message"] = tostring(parsed_message["msg"])
    end

    return 2, timestamp, new_record
end
