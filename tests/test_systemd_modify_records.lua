dofile("docker/overlay/etc/fluent-bit/systemd_modify_records.lua")

-- Test 1: System service (_SYSTEMD_UNIT stripped to SYSTEMD_UNIT)
local _, _, record1 = systemd_modify_records("flb.self.node.log.systemd.host", 1000, {
    SYSTEMD_UNIT = "sshd.service",
    MESSAGE = "Accepted publickey for agent",
    PRIORITY = "6",
})
assert(record1.service_name == "sshd.service", "Expected sshd.service, got " .. tostring(record1.service_name))
assert(record1.message == "Accepted publickey for agent")
assert(record1.level == "info")

-- Test 2: User service (_SYSTEMD_USER_UNIT stripped to SYSTEMD_USER_UNIT)
-- SYSTEMD_UNIT is user@1000.service, SYSTEMD_USER_UNIT is app-chatgpt-desktop.service
local _, _, record2 = systemd_modify_records("flb.self.node.log.systemd.host", 1000, {
    SYSTEMD_UNIT = "user@1000.service",
    SYSTEMD_USER_UNIT = "app-chatgpt-desktop.service",
    MESSAGE = "noVNC listening on 0.0.0.0:6080",
    PRIORITY = "6",
})
assert(record2.service_name == "app-chatgpt-desktop.service",
    "Expected app-chatgpt-desktop.service, got " .. tostring(record2.service_name))
assert(record2.message == "noVNC listening on 0.0.0.0:6080")
assert(record2.level == "info")

-- Test 3: User service with underscored fallback
local _, _, record3 = systemd_modify_records("flb.self.node.log.systemd.host", 1000, {
    _SYSTEMD_UNIT = "user@1000.service",
    _SYSTEMD_USER_UNIT = "app-chatgpt-desktop.service",
    MESSAGE = "Error: Failed to connect",
    PRIORITY = "6",
})
assert(record3.service_name == "app-chatgpt-desktop.service",
    "Expected app-chatgpt-desktop.service, got " .. tostring(record3.service_name))
assert(record3.level == "error")

-- Test 4: Syslog fallback with system_log_add_unit
local _, _, syslog_record = system_log_add_unit("flb.self.node.log.system.host", 1000, {
    process = "sshd[1234]",
    message = "Connection closed",
})
assert(syslog_record.SYSTEMD_UNIT == "sshd.service",
    "Expected sshd.service, got " .. tostring(syslog_record.SYSTEMD_UNIT))

print("systemd_modify_records.lua tests passed successfully!")
