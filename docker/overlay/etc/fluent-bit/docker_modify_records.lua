--[[
File: docker_modify_records.lua
Project: fluent-bit
Description: Modify Docker container log records with source_* attributes and Swarm task service name extraction.
--]]

local function is_swarm_identifier(value)
    return value ~= nil
        and string.len(value) == 25
        and string.match(value, "^[a-z0-9]+$") ~= nil
end

local function service_from_container_name(container_name)
    local service_name, task_slot, task_id = string.match(
        container_name,
        "^(.-)%.([^.]+)%.([^.]+)$"
    )

    local is_replicated_task = tonumber(task_slot) ~= nil
    local is_global_task = is_swarm_identifier(task_slot)

    if service_name ~= nil
        and is_swarm_identifier(task_id)
        and (is_replicated_task or is_global_task) then
        return service_name
    end

    return container_name
end

function docker_modify_records(tag, timestamp, record)
    local new_record = record
    local attrs = record["attrs"]
    local container_name = nil
    local container_stream = record["source"]

    -- Preserve Docker's exact timestamp representation. The global formatter
    -- parses it as UTC into Fluent Bit's {sec,nsec} event time without os.time
    -- local-time shifts or floating-point nanosecond loss.
    if record["timestamp"] == nil and record["time"] ~= nil then
        new_record["timestamp"] = record["time"]
    end

    new_record["source_category"] = "docker"

    if type(attrs) == "table" then
        for key, value in pairs(attrs) do
            if key == "source" or string.sub(key, 1, 7) == "source." then
                local k = key == "source" and "source" or ("source_" .. string.sub(key, 8))
                new_record[k] = value
            end
        end
    end

    -- Preserve Docker container stream (stdout/stderr) without overriding source
    if container_stream == "stdout" or container_stream == "stderr" then
        new_record["source_stream"] = container_stream
    end
    new_record["source"] = "docker"

    if record["container_name"] ~= nil then
        container_name = string.gsub(record["container_name"], "^/", "")
        new_record["source_container_name"] = container_name
    end

    if record["container_id"] ~= nil then
        new_record["source_container_id"] = record["container_id"]
    end

    if new_record["source_service"] == nil or tostring(new_record["source_service"]) == "" then
        if container_name ~= nil and container_name ~= "" then
            -- Swarm names are stack_service.slot.task-id for replicated services
            -- and stack_service.node-id.task-id for global services.
            new_record["source_service"] = service_from_container_name(container_name)
        else
            new_record["source_service"] = "docker"
        end
    end

    if record["log"] ~= nil then
        new_record["message"] = record["log"]
        new_record["log"] = nil
    end

    return 1, timestamp, new_record
end
