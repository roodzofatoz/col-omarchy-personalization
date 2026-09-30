"""Unit tests for bin/omarchy-a75 (no hardware needed).

Run: python3 -m unittest bin/test_omarchy_a75.py -v
"""

import errno
import importlib.machinery
import importlib.util
import json
import os
import pathlib
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent


def load_cli():
    loader = importlib.machinery.SourceFileLoader("omarchy_a75", str(HERE / "omarchy-a75"))
    spec = importlib.util.spec_from_loader("omarchy_a75", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


cli = load_cli()


class FramingTest(unittest.TestCase):
    def test_preset_write_matches_vendor_bytes(self):
        # Vendor: [29, preset] with BIT7 → gaming (2) checksums to 255-31=224.
        r = cli.new_report(cli.CMD_SET_KEY_MAGNETISM_MODE)
        r[1] = 2
        out = cli.finalize(r, "bit7")
        self.assertEqual(len(out), 64)
        self.assertEqual(list(out[:8]), [29, 2, 0, 0, 0, 0, 0, 224])

    def test_bit8_checksum_covers_first_eight_bytes(self):
        r = cli.new_report(7)          # SET_LEDPARAM style command
        r[1] = 1
        r[7] = 9
        out = cli.finalize(r, "bit8")
        self.assertEqual(out[8], 255 - ((7 + 1 + 9) & 255))

    def test_none_leaves_bytes_untouched(self):
        r = cli.new_report(1)
        r[7] = 42
        out = cli.finalize(r, "none")
        self.assertEqual(out[7], 42)

    def test_bit7_wraps_sum_above_255(self):
        r = cli.new_report(200)
        r[1] = 200
        out = cli.finalize(r, "bit7")
        self.assertEqual(out[7], 255 - ((400) & 255))


def fake_sysfs(root, name, hid_id, descriptor):
    d = os.path.join(root, name, "device")
    os.makedirs(d)
    with open(os.path.join(d, "uevent"), "w") as f:
        f.write("HID_ID=%s\nHID_NAME=VGN A75\n" % hid_id)
    with open(os.path.join(d, "report_descriptor"), "wb") as f:
        f.write(descriptor)


VENDOR_DESC = bytes.fromhex("06ffff0902a1010902158025ff9540750891020902b102c0")
BOOT_KBD_DESC = bytes.fromhex("05010906a101c0")


class DiscoveryTest(unittest.TestCase):
    def test_usage_pages_reads_two_byte_vendor_page(self):
        self.assertIn(0xFFFF, cli.usage_pages(VENDOR_DESC))
        self.assertEqual(cli.usage_pages(BOOT_KBD_DESC), {0x0001})

    def test_candidates_keep_only_vendor_interface_of_a75(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake_sysfs(tmp, "hidraw3", "0003:00003151:00004015", BOOT_KBD_DESC)
            fake_sysfs(tmp, "hidraw4", "0003:00003151:00004015", VENDOR_DESC)
            fake_sysfs(tmp, "hidraw5", "0003:00001532:000000C1", VENDOR_DESC)
            found = cli.candidates(sys_root=tmp, dev_root="/devx")
        self.assertEqual(found, [{"path": "/devx/hidraw4", "product": 0x4015}])


class ExchangeTest(unittest.TestCase):
    def setUp(self):
        self._real = cli.HidrawTransport

    def tearDown(self):
        cli.HidrawTransport = self._real

    def test_probe_returns_firmware_from_get_rev_reply(self):
        reply = bytes([128, 0x06, 0x01] + [0] * 61)
        t = cli.FakeTransport([reply])
        self.assertEqual(cli.probe(t), 0x0106)
        self.assertEqual(t.sent[0][0], cli.CMD_GET_REV)

    def test_probe_skips_wrong_echo_then_gives_up(self):
        t = cli.FakeTransport([bytes([1] + [0] * 63)] * 3)
        self.assertIsNone(cli.probe(t))

    def test_probe_treats_epipe_as_wrong_interface(self):
        t = cli.FakeTransport([OSError(errno.EPIPE, "epipe")])
        self.assertIsNone(cli.probe(t))

    def test_open_keyboard_reports_unplugged_on_enodev(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake_sysfs(tmp, "hidraw4", "0003:00003151:00004015", VENDOR_DESC)
            cli.HidrawTransport = lambda path: cli.FakeTransport([OSError(errno.ENODEV, "gone")])
            transport, info = cli.open_keyboard(sys_root=tmp, dev_root="/devx")
        self.assertIsNone(transport)
        self.assertFalse(info["present"])

    def test_open_keyboard_reports_stalled_pipe_on_eproto(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake_sysfs(tmp, "hidraw4", "0003:00003151:00004015", VENDOR_DESC)
            cli.HidrawTransport = lambda path: cli.FakeTransport([OSError(errno.EPROTO, "proto")])
            transport, info = cli.open_keyboard(sys_root=tmp, dev_root="/devx")
        self.assertIsNone(transport)
        self.assertTrue(info["present"])
        self.assertTrue(info["stalled"])
        self.assertIn("replug", info["error"])

    def test_open_keyboard_flags_permission_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake_sysfs(tmp, "hidraw4", "0003:00003151:00004015", VENDOR_DESC)
            cli.HidrawTransport = lambda path: cli.FakeTransport([PermissionError(errno.EACCES, "denied")])
            transport, info = cli.open_keyboard(sys_root=tmp, dev_root="/devx")
        self.assertIsNone(transport)
        self.assertTrue(info["present"])
        self.assertTrue(info["permissionError"])


class KeyboardReadTest(unittest.TestCase):
    def test_status_decodes_vendor_replies(self):
        replies = [
            bytes([133, 1] + [0] * 62),               # GET_PROFILE → profile 1
            bytes([157, 2, 0] + [0] * 61),            # GET_KEY_MAGNETISM_MODE → gaming, enabled
            bytes([132, 1, 2] + [0] * 61),            # GET_REPORT → code 2 → 500 Hz
        ]
        kb = cli.Keyboard(cli.FakeTransport(replies))
        st = kb.status()
        self.assertEqual(st["profile"], 1)
        self.assertEqual(st["preset"], "gaming")
        self.assertFalse(st["keyboardDisabled"])
        self.assertEqual(st["reportRate"], 500)

    def test_get_report_sends_profile_byte(self):
        kb = cli.Keyboard(cli.FakeTransport([bytes([133, 3] + [0] * 62), bytes([132, 3, 1] + [0] * 61)]))
        kb.profile()
        kb.report_rate()
        self.assertEqual(kb.transport.sent[1][:2], bytes([132, 3]))

    def test_format_firmware_matches_vendor_hex_display(self):
        # The vendor hub shows the raw GET_REV word as hex (0x0112 → "112").
        self.assertEqual(cli.format_firmware(0x0112), "112")
        self.assertEqual(cli.format_firmware(0x0106), "106")


class CliTest(unittest.TestCase):
    def test_status_without_device_prints_present_false(self):
        with tempfile.TemporaryDirectory() as tmp:
            import io, contextlib
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                code = cli.main(["--sys-root", tmp, "status"])
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(buf.getvalue())["present"], False)


class KeyboardWriteTest(unittest.TestCase):
    def setUp(self):
        # The vendor's settle delays are real-time waits; not needed against a fake.
        self._delays = (cli.BIG_DELAY, cli.RECORD_DELAY)
        cli.BIG_DELAY = cli.RECORD_DELAY = 0

    def tearDown(self):
        cli.BIG_DELAY, cli.RECORD_DELAY = self._delays

    def test_set_preset_writes_then_rereads(self):
        t = cli.FakeTransport([bytes([157, 3, 1] + [0] * 61)])
        kb = cli.Keyboard(t)
        out = kb.set_preset("custom", keyboard_disabled=True)
        self.assertEqual(list(t.sent[0][:8]), [29, 3, 1, 0, 0, 0, 0, 255 - 33])
        self.assertEqual(out, {"mode": "custom", "keyboardDisabled": True})

    def test_set_preset_rejects_unknown_name(self):
        with self.assertRaises(ValueError):
            cli.Keyboard(cli.FakeTransport([])).set_preset("turbo")

    def test_set_profile_and_rate_bytes(self):
        t = cli.FakeTransport([bytes([133, 2] + [0] * 62), bytes([132, 2, 1] + [0] * 61)])
        kb = cli.Keyboard(t)
        kb.set_profile(2)
        kb.set_report_rate(1000)
        self.assertEqual(t.sent[0][:2], bytes([5, 2]))
        self.assertEqual(t.sent[2][:3], bytes([4, 2, 1]))   # SET_REPORT profile 2, code 1


class TriggerRecordTest(unittest.TestCase):
    def test_all_keys_record_layout(self):
        t = {"actuation": 15, "release": 12, "rt": True, "rtPress": 3, "rtRelease": 4, "deadzoneBottom": 5}
        rec = cli.trigger_record(0, t, None)
        self.assertEqual(rec[0], 26)
        self.assertEqual(rec[1], 0)
        self.assertEqual(rec[2], 1)
        self.assertEqual(rec[3], 0x80)
        self.assertEqual(rec[4], 15)
        self.assertEqual(rec[5], 1)
        self.assertEqual(rec[6], 0)
        self.assertEqual(rec[7], 255 - ((26 + 1 + 0x80 + 15 + 1) & 255))
        self.assertEqual(rec[8], 12)
        self.assertEqual(rec[9], 3)
        self.assertEqual(rec[10], 4)
        self.assertEqual(rec[25], 4)          # 10*0.5mm - 1

    def test_single_key_record_uses_slot_and_no_rt_bytes(self):
        t = {"actuation": 20, "release": 20, "rt": False, "rtPress": 3, "rtRelease": 3, "deadzoneBottom": 0}
        rec = cli.trigger_record(2, t, 37)
        self.assertEqual((rec[1], rec[3], rec[5], rec[6]), (2, 0, 0, 37))
        self.assertEqual((rec[9], rec[10], rec[25]), (0, 0, 0))

    def test_normalize_clamps_rounds_and_orders(self):
        t, adjusted = cli.normalize_trigger({"actuation": 47, "release": 0.4, "rt": "yes", "rtPress": 99, "rtRelease": -1, "deadzoneBottom": 30})
        self.assertEqual(t["actuation"], 40)
        self.assertEqual(t["release"], 1)
        self.assertTrue(t["rt"])
        self.assertEqual((t["rtPress"], t["rtRelease"], t["deadzoneBottom"]), (40, 1, 10))
        self.assertTrue(adjusted)

    def test_normalize_lowers_release_above_actuation(self):
        t, adjusted = cli.normalize_trigger({"actuation": 10, "release": 25})
        self.assertEqual(t["release"], 10)
        self.assertTrue(adjusted)


class ProfileStateTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self._dir = cli.STATE_DIR
        cli.STATE_DIR = self.tmp.name

    def tearDown(self):
        cli.STATE_DIR = self._dir
        self.tmp.cleanup()

    def test_missing_file_gives_unsynced_defaults(self):
        data = cli.load_profile(1)
        self.assertFalse(data["synced"])
        self.assertEqual(data["default"], cli.default_trigger())
        self.assertEqual(data["keys"], {})

    def test_corrupt_file_gives_defaults_with_warning(self):
        os.makedirs(cli.STATE_DIR, exist_ok=True)
        with open(cli.profile_path(1), "w") as f:
            f.write("{not json")
        data = cli.load_profile(1)
        self.assertFalse(data["synced"])
        self.assertIn("warning", data)
        self.assertTrue(data["warning"])

    def test_foreign_shapes_give_defaults_with_warning(self):
        os.makedirs(cli.STATE_DIR, exist_ok=True)
        shapes = [
            '{"keys": {"3": "x"}}',
            '{"keys": {"3": [1, 2]}}',
            '{"default": "abc", "keys": {}}',
            '{"default": [1], "keys": {}}',
            '{"default": {"actuation": 1e999}, "keys": {}}',
            '[1, 2, 3]',
        ]
        for text in shapes:
            with open(cli.profile_path(2), "w") as f:
                f.write(text)
            data = cli.load_profile(2)
            self.assertFalse(data["synced"], text)
            self.assertTrue(data["warning"], text)
            self.assertEqual(data["default"], cli.default_trigger(), text)

    def test_round_trip(self):
        data = cli.load_profile(0)
        data["keys"]["12"] = dict(cli.default_trigger(), actuation=5)
        data["synced"] = True
        cli.save_profile(0, data)
        back = cli.load_profile(0)
        self.assertEqual(back["keys"]["12"]["actuation"], 5)
        self.assertTrue(back["synced"])


class TriggerCliTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self._dir = cli.STATE_DIR
        cli.STATE_DIR = self.tmp.name
        self._real = cli.HidrawTransport
        self._delays = (cli.BIG_DELAY, cli.RECORD_DELAY)
        cli.BIG_DELAY = cli.RECORD_DELAY = 0

    def tearDown(self):
        cli.STATE_DIR = self._dir
        cli.HidrawTransport = self._real
        cli.BIG_DELAY, cli.RECORD_DELAY = self._delays
        self.tmp.cleanup()

    def run_cli(self, sysroot, argv):
        import io, contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            code = cli.main(["--sys-root", sysroot, "--dev-root", "/devx"] + argv)
        return code, json.loads(buf.getvalue())

    def fake_device(self, extra_replies):
        base = [bytes([128, 6, 1] + [0] * 61)]           # probe
        cli.HidrawTransport = lambda path: cli.FakeTransport(base + extra_replies)

    def test_dry_run_prints_records_and_writes_nothing_to_device(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake_sysfs(tmp, "hidraw4", "0003:00003151:00004015", VENDOR_DESC)
            status_replies = [bytes([133, 0] + [0] * 62), bytes([157, 3, 0] + [0] * 61), bytes([132, 0, 1] + [0] * 61)]
            self.fake_device([bytes([133, 0] + [0] * 62)] + status_replies)
            code, out = self.run_cli(tmp, ["trigger", "--keys", "3,4", "--actuation", "0.8", "--rt", "on", "--dry-run"])
        self.assertEqual(code, 0)
        self.assertEqual(out["written"], 0)
        self.assertEqual(len(out["reports"]), 2)
        self.assertTrue(out["reports"][0].startswith("1a00018008"))   # 26, prof 0, 1, 0x80, 8
        self.assertEqual(out["profileState"]["keys"]["3"]["actuation"], 8)
        self.assertFalse(out["profileState"]["synced"])

    def test_status_is_held_while_the_vendor_hub_runs(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake_sysfs(tmp, "hidraw4", "0003:00003151:00004015", VENDOR_DESC)
            self.fake_device([])
            os.makedirs(cli.STATE_DIR, exist_ok=True)
            with open(cli.hub_hold_path(), "w") as f:
                f.write("test\n")
            code, out = self.run_cli(tmp, ["status"])
        self.assertEqual(code, 0)
        self.assertTrue(out["held"])
        self.assertTrue(out["present"])

    def test_device_lock_is_taken_and_released(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake_sysfs(tmp, "hidraw4", "0003:00003151:00004015", VENDOR_DESC)
            self.fake_device([bytes([133, 0] + [0] * 62), bytes([157, 3, 0] + [0] * 61), bytes([132, 0, 1] + [0] * 61)])
            code, out = self.run_cli(tmp, ["status"])
            self.assertEqual(code, 0)
            self.assertTrue(os.path.exists(cli.device_lock_path()))
            # Someone else holding the lock makes the CLI report busy instead of hanging.
            import fcntl as _fcntl
            holder = os.open(cli.device_lock_path(), os.O_RDWR | os.O_CREAT)
            _fcntl.flock(holder, _fcntl.LOCK_EX)
            cli.LOCK_TIMEOUT = 0.2
            self.fake_device([])
            code, out = self.run_cli(tmp, ["status"])
            os.close(holder)
        self.assertEqual(code, 1)
        self.assertIn("busy", out["error"])

    def test_trigger_waits_after_each_record_and_after_the_batch(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake_sysfs(tmp, "hidraw4", "0003:00003151:00004015", VENDOR_DESC)
            cli.RECORD_DELAY, cli.BIG_DELAY = 0.001, 0.002
            slept = []
            real_sleep = cli.time.sleep
            cli.time.sleep = lambda s: slept.append(s)
            try:
                status_replies = [bytes([133, 0] + [0] * 62), bytes([157, 3, 0] + [0] * 61), bytes([132, 0, 1] + [0] * 61)]
                self.fake_device([bytes([133, 0] + [0] * 62), bytes([157, 3, 0] + [0] * 61)] + status_replies)
                code, out = self.run_cli(tmp, ["trigger", "--keys", "8,9", "--actuation", "1.0"])
            finally:
                cli.time.sleep = real_sleep
        self.assertEqual(out["written"], 2)
        self.assertEqual(slept.count(0.001), 2)          # one wait per record
        self.assertEqual(slept[-1], 0.002)                # batch wait before the status GETs

    def test_all_keys_clears_per_key_entries_and_marks_synced(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake_sysfs(tmp, "hidraw4", "0003:00003151:00004015", VENDOR_DESC)
            data = cli.load_profile(0)
            data["keys"]["9"] = cli.default_trigger()
            cli.save_profile(0, data)
            status_replies = [bytes([133, 0] + [0] * 62), bytes([157, 3, 0] + [0] * 61), bytes([132, 0, 1] + [0] * 61)]
            self.fake_device([bytes([133, 0] + [0] * 62), bytes([157, 3, 0] + [0] * 61)] + status_replies)
            code, out = self.run_cli(tmp, ["trigger", "--all", "--actuation", "1.5", "--release", "1.0"])
        self.assertEqual(code, 0)
        self.assertEqual(out["written"], 1)
        self.assertEqual(out["profileState"]["keys"], {})
        self.assertEqual(out["profileState"]["default"]["actuation"], 15)
        self.assertTrue(out["profileState"]["synced"])


class DepthTest(unittest.TestCase):
    def test_set_depth_report_bytes(self):
        t = cli.FakeTransport([])
        cli.Keyboard(t).set_depth_report(True)
        self.assertEqual(list(t.sent[0][:8]), [27, 1, 0, 0, 0, 0, 0, 255 - 28])

    def test_parse_depth_frame(self):
        frame = bytes.fromhex("051b1545")   # captured: Q at 2.1 mm, sensor level 0x45
        self.assertEqual(cli.parse_depth_frame(frame), {"travel": 21, "level": 69, "raw": "051b1545"})

    def test_parse_depth_frame_release(self):
        self.assertEqual(cli.parse_depth_frame(bytes.fromhex("051b0000"))["travel"], 0)

    def test_parse_ignores_other_reports(self):
        self.assertIsNone(cli.parse_depth_frame(bytes([0x02, 0, 0, 0])))
        self.assertIsNone(cli.parse_depth_frame(b""))


if __name__ == "__main__":
    unittest.main()
