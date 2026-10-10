"""Validate syslog configuration and delivery inside the router image.

Run from the repository root: python3 tests/test_syslog_udp.py
Requires the overlay mounted at /etc/fluent-bit and Fluent Bit installed.
"""

import json
import os
import socket
import subprocess
import tempfile
import time
import unittest
from datetime import datetime
from pathlib import Path


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class SyslogTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="flb-syslog-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = self.root / "config"
        self.env = {
            **os.environ,
            "CUSTOM_CONFIG_PATH": str(self.config),
            "FLUENT_STORAGE_PATH": str(self.root / "storage"),
            "CERTIFICATES_DIRECTORY": str(self.root / "certs"),
            "HOST_HOSTNAME": "receiving-router",
            "INSTANCE_ID": "receiver-instance",
            "ENVIRONMENT_NAME": "syslog-test",
            "INFRASTRUCTURE_PROVIDER": "self",
            "FLUENT_BIT_TAG_PREFIX": "flb",
            "ENABLE_SYSLOG_INPUT": "false",
            "ENABLE_SYSLOG_LEGACY_INPUT": "false",
            "SYSLOG_INPUT_MODE": "udp",
            "SYSLOG_LEGACY_INPUT_MODE": "udp",
            "ENABLE_STDOUT_OUTPUT": "true",
            "ENABLE_SYSTEMD_INPUT": "false",
            "ENABLE_TLS_FORWARD_INPUT": "false",
            "HTTP_SERVER_PORT": str(free_port()),
            "FLUENT_STORAGE_MAX_CHUNKS_UP": "128",
            "FLUENT_STORAGE_SYNC": "normal",
            "FLUENT_STORAGE_CHECKSUM": "off",
            "FLUENT_STORAGE_BACKLOG_MEM_LIMIT": "20M",
            "FLUENT_BIT_LOG_LEVEL": "info",
        }
        for key in ("SYSLOG_INPUT_PORT", "SYSLOG_LEGACY_INPUT_PORT"):
            self.env.pop(key, None)

    def generate(self):
        return subprocess.run(
            ["bash", "docker/overlay/entrypoint.sh", "config_test"],
            env=self.env,
            capture_output=True,
            text=True,
            timeout=25,
        )

    def test_disabled(self):
        result = self.generate()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("#- fluent-bit.syslog.input.yaml", (self.config / "fluent-bit.yaml").read_text())
        self.assertNotIn("parsers:", (self.config / "fluent-bit.syslog.input.yaml").read_text())

    def test_defaults(self):
        self.env.update(ENABLE_SYSLOG_INPUT="true", ENABLE_SYSLOG_LEGACY_INPUT="true")
        result = self.generate()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        config = (self.config / "fluent-bit.syslog.input.yaml").read_text()
        for expected in ("port: 5140", "port: 5141", "parser: syslog-rfc5424", "parser: syslog-rfc3164"):
            self.assertIn(expected, config)
        self.assertEqual(config.count("    - name: syslog"), 2)
        self.assertEqual(config.count("    - name: lua"), 1)
        self.assertIn("parsers:", config)
        self.assertNotIn("parsers_file:", (self.config / "fluent-bit.yaml").read_text())
        self.assertFalse((self.config / "fluent-bit.syslog-legacy.input.yaml").exists())

    def test_invalid_settings(self):
        self.env.update(
            ENABLE_SYSLOG_INPUT="true",
            ENABLE_SYSLOG_LEGACY_INPUT="true",
            SYSLOG_INPUT_PORT="65536",
            SYSLOG_LEGACY_INPUT_MODE="unix_udp",
        )
        result = self.generate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("SYSLOG_INPUT_PORT must be", result.stdout)
        self.assertIn("SYSLOG_LEGACY_INPUT_MODE must be", result.stdout)

    def test_duplicate_endpoint(self):
        self.env.update(
            ENABLE_SYSLOG_INPUT="true",
            ENABLE_SYSLOG_LEGACY_INPUT="true",
            SYSLOG_INPUT_PORT="5140",
            SYSLOG_LEGACY_INPUT_PORT="5140",
        )
        result = self.generate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must use different ports", result.stdout)

    def receive(self, formats, mode="udp", threaded=False, modern_message=None):
        messages = {
            "syslog": (
                "<36>1 2026-10-10T12:00:00.000Z modern-node sshd 123 ID47 - modern test",
                "modern-node",
                4,
                "warn",
            ),
            "syslog-legacy": ("<35>Oct 10 12:00:00 legacy-node sshd[123]: legacy test", "legacy-node", 3, "error"),
        }
        if modern_message is not None:
            messages["syslog"] = (modern_message, "modern-node", 4, "warn")
        endpoints = {}
        for name in formats:
            prefix = "SYSLOG" if name == "syslog" else "SYSLOG_LEGACY"
            port = free_port()
            while port in endpoints.values():
                port = free_port()
            endpoints[name] = port
            self.env.update(
                {f"ENABLE_{prefix}_INPUT": "true", f"{prefix}_INPUT_PORT": str(port), f"{prefix}_INPUT_MODE": mode}
            )
        self.env["ENABLE_THREADED_NETWORK_INPUTS"] = str(threaded).lower()
        result = self.generate()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        (self.config / "fluent-bit.debug.output.yaml").write_text(
            "pipeline:\n  outputs:\n    - name: stdout\n      match: '*'\n      format: json_lines\n"
        )
        with (self.root / "output.log").open("w+") as output:
            process = subprocess.Popen(
                ["/opt/fluent-bit/bin/fluent-bit", "-c", str(self.config / "fluent-bit.yaml")],
                env=self.env,
                stdout=output,
                stderr=subprocess.STDOUT,
            )
            try:
                started_at = time.time()
                deadline = time.monotonic() + 12
                records = {}
                while time.monotonic() < deadline and set(records) != set(formats):
                    self.assertIsNone(process.poll(), (self.root / "output.log").read_text())
                    for name, port in endpoints.items():
                        kind = socket.SOCK_DGRAM if mode == "udp" else socket.SOCK_STREAM
                        with socket.socket(socket.AF_INET, kind) as sender:
                            if mode == "udp":
                                sender.sendto(b"malformed syslog", ("127.0.0.1", port))
                                sender.sendto(messages[name][0].encode(), ("127.0.0.1", port))
                            else:
                                try:
                                    sender.connect(("127.0.0.1", port))
                                except ConnectionRefusedError:
                                    continue
                                sender.sendall((messages[name][0] + "\n").encode())
                    time.sleep(0.3)
                    output.seek(0)
                    for line in output.read().splitlines():
                        try:
                            record = json.loads(line)
                        except ValueError:
                            continue
                        if isinstance(record, dict) and record.get("source") == "syslog":
                            name = record["source_routing_tag"].rsplit(".", 1)[-1]
                            records[name] = record
                self.assertEqual(set(records), set(formats), (self.root / "output.log").read_text())
                for name, record in records.items():
                    message, hostname, level, levelname = messages[name]
                    self.assertEqual(record["source_hostname"], hostname)
                    self.assertEqual(record["service_name"], "sshd")
                    self.assertEqual(record["level"], level)
                    self.assertEqual(record["levelname"], levelname)
                    self.assertEqual(record["syslog_severity"], level)
                    self.assertEqual(record["syslog_facility"], 4)
                    self.assertIsInstance(record["pri"], int)
                    self.assertEqual(record["pri"], 36 if name == "syslog" else 35)
                    self.assertEqual(record["source_env"], "syslog-test")
                    self.assertEqual(record["source_category"], "system")
                    self.assertEqual(record["syslog_raw_message"], message)
                    self.assertEqual(record["message"], "modern test" if name == "syslog" else "legacy test")
                    self.assertIn("syslog_source_address", record)
                    self.assertNotIn("source_instance_id", record)
                    if name == "syslog":
                        emitted_at = datetime.fromisoformat(record["timestamp"].replace("Z", "+00:00")).timestamp()
                        supplied_time = message.split(" ", 2)[1]
                        if supplied_time == "-":
                            self.assertGreaterEqual(emitted_at, started_at - 1)
                            self.assertLessEqual(emitted_at, time.time() + 1)
                        else:
                            expected_time = datetime.fromisoformat(supplied_time.replace("Z", "+00:00")).timestamp()
                            self.assertAlmostEqual(emitted_at, expected_time, places=3)
            finally:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()

    def test_modern_only(self):
        self.receive(["syslog"])

    def test_legacy_only(self):
        self.receive(["syslog-legacy"])

    def test_simultaneous_udp(self):
        self.receive(["syslog", "syslog-legacy"], threaded=True)

    def test_simultaneous_tcp(self):
        self.receive(["syslog", "syslog-legacy"], mode="tcp")

    def test_rfc5424_without_fraction(self):
        self.receive(["syslog"], modern_message="<36>1 2026-10-10T12:00:00Z modern-node sshd 123 ID47 - modern test")

    def test_rfc5424_nil_timestamp(self):
        self.receive(["syslog"], modern_message="<36>1 - modern-node sshd 123 ID47 - modern test")

    def test_rfc5424_structured_data(self):
        self.receive(
            ["syslog"],
            modern_message=(
                "<36>1 2026-10-10T12:00:00.000+02:00 modern-node sshd 123 ID47 "
                r'[test@32473 key="a\]b\"c\\d"][other@32473 id="2"] modern test'
            ),
        )


if __name__ == "__main__":
    unittest.main()
