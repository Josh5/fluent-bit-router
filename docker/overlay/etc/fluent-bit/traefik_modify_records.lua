--[[
File: traefik_modify_records.lua
Project: fluent-bit
Description: Parse and normalize Traefik reverse proxy access log records with category=proxy.
--]]

local cjson = require("cjson")

function traefik_modify_records(tag, timestamp, record)
    local new_record = record

    -- Set category strictly to "proxy"
    new_record["source_category"] = "proxy"

    -- Default service name to "proxy" if unassigned or generic docker
    if new_record["source_service"] == nil or new_record["source_service"] == "" or new_record["source_service"] == "docker" then
        new_record["source_service"] = "proxy"
    end

    -- If message contains an unparsed JSON string, attempt decoding it
    if type(record["message"]) == "string" and string.sub(record["message"], 1, 1) == "{" then
        local success, parsed = pcall(cjson.decode, record["message"])
        if success and type(parsed) == "table" then
            for k, v in pairs(parsed) do
                if new_record[k] == nil then
                    new_record[k] = v
                end
            end
        end
    end

    -- Extract Traefik access log JSON fields if present
    local client_addr = new_record["ClientAddr"] or new_record["ClientHost"]
    if client_addr ~= nil then
        -- Strip port if present in IP:port string
        local ip = string.match(client_addr, "^([^:]+)")
        new_record["source_client_ip"] = ip or client_addr
    end

    if new_record["RequestMethod"] ~= nil then
        new_record["source_http_method"] = new_record["RequestMethod"]
    end

    if new_record["RequestPath"] ~= nil then
        new_record["source_http_path"] = new_record["RequestPath"]
    end

    local status = tonumber(new_record["DownstreamStatus"] or new_record["OriginStatus"] or new_record["Status"])
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

    if new_record["Duration"] ~= nil then
        new_record["source_request_duration"] = new_record["Duration"]
    end

    if new_record["RouterName"] ~= nil then
        new_record["source_proxy_router"] = new_record["RouterName"]
    end

    if new_record["ServiceName"] ~= nil then
        new_record["source_proxy_service"] = new_record["ServiceName"]
    end

    return 1, timestamp, new_record
end
